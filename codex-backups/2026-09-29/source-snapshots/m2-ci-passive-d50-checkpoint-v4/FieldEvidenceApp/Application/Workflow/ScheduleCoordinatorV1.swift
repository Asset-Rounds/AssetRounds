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

    /// Canonical C51 override append. Recovery checks the exact journaled
    /// command before evaluating a frontier that may already include this
    /// accepted override; every new effect requires the validation closure.
    func recordOverride(_ event: ScheduleOverrideEventV1,
                        predecessor: ScheduleOverrideEventV1?,
                        release: ScheduleDefinitionReleaseV1,
                        validateNewEffect: () throws -> Void) throws -> ScheduleMutationReceiptV1 {
        let mutation = try ScheduleMutationV1(workspaceID: event.workspaceID,
            mutationID: event.mutationID,
            payload: .appendOverrideEvent(event, predecessor: predecessor, release: release))
        try mutation.validate()
        let expected = try WorkspaceMutationCanonicalV1.sha256(mutation)
        if let accepted = try writer.acceptedScheduleMutation(mutation) {
            guard accepted.mutationSHA256 == expected else { throw ScheduleFailureV1.divergentReplay }
            return accepted
        }
        try validateNewEffect()
        return try commit(mutation)
    }

    /// The exact one-time work link and occurrence start share one transaction.
    /// Calling this API is explicit user intent; due projection never starts work.
    func start(_ event: OccurrenceHistoryEventV1,
               predecessor: OccurrenceHistoryEventV1,
               release: ScheduleDefinitionReleaseV1) throws -> ScheduleMutationReceiptV1 {
        try commit(.init(workspaceID: event.workspaceID, mutationID: event.mutationID,
                         payload: .startOccurrence(event, predecessor: predecessor, release: release)))
    }

    func startRecurringRound(_ request: RecurringRoundStartRequestV1,
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
        return try .init(request: request,
                         scheduleReceipt: start(request.event, predecessor: request.predecessor,
                                                release: request.release))
    }

    func generate(definition: ScheduleDefinitionReleaseV1,
                  history: [OccurrenceHistoryEventV1],
                  completionHistory: [OccurrenceHistoryEventV1],
                  window: OccurrenceGenerationWindowV1,
                  resolver: any ScheduleCalendarResolvingV1,
                  releaseHistory: [ScheduleDefinitionReleaseV1] = [],
                  event: (OccurrenceGenerationCandidateV1) throws -> OccurrenceHistoryEventV1) throws -> ScheduleMutationReceiptV1? {
        let plan = try ScheduleOccurrenceGeneratorV1.generate(definition: definition, history: history,
                                                               completionHistory: completionHistory,
                                                               window: window, resolver: resolver,
                                                               releaseHistory: releaseHistory)
        guard !plan.candidates.isEmpty else { return nil }
        let events = try plan.candidates.map(event)
        guard let mutationID = events.first?.mutationID,
              events.allSatisfy({ $0.mutationID == mutationID }) else {
            throw ScheduleFailureV1.divergentReplay
        }
        return try commit(.init(workspaceID: definition.workspaceID, mutationID: mutationID,
                                payload: .generateOccurrences(release: definition, plan: plan, events: events)))
    }

    /// Commits or replays an exact, previously frozen generation command. The
    /// current plan is evaluated only for a new effect; an accepted identical
    /// mutation therefore recovers its receipt after generated history exists.
    func generateFrozen(definition: ScheduleDefinitionReleaseV1,
                        plan: OccurrenceGenerationPlanV1,
                        events: [OccurrenceHistoryEventV1],
                        currentPlan: () throws -> OccurrenceGenerationPlanV1) throws
        -> ScheduleMutationReceiptV1? {
        try plan.validate(definition: definition)
        guard !plan.candidates.isEmpty else {
            guard events.isEmpty else { throw ScheduleFailureV1.divergentReplay }
            return nil
        }
        guard let mutationID = events.first?.mutationID,
              events.allSatisfy({ $0.mutationID == mutationID }) else {
            throw ScheduleFailureV1.divergentReplay
        }
        let mutation = try ScheduleMutationV1(workspaceID: definition.workspaceID,
            mutationID: mutationID,
            payload: .generateOccurrences(release: definition, plan: plan, events: events))
        try mutation.validate()
        let expected = try WorkspaceMutationCanonicalV1.sha256(mutation)
        if let accepted = try writer.acceptedScheduleMutation(mutation) {
            guard accepted.mutationSHA256 == expected else { throw ScheduleFailureV1.divergentReplay }
            return accepted
        }
        guard try currentPlan() == plan else { throw ScheduleFailureV1.staleBasis }
        return try commit(mutation)
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

    /// C51 remains projection-only here. Canonical calendar/override mutation
    /// envelopes are committed by the existing WorkspaceWriter lanes.
    func previewAdvancedChange(definition: ScheduleDefinitionReleaseV1,
                               binding: AdvancedScheduleReleaseBindingV1,
                               calendar: ExceptionCalendarReleaseV1,
                               existingOverrideEvents: [ScheduleOverrideEventV1],
                               proposedOverride: ScheduleOverrideEventV1?,
                               occurrences: [ScheduleChangeOccurrenceInputV1],
                               evaluatedRange: ScheduleLocalDateRangeV1,
                               activeUpcomingWorkspaceCount: Int) throws -> ScheduleChangePreviewV1 {
        try ScheduleExceptionProjectionEngineV1.preview(definition: definition, binding: binding,
            calendar: calendar, existingOverrideEvents: existingOverrideEvents,
            proposedOverride: proposedOverride, occurrences: occurrences,
            evaluatedRange: evaluatedRange,
            activeUpcomingWorkspaceCount: activeUpcomingWorkspaceCount)
    }

    func validateAdvancedCommit(preview: ScheduleChangePreviewV1,
                                currentFrontier: ScheduleChangeFrontierV1) throws {
        try ScheduleExceptionProjectionEngineV1.validateCommit(preview: preview,
                                                                currentFrontier: currentFrontier)
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

enum C34RouteAdoptionBoundary_ScheduleCoordinatorV1 {
    static let scheduleDestination = NavigationDestinationV1.scheduleOccurrence
    static let scheduleAnchorType = C34OccurrenceNavigationAnchorV1.self
    static let restorationStartsAutomaticWork = false
}

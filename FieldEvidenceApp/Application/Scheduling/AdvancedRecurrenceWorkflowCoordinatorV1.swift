import Foundation

enum AdvancedRecurrenceWorkflowFailureV1: Error, Equatable, Sendable {
    case unsupportedPattern
    case staleContext
    case missingGenerationEvent
    case divergentGenerationEvent
    case reminderCapabilityUnavailable
}

/// The C38 authoring surface is deliberately narrower than the full C51
/// grammar. It cannot introduce free-form recurrence text or another interpreter.
enum AdvancedRecurrenceAuthoringPatternV1: Equatable, Sendable {
    case daily(interval: Int)
    case weekly(interval: Int, weekdays: [ScheduleWeekdayV1])
    case calendarDay(interval: Int, day: Int, missingDayPolicy: MissingDayPolicyV1)
    case weekday(interval: Int, ordinal: ScheduleWeekdayOrdinalV1, weekday: ScheduleWeekdayV1)
    case lastDay(interval: Int)

    var recurrence: AdvancedRecurrenceRuleV1 {
        switch self {
        case .daily(let interval): return .daily(interval: interval)
        case .weekly(let interval, let weekdays):
            return .weekly(interval: interval, weekdays: weekdays)
        case .calendarDay(let interval, let day, let policy):
            return .monthlyDay(interval: interval, day: day, missingDayPolicy: policy)
        case .weekday(let interval, let ordinal, let weekday):
            return .monthlyWeekday(interval: interval, ordinal: ordinal, weekday: weekday)
        case .lastDay(let interval):
            return .monthlyDay(interval: interval, day: 31, missingDayPolicy: .lastValidDay)
        }
    }

    func validate() throws { try recurrence.validate() }

    init(recurrence: AdvancedRecurrenceRuleV1) throws {
        switch recurrence {
        case .daily(let interval): self = .daily(interval: interval)
        case .weekly(let interval, let weekdays): self = .weekly(interval: interval, weekdays: weekdays)
        case .monthlyDay(let interval, let day, let policy)
            where day == 31 && policy == .lastValidDay:
            self = .lastDay(interval: interval)
        case .monthlyDay(let interval, let day, let policy):
            self = .calendarDay(interval: interval, day: day, missingDayPolicy: policy)
        case .monthlyWeekday(let interval, let ordinal, let weekday):
            self = .weekday(interval: interval, ordinal: ordinal, weekday: weekday)
        case .yearly, .completionRelative:
            throw AdvancedRecurrenceWorkflowFailureV1.unsupportedPattern
        }
        try validate()
    }
}

protocol AdvancedRecurrenceTimeZoneResolvingV1: Sendable {
    func timeZone(identifier: String) -> TimeZone?
}

struct FoundationAdvancedRecurrenceTimeZoneResolverV1: AdvancedRecurrenceTimeZoneResolvingV1 {
    func timeZone(identifier: String) -> TimeZone? { TimeZone(identifier: identifier) }
}

struct AdvancedRecurrenceWorkflowContextV1: Sendable {
    let definition: ScheduleDefinitionReleaseV1
    let binding: AdvancedScheduleReleaseBindingV1
    let calendar: ExceptionCalendarReleaseV1
    let overrideEvents: [ScheduleOverrideEventV1]
    let previewOccurrences: [ScheduleChangeOccurrenceInputV1]
    let definitions: [ScheduleDefinitionReleaseV1]
    let history: [OccurrenceHistoryEventV1]
    let completionHistory: [OccurrenceHistoryEventV1]
    let releaseHistory: [ScheduleDefinitionReleaseV1]
    let evaluatedRange: ScheduleLocalDateRangeV1
    let activeUpcomingWorkspaceCount: Int
    let priorEvaluationAt: Date?
    let reminderLocalizationKey: String

    func validate() throws {
        try definition.validate(); try binding.validate(); try calendar.validate()
        try overrideEvents.forEach { try $0.validate() }
        try previewOccurrences.forEach { try $0.validate() }
        try definitions.forEach { try $0.validate() }
        try history.forEach { try $0.validateIntrinsic() }
        try completionHistory.forEach { try $0.validateIntrinsic() }
        try releaseHistory.forEach { try $0.validate() }
        try evaluatedRange.validate(); try priorEvaluationAt.map(ScheduleLimitsV1.instant)
        try ScheduleLimitsV1.token(reminderLocalizationKey)
        let reference = try ScheduleDefinitionReleaseReferenceV1(definition)
        guard binding.scheduleRelease == reference,
              binding.calendarRelease == calendar.reference,
              definition.recurrence == .advanced(binding.configuration),
              definitions.contains(definition),
              definitions.allSatisfy({ $0.workspaceID == definition.workspaceID }),
              history.allSatisfy({ $0.workspaceID == definition.workspaceID }),
              completionHistory.allSatisfy({ $0.workspaceID == definition.workspaceID }),
              releaseHistory.allSatisfy({ $0.workspaceID == definition.workspaceID }),
              activeUpcomingWorkspaceCount >= 0 else {
            throw AdvancedRecurrenceWorkflowFailureV1.staleContext
        }
    }
}

struct AdvancedRecurrenceHistoryRowV1: Equatable, Sendable {
    let occurrenceID: OccurrenceIDV1
    let revision: UInt64
    let action: OccurrenceHistoryActionV1
    let state: OccurrenceStateV1
    let effectiveDueAtUTC: Date?
    let localTimeDisposition: LocalTimeDispositionV1
    let exceptionKind: ScheduleExceptionKindV1?
    let isImmutableHistory: Bool
}

enum AdvancedRecurrenceReminderStateV1: Equatable, Sendable {
    case available(ReminderProjectionV1)
    case suppressedForClockRollback
}

struct AdvancedRecurrenceWorkflowProjectionV1: Equatable, Sendable {
    let pattern: AdvancedRecurrenceAuthoringPatternV1
    let activeRange: ScheduleLocalDateRangeV1
    let ianaTimeZoneIdentifier: String
    let ambiguousTimePolicy: AmbiguousLocalTimePolicyV1
    let nonexistentTimePolicy: NonexistentLocalTimePolicyV1
    let exceptionPreview: ScheduleChangePreviewV1
    let dueQueue: DueQueueProjectionV1
    let reminders: AdvancedRecurrenceReminderStateV1
    let history: [AdvancedRecurrenceHistoryRowV1]
    let evaluatedAt: Date
    let clockDisposition: ScheduleClockDispositionV1
    let canCommitExceptionChange: Bool
}

enum AdvancedRecurrenceWorkflowCommandV1: Sendable {
    case previewException(ScheduleOverrideEventV1?)
    case previewGeneration(OccurrenceGenerationWindowV1)
    case commitException(preview: ScheduleChangePreviewV1,
                         currentFrontier: ScheduleChangeFrontierV1,
                         predecessor: ScheduleOverrideEventV1?)
    case recordOccurrence(event: OccurrenceHistoryEventV1,
                          predecessor: OccurrenceHistoryEventV1?)
    case generate(plan: OccurrenceGenerationPlanV1,
                  events: [OccurrenceHistoryEventV1])
    case reconcileReminders
}

enum AdvancedRecurrenceWorkflowOutcomeV1: Sendable {
    case projected(AdvancedRecurrenceWorkflowProjectionV1)
    case generationPreview(OccurrenceGenerationPlanV1)
    case exceptionCommitted(ScheduleMutationReceiptV1)
    case occurrenceRecorded(ScheduleMutationReceiptV1)
    case occurrencesGenerated(ScheduleMutationReceiptV1?)
    case remindersReconciled(ReminderProjectionV1)
}

@MainActor final class AdvancedRecurrenceWorkflowCoordinatorV1 {
    private let schedule: ScheduleCoordinatorV1
    private let exceptions: ScheduleExceptionCoordinatorV1
    private let reminderLifecycle: ScheduleReminderLifecycleV1?
    private let clock: any ApplicationClock
    private let timeZones: any AdvancedRecurrenceTimeZoneResolvingV1

    init(schedule: ScheduleCoordinatorV1,
         exceptions: ScheduleExceptionCoordinatorV1,
         reminderLifecycle: ScheduleReminderLifecycleV1? = nil,
         clock: any ApplicationClock,
         timeZones: any AdvancedRecurrenceTimeZoneResolvingV1 = FoundationAdvancedRecurrenceTimeZoneResolverV1()) {
        self.schedule = schedule; self.exceptions = exceptions
        self.reminderLifecycle = reminderLifecycle; self.clock = clock; self.timeZones = timeZones
    }

    func project(context: AdvancedRecurrenceWorkflowContextV1,
                 proposedOverride: ScheduleOverrideEventV1? = nil) throws
        -> AdvancedRecurrenceWorkflowProjectionV1 {
        try validateRuntime(context)
        let now = clock.now()
        let evaluation = try ScheduleProjectionEvaluationV1(evaluatedAt: now,
                                                              priorEvaluationAt: context.priorEvaluationAt)
        let preview = try exceptions.preview(definition: context.definition, binding: context.binding,
            calendar: context.calendar, existingOverrideEvents: context.overrideEvents,
            proposedOverride: proposedOverride, occurrences: context.previewOccurrences,
            evaluatedRange: context.evaluatedRange,
            activeUpcomingWorkspaceCount: context.activeUpcomingWorkspaceCount)
        let due = try schedule.dueQueue(workspaceID: context.definition.workspaceID,
            evaluation: evaluation, definitions: context.definitions, history: context.history)
        let reminderState: AdvancedRecurrenceReminderStateV1
        if evaluation.permitsReminderReconciliation {
            reminderState = .available(try schedule.reminders(dueQueue: due, evaluation: evaluation,
                                                               localizationKey: context.reminderLocalizationKey))
        } else {
            reminderState = .suppressedForClockRollback
        }
        return try .init(pattern: .init(recurrence: context.binding.recurrence),
            activeRange: context.calendar.effectiveRange,
            ianaTimeZoneIdentifier: context.definition.timeBasis.ianaTimeZoneIdentifier,
            ambiguousTimePolicy: context.definition.timeBasis.ambiguousTimePolicy,
            nonexistentTimePolicy: context.definition.timeBasis.nonexistentTimePolicy,
            exceptionPreview: preview, dueQueue: due, reminders: reminderState,
            history: historyRows(context.history, dueQueue: due), evaluatedAt: now,
            clockDisposition: evaluation.disposition, canCommitExceptionChange: true)
    }

    func execute(_ command: AdvancedRecurrenceWorkflowCommandV1,
                 context: AdvancedRecurrenceWorkflowContextV1) async throws
        -> AdvancedRecurrenceWorkflowOutcomeV1 {
        try validateRuntime(context)
        switch command {
        case .previewException(let proposed):
            return .projected(try project(context: context, proposedOverride: proposed))
        case .previewGeneration(let window):
            return .generationPreview(try previewGeneration(window: window, context: context))
        case .commitException(let preview, let frontier, let predecessor):
            guard let proposed = preview.proposedOverride,
                  proposed.workspaceID == context.definition.workspaceID,
                  proposed.scheduleRelease == (try ScheduleDefinitionReleaseReferenceV1(context.definition)) else {
                throw AdvancedRecurrenceWorkflowFailureV1.staleContext
            }
            return .exceptionCommitted(try schedule.recordOverride(proposed,
                predecessor: predecessor, release: context.definition) {
                    try self.exceptions.validateCommit(preview: preview, currentFrontier: frontier)
                })
        case .recordOccurrence(let event, let predecessor):
            guard event.workspaceID == context.definition.workspaceID,
                  event.scheduleRelease == (try ScheduleDefinitionReleaseReferenceV1(context.definition)) else {
                throw AdvancedRecurrenceWorkflowFailureV1.staleContext
            }
            return .occurrenceRecorded(try schedule.record(event, predecessor: predecessor,
                                                            release: context.definition))
        case .generate(let plan, let events):
            return .occurrencesGenerated(try generate(plan: plan, events: events, context: context))
        case .reconcileReminders:
            guard let reminderLifecycle else {
                throw AdvancedRecurrenceWorkflowFailureV1.reminderCapabilityUnavailable
            }
            let projection = try project(context: context)
            guard case .available(let reminders) = projection.reminders else {
                throw ScheduleFailureV1.staleBasis
            }
            try await reminderLifecycle.rebuild(reminders)
            return .remindersReconciled(reminders)
        }
    }

    /// Recovery reruns the exact command. Canonical record/generation commands
    /// retain the caller-supplied event MutationID and reach C28 idempotency.
    func recover(_ command: AdvancedRecurrenceWorkflowCommandV1,
                 context: AdvancedRecurrenceWorkflowContextV1) async throws
        -> AdvancedRecurrenceWorkflowOutcomeV1 {
        try await execute(command, context: context)
    }

    func previewGeneration(window: OccurrenceGenerationWindowV1,
                           context: AdvancedRecurrenceWorkflowContextV1) throws
        -> OccurrenceGenerationPlanV1 {
        try validateRuntime(context)
        return try ScheduleOccurrenceGeneratorV1.generate(definition: context.definition,
            history: context.history, completionHistory: context.completionHistory,
            window: window, resolver: resolver(context), releaseHistory: context.releaseHistory)
    }

    private func validateRuntime(_ context: AdvancedRecurrenceWorkflowContextV1) throws {
        try context.validate()
        guard timeZones.timeZone(identifier: context.definition.timeBasis.ianaTimeZoneIdentifier) != nil else {
            throw AdvancedRecurrenceWorkflowFailureV1.staleContext
        }
        _ = try AdvancedRecurrenceAuthoringPatternV1(recurrence: context.binding.recurrence)
    }

    private func resolver(_ context: AdvancedRecurrenceWorkflowContextV1)
        -> AdvancedScheduleCalendarResolverV1 {
        .init(binding: context.binding, calendarRelease: context.calendar,
              overrideEvents: context.overrideEvents,
              activeUpcomingWorkspaceCount: context.activeUpcomingWorkspaceCount,
              chainHistory: context.history)
    }

    private func generate(plan: OccurrenceGenerationPlanV1,
                          events: [OccurrenceHistoryEventV1],
                          context: AdvancedRecurrenceWorkflowContextV1) throws
        -> ScheduleMutationReceiptV1? {
        let calendarResolver = resolver(context)
        try plan.validate(definition: context.definition)
        let byOccurrence = Dictionary(grouping: events, by: \.occurrenceID)
        guard events.count == plan.candidates.count,
              Set(byOccurrence.keys) == Set(plan.candidates.map(\.occurrenceID)),
              byOccurrence.values.allSatisfy({ $0.count == 1 }) else {
            throw AdvancedRecurrenceWorkflowFailureV1.missingGenerationEvent
        }
        for candidate in plan.candidates {
            guard let event = byOccurrence[candidate.occurrenceID]?.first,
                  event.action == .generated,
                  event.scheduleRelease == plan.scheduleRelease,
                  event.nominalBasis == candidate.nominalBasis,
                  event.effectiveBasis == candidate.effectiveBasis,
                  event.identityPredecessorOccurrenceID == candidate.predecessorOccurrenceID,
                  event.identityCompletionEventSHA256 == candidate.completionEventSHA256 else {
                throw AdvancedRecurrenceWorkflowFailureV1.divergentGenerationEvent
            }
        }
        return try schedule.generateFrozen(definition: context.definition, plan: plan, events: events) {
            try ScheduleOccurrenceGeneratorV1.generate(definition: context.definition,
                history: context.history, completionHistory: context.completionHistory,
                window: plan.window, resolver: calendarResolver,
                releaseHistory: context.releaseHistory)
        }
    }

    private func historyRows(_ history: [OccurrenceHistoryEventV1],
                             dueQueue: DueQueueProjectionV1) -> [AdvancedRecurrenceHistoryRowV1] {
        let states = Dictionary(uniqueKeysWithValues: dueQueue.entries.map { ($0.occurrenceID, $0) })
        return Dictionary(grouping: history, by: \.occurrenceID).compactMap { id, events in
            guard let latest = events.max(by: { $0.revision < $1.revision }),
                  let due = states[id] else { return nil }
            return .init(occurrenceID: id, revision: latest.revision, action: latest.action,
                state: due.state, effectiveDueAtUTC: due.effectiveDueAtUTC,
                localTimeDisposition: latest.effectiveBasis.disposition,
                exceptionKind: latest.exception?.kind,
                isImmutableHistory: [.started, .completed, .missed].contains(due.state))
        }.sorted { ($0.effectiveDueAtUTC ?? .distantFuture, $0.occurrenceID)
            < ($1.effectiveDueAtUTC ?? .distantFuture, $1.occurrenceID) }
    }
}

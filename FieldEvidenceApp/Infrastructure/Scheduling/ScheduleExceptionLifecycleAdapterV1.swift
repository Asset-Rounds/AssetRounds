import Foundation

/// C51 projection-only lifecycle. It owns no store, network, provider, timer,
/// bookmark, credential, or writer; relaunch recovery is exact recomputation
/// from C28 occurrence truth plus immutable C51 releases/events.
@MainActor final class ScheduleExceptionLifecycleAdapterV1: ScheduleExceptionProjectingV1 {
    func preview(definition: ScheduleDefinitionReleaseV1,
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

    func validateCommit(preview: ScheduleChangePreviewV1,
                        currentFrontier: ScheduleChangeFrontierV1) throws {
        try ScheduleExceptionProjectionEngineV1.validateCommit(preview: preview,
                                                                currentFrontier: currentFrontier)
    }

    func recoverAfterInterruption(definition: ScheduleDefinitionReleaseV1,
                                  binding: AdvancedScheduleReleaseBindingV1,
                                  calendar: ExceptionCalendarReleaseV1,
                                  overrideEvents: [ScheduleOverrideEventV1],
                                  occurrences: [ScheduleChangeOccurrenceInputV1],
                                  evaluatedRange: ScheduleLocalDateRangeV1,
                                  activeUpcomingWorkspaceCount: Int) throws -> ScheduleChangePreviewV1 {
        try preview(definition: definition, binding: binding, calendar: calendar,
                    existingOverrideEvents: overrideEvents, proposedOverride: nil,
                    occurrences: occurrences, evaluatedRange: evaluatedRange,
                    activeUpcomingWorkspaceCount: activeUpcomingWorkspaceCount)
    }

    static let persistsPreviewOrRecoveryState = false
    static let createsSecondWriter = false
    static let usesProviderNetworkCredentialsOrBookmarks = false
    static let c28OccurrenceHistoryRemainsSoleTruth = true
}

/// Production C51 expansion engine. It emits C28 candidates only; persistence,
/// duplicate rejection, and receipt authority remain in ScheduleOccurrenceGeneratorV1.
struct AdvancedScheduleCalendarResolverV1: ScheduleCalendarResolvingV1 {
    let binding: AdvancedScheduleReleaseBindingV1
    let calendarRelease: ExceptionCalendarReleaseV1
    let overrideEvents: [ScheduleOverrideEventV1]
    let activeUpcomingWorkspaceCount: Int
    let chainHistory: [OccurrenceHistoryEventV1]

    init(binding: AdvancedScheduleReleaseBindingV1,
         calendarRelease: ExceptionCalendarReleaseV1,
         overrideEvents: [ScheduleOverrideEventV1],
         activeUpcomingWorkspaceCount: Int = 0,
         chainHistory: [OccurrenceHistoryEventV1] = []) {
        self.binding = binding; self.calendarRelease = calendarRelease
        self.overrideEvents = overrideEvents
        self.activeUpcomingWorkspaceCount = activeUpcomingWorkspaceCount
        self.chainHistory = chainHistory
    }

    func candidates(definition: ScheduleDefinitionReleaseV1,
                    window: OccurrenceGenerationWindowV1,
                    completionHistory: [OccurrenceHistoryEventV1]) throws -> [OccurrenceGenerationCandidateV1] {
        try definition.validate(); try window.validate(definition: definition)
        try binding.validate(); try calendarRelease.validate()
        try chainHistory.forEach { try $0.validateIntrinsic() }
        guard binding.scheduleRelease == (try ScheduleDefinitionReleaseReferenceV1(definition)),
              binding.calendarRelease == calendarRelease.reference else { throw ScheduleFailureV1.staleBasis }
        try ScheduleOverridePrecedenceV1.validateClosure(overrideEvents,
                                                         for: binding.scheduleRelease)
        let budget = try AdvancedScheduleGenerationBudgetV1()
        let maximumWindow = Double((budget.lookaheadDays + budget.reconciliationBackfillDays)
                                   * ScheduleLimitsV1.maximumCalendarDaySeconds)
        guard window.endsAtUTC.timeIntervalSince(window.startsAtUTC) <= maximumWindow,
              window.maximumOccurrences <= budget.maximumGeneratedPerSchedule else {
            throw ScheduleFailureV1.limitExceeded
        }
        let zone = try requireZone(definition.timeBasis.ianaTimeZoneIdentifier)
        let anchor = try localParts(definition.startsAtUTC, zone: zone)
        let localWindowStart = try localParts(window.startsAtUTC, zone: zone).date
        let localWindowEnd = try localParts(window.endsAtUTC, zone: zone).date
        var generated: [OccurrenceGenerationCandidateV1] = []
        switch binding.recurrence {
        case .completionRelative(let interval, let unit, let gapPolicy):
            if completionHistory.isEmpty {
                if definition.startsAtUTC >= window.startsAtUTC && definition.startsAtUTC <= window.endsAtUTC {
                    generated.append(try candidate(definition: definition, nominalDate: anchor.date,
                        nominalWindow: anchor.window, predecessorOccurrenceID: nil,
                        completionEventSHA256: nil))
                } else if gapPolicy == .requireManualAnchor {
                    throw ScheduleFailureV1.manualResolutionRequired
                }
            }
            for completion in completionHistory.sorted(by: { $0.eventSHA256 < $1.eventSHA256 }) {
                guard completion.action == .complete, let completedAt = completion.completedAt else { continue }
                let completedLocal = try localParts(completedAt, zone: zone)
                let nominal = try add(interval: interval, unit: unit, to: completedLocal.date)
                if nominal < localWindowStart || nominal > localWindowEnd { continue }
                generated.append(try candidate(definition: definition, nominalDate: nominal,
                    nominalWindow: anchor.window, predecessorOccurrenceID: completion.occurrenceID,
                    completionEventSHA256: completion.eventSHA256))
                if generated.count > window.maximumOccurrences { throw ScheduleFailureV1.limitExceeded }
            }
            let explicitSkips = chainHistory.filter { $0.exception?.kind == .skipped }
                .sorted { $0.eventSHA256 < $1.eventSHA256 }
            if !explicitSkips.isEmpty && gapPolicy == .requireManualAnchor {
                throw ScheduleFailureV1.manualResolutionRequired
            }
            if gapPolicy == .anchorToNominalAfterExplicitSkip {
                for skipped in explicitSkips {
                    let skippedNominal = try ScheduleLocalDateV1(skipped.nominalBasis.nominalLocalDate)
                    let nominal = try add(interval: interval, unit: unit, to: skippedNominal)
                    if nominal < localWindowStart || nominal > localWindowEnd { continue }
                    generated.append(try candidate(definition: definition, nominalDate: nominal,
                        nominalWindow: anchor.window, predecessorOccurrenceID: skipped.occurrenceID,
                        completionEventSHA256: skipped.eventSHA256))
                    if generated.count > window.maximumOccurrences { throw ScheduleFailureV1.limitExceeded }
                }
            }
        default:
            var cursor = localWindowStart
            var inspected = 0
            while cursor <= localWindowEnd {
                inspected += 1
                guard inspected <= budget.lookaheadDays + budget.reconciliationBackfillDays + 2 else {
                    throw ScheduleFailureV1.limitExceeded
                }
                if try matches(cursor, anchor: anchor.date, rule: binding.recurrence) {
                    generated.append(try candidate(definition: definition, nominalDate: cursor,
                        nominalWindow: anchor.window, predecessorOccurrenceID: nil,
                        completionEventSHA256: nil))
                    if generated.count > window.maximumOccurrences { throw ScheduleFailureV1.limitExceeded }
                }
                cursor = try addDays(1, to: cursor)
            }
        }
        guard activeUpcomingWorkspaceCount >= 0,
              activeUpcomingWorkspaceCount <= Int.max - generated.count else {
            throw ScheduleFailureV1.limitExceeded
        }
        try budget.validate(generatedCount: generated.count,
                            activeUpcomingWorkspaceCount: activeUpcomingWorkspaceCount + generated.count)
        return generated.sorted { $0.occurrenceID < $1.occurrenceID }
    }

    private func candidate(definition: ScheduleDefinitionReleaseV1,
                           nominalDate: ScheduleLocalDateV1,
                           nominalWindow: ScheduleLocalAnchorV1,
                           predecessorOccurrenceID: OccurrenceIDV1?,
                           completionEventSHA256: String?) throws -> OccurrenceGenerationCandidateV1 {
        let nominalResolution = try TimeContextRule.resolveScheduleCivilTime(date: nominalDate,
            window: nominalWindow, timeBasis: definition.timeBasis)
        let timeBasisSHA256 = try definition.timeBasis.canonicalSHA256()
        let nominalBasis = ResolvedOccurrenceBasisV1(nominalLocalDate: nominalDate.canonicalString,
            nominalLocalTime: localTime(nominalWindow), resolvedAtUTC: nominalResolution.resolvedAtUTC,
            utcOffsetSeconds: nominalResolution.utcOffsetSeconds, disposition: nominalResolution.disposition,
            timeBasisSHA256: timeBasisSHA256, adjustmentProvenanceSHA256: nil)
        try nominalBasis.validate()
        let occurrenceID = try OccurrenceIDV1(scheduleDefinitionID: definition.scheduleDefinitionID,
            identityNamespaceID: definition.occurrenceIdentityNamespaceID,
            nominalKey: nominalBasis.nominalKey,
            predecessorOccurrenceID: predecessorOccurrenceID,
            completionEventSHA256: completionEventSHA256)
        let resolution = try ScheduleOverridePrecedenceV1.resolve(occurrenceID: occurrenceID,
            nominalDate: nominalDate, nominalWindow: nominalWindow,
            scheduleRelease: binding.scheduleRelease, calendar: calendarRelease,
            adjustmentPolicy: binding.businessDayAdjustmentPolicy, events: overrideEvents)
        let effectiveBasis: ResolvedOccurrenceBasisV1
        if let date = resolution.effectiveDate, let window = resolution.effectiveWindow {
            let value = try TimeContextRule.resolveScheduleCivilTime(date: date, window: window,
                                                                     timeBasis: definition.timeBasis)
            effectiveBasis = .init(nominalLocalDate: nominalDate.canonicalString,
                nominalLocalTime: localTime(nominalWindow), resolvedAtUTC: value.resolvedAtUTC,
                utcOffsetSeconds: value.utcOffsetSeconds, disposition: value.disposition,
                timeBasisSHA256: timeBasisSHA256,
                adjustmentProvenanceSHA256: try adjustmentDigest(resolution))
        } else {
            effectiveBasis = .init(nominalLocalDate: nominalDate.canonicalString,
                nominalLocalTime: localTime(nominalWindow), resolvedAtUTC: nil, utcOffsetSeconds: nil,
                disposition: .nonexistentGap, timeBasisSHA256: timeBasisSHA256,
                adjustmentProvenanceSHA256: try adjustmentDigest(resolution))
        }
        try effectiveBasis.validate()
        return .init(occurrenceID: occurrenceID, nominalBasis: nominalBasis,
                     effectiveBasis: effectiveBasis,
                     predecessorOccurrenceID: predecessorOccurrenceID,
                     completionEventSHA256: completionEventSHA256)
    }

    private func adjustmentDigest(_ resolution: ScheduleOverrideResolutionV1) throws -> String? {
        if let event = resolution.event { return event.eventSHA256 }
        if resolution.level == .exceptionCalendar { return calendarRelease.releaseSHA256 }
        return nil
    }

    private func matches(_ date: ScheduleLocalDateV1, anchor: ScheduleLocalDateV1,
                         rule: AdvancedRecurrenceRuleV1) throws -> Bool {
        guard date >= anchor else { return false }
        switch rule {
        case .daily(let interval): return try dayDistance(anchor, date) % interval == 0
        case .weekly(let interval, let weekdays):
            return (try dayDistance(anchor, date) / 7) % interval == 0
                && weekdays.contains(try date.weekday())
        case .monthlyDay(let interval, let day, let policy):
            let distance = monthDistance(anchor, date)
            guard distance >= 0, distance % interval == 0 else { return false }
            let last = try lastDay(year: date.year, month: date.month)
            if day <= last { return date.day == day }
            switch policy { case .lastValidDay: return date.day == last
            case .skipWithReason: return false
            case .requireManualResolution: throw ScheduleFailureV1.manualResolutionRequired }
        case .monthlyWeekday(let interval, let ordinal, let weekday):
            let distance = monthDistance(anchor, date)
            guard distance >= 0, distance % interval == 0, try date.weekday() == weekday else { return false }
            return date.day == (try ordinalDay(year: date.year, month: date.month,
                                               weekday: weekday, ordinal: ordinal))
        case .yearly(let interval, let month, let day, let policy):
            guard (date.year - anchor.year) % interval == 0, date.month == month else { return false }
            let last = try lastDay(year: date.year, month: month)
            if day <= last { return date.day == day }
            switch policy { case .lastValidDay: return date.day == last
            case .skipWithReason: return false
            case .requireManualResolution: throw ScheduleFailureV1.manualResolutionRequired }
        case .completionRelative: return false
        }
    }

    private func ordinalDay(year: Int, month: Int, weekday: ScheduleWeekdayV1,
                            ordinal: ScheduleWeekdayOrdinalV1) throws -> Int {
        let last = try lastDay(year: year, month: month)
        let matches = try (1...last).filter { try ScheduleLocalDateV1(year: year, month: month, day: $0).weekday() == weekday }
        let index: Int
        switch ordinal { case .first: index = 0; case .second: index = 1
        case .third: index = 2; case .fourth: index = 3
        case .last: guard let value = matches.last else { throw ScheduleFailureV1.invalidValue }; return value }
        guard matches.indices.contains(index) else { throw ScheduleFailureV1.invalidValue }
        return matches[index]
    }

    private func lastDay(year: Int, month: Int) throws -> Int {
        let calendar = try utcCalendar()
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else { throw ScheduleFailureV1.invalidValue }
        return range.count
    }

    private func dayDistance(_ lhs: ScheduleLocalDateV1, _ rhs: ScheduleLocalDateV1) throws -> Int {
        let calendar = try utcCalendar()
        guard let l = calendar.date(from: DateComponents(year: lhs.year, month: lhs.month, day: lhs.day)),
              let r = calendar.date(from: DateComponents(year: rhs.year, month: rhs.month, day: rhs.day)),
              let value = calendar.dateComponents([.day], from: l, to: r).day else {
            throw ScheduleFailureV1.invalidValue
        }
        return value
    }

    private func monthDistance(_ lhs: ScheduleLocalDateV1, _ rhs: ScheduleLocalDateV1) -> Int {
        (rhs.year - lhs.year) * 12 + rhs.month - lhs.month
    }

    private func add(interval: Int, unit: CompletionRelativeCalendarUnitV1,
                     to date: ScheduleLocalDateV1) throws -> ScheduleLocalDateV1 {
        let component: Calendar.Component
        switch unit { case .days: component = .day; case .weeks: component = .weekOfYear
        case .months: component = .month; case .years: component = .year }
        let calendar = try utcCalendar()
        guard let source = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)),
              let result = calendar.date(byAdding: component, value: interval, to: source) else {
            throw ScheduleFailureV1.invalidValue
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: result)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            throw ScheduleFailureV1.invalidValue
        }
        return try .init(year: year, month: month, day: day)
    }

    private func addDays(_ count: Int, to date: ScheduleLocalDateV1) throws -> ScheduleLocalDateV1 {
        try add(interval: count, unit: .days, to: date)
    }

    private func requireZone(_ identifier: String) throws -> TimeZone {
        guard TimeZone.knownTimeZoneIdentifiers.contains(identifier),
              let zone = TimeZone(identifier: identifier) else { throw ScheduleFailureV1.invalidValue }
        return zone
    }

    private func localParts(_ instant: Date, zone: TimeZone) throws -> (date: ScheduleLocalDateV1, window: ScheduleLocalAnchorV1) {
        var calendar = Calendar(identifier: .gregorian); calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = zone
        let value = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        guard let year = value.year, let month = value.month, let day = value.day,
              let hour = value.hour, let minute = value.minute, let second = value.second else {
            throw ScheduleFailureV1.invalidValue
        }
        return (try .init(year: year, month: month, day: day),
                .init(year: nil, month: nil, day: nil, weekday: nil, weekdayOrdinal: nil,
                      hour: hour, minute: minute, second: second))
    }

    private func localTime(_ window: ScheduleLocalAnchorV1) -> String {
        String(format: "%02d:%02d:%02d", window.hour, window.minute, window.second)
    }

    private func utcCalendar() throws -> Calendar {
        var value = Calendar(identifier: .gregorian); value.locale = Locale(identifier: "en_US_POSIX")
        guard let utc = TimeZone(secondsFromGMT: 0) else { throw ScheduleFailureV1.invalidValue }
        value.timeZone = utc; return value
    }
}

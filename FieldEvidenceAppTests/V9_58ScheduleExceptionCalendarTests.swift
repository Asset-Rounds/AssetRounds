import Foundation
import XCTest
@testable import FieldEvidenceApp

private enum C51ScheduleTestSupport {
    static let base = Date(timeIntervalSince1970: 1_804_000_000)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c5100000-0000-4000-8000-%012x", value))!
    }

    static func digest(_ character: Character = "a") -> String {
        String(repeating: character, count: 64)
    }

    static func workspace(_ value: Int = 1) -> WorkspaceID {
        .init(rawValue: id(value))
    }

    static func mutation(_ value: Int) throws -> MutationIDV1 {
        try .init(rawValue: id(value))
    }

    static func actor(_ value: Int, responsibility: ResponsibilityKindV1 = .recordedBy) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(value), workspaceID: workspace(), displayName: "C51 local actor"
        )
        return try .init(
            snapshotID: id(value + 1), workspaceID: workspace(), actor: reference,
            responsibility: responsibility, displayNameAtTime: reference.displayName, capturedAt: base
        )
    }

    static func date(_ value: String) throws -> ScheduleLocalDateV1 {
        try .init(value)
    }

    static func range(_ startsOn: String, _ endsOn: String) throws -> ScheduleLocalDateRangeV1 {
        let value = ScheduleLocalDateRangeV1(startsOn: try date(startsOn), endsOn: try date(endsOn))
        try value.validate()
        return value
    }

    static func anchor(
        year: Int? = nil, month: Int? = nil, day: Int? = nil,
        weekday: Int? = nil, weekdayOrdinal: Int? = nil,
        hour: Int = 9, minute: Int = 0, second: Int = 0
    ) -> ScheduleLocalAnchorV1 {
        .init(year: year, month: month, day: day, weekday: weekday,
              weekdayOrdinal: weekdayOrdinal, hour: hour, minute: minute, second: second)
    }

    static func timeBasis(
        zone: String = "America/New_York",
        ambiguous: AmbiguousLocalTimePolicyV1 = .earlierOffset,
        nonexistent: NonexistentLocalTimePolicyV1 = .shiftForwardByGap
    ) throws -> FrozenScheduleTimeBasisV1 {
        try .init(
            ianaTimeZoneIdentifier: zone,
            timeZoneRuleSetVersion: "2026a",
            timeZoneRuleSetSHA256: digest("b"),
            ambiguousTimePolicy: ambiguous,
            nonexistentTimePolicy: nonexistent,
            calendarBasisSHA256: digest("c")
        )
    }

    static func scheduleReference(_ slot: Int = 100) -> ScheduleDefinitionReleaseReferenceV1 {
        try! ScheduleDefinitionReleaseReferenceV1(scheduleDefinition(slot))
    }

    static func scheduleDefinition(_ slot: Int = 100, maximum: Int = 8) throws -> ScheduleDefinitionReleaseV1 {
        let fact = FactDefinitionV1(
            factID: "fact", labelLocalizationKey: "survey.fact.label",
            accessibilityLabelLocalizationKey: "survey.fact.accessibility",
            helpLocalizationKey: "survey.fact.help", required: true,
            defaultValue: nil, visibility: nil,
            payload: .shortText(.init(maximumUTF8Bytes: 64))
        )
        let survey = try SurveyDefinitionReleaseV1(
            releaseID: id(slot + 10), workspaceID: workspace(), definitionID: id(slot + 11),
            activityKind: .survey, ownerPackageID: ShippingIlluminatedSignAdapterV1.packageID,
            sections: [.init(sectionID: "section", titleLocalizationKey: "survey.section.title",
                             accessibilityHeadingLocalizationKey: "survey.section.heading", ordinal: 0, facts: [fact])],
            completionRules: [.init(ruleID: "complete", expression: .allRequiredVisibleFactsAnswered,
                                    failureLocalizationKey: "survey.complete.failure")],
            claimsProfile: .init(profileID: "claims", activityKind: .survey, allowedClaimKeys: [],
                                 forbiddenClaimKeys: ["approval"], limitationLocalizationKeys: ["survey.limit"]),
            reportProjection: .init(projectionID: "report", projectionVersion: "1",
                                   headingLocalizationKey: "survey.report.heading",
                                   emptyValueLocalizationKey: "survey.report.empty",
                                   sectionIDs: ["section"], includedFactIDs: ["fact"]),
            localizationReleaseSHA256: digest("f"), revision: 1,
            mutationID: try mutation(slot + 20), authoredBy: try actor(slot + 30), authoredAt: base
        )
        let workflow = try WorkflowDefinitionV1(
            workflowID: "c51.schedule.workflow", entryNodeID: "start", declaredFieldIDs: [], nodes: [
                try .init(nodeID: "start", kind: .section, localizationKey: "c51.start", outgoingNodeIDs: ["end"]),
                try .init(nodeID: "end", kind: .terminal, localizationKey: "c51.end", outgoingNodeIDs: [])
            ]
        )
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(), workflow: workflow
        )
        let packageRelease = try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(draft)
        ).release
        let recurrence = ScheduleRecurrenceV1.fixedCalendar(
            .init(cadence: .daily, interval: 1, anchor: anchor())
        )
        return try .init(
            scheduleDefinitionID: id(slot), releaseID: id(slot + 1), workspaceID: workspace(),
            occurrenceIdentityNamespaceID: id(slot + 2), action: .create, lifecycleState: .active,
            recurrence: recurrence, timeBasis: try timeBasis(),
            startsAtUTC: base.addingTimeInterval(-86_400), generationHorizonDays: 30,
            maximumGeneratedOccurrences: maximum, readyLeadSeconds: 3_600,
            overdueGraceSeconds: 7_200,
            subject: .init(kind: .asset, subjectID: id(50), revision: 1, ownerAssetID: nil),
            workDefinition: try .init(kind: .roundSession, definition: survey, packageRelease: packageRelease),
            revision: 1, mutationID: try mutation(slot + 40),
            authoredBy: try actor(slot + 50), authoredAt: base
        )
    }

    static func advancedScheduleDefinition(
        _ slot: Int, recurrence: AdvancedRecurrenceRuleV1,
        calendar: ExceptionCalendarReleaseV1, maximum: Int = 64
    ) throws -> ScheduleDefinitionReleaseV1 {
        let base = try scheduleDefinition(slot, maximum: maximum)
        let configuration = AdvancedScheduleConfigurationV1(
            recurrence: recurrence, calendarRelease: calendar.reference,
            businessDayAdjustmentPolicy: .nextIncludedDay
        )
        let advancedTimeBasis = try FrozenScheduleTimeBasisV1(
            ianaTimeZoneIdentifier: base.timeBasis.ianaTimeZoneIdentifier,
            timeZoneRuleSetVersion: base.timeBasis.timeZoneRuleSetVersion,
            timeZoneRuleSetSHA256: base.timeBasis.timeZoneRuleSetSHA256,
            ambiguousTimePolicy: base.timeBasis.ambiguousTimePolicy,
            nonexistentTimePolicy: base.timeBasis.nonexistentTimePolicy,
            calendarBasisID: calendar.calendarID.uuidString.lowercased(),
            calendarBasisRevision: calendar.revision,
            calendarBasisSHA256: calendar.releaseSHA256
        )
        return try .init(
            scheduleDefinitionID: base.scheduleDefinitionID,
            releaseID: base.releaseID, workspaceID: base.workspaceID,
            occurrenceIdentityNamespaceID: base.occurrenceIdentityNamespaceID,
            action: base.action, lifecycleState: base.lifecycleState,
            recurrence: .advanced(configuration), timeBasis: advancedTimeBasis,
            startsAtUTC: base.startsAtUTC, endsAtUTC: base.endsAtUTC,
            generationHorizonDays: 400,
            maximumGeneratedOccurrences: base.maximumGeneratedOccurrences,
            readyLeadSeconds: base.readyLeadSeconds,
            overdueGraceSeconds: base.overdueGraceSeconds,
            subject: base.subject, workDefinition: base.workDefinition,
            assignee: base.assignee, revision: base.revision,
            mutationID: base.mutationID, authoredBy: base.authoredBy,
            authoredAt: base.authoredAt
        )
    }

    static func calendar(
        slot: Int = 200,
        zone: String = "America/New_York",
        effectiveStartsOn: String = "2025-01-01",
        effectiveEndsOn: String = "2025-12-31",
        excludedDates: [ScheduleLocalDateV1] = [],
        excludedRanges: [ScheduleLocalDateRangeV1] = [],
        includedOverrideDates: [ScheduleLocalDateV1] = [],
        baseIncludedWeekdays: [ScheduleWeekdayV1] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    ) throws -> ExceptionCalendarReleaseV1 {
        try .init(
            workspaceID: workspace(), calendarID: id(slot), releaseID: id(slot + 1), name: "C51 calendar",
            ianaTimeZoneIdentifier: zone,
            effectiveRange: try range(effectiveStartsOn, effectiveEndsOn),
            baseIncludedWeekdays: baseIncludedWeekdays,
            excludedDates: excludedDates, excludedRanges: excludedRanges,
            includedOverrideDates: includedOverrideDates,
            revision: 1, mutationID: try mutation(slot + 2),
            authoredBy: try actor(slot + 3), authoredAt: base
        )
    }

    static func resolvedBasis(
        date: String, time: String = "09:00:00", schedule: ScheduleDefinitionReleaseV1,
        resolved: Date? = base, disposition: LocalTimeDispositionV1 = .unambiguous,
        offset: Int? = -14_400, adjustment: String? = nil
    ) throws -> ResolvedOccurrenceBasisV1 {
        let value = ResolvedOccurrenceBasisV1(
            nominalLocalDate: date, nominalLocalTime: time, resolvedAtUTC: resolved,
            utcOffsetSeconds: resolved == nil ? nil : offset, disposition: disposition,
            timeBasisSHA256: try schedule.timeBasis.canonicalSHA256(),
            adjustmentProvenanceSHA256: adjustment
        )
        try value.validate()
        return value
    }

    static func scheduleBasis(
        nominalDate: String, effectiveDate: String?, calendar: ExceptionCalendarReleaseV1,
        timeBasis: FrozenScheduleTimeBasisV1 = try! C51ScheduleTestSupport.timeBasis(),
        reason: ScheduleBasisAdjustmentReasonV1 = .none,
        sourceOverride: String? = nil, predecessor: String? = nil
    ) throws -> OccurrenceScheduleBasisV2 {
        try TimeContextRule.freezeScheduleBasisV2(
            nominalDate: try date(nominalDate),
            effectiveDate: effectiveDate.map { try! date($0) },
            nominalWindow: anchor(),
            effectiveWindow: effectiveDate == nil ? nil : anchor(),
            calendarRelease: calendar.reference,
            timeBasis: timeBasis,
            adjustmentReason: reason,
            sourceOverrideEventSHA256: sourceOverride,
            predecessorBasisSHA256: predecessor
        )
    }

    static func override(
        schedule: ScheduleDefinitionReleaseReferenceV1,
        targetDate: String, occurrenceID: OccurrenceIDV1? = nil,
        scope: ScheduleOverrideScopeV1, kind: ScheduleOccurrenceOverrideKindV1,
        effectiveRange: ScheduleLocalDateRangeV1,
        replacementDate: String? = nil, replacementHour: Int = 10,
        slot: Int, expectedFrontier: String = digest("f"), revision: UInt64 = 1,
        supersedes: UUID? = nil, predecessor: String? = nil
    ) throws -> ScheduleOverrideEventV1 {
        let targetDateValue = try date(targetDate)
        let target: ScheduleOverrideTargetV1 = occurrenceID.map {
            .occurrence($0, nominalDate: targetDateValue)
        } ?? .nominalDate(targetDateValue)
        return try .init(
            eventID: id(slot), workspaceID: schedule.workspaceID, scheduleRelease: schedule,
            target: target, scope: scope, kind: kind, effectiveRange: effectiveRange,
            replacementDate: replacementDate.map { try! date($0) },
            replacementWindow: kind == .skip ? nil : anchor(hour: replacementHour),
            reasonCode: "C51_TEST_OVERRIDE", expectedScheduleRevision: schedule.revision,
            expectedOverrideFrontierSHA256: expectedFrontier, supersedesEventID: supersedes,
            predecessorEventSHA256: predecessor, revision: revision,
            mutationID: try mutation(slot + 1000), recordedBy: try actor(slot + 1100), recordedAt: base
        )
    }

    static func occurrence(
        schedule: ScheduleDefinitionReleaseV1, basis: ResolvedOccurrenceBasisV1
    ) throws -> OccurrenceIDV1 {
        try .init(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            nominalKey: basis.nominalKey
        )
    }

    static func historyEvent(
        schedule: ScheduleDefinitionReleaseV1, occurrenceID: OccurrenceIDV1,
        basis: ResolvedOccurrenceBasisV1, action: OccurrenceHistoryActionV1,
        predecessor: OccurrenceHistoryEventV1? = nil, exception: ScheduleExceptionV1? = nil,
        work: ScheduledWorkInstanceReferenceV1? = nil, slot: Int
    ) throws -> OccurrenceHistoryEventV1 {
        try .init(
            eventID: id(slot), workspaceID: workspace(), occurrenceID: occurrenceID,
            scheduleRelease: .init(schedule), action: action,
            nominalBasis: basis, effectiveBasis: basis, exception: exception,
            workInstance: work,
            completedAt: action == .complete ? base.addingTimeInterval(60) : nil,
            predecessor: predecessor, revision: (predecessor?.revision ?? 0) + 1,
            mutationID: try mutation(slot + 2000), recordedBy: try actor(slot + 2100), recordedAt: base
        )
    }

    static func addingDays(_ value: Int, to source: ScheduleLocalDateV1) throws -> ScheduleLocalDateV1 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: source.year, month: source.month, day: source.day))!
        let result = calendar.date(byAdding: .day, value: value, to: date)!
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        return try .init(year: components.year!, month: components.month!, day: components.day!)
    }
}

private struct C51Resolver: ScheduleCalendarResolvingV1 {
    let values: [OccurrenceGenerationCandidateV1]

    func candidates(
        definition: ScheduleDefinitionReleaseV1,
        window: OccurrenceGenerationWindowV1,
        completionHistory: [OccurrenceHistoryEventV1]
    ) throws -> [OccurrenceGenerationCandidateV1] {
        values
    }
}

private struct C51ScheduleCorpus: Decodable {
    let cardID: String
    let schema: String
    let schemaVersion: Int
    let evidenceIDs: [String]
    let recurrenceKinds: [String]
    let dstCases: [String]
    let monthBoundaryDates: [String]
    let weekdayOrdinals: [String]
    let calendarDispositions: [String]
    let overrideScopes: [String]
    let overrideKinds: [String]
    let precedenceLevels: [String]
    let immutableHistoryStates: [String]
    let bounds: C51ScheduleBounds
    let forbiddenCapabilities: [String]
    let statusFlags: C51ScheduleStatusFlags
}

private struct C51ScheduleBounds: Decodable {
    let lookaheadDays: Int
    let reconciliationBackfillDays: Int
    let maximumGeneratedPerSchedule: Int
    let maximumActiveUpcomingPerWorkspace: Int
}

private struct C51ScheduleStatusFlags: Decodable {
    let acceptance: Bool
    let adoption: Bool
    let hosted: Bool
    let native: Bool
    let release: Bool
}

final class V9_58ScheduleExceptionCalendarTests: XCTestCase {
    private func corpus() throws -> C51ScheduleCorpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C51ScheduleExceptionCalendarCorpusV1",
                withExtension: "json", subdirectory: "Fixtures/V22/Scheduling"
            ) ?? bundle.url(forResource: "V22P03C51ScheduleExceptionCalendarCorpusV1", withExtension: "json")
        )
        return try JSONDecoder().decode(C51ScheduleCorpus.self, from: Data(contentsOf: url))
    }

    func testV23P03C51G01GrammarDSTLeapMonthAndNthLastWeekdayCorpus() throws {
        let corpus = try corpus()
        XCTAssertEqual(corpus.cardID, "V23-P03-C51")
        XCTAssertEqual(corpus.schema, "V22P03C51ScheduleExceptionCalendarCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.recurrenceKinds, ["DAILY", "WEEKLY", "MONTHLY_DAY", "MONTHLY_WEEKDAY", "YEARLY", "COMPLETION_RELATIVE"])
        XCTAssertEqual(corpus.dstCases, ["SPRING_NONEXISTENT_GAP", "FALL_AMBIGUOUS_FOLD"])
        XCTAssertEqual(corpus.weekdayOrdinals, ScheduleWeekdayOrdinalV1.allCases.map(\.rawValue))

        let rules: [AdvancedRecurrenceRuleV1] = [
            .daily(interval: 1),
            .weekly(interval: 2, weekdays: [.monday, .wednesday, .friday]),
            .monthlyDay(interval: 1, day: 31, missingDayPolicy: .lastValidDay),
            .monthlyWeekday(interval: 1, ordinal: .last, weekday: .friday),
            .yearly(interval: 1, month: 2, day: 29, missingDayPolicy: .skipWithReason),
            .completionRelative(interval: 1, unit: .months, gapPolicy: .pauseChain)
        ]
        try rules.forEach { try $0.validate() }
        XCTAssertThrowsError(try AdvancedRecurrenceRuleV1.weekly(interval: 1, weekdays: [.friday, .monday]).validate())
        XCTAssertThrowsError(try AdvancedRecurrenceRuleV1.daily(interval: 0).validate())
        XCTAssertThrowsError(try AdvancedRecurrenceRuleV1.yearly(interval: 11, month: 1, day: 1, missingDayPolicy: .skipWithReason).validate())

        XCTAssertNoThrow(try C51ScheduleTestSupport.date("2024-02-29"))
        XCTAssertThrowsError(try C51ScheduleTestSupport.date("2023-02-29"))
        for value in corpus.monthBoundaryDates {
            XCTAssertNoThrow(try C51ScheduleTestSupport.date(value))
        }

        let spring = try C51ScheduleTestSupport.timeBasis(nonexistent: .shiftForwardByGap)
        let springResolution = try TimeContextRule.resolveScheduleCivilTime(
            date: try C51ScheduleTestSupport.date("2027-03-14"),
            window: C51ScheduleTestSupport.anchor(hour: 2, minute: 30), timeBasis: spring
        )
        XCTAssertEqual(springResolution.disposition, .nonexistentGap)
        XCTAssertNotNil(springResolution.resolvedAtUTC)

        let gapSkip = try C51ScheduleTestSupport.timeBasis(nonexistent: .skipOccurrence)
        let skippedGap = try TimeContextRule.resolveScheduleCivilTime(
            date: try C51ScheduleTestSupport.date("2027-03-14"),
            window: C51ScheduleTestSupport.anchor(hour: 2, minute: 30), timeBasis: gapSkip
        )
        XCTAssertEqual(skippedGap.disposition, .nonexistentGap)
        XCTAssertNil(skippedGap.resolvedAtUTC)

        let earlier = try C51ScheduleTestSupport.timeBasis(ambiguous: .earlierOffset)
        let later = try C51ScheduleTestSupport.timeBasis(ambiguous: .laterOffset)
        let earlierResolution = try TimeContextRule.resolveScheduleCivilTime(
            date: try C51ScheduleTestSupport.date("2027-11-07"),
            window: C51ScheduleTestSupport.anchor(hour: 1, minute: 30), timeBasis: earlier
        )
        let laterResolution = try TimeContextRule.resolveScheduleCivilTime(
            date: try C51ScheduleTestSupport.date("2027-11-07"),
            window: C51ScheduleTestSupport.anchor(hour: 1, minute: 30), timeBasis: later
        )
        XCTAssertEqual(earlierResolution.disposition, .ambiguousFold)
        XCTAssertEqual(laterResolution.disposition, .ambiguousFold)
        XCTAssertNotEqual(earlierResolution.resolvedAtUTC, laterResolution.resolvedAtUTC)

        let invalidZone = try C51ScheduleTestSupport.timeBasis(zone: "C51/Invalid")
        XCTAssertThrowsError(try TimeContextRule.resolveScheduleCivilTime(
            date: try C51ScheduleTestSupport.date("2027-03-14"),
            window: C51ScheduleTestSupport.anchor(hour: 9), timeBasis: invalidZone
        )) { error in
            XCTAssertEqual(error as? TimeContextRuleError, .invalidTimeZoneID)
        }
    }

    func testV23P03C51G01ProductionAdvancedResolverCoversEveryRuleAndBudgetGuards() throws {
        let calendar = try C51ScheduleTestSupport.calendar(
            slot: 900, effectiveStartsOn: "2027-01-01", effectiveEndsOn: "2028-12-31"
        )
        let rules: [(AdvancedRecurrenceRuleV1, Double)] = [
            (.daily(interval: 1), 86_400),
            (.weekly(interval: 1, weekdays: [.monday, .wednesday, .friday]), 14 * 86_400),
            (.monthlyDay(interval: 1, day: 31, missingDayPolicy: .lastValidDay), 120 * 86_400),
            (.monthlyWeekday(interval: 1, ordinal: .last, weekday: .friday), 120 * 86_400),
            (.yearly(interval: 1, month: 2, day: 29, missingDayPolicy: .skipWithReason), 400 * 86_400),
            (.completionRelative(interval: 1, unit: .months, gapPolicy: .pauseChain), 86_400)
        ]
        for (index, item) in rules.enumerated() {
            let release = try C51ScheduleTestSupport.advancedScheduleDefinition(
                910 + index, recurrence: item.0, calendar: calendar
            )
            let binding = try AdvancedScheduleReleaseBindingV1(release)
            XCTAssertEqual(binding.recurrence, item.0)
            XCTAssertEqual(binding.calendarRelease, calendar.reference)
            let resolver = AdvancedScheduleCalendarResolverV1(
                binding: binding, calendarRelease: calendar, overrideEvents: []
            )
            let timeBasisDigest = try release.timeBasis.canonicalSHA256()
            let window = OccurrenceGenerationWindowV1(
                startsAtUTC: release.startsAtUTC,
                endsAtUTC: release.startsAtUTC.addingTimeInterval(item.1),
                maximumOccurrences: 64
            )
            let candidates = try resolver.candidates(
                definition: release, window: window, completionHistory: []
            )
            XCTAssertFalse(candidates.isEmpty, "no production candidate for \(item.0)")
            XCTAssertTrue(candidates.allSatisfy { $0.predecessorOccurrenceID == nil })
            XCTAssertTrue(candidates.allSatisfy { $0.completionEventSHA256 == nil })
            XCTAssertTrue(candidates.allSatisfy { $0.nominalBasis.timeBasisSHA256 == timeBasisDigest })
        }

        let manualRelease = try C51ScheduleTestSupport.advancedScheduleDefinition(
            920,
            recurrence: .monthlyDay(interval: 1, day: 31, missingDayPolicy: .requireManualResolution),
            calendar: calendar
        )
        let manualBinding = try AdvancedScheduleReleaseBindingV1(manualRelease)
        let manualResolver = AdvancedScheduleCalendarResolverV1(
            binding: manualBinding, calendarRelease: calendar, overrideEvents: []
        )
        let aprilWindow = OccurrenceGenerationWindowV1(
            startsAtUTC: manualRelease.startsAtUTC,
            endsAtUTC: manualRelease.startsAtUTC.addingTimeInterval(60 * 86_400),
            maximumOccurrences: 64
        )
        XCTAssertThrowsError(try manualResolver.candidates(
            definition: manualRelease, window: aprilWindow, completionHistory: []
        ))

        let workspaceBoundResolver = AdvancedScheduleCalendarResolverV1(
            binding: manualBinding, calendarRelease: calendar, overrideEvents: [],
            activeUpcomingWorkspaceCount: 10_001
        )
        XCTAssertThrowsError(try workspaceBoundResolver.candidates(
            definition: manualRelease, window: .init(
                startsAtUTC: manualRelease.startsAtUTC,
                endsAtUTC: manualRelease.startsAtUTC.addingTimeInterval(86_400),
                maximumOccurrences: 64
            ), completionHistory: []
        ))
    }

    func testV23P03C51A01CalendarPrecedenceEveryOverrideScopeKindAndConflict() throws {
        let corpus = try corpus()
        XCTAssertEqual(corpus.calendarDispositions, [
            "INCLUDED_OVERRIDE", "EXCLUDED_DATE", "EXCLUDED_RANGE",
            "BASE_INCLUDED_WEEKDAY", "BASE_EXCLUDED_WEEKDAY"
        ])
        XCTAssertEqual(corpus.overrideScopes, ScheduleOverrideScopeV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.overrideKinds, ScheduleOccurrenceOverrideKindV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.precedenceLevels, [
            "BASE_RECURRENCE", "EXCEPTION_CALENDAR", "EFFECTIVE_SERIES_OVERRIDE",
            "EXPLICIT_OCCURRENCE_OVERRIDE"
        ])

        let jan06 = try C51ScheduleTestSupport.date("2025-01-06")
        let jan07 = try C51ScheduleTestSupport.date("2025-01-07")
        let jan08 = try C51ScheduleTestSupport.date("2025-01-08")
        let jan11 = try C51ScheduleTestSupport.date("2025-01-11")
        let jan12 = try C51ScheduleTestSupport.date("2025-01-12")
        let jan13 = try C51ScheduleTestSupport.date("2025-01-13")
        let excludedRange = try C51ScheduleTestSupport.range("2025-01-07", "2025-01-08")
        let calendar = try C51ScheduleTestSupport.calendar(
            excludedDates: [jan06],
            excludedRanges: [excludedRange],
            includedOverrideDates: [jan06, jan12]
        )
        XCTAssertEqual(try calendar.disposition(on: jan06), .includedOverride)
        XCTAssertEqual(try calendar.disposition(on: jan07), .excludedRange)
        XCTAssertEqual(try calendar.disposition(on: jan08), .excludedRange)
        XCTAssertEqual(try calendar.disposition(on: jan12), .includedOverride)
        XCTAssertEqual(try calendar.disposition(on: jan13), .baseIncludedWeekday)
        XCTAssertEqual(try calendar.disposition(on: jan11), .baseExcludedWeekday)
        XCTAssertTrue(try calendar.isIncluded(jan06))
        XCTAssertFalse(try calendar.isIncluded(jan07))
        XCTAssertThrowsError(try calendar.disposition(on: try C51ScheduleTestSupport.date("2026-01-01")))

        let schedule = C51ScheduleTestSupport.scheduleReference()
        let nominalWindow = C51ScheduleTestSupport.anchor()
        let occurrenceID = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            nominalKey: "2025-01-06T09:00:00"
        )
        let excludedResolution = try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan07, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .nextIncludedDay, events: []
        )
        XCTAssertEqual(excludedResolution.level, .exceptionCalendar)
        XCTAssertEqual(excludedResolution.effectiveDate, try C51ScheduleTestSupport.date("2025-01-09"))
        XCTAssertEqual(excludedResolution.adjustmentReason, .nextIncludedDay)
        let previousResolution = try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan07, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .previousIncludedDay, events: []
        )
        XCTAssertEqual(previousResolution.effectiveDate, jan06)
        let manualResolution = try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan07, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .requireManualResolution, events: []
        )
        XCTAssertTrue(manualResolution.requiresManualResolution)
        XCTAssertNil(manualResolution.effectiveDate)
        let skippedResolution = try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan07, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .skipWithReason, events: []
        )
        XCTAssertNil(skippedResolution.effectiveDate)
        XCTAssertEqual(skippedResolution.adjustmentReason, .explicitSkip)

        let effectiveRange = try C51ScheduleTestSupport.range("2025-01-01", "2025-12-31")
        let exactSkip = try C51ScheduleTestSupport.override(
            schedule: schedule, targetDate: "2025-01-06", occurrenceID: occurrenceID,
            scope: .thisOccurrence, kind: .skip, effectiveRange: effectiveRange, slot: 220
        )
        let seriesMove = try C51ScheduleTestSupport.override(
            schedule: schedule, targetDate: "2025-01-01", scope: .thisAndFuture, kind: .move,
            effectiveRange: effectiveRange, replacementDate: "2025-01-15", replacementHour: 10, slot: 221
        )
        let allSeriesMove = try C51ScheduleTestSupport.override(
            schedule: schedule, targetDate: "2025-01-01", scope: .entireSeries, kind: .move,
            effectiveRange: effectiveRange, replacementDate: "2025-01-20", replacementHour: 11, slot: 222
        )
        let addOne = try C51ScheduleTestSupport.override(
            schedule: schedule, targetDate: "2025-01-12", occurrenceID: occurrenceID,
            scope: .thisOccurrence, kind: .addOne, effectiveRange: effectiveRange,
            replacementDate: "2025-01-16", replacementHour: 8, slot: 223
        )
        try [exactSkip, seriesMove, allSeriesMove, addOne].forEach { try $0.validate() }
        XCTAssertEqual(exactSkip.target.occurrenceID, occurrenceID)
        XCTAssertEqual(seriesMove.scope, .thisAndFuture)
        XCTAssertEqual(allSeriesMove.scope, .entireSeries)
        XCTAssertEqual(addOne.kind, .addOne)

        let exact = try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan06, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .nextIncludedDay, events: [exactSkip, seriesMove]
        )
        XCTAssertEqual(exact.level, .explicitOccurrenceOverride)
        XCTAssertEqual(exact.event?.eventID, exactSkip.eventID)
        XCTAssertNil(exact.effectiveDate)

        let series = try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan13, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .nextIncludedDay, events: [seriesMove]
        )
        XCTAssertEqual(series.level, .effectiveSeriesOverride)
        XCTAssertEqual(series.effectiveDate, try C51ScheduleTestSupport.date("2025-01-15"))
        XCTAssertEqual(series.adjustmentReason, .explicitMove)

        let entireSeries = try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan13, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .nextIncludedDay, events: [allSeriesMove]
        )
        XCTAssertEqual(entireSeries.level, .effectiveSeriesOverride)
        XCTAssertEqual(entireSeries.effectiveDate, try C51ScheduleTestSupport.date("2025-01-20"))

        let addResolution = try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan12, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .nextIncludedDay, events: [addOne]
        )
        XCTAssertEqual(addResolution.level, .explicitOccurrenceOverride)
        XCTAssertEqual(addResolution.effectiveDate, try C51ScheduleTestSupport.date("2025-01-16"))
        XCTAssertEqual(addResolution.adjustmentReason, .none)

        let conflict = try C51ScheduleTestSupport.override(
            schedule: schedule, targetDate: "2025-01-06", occurrenceID: occurrenceID,
            scope: .thisOccurrence, kind: .skip, effectiveRange: effectiveRange, slot: 224
        )
        XCTAssertThrowsError(try ScheduleOverridePrecedenceV1.resolve(
            occurrenceID: occurrenceID, nominalDate: jan06, nominalWindow: nominalWindow,
            calendar: calendar, adjustmentPolicy: .nextIncludedDay, events: [exactSkip, conflict]
        ))

        let successor = try C51ScheduleTestSupport.override(
            schedule: schedule, targetDate: "2025-01-01", scope: .thisAndFuture, kind: .move,
            effectiveRange: effectiveRange, replacementDate: "2025-01-16", replacementHour: 12,
            slot: 225, revision: 2, supersedes: seriesMove.eventID,
            predecessor: seriesMove.eventSHA256
        )
        let active = try ScheduleOverridePrecedenceV1.activeEvents([seriesMove, successor])
        XCTAssertEqual(active, [successor])
    }

    func testV23P03C51H01BoundsStaleFrontierDigestZoneRangeRollbackAndCorruptionFailClosed() throws {
        let corpus = try corpus()
        XCTAssertEqual(corpus.bounds.lookaheadDays, AdvancedScheduleGenerationBudgetV1.lookaheadDays)
        XCTAssertEqual(corpus.bounds.reconciliationBackfillDays, AdvancedScheduleGenerationBudgetV1.reconciliationBackfillDays)
        XCTAssertEqual(corpus.bounds.maximumGeneratedPerSchedule, AdvancedScheduleGenerationBudgetV1.maximumGeneratedPerSchedule)
        XCTAssertEqual(corpus.bounds.maximumActiveUpcomingPerWorkspace, AdvancedScheduleGenerationBudgetV1.maximumActiveUpcomingPerWorkspace)

        let budget = try AdvancedScheduleGenerationBudgetV1()
        XCTAssertNoThrow(try budget.validate(generatedCount: 512, activeUpcomingWorkspaceCount: 10_000))
        XCTAssertThrowsError(try budget.validate(generatedCount: 513, activeUpcomingWorkspaceCount: 0))
        XCTAssertThrowsError(try budget.validate(generatedCount: 0, activeUpcomingWorkspaceCount: 10_001))
        XCTAssertThrowsError(try AdvancedScheduleGenerationBudgetV1(lookaheadDays: 399))
        XCTAssertThrowsError(try AdvancedScheduleGenerationBudgetV1(maximumGeneratedPerSchedule: 511))

        let inRangeDate = try C51ScheduleTestSupport.date("2025-01-01")
        let invalidRange = ScheduleLocalDateRangeV1(
            startsOn: try C51ScheduleTestSupport.date("2025-02-02"),
            endsOn: try C51ScheduleTestSupport.date("2025-02-01")
        )
        XCTAssertThrowsError(try invalidRange.validate())
        XCTAssertThrowsError(try C51ScheduleTestSupport.calendar(zone: "C51/NoSuchZone"))
        XCTAssertThrowsError(try C51ScheduleTestSupport.calendar(
            excludedDates: Array(repeating: inRangeDate, count: 367)
        ))
        let oneDayRange = try C51ScheduleTestSupport.range("2025-01-01", "2025-01-01")
        XCTAssertThrowsError(try C51ScheduleTestSupport.calendar(
            excludedRanges: Array(repeating: oneDayRange, count: 33)
        ))
        XCTAssertThrowsError(try C51ScheduleTestSupport.calendar(
            includedOverrideDates: Array(repeating: inRangeDate, count: 367)
        ))

        let calendar = try C51ScheduleTestSupport.calendar(slot: 300)
        let schedule = C51ScheduleTestSupport.scheduleReference(300)
        let evaluatedRange = try C51ScheduleTestSupport.range("2025-01-01", "2025-12-31")
        let frontier = try ScheduleChangeFrontierV1(
            workspaceID: C51ScheduleTestSupport.workspace(), scheduleRelease: schedule,
            calendarRelease: calendar.reference, overrideEvents: [],
            occurrenceClosureSHA256: C51ScheduleTestSupport.digest("g"),
            evaluatedRange: evaluatedRange, budget: budget
        )
        XCTAssertNoThrow(try frontier.validate())
        XCTAssertThrowsError(try ScheduleChangeFrontierV1(
            workspaceID: C51ScheduleTestSupport.workspace(2), scheduleRelease: schedule,
            calendarRelease: calendar.reference, overrideEvents: [],
            occurrenceClosureSHA256: C51ScheduleTestSupport.digest("g"),
            evaluatedRange: evaluatedRange, budget: budget
        ))

        let exactOccurrence = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            nominalKey: "2025-01-01T09:00:00"
        )
        let staleOverride = try C51ScheduleTestSupport.override(
            schedule: schedule, targetDate: "2025-01-01", occurrenceID: exactOccurrence,
            scope: .thisOccurrence, kind: .skip, effectiveRange: evaluatedRange,
            slot: 301, expectedFrontier: C51ScheduleTestSupport.digest("s")
        )
        XCTAssertThrowsError(try ScheduleOverridePrecedenceV1.validateExpectedFrontier(
            staleOverride, against: []
        ))
        XCTAssertThrowsError(try calendar.disposition(on: try C51ScheduleTestSupport.date("2026-01-01")))

        let rollback = try ScheduleProjectionEvaluationV1(
            evaluatedAt: C51ScheduleTestSupport.base,
            priorEvaluationAt: C51ScheduleTestSupport.base.addingTimeInterval(60)
        )
        XCTAssertEqual(rollback.disposition, .rollbackDetected)
        XCTAssertFalse(rollback.permitsReminderReconciliation)

        let hostileOffset = ResolvedOccurrenceBasisV1(
            nominalLocalDate: "2025-11-02", nominalLocalTime: "01:30:00",
            resolvedAtUTC: C51ScheduleTestSupport.base, utcOffsetSeconds: Int.min,
            disposition: .ambiguousFold, timeBasisSHA256: C51ScheduleTestSupport.digest("z"),
            adjustmentProvenanceSHA256: nil
        )
        XCTAssertThrowsError(try hostileOffset.validate())
        XCTAssertThrowsError(try OccurrenceIDV1(rawValue: "not-a-digest").validate())

        var corruptCalendarBytes = try ScheduleCanonicalCodecV1.data(calendar)
        corruptCalendarBytes[0] ^= 0xff
        XCTAssertThrowsError(try ScheduleCanonicalCodecV1.decode(
            ExceptionCalendarReleaseV1.self, from: corruptCalendarBytes
        ))
        var corruptFrontierBytes = try ScheduleCanonicalCodecV1.data(frontier)
        corruptFrontierBytes[corruptFrontierBytes.index(before: corruptFrontierBytes.endIndex)] ^= 0xff
        XCTAssertThrowsError(try ScheduleCanonicalCodecV1.decode(
            ScheduleChangeFrontierV1.self, from: corruptFrontierBytes
        ))
    }

    func testV23P03C51H02StableLineageAndImmutableStartedCompletedMissedHistory() throws {
        let schedule = try C51ScheduleTestSupport.scheduleDefinition(400)
        let calendar = try C51ScheduleTestSupport.calendar(slot: 410)
        let basisA = try C51ScheduleTestSupport.scheduleBasis(
            nominalDate: "2025-02-28", effectiveDate: "2025-02-28", calendar: calendar,
            timeBasis: try C51ScheduleTestSupport.timeBasis()
        )
        let basisB = try C51ScheduleTestSupport.scheduleBasis(
            nominalDate: "2025-03-01", effectiveDate: "2025-02-28", calendar: calendar,
            timeBasis: try C51ScheduleTestSupport.timeBasis()
        )
        XCTAssertNotEqual(basisA.basisSHA256, basisB.basisSHA256)
        XCTAssertNotEqual(basisA.nominalDate, basisB.nominalDate)
        XCTAssertEqual(basisA.effectiveDate, basisB.effectiveDate)

        let basisC = try C51ScheduleTestSupport.scheduleBasis(
            nominalDate: "2025-03-02", effectiveDate: "2025-03-02", calendar: calendar,
            timeBasis: try C51ScheduleTestSupport.timeBasis()
        )
        let firstID = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            nominalKey: "2025-02-28T09:00:00"
        )
        let secondID = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            nominalKey: "2025-03-01T09:00:00"
        )
        let thirdID = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            nominalKey: "2025-03-02T09:00:00"
        )
        XCTAssertNotEqual(firstID, secondID)

        let inputs: [ScheduleChangeOccurrenceInputV1] = [
            .init(occurrenceID: firstID, state: .started, basis: basisA),
            .init(occurrenceID: secondID, state: .completed, basis: basisB),
            .init(occurrenceID: thirdID, state: .missed, basis: basisC)
        ]
        let unchangedEffects = [basisA, basisB, basisC].enumerated().map { index, basis in
            let id = [firstID, secondID, thirdID][index]
            return ScheduleChangeEffectV1(
                occurrenceID: id, successorOccurrenceID: nil, disposition: .unchanged,
                priorBasisSHA256: basis.basisSHA256, resultingBasis: basis,
                sourceOverrideEventSHA256: nil
            )
        }
        XCTAssertNoThrow(try ScheduleOccurrenceLineageV1.validateHistoryImmutability(
            inputs: inputs, effects: unchangedEffects
        ))
        let moved = ScheduleChangeEffectV1(
            occurrenceID: firstID, successorOccurrenceID: secondID, disposition: .moved,
            priorBasisSHA256: basisA.basisSHA256, resultingBasis: basisB,
            sourceOverrideEventSHA256: C51ScheduleTestSupport.digest("m")
        )
        XCTAssertThrowsError(try ScheduleOccurrenceLineageV1.validateHistoryImmutability(
            inputs: inputs, effects: [moved, unchangedEffects[1], unchangedEffects[2]]
        ))

        let addOne = try C51ScheduleTestSupport.override(
            schedule: try .init(schedule), targetDate: "2025-03-02", occurrenceID: thirdID,
            scope: .thisOccurrence, kind: .addOne,
            effectiveRange: try C51ScheduleTestSupport.range("2025-01-01", "2025-12-31"),
            replacementDate: "2025-03-04", replacementHour: 8, slot: 411
        )
        let addedID = try ScheduleOccurrenceLineageV1.addedOccurrenceID(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            overrideEvent: addOne
        )
        XCTAssertEqual(addedID, try ScheduleOccurrenceLineageV1.addedOccurrenceID(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            overrideEvent: addOne
        ))
        XCTAssertNotEqual(addedID, thirdID)

        let resolvedA = try C51ScheduleTestSupport.resolvedBasis(
            date: "2025-02-28", schedule: schedule
        )
        let resolvedB = try C51ScheduleTestSupport.resolvedBasis(
            date: "2025-03-02", schedule: schedule
        )
        let historyID = try C51ScheduleTestSupport.occurrence(schedule: schedule, basis: resolvedA)
        let missedID = try C51ScheduleTestSupport.occurrence(schedule: schedule, basis: resolvedB)
        let generated = try C51ScheduleTestSupport.historyEvent(
            schedule: schedule, occurrenceID: historyID, basis: resolvedA,
            action: .generated, slot: 420
        )
        let work = ScheduledWorkInstanceReferenceV1.roundSession(
            sessionID: C51ScheduleTestSupport.id(421), revision: 1,
            sessionSHA256: C51ScheduleTestSupport.digest("w")
        )
        let started = try C51ScheduleTestSupport.historyEvent(
            schedule: schedule, occurrenceID: historyID, basis: resolvedA,
            action: .start, predecessor: generated, work: work, slot: 422
        )
        let completed = try C51ScheduleTestSupport.historyEvent(
            schedule: schedule, occurrenceID: historyID, basis: resolvedA,
            action: .complete, predecessor: started, work: work, slot: 423
        )
        let missedGenerated = try C51ScheduleTestSupport.historyEvent(
            schedule: schedule, occurrenceID: missedID, basis: resolvedB,
            action: .generated, slot: 424
        )
        let missedException = try ScheduleExceptionV1(
            exceptionID: C51ScheduleTestSupport.id(425), kind: .missed,
            priorEffectiveBasisSHA256: try ScheduleCanonicalCodecV1.sha256(resolvedB),
            reasonCode: "C51_MISSED", recordedBy: try C51ScheduleTestSupport.actor(426),
            recordedAt: C51ScheduleTestSupport.base
        )
        let missed = try C51ScheduleTestSupport.historyEvent(
            schedule: schedule, occurrenceID: missedID, basis: resolvedB,
            action: .applyException, predecessor: missedGenerated,
            exception: missedException, slot: 427
        )
        XCTAssertNoThrow(try ScheduleLifecycleClosureV1(
            definitions: [schedule], history: [generated, started, completed, missedGenerated, missed]
        ).validate())
        XCTAssertEqual(completed.action, .complete)
        XCTAssertEqual(missed.exception?.kind, .missed)
    }

    func testV23P03C51I01EffectBeforeReceiptPartialGenerationRetryAndBackupReplay() throws {
        let schedule = try C51ScheduleTestSupport.scheduleDefinition(500)
        let scheduleReference = try ScheduleDefinitionReleaseReferenceV1(schedule)
        let calendar = try C51ScheduleTestSupport.calendar(slot: 510)
        let effectiveRange = try C51ScheduleTestSupport.range("2025-01-01", "2025-12-31")
        let basis = try C51ScheduleTestSupport.scheduleBasis(
            nominalDate: "2025-02-28", effectiveDate: "2025-02-28", calendar: calendar
        )
        let occurrenceID = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
            nominalKey: "2025-02-28T09:00:00"
        )
        let proposed = try C51ScheduleTestSupport.override(
            schedule: scheduleReference, targetDate: "2025-02-28", occurrenceID: occurrenceID,
            scope: .thisOccurrence, kind: .move, effectiveRange: effectiveRange,
            replacementDate: "2025-03-03", replacementHour: 10, slot: 511
        )
        let frontier = try ScheduleChangeFrontierV1(
            workspaceID: schedule.workspaceID, scheduleRelease: scheduleReference,
            calendarRelease: calendar.reference, overrideEvents: [proposed],
            occurrenceClosureSHA256: C51ScheduleTestSupport.digest("h"),
            evaluatedRange: effectiveRange, budget: try .init()
        )
        let effect = ScheduleChangeEffectV1(
            occurrenceID: occurrenceID, successorOccurrenceID: nil, disposition: .moved,
            priorBasisSHA256: basis.basisSHA256, resultingBasis: basis,
            sourceOverrideEventSHA256: proposed.eventSHA256
        )
        let preview = try ScheduleChangePreviewV1(
            frontier: frontier, proposedOverride: proposed, effects: [effect]
        )
        XCTAssertNoThrow(try preview.validate())
        let receipt = try ScheduleChangeReceiptV1(
            preview: preview, mutationID: try C51ScheduleTestSupport.mutation(512),
            committedOverride: proposed.reference,
            canonicalMutationReceiptSHA256: C51ScheduleTestSupport.digest("i"),
            committedAt: C51ScheduleTestSupport.base
        )
        XCTAssertNoThrow(try receipt.validate(preview: preview))
        XCTAssertEqual(
            try ScheduleCanonicalCodecV1.decode(
                ScheduleChangeReceiptV1.self, from: ScheduleCanonicalCodecV1.data(receipt)
            ), receipt
        )

        var corruptReceiptBytes = try ScheduleCanonicalCodecV1.data(receipt)
        corruptReceiptBytes[corruptReceiptBytes.index(before: corruptReceiptBytes.endIndex)] ^= 0xff
        XCTAssertThrowsError(try ScheduleCanonicalCodecV1.decode(
            ScheduleChangeReceiptV1.self, from: corruptReceiptBytes
        ))

        let candidateBasis = try C51ScheduleTestSupport.resolvedBasis(
            date: "2025-02-28", schedule: schedule, resolved: C51ScheduleTestSupport.base
        )
        let candidateID = try C51ScheduleTestSupport.occurrence(schedule: schedule, basis: candidateBasis)
        let candidate = OccurrenceGenerationCandidateV1(
            occurrenceID: candidateID, nominalBasis: candidateBasis, effectiveBasis: candidateBasis
        )
        let generationWindow = OccurrenceGenerationWindowV1(
            startsAtUTC: schedule.startsAtUTC,
            endsAtUTC: schedule.startsAtUTC.addingTimeInterval(172_800), maximumOccurrences: 8
        )
        let firstPlan = try ScheduleOccurrenceGeneratorV1.generate(
            definition: schedule, history: [], completionHistory: [], window: generationWindow,
            resolver: C51Resolver(values: [candidate])
        )
        XCTAssertEqual(firstPlan.candidates.map(\.occurrenceID), [candidateID])
        let generated = try C51ScheduleTestSupport.historyEvent(
            schedule: schedule, occurrenceID: candidateID, basis: candidateBasis,
            action: .generated, slot: 513
        )
        let retryPlan = try ScheduleOccurrenceGeneratorV1.generate(
            definition: schedule, history: [generated], completionHistory: [], window: generationWindow,
            resolver: C51Resolver(values: [candidate])
        )
        XCTAssertTrue(retryPlan.candidates.isEmpty)
        XCTAssertEqual(retryPlan.existingOccurrenceIDs, [candidateID])
        XCTAssertThrowsError(try ScheduleOccurrenceGeneratorV1.generate(
            definition: schedule, history: [], completionHistory: [], window: generationWindow,
            resolver: C51Resolver(values: [candidate, candidate])
        ))

        let records = [
            V27BackupScheduleRecordV1(
                kind: .scheduleRelease, id: schedule.releaseID,
                workspaceID: schedule.workspaceID.rawValue, revision: schedule.revision,
                canonicalData: try ScheduleCanonicalCodecV1.data(schedule)
            ),
            V27BackupScheduleRecordV1(
                kind: .occurrenceHistory, id: generated.eventID,
                workspaceID: schedule.workspaceID.rawValue, revision: generated.revision,
                canonicalData: try ScheduleCanonicalCodecV1.data(generated)
            ),
            V27BackupScheduleRecordV1(
                kind: .exceptionCalendarRelease, id: calendar.releaseID,
                workspaceID: calendar.workspaceID.rawValue, revision: calendar.revision,
                canonicalData: try ScheduleCanonicalCodecV1.data(calendar)
            ),
            V27BackupScheduleRecordV1(
                kind: .scheduleOverrideEvent, id: proposed.eventID,
                workspaceID: proposed.workspaceID.rawValue, revision: proposed.revision,
                canonicalData: try ScheduleCanonicalCodecV1.data(proposed)
            )
        ].sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        XCTAssertTrue(C51ScheduleBackupClosureV1.validatesEnvelope(records))
        XCTAssertFalse(C51ScheduleBackupClosureV1.validatesEnvelope(Array(records.reversed())))
        XCTAssertFalse(C51ScheduleBackupClosureV1.validatesEnvelope(records + [records[0]]))
        XCTAssertEqual(
            try ScheduleCanonicalCodecV1.decode(
                ExceptionCalendarReleaseV1.self, from: records[0].kind == .exceptionCalendarRelease
                    ? records[0].canonicalData : records[1].canonicalData
            ), calendar
        )
        XCTAssertTrue(C51ScheduleBackupClosureV1.preservedV27RecordBytes)
        XCTAssertFalse(C51ScheduleBackupClosureV1.derivedDueReminderAndPreviewStateIsArchived)
        XCTAssertFalse(C51ScheduleBackupClosureV1.sourceScheduleAutomaticallyActiveAfterCloneOrFork)
    }

    func testV23P03C51R01RestoreRebuildsDerivedSearchReportReminderAndAllDaysWithoutForbiddenTruth() throws {
        let corpus = try corpus()
        XCTAssertEqual(corpus.forbiddenCapabilities, [
            "EVENTKIT_PERMISSION", "NETWORK_CALENDAR_FEED",
            "NOTIFICATION_DELIVERY_AS_SCHEDULE_TRUTH"
        ])
        XCTAssertFalse(corpus.statusFlags.acceptance)
        XCTAssertFalse(corpus.statusFlags.adoption)
        XCTAssertFalse(corpus.statusFlags.hosted)
        XCTAssertFalse(corpus.statusFlags.native)
        XCTAssertFalse(corpus.statusFlags.release)

        let schedule = try C51ScheduleTestSupport.scheduleDefinition(700)
        let basis = try C51ScheduleTestSupport.resolvedBasis(
            date: "2025-02-28", schedule: schedule,
            resolved: C51ScheduleTestSupport.base.addingTimeInterval(3_600)
        )
        let occurrenceID = try C51ScheduleTestSupport.occurrence(schedule: schedule, basis: basis)
        let generated = try C51ScheduleTestSupport.historyEvent(
            schedule: schedule, occurrenceID: occurrenceID, basis: basis,
            action: .generated, slot: 701
        )
        let queue = try DueQueueProjectionV1(
            workspaceID: schedule.workspaceID, evaluatedAt: C51ScheduleTestSupport.base,
            definitions: [schedule], history: [generated]
        )
        XCTAssertEqual(queue.entries.map(\.state), [.ready])
        let reminder = try ReminderProjectionV1(dueQueue: queue, localizationKey: "schedule.reminder")
        let rebuiltReminder = try ReminderProjectionV1(dueQueue: queue, localizationKey: "schedule.reminder")
        XCTAssertEqual(rebuiltReminder, reminder)
        XCTAssertEqual(reminder.dueQueueSHA256, queue.projectionSHA256)

        let report = try ScheduleReportProjectionV1(
            definition: schedule, dueQueue: queue, history: [generated], reminder: reminder
        )
        let rebuiltReport = try ScheduleReportProjectionV1(
            definition: schedule, dueQueue: queue, history: [generated], reminder: rebuiltReminder
        )
        XCTAssertEqual(report, rebuiltReport)
        XCTAssertNoThrow(try ScheduleReportProjectionPolicyV1.validate(report))
        XCTAssertTrue(ScheduleReportProjectionPolicyV1.metadataOnly)
        XCTAssertTrue(ScheduleReportProjectionPolicyV1.derivedOnly)
        XCTAssertTrue(ScheduleReportProjectionPolicyV1.historicalDisplayIsFrozen)
        XCTAssertFalse(ScheduleReportProjectionPolicyV1.notificationDeliveryIsTruth)

        let reportOccurrence = try XCTUnwrap(report.occurrences.first)
        let searchRecord = try ScheduleOccurrenceSearchRecordV1(
            projection: report, occurrence: reportOccurrence
        )
        let rebuiltSearchRecord = try ScheduleOccurrenceSearchRecordV1(
            projection: rebuiltReport, occurrence: try XCTUnwrap(rebuiltReport.occurrences.first)
        )
        XCTAssertEqual(searchRecord, rebuiltSearchRecord)
        XCTAssertNoThrow(try ScheduleOccurrenceSearchProjectionPolicyV1.validate(searchRecord))
        XCTAssertEqual(
            try SearchCoordinatorV1.searchScheduleOccurrenceMetadata(
                query: "ready", records: [searchRecord]
            ), [searchRecord]
        )

        let restoredQueue = try ScheduleCanonicalCodecV1.decode(
            DueQueueProjectionV1.self, from: ScheduleCanonicalCodecV1.data(queue)
        )
        let restoredReminder = try ScheduleCanonicalCodecV1.decode(
            ReminderProjectionV1.self, from: ScheduleCanonicalCodecV1.data(reminder)
        )
        let restoredReport = try ScheduleCanonicalCodecV1.decode(
            ScheduleReportProjectionV1.self, from: ScheduleCanonicalCodecV1.data(report)
        )
        XCTAssertEqual(restoredQueue, queue)
        XCTAssertEqual(restoredReminder, reminder)
        XCTAssertEqual(restoredReport, report)
        XCTAssertEqual(restoredQueue.entries, restoredQueue.entries)
        XCTAssertEqual(restoredReport.occurrences.map(\.occurrenceID), [occurrenceID])

        let allDays = AllDaysCompatibilityCalendarV1.reference(workspaceID: schedule.workspaceID)
        XCTAssertEqual(AllDaysCompatibilityCalendarV1.includedWeekdays, ScheduleWeekdayV1.allCases.sorted())
        XCTAssertFalse(AllDaysCompatibilityCalendarV1.changesExistingOccurrenceIDsOrDates)
        XCTAssertNoThrow(try AllDaysCompatibilityCalendarV1.validate(reference: allDays))
        XCTAssertFalse(AllDaysCompatibilityCalendarV1.requiresPersistedReleaseRow)

        XCTAssertTrue(ScheduleGenerationJobBoundaryV1.outputIsDerivedPlan)
        XCTAssertTrue(ScheduleLocalJobBoundaryV1.derivedProjectionsAreRebuildable)
        XCTAssertTrue(ScheduleGenerationRunnerBoundaryV1.retriesAreIdempotent)
        XCTAssertFalse(ScheduleNotificationCapabilityBoundaryV1.permissionIsCanonicalScheduleTruth)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
        XCTAssertFalse(SurveySessionScheduleBoundaryV1.dueProjectionMayCreateSession)
        XCTAssertFalse(CheckRunnerScheduleCoordinatorBoundaryV1.checkRunnerMayAutoStartOccurrence)
        XCTAssertFalse(CameraScheduleBoundaryV1.cameraResolutionMayStartOccurrence)
        XCTAssertFalse(AssetSemanticScheduleBoundaryV1.assetSemanticsInferDueState)
        XCTAssertFalse(C51ScheduleBackupClosureV1.derivedDueReminderAndPreviewStateIsArchived)
    }
}

extension V9_58ScheduleExceptionCalendarTests {
    func testV23P03C34RouteConformanceReceiptUsesFourRootsAndNoMutationAuthority() throws {
        let receipt = RouteConformanceReceiptV1(
            registry: try RouteRegistryV1(), evidenceKind: .golden,
            observedShellCount: 1, observedParserCount: 1,
            observedMutationAuthorityCount: 0
        )
        try receipt.validate()
        XCTAssertEqual(receipt.roots, AppRootV1.frozenOrder)
        XCTAssertEqual(receipt.roots.count, 4)
        XCTAssertEqual(receipt.mutationAuthorityCount, 0)
    }
}

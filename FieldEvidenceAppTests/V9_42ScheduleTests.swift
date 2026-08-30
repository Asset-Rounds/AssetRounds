import Foundation
import XCTest
@testable import FieldEvidenceApp

private enum C28ScheduleTestSupport {
    static let base = Date(timeIntervalSince1970: 1_804_000_000)
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "c2800000-0000-4000-8000-%012x", n))! }
    static func digest(_ c: Character = "a") -> String { String(repeating: c, count: 64) }
    static func workspace() -> WorkspaceID { .init(rawValue: id(1)) }
    static func mutation(_ n: Int) throws -> MutationIDV1 { try .init(rawValue: id(n)) }
    static func actor(_ n: Int, responsibility: ResponsibilityKindV1 = .recordedBy) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(actorReferenceID: id(n), workspaceID: workspace(), displayName: "C28 local actor")
        return try .init(snapshotID: id(n + 1), workspaceID: workspace(), actor: reference,
                         responsibility: responsibility, displayNameAtTime: reference.displayName, capturedAt: base)
    }
    static func definition() throws -> SurveyDefinitionReleaseV1 {
        let fact = FactDefinitionV1(factID: "fact", labelLocalizationKey: "survey.fact.label",
                                    accessibilityLabelLocalizationKey: "survey.fact.accessibility",
                                    helpLocalizationKey: "survey.fact.help", required: true,
                                    defaultValue: nil, visibility: nil,
                                    payload: .shortText(.init(maximumUTF8Bytes: 64)))
        return try .init(releaseID: id(10), workspaceID: workspace(), definitionID: id(11), activityKind: .survey,
                         ownerPackageID: ShippingIlluminatedSignAdapterV1.packageID,
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
                         localizationReleaseSHA256: digest("b"), revision: 1, mutationID: try mutation(20),
                         authoredBy: try actor(30), authoredAt: base)
    }
    static func package() throws -> InspectionPackageReleaseV1 {
        let workflow = try WorkflowDefinitionV1(workflowID: "c28.schedule.workflow", entryNodeID: "start",
                                                 declaredFieldIDs: [], nodes: [
            try .init(nodeID: "start", kind: .section, localizationKey: "c28.start", outgoingNodeIDs: ["end"]),
            try .init(nodeID: "end", kind: .terminal, localizationKey: "c28.end", outgoingNodeIDs: [])
        ])
        let draft = try InspectionPackageReleaseV1.makeDraft(package: ShippingIlluminatedSignAdapterV1.inspectionPackage(), workflow: workflow)
        return try InspectionPackageReleasePublisherV1.publish(InspectionPackageReleasePublisherV1.test(draft)).release
    }
    static func timeBasis() throws -> FrozenScheduleTimeBasisV1 {
        try .init(ianaTimeZoneIdentifier: "America/New_York", timeZoneRuleSetVersion: "2026a",
                  timeZoneRuleSetSHA256: digest("c"), ambiguousTimePolicy: .earlierOffset,
                  nonexistentTimePolicy: .shiftForwardByGap, calendarBasisSHA256: digest("d"))
    }
    static func release(recurrence: ScheduleRecurrenceV1, slot: Int = 100,
                        maximum: Int = 8) throws -> ScheduleDefinitionReleaseV1 {
        let definition = try definition(), package = try package()
        return try .init(scheduleDefinitionID: id(slot), releaseID: id(slot + 1), workspaceID: workspace(),
                         occurrenceIdentityNamespaceID: id(slot + 2), action: .create, lifecycleState: .active,
                         recurrence: recurrence, timeBasis: try timeBasis(),
                         startsAtUTC: base.addingTimeInterval(-86_400), generationHorizonDays: 30,
                         maximumGeneratedOccurrences: maximum, readyLeadSeconds: 3_600, overdueGraceSeconds: 7_200,
                         subject: .init(kind: .asset, subjectID: id(50), revision: 1, ownerAssetID: nil),
                         workDefinition: try .init(kind: .roundSession, definition: definition, packageRelease: package),
                         revision: 1, mutationID: try mutation(slot + 10), authoredBy: try actor(slot + 20), authoredAt: base)
    }
    static func basis(date: String, time: String, resolved: Date?, disposition: LocalTimeDispositionV1,
                      schedule: ScheduleDefinitionReleaseV1, adjustment: String? = nil) throws -> ResolvedOccurrenceBasisV1 {
        let value = ResolvedOccurrenceBasisV1(nominalLocalDate: date, nominalLocalTime: time, resolvedAtUTC: resolved,
                                              utcOffsetSeconds: resolved == nil ? nil : -14_400, disposition: disposition,
                                              timeBasisSHA256: try schedule.timeBasis.canonicalSHA256(),
                                              adjustmentProvenanceSHA256: adjustment)
        try value.validate(); return value
    }
    static func event(schedule: ScheduleDefinitionReleaseV1, occurrence: OccurrenceIDV1,
                      basis: ResolvedOccurrenceBasisV1, action: OccurrenceHistoryActionV1,
                      predecessor: OccurrenceHistoryEventV1? = nil, slot: Int,
                      work: ScheduledWorkInstanceReferenceV1? = nil) throws -> OccurrenceHistoryEventV1 {
        try .init(eventID: id(slot), workspaceID: workspace(), occurrenceID: occurrence,
                  scheduleRelease: .init(schedule), action: action, nominalBasis: basis, effectiveBasis: basis,
                  workInstance: work, completedAt: action == .complete ? base.addingTimeInterval(60) : nil,
                  predecessor: predecessor, revision: (predecessor?.revision ?? 0) + 1,
                  mutationID: try mutation(slot + 2_000), recordedBy: try actor(slot + 3_000), recordedAt: base)
    }
}

private struct C28Resolver: ScheduleCalendarResolvingV1 {
    let values: [OccurrenceGenerationCandidateV1]
    func candidates(definition: ScheduleDefinitionReleaseV1, window: OccurrenceGenerationWindowV1,
                    completionHistory: [OccurrenceHistoryEventV1]) throws -> [OccurrenceGenerationCandidateV1] { values }
}

private struct C28ScheduleCorpus: Decodable {
    let schema: String
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let persistentKindLifecycleModelCount: Int
    let durableFamilies: [String]
    let occurrenceStates: [String]
    let compatibility: C28ScheduleCompatibility
}

private struct C28ScheduleCompatibility: Decodable {
    let legacyFixedCalendarAndCompletionRelativeRemainCanonical: Bool
    let advancedRecurrenceIsAdditive: Bool
    let allDaysCompatibilityPreservesOccurrenceIdentityAndDate: Bool
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
}

final class V9_42ScheduleTests: XCTestCase {
    func testV23P03C28G01DeterministicScheduleAndOccurrenceIdentitySurviveDSTAndTravel() throws {
        let bundle = Bundle(for: Self.self)
        let corpusURL = try XCTUnwrap(bundle.url(forResource: "V22P03C28ScheduleCorpusV1", withExtension: "json",
                                                 subdirectory: "Fixtures/V22/Schedules") ??
                                      bundle.url(forResource: "V22P03C28ScheduleCorpusV1", withExtension: "json"))
        let corpus = try JSONDecoder().decode(C28ScheduleCorpus.self, from: Data(contentsOf: corpusURL))
        XCTAssertEqual(corpus.schema, "V22P03C28ScheduleCorpusV1")
        XCTAssertEqual(corpus.persistentSchemaVersion, 27)
        XCTAssertEqual(corpus.recordsSchemaVersion, 26)
        XCTAssertEqual(corpus.persistentKindLifecycleModelCount, 96)
        XCTAssertEqual(corpus.durableFamilies, ["ScheduleDefinitionReleaseV1", "OccurrenceHistoryEventV1"])
        XCTAssertEqual(corpus.occurrenceStates, OccurrenceStateV1.allCases.map(\.rawValue))
        let rule = FixedCalendarScheduleRuleV1(cadence: .daily, interval: 1,
                                               anchor: .init(year: nil, month: nil, day: nil, weekday: nil,
                                                             weekdayOrdinal: nil, hour: 2, minute: 30, second: 0))
        let release = try C28ScheduleTestSupport.release(recurrence: .fixedCalendar(rule))
        let shifted = try C28ScheduleTestSupport.basis(date: "2027-03-14", time: "02:30:00",
                                                       resolved: C28ScheduleTestSupport.base.addingTimeInterval(3_600),
                                                       disposition: .nonexistentGap, schedule: release,
                                                       adjustment: C28ScheduleTestSupport.digest("e"))
        let occurrence = try OccurrenceIDV1(scheduleDefinitionID: release.scheduleDefinitionID,
                                             identityNamespaceID: release.occurrenceIdentityNamespaceID,
                                             nominalKey: shifted.nominalKey)
        let candidate = OccurrenceGenerationCandidateV1(occurrenceID: occurrence, nominalBasis: shifted, effectiveBasis: shifted)
        let window = OccurrenceGenerationWindowV1(startsAtUTC: release.startsAtUTC,
                                                   endsAtUTC: release.startsAtUTC.addingTimeInterval(172_800), maximumOccurrences: 8)
        let left = try ScheduleOccurrenceGeneratorV1.generate(definition: release, history: [], completionHistory: [],
                                                               window: window, resolver: C28Resolver(values: [candidate]))
        let right = try ScheduleOccurrenceGeneratorV1.generate(definition: release, history: [], completionHistory: [],
                                                                window: window, resolver: C28Resolver(values: [candidate]))
        XCTAssertEqual(left, right)
        XCTAssertEqual(left.candidates.first?.effectiveBasis.disposition, .nonexistentGap)
        XCTAssertEqual(left.scheduleRelease.timeBasisSHA256, try release.timeBasis.canonicalSHA256())
        XCTAssertEqual(release.timeBasis.ianaTimeZoneIdentifier, "America/New_York")
    }

    func testV23P03C28A01FixedAndCompletionRelativePoliciesRemainDistinct() throws {
        let anchor = ScheduleLocalAnchorV1(year: nil, month: nil, day: nil, weekday: nil,
                                           weekdayOrdinal: nil, hour: 9, minute: 0, second: 0)
        let fixed = try C28ScheduleTestSupport.release(recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)), slot: 200)
        let relative = try C28ScheduleTestSupport.release(recurrence: .completionRelative(.init(interval: 1, unit: .calendarDays, firstAnchor: anchor)), slot: 300)
        let basis = try C28ScheduleTestSupport.basis(date: "2027-03-15", time: "09:00:00", resolved: C28ScheduleTestSupport.base,
                                                     disposition: .unambiguous, schedule: fixed)
        let fixedID = try OccurrenceIDV1(scheduleDefinitionID: fixed.scheduleDefinitionID,
                                         identityNamespaceID: fixed.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey)
        let relativeID = try OccurrenceIDV1(scheduleDefinitionID: relative.scheduleDefinitionID,
                                            identityNamespaceID: relative.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey,
                                            predecessorOccurrenceID: fixedID, completionEventSHA256: C28ScheduleTestSupport.digest("f"))
        XCTAssertNotEqual(fixedID, relativeID)
        if case .fixedCalendar = fixed.recurrence {} else { XCTFail("fixed policy changed") }
        if case .completionRelative = relative.recurrence {} else { XCTFail("completion policy changed") }

        let relativeBasis = try C28ScheduleTestSupport.basis(date: "2027-03-15", time: "09:00:00",
                                                             resolved: C28ScheduleTestSupport.base,
                                                             disposition: .unambiguous, schedule: relative)
        let firstID = try OccurrenceIDV1(scheduleDefinitionID: relative.scheduleDefinitionID,
                                         identityNamespaceID: relative.occurrenceIdentityNamespaceID,
                                         nominalKey: relativeBasis.nominalKey)
        let generated = try C28ScheduleTestSupport.event(schedule: relative, occurrence: firstID,
                                                          basis: relativeBasis, action: .generated, slot: 320)
        let work = ScheduledWorkInstanceReferenceV1.roundSession(sessionID: C28ScheduleTestSupport.id(321), revision: 1,
                                                                 sessionSHA256: C28ScheduleTestSupport.digest("2"))
        let started = try C28ScheduleTestSupport.event(schedule: relative, occurrence: firstID,
                                                        basis: relativeBasis, action: .start,
                                                        predecessor: generated, slot: 322, work: work)
        let completed = try C28ScheduleTestSupport.event(schedule: relative, occurrence: firstID,
                                                          basis: relativeBasis, action: .complete,
                                                          predecessor: started, slot: 323, work: work)
        let nextBasis = try C28ScheduleTestSupport.basis(date: "2027-03-16", time: "09:00:00",
                                                         resolved: C28ScheduleTestSupport.base.addingTimeInterval(86_400),
                                                         disposition: .unambiguous, schedule: relative)
        let nextID = try OccurrenceIDV1(scheduleDefinitionID: relative.scheduleDefinitionID,
                                        identityNamespaceID: relative.occurrenceIdentityNamespaceID,
                                        nominalKey: nextBasis.nominalKey, predecessorOccurrenceID: firstID,
                                        completionEventSHA256: completed.eventSHA256)
        let candidate = OccurrenceGenerationCandidateV1(occurrenceID: nextID, nominalBasis: nextBasis,
                                                         effectiveBasis: nextBasis, predecessorOccurrenceID: firstID,
                                                         completionEventSHA256: completed.eventSHA256)
        let plan = try ScheduleOccurrenceGeneratorV1.generate(definition: relative,
                                                               history: [generated, started, completed],
                                                               completionHistory: [completed],
                                                               window: .init(startsAtUTC: relative.startsAtUTC,
                                                                             endsAtUTC: relative.startsAtUTC.addingTimeInterval(172_800),
                                                                             maximumOccurrences: 8),
                                                               resolver: C28Resolver(values: [candidate]))
        XCTAssertEqual(plan.candidates.map(\.occurrenceID), [nextID])
    }

    func testV23P03C28H01AmbiguousNonexistentRollbackDuplicateAndLateCompletionFailClosed() throws {
        let evaluation = try ScheduleProjectionEvaluationV1(evaluatedAt: C28ScheduleTestSupport.base,
                                                             priorEvaluationAt: C28ScheduleTestSupport.base.addingTimeInterval(60))
        XCTAssertEqual(evaluation.disposition, .rollbackDetected)
        XCTAssertFalse(evaluation.permitsReminderReconciliation)
        XCTAssertThrowsError(try OccurrenceIDV1(rawValue: "not-a-digest").validate())
        let hostileOffset = ResolvedOccurrenceBasisV1(nominalLocalDate: "2027-11-07", nominalLocalTime: "01:30:00",
                                                       resolvedAtUTC: C28ScheduleTestSupport.base,
                                                       utcOffsetSeconds: Int.min, disposition: .ambiguousFold,
                                                       timeBasisSHA256: C28ScheduleTestSupport.digest("8"),
                                                       adjustmentProvenanceSHA256: nil)
        XCTAssertThrowsError(try hostileOffset.validate())
        let anchor = ScheduleLocalAnchorV1(year: nil, month: nil, day: nil, weekday: nil,
                                           weekdayOrdinal: nil, hour: 9, minute: 0, second: 0)
        let release = try C28ScheduleTestSupport.release(recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)), slot: 400)
        let basis = try C28ScheduleTestSupport.basis(date: "2027-03-15", time: "09:00:00", resolved: C28ScheduleTestSupport.base,
                                                     disposition: .unambiguous, schedule: release)
        let occurrence = try OccurrenceIDV1(scheduleDefinitionID: release.scheduleDefinitionID,
                                             identityNamespaceID: release.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey)
        let generated = try C28ScheduleTestSupport.event(schedule: release, occurrence: occurrence, basis: basis,
                                                          action: .generated, slot: 500)
        XCTAssertEqual(generated.scheduleRelease.workspaceID, release.workspaceID)
        XCTAssertEqual(generated.scheduleRelease.occurrenceIdentityNamespaceID, release.occurrenceIdentityNamespaceID)
        XCTAssertThrowsError(try C28ScheduleTestSupport.event(schedule: release,
                                                               occurrence: .init(rawValue: C28ScheduleTestSupport.digest("7")),
                                                               basis: basis, action: .generated, slot: 501))
        let ambiguous = ResolvedOccurrenceBasisV1(nominalLocalDate: "2027-11-07", nominalLocalTime: "01:30:00",
                                                  resolvedAtUTC: C28ScheduleTestSupport.base, utcOffsetSeconds: -14_400,
                                                  disposition: .ambiguousFold,
                                                  timeBasisSHA256: try release.timeBasis.canonicalSHA256(),
                                                  adjustmentProvenanceSHA256: C28ScheduleTestSupport.digest("9"))
        XCTAssertNoThrow(try ambiguous.validate())
        XCTAssertEqual(release.timeBasis.ambiguousTimePolicy, .earlierOffset)
        let retiredException = try ScheduleExceptionV1(exceptionID: C28ScheduleTestSupport.id(502),
                                                        kind: .retiredForRuleChange,
                                                        priorEffectiveBasisSHA256: ScheduleCanonicalCodecV1.sha256(generated.effectiveBasis),
                                                        replacementOccurrenceID: try OccurrenceIDV1(
                                                            scheduleDefinitionID: release.scheduleDefinitionID,
                                                            identityNamespaceID: C28ScheduleTestSupport.id(503),
                                                            nominalKey: basis.nominalKey),
                                                        reasonCode: "RULE_REPLACED",
                                                        recordedBy: C28ScheduleTestSupport.actor(504),
                                                        recordedAt: C28ScheduleTestSupport.base)
        let retired = try OccurrenceHistoryEventV1(eventID: C28ScheduleTestSupport.id(505),
                                                    workspaceID: release.workspaceID, occurrenceID: occurrence,
                                                    scheduleRelease: .init(release), action: .applyException,
                                                    nominalBasis: basis, effectiveBasis: basis, exception: retiredException,
                                                    predecessor: generated, revision: 2,
                                                    mutationID: C28ScheduleTestSupport.mutation(506),
                                                    recordedBy: C28ScheduleTestSupport.actor(507),
                                                    recordedAt: C28ScheduleTestSupport.base)
        let retiredQueue = try DueQueueProjectionV1(workspaceID: release.workspaceID,
                                                     evaluatedAt: C28ScheduleTestSupport.base.addingTimeInterval(100_000),
                                                     definitions: [release], history: [generated, retired])
        XCTAssertEqual(retiredQueue.entries.map(\.state), [.cancelled])
        XCTAssertTrue(try ReminderProjectionV1(dueQueue: retiredQueue,
                                                localizationKey: "schedule.reminder").reminders.isEmpty)
        XCTAssertThrowsError(try ScheduleLifecycleClosureV1(definitions: [release], history: [generated, generated]).validate())
        XCTAssertThrowsError(try ScheduleOccurrenceGeneratorV1.generate(definition: release, history: [generated],
                                                                         completionHistory: [generated],
                                                                         window: .init(startsAtUTC: release.startsAtUTC,
                                                                                       endsAtUTC: release.startsAtUTC.addingTimeInterval(86_400),
                                                                                       maximumOccurrences: 8), resolver: C28Resolver(values: [])))
    }

    func testV23P03C28I01BoundedGenerationAndOccurrenceHistoryRetryIdempotently() throws {
        let anchor = ScheduleLocalAnchorV1(year: nil, month: nil, day: nil, weekday: nil,
                                           weekdayOrdinal: nil, hour: 9, minute: 0, second: 0)
        let release = try C28ScheduleTestSupport.release(recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)), slot: 600, maximum: 1)
        XCTAssertThrowsError(try OccurrenceGenerationWindowV1(startsAtUTC: release.startsAtUTC,
                                                               endsAtUTC: release.startsAtUTC.addingTimeInterval(86_400),
                                                               maximumOccurrences: 2).validate(definition: release))
        let basis = try C28ScheduleTestSupport.basis(date: "2027-03-15", time: "09:00:00", resolved: C28ScheduleTestSupport.base,
                                                     disposition: .unambiguous, schedule: release)
        let occurrence = try OccurrenceIDV1(scheduleDefinitionID: release.scheduleDefinitionID,
                                             identityNamespaceID: release.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey)
        let generated = try C28ScheduleTestSupport.event(schedule: release, occurrence: occurrence, basis: basis, action: .generated, slot: 700)
        let work = ScheduledWorkInstanceReferenceV1.roundSession(sessionID: C28ScheduleTestSupport.id(701), revision: 1,
                                                                 sessionSHA256: C28ScheduleTestSupport.digest("1"))
        let started = try C28ScheduleTestSupport.event(schedule: release, occurrence: occurrence, basis: basis,
                                                        action: .start, predecessor: generated, slot: 702, work: work)
        let completed = try C28ScheduleTestSupport.event(schedule: release, occurrence: occurrence, basis: basis,
                                                          action: .complete, predecessor: started, slot: 703, work: work)
        try ScheduleLifecycleClosureV1(definitions: [release], history: [generated, started, completed]).validate()
        XCTAssertThrowsError(try C28ScheduleTestSupport.event(schedule: release, occurrence: occurrence, basis: basis,
                                                               action: .start, predecessor: started, slot: 704, work: work))
        XCTAssertEqual(try ScheduleCanonicalCodecV1.data(completed), try ScheduleCanonicalCodecV1.data(completed))
    }

    func testV23P03C28R01RestoreRebuildsDueQueueAndReminderProjectionWithoutNotificationTruth() throws {
        let anchor = ScheduleLocalAnchorV1(year: nil, month: nil, day: nil, weekday: nil,
                                           weekdayOrdinal: nil, hour: 9, minute: 0, second: 0)
        let release = try C28ScheduleTestSupport.release(recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)), slot: 800)
        let basis = try C28ScheduleTestSupport.basis(date: "2027-03-15", time: "09:00:00", resolved: C28ScheduleTestSupport.base.addingTimeInterval(3_600),
                                                     disposition: .unambiguous, schedule: release)
        let occurrence = try OccurrenceIDV1(scheduleDefinitionID: release.scheduleDefinitionID,
                                             identityNamespaceID: release.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey)
        let generated = try C28ScheduleTestSupport.event(schedule: release, occurrence: occurrence, basis: basis, action: .generated, slot: 810)
        let restoredRelease = try ScheduleCanonicalCodecV1.decode(ScheduleDefinitionReleaseV1.self,
                                                                   from: ScheduleCanonicalCodecV1.data(release))
        let restoredEvent = try ScheduleCanonicalCodecV1.decode(OccurrenceHistoryEventV1.self,
                                                                 from: ScheduleCanonicalCodecV1.data(generated))
        let queue = try DueQueueProjectionV1(workspaceID: C28ScheduleTestSupport.workspace(), evaluatedAt: C28ScheduleTestSupport.base,
                                             definitions: [restoredRelease], history: [restoredEvent])
        let reminder = try ReminderProjectionV1(dueQueue: queue, localizationKey: "schedule.reminder")
        let rebuilt = try ReminderProjectionV1(dueQueue: queue, localizationKey: "schedule.reminder")
        XCTAssertEqual(queue.entries.map(\.state), [.ready])
        XCTAssertEqual(reminder.reminders.map(\.occurrenceID), [occurrence])
        XCTAssertEqual(rebuilt, reminder)
        XCTAssertTrue(ScheduleLocalJobBoundaryV1.derivedProjectionsAreRebuildable)
        XCTAssertFalse(ScheduleNotificationCapabilityBoundaryV1.permissionIsCanonicalScheduleTruth)
    }

    func testV23P03C28CompatibilityKeepsLegacyRecurrencesAndAddsAdvancedAllDaysBinding() throws {
        let bundle = Bundle(for: Self.self)
        let corpusURL = try XCTUnwrap(bundle.url(
            forResource: "V22P03C28ScheduleCorpusV1", withExtension: "json",
            subdirectory: "Fixtures/V22/Schedules"
        ) ?? bundle.url(forResource: "V22P03C28ScheduleCorpusV1", withExtension: "json"))
        let corpus = try JSONDecoder().decode(C28ScheduleCorpus.self, from: Data(contentsOf: corpusURL))
        XCTAssertTrue(corpus.compatibility.legacyFixedCalendarAndCompletionRelativeRemainCanonical)
        XCTAssertTrue(corpus.compatibility.advancedRecurrenceIsAdditive)
        XCTAssertTrue(corpus.compatibility.allDaysCompatibilityPreservesOccurrenceIdentityAndDate)
        XCTAssertEqual(corpus.compatibility.persistentSchemaVersion, corpus.persistentSchemaVersion)
        XCTAssertEqual(corpus.compatibility.recordsSchemaVersion, corpus.recordsSchemaVersion)

        let anchor = ScheduleLocalAnchorV1(year: nil, month: nil, day: nil, weekday: nil,
                                           weekdayOrdinal: nil, hour: 9, minute: 0, second: 0)
        let fixed = try C28ScheduleTestSupport.release(
            recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)), slot: 900
        )
        let relative = try C28ScheduleTestSupport.release(
            recurrence: .completionRelative(.init(interval: 1, unit: .calendarDays, firstAnchor: anchor)), slot: 901
        )
        if case .fixedCalendar = fixed.recurrence {} else { XCTFail("C28 fixed recurrence changed") }
        if case .completionRelative = relative.recurrence {} else { XCTFail("C28 relative recurrence changed") }
        XCTAssertEqual(
            try ScheduleCanonicalCodecV1.decode(
                ScheduleDefinitionReleaseV1.self, from: ScheduleCanonicalCodecV1.data(fixed)
            ), fixed
        )
        XCTAssertEqual(
            try ScheduleCanonicalCodecV1.decode(
                ScheduleDefinitionReleaseV1.self, from: ScheduleCanonicalCodecV1.data(relative)
            ), relative
        )

        let allDays = AllDaysCompatibilityCalendarV1.reference(workspaceID: fixed.workspaceID)
        let configuration = AdvancedScheduleConfigurationV1(
            recurrence: .monthlyWeekday(interval: 1, ordinal: .last, weekday: .friday),
            calendarRelease: allDays, businessDayAdjustmentPolicy: .nextIncludedDay
        )
        let allDaysTimeBasis = try FrozenScheduleTimeBasisV1(
            ianaTimeZoneIdentifier: fixed.timeBasis.ianaTimeZoneIdentifier,
            timeZoneRuleSetVersion: fixed.timeBasis.timeZoneRuleSetVersion,
            timeZoneRuleSetSHA256: fixed.timeBasis.timeZoneRuleSetSHA256,
            ambiguousTimePolicy: fixed.timeBasis.ambiguousTimePolicy,
            nonexistentTimePolicy: fixed.timeBasis.nonexistentTimePolicy,
            calendarBasisID: allDays.calendarID.uuidString.lowercased(),
            calendarBasisRevision: allDays.revision,
            calendarBasisSHA256: allDays.releaseSHA256
        )
        let advanced = try ScheduleDefinitionReleaseV1(
            scheduleDefinitionID: fixed.scheduleDefinitionID, releaseID: fixed.releaseID,
            workspaceID: fixed.workspaceID, occurrenceIdentityNamespaceID: fixed.occurrenceIdentityNamespaceID,
            action: fixed.action, lifecycleState: fixed.lifecycleState, recurrence: .advanced(configuration),
            timeBasis: allDaysTimeBasis, startsAtUTC: fixed.startsAtUTC, endsAtUTC: fixed.endsAtUTC,
            generationHorizonDays: fixed.generationHorizonDays,
            maximumGeneratedOccurrences: fixed.maximumGeneratedOccurrences,
            readyLeadSeconds: fixed.readyLeadSeconds, overdueGraceSeconds: fixed.overdueGraceSeconds,
            subject: fixed.subject, workDefinition: fixed.workDefinition, assignee: fixed.assignee,
            revision: fixed.revision, mutationID: fixed.mutationID,
            authoredBy: fixed.authoredBy, authoredAt: fixed.authoredAt
        )
        let binding = try AdvancedScheduleReleaseBindingV1(advanced)
        XCTAssertEqual(binding.calendarRelease, allDays)
        XCTAssertEqual(binding.recurrence, configuration.recurrence)
        XCTAssertFalse(AllDaysCompatibilityCalendarV1.changesExistingOccurrenceIDsOrDates)
        XCTAssertNoThrow(try AllDaysCompatibilityCalendarV1.validate(reference: allDays))
    }
}

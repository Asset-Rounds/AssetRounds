import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C38Corpus: Decodable {
    struct Pattern: Decodable { let kind: String; let minimumInterval: Int; let maximumInterval: Int }
    struct Golden: Decodable {
        let patterns: [Pattern]; let overrideKinds: [String]
        let deterministicOccurrenceIdentity: Bool; let dueHistoryAppendOnly: Bool
        let reminderHistoryAppendOnly: Bool
    }
    struct Alternate: Decodable { let calendarCases: [String]; let scopes: [String] }
    struct Persistence: Decodable {
        let addsDurableFamily: Bool; let changesSchema: Bool; let createsRecurrenceEngine: Bool
    }
    struct Claims: Decodable {
        let nativeCalendarIntegrated: Bool; let nativeReminderIntegrated: Bool
        let hostedCalendarIntegrated: Bool; let hostedReminderIntegrated: Bool
        let providerAdopted: Bool; let providerAccepted: Bool; let providerReleased: Bool
        let networkRequired: Bool; let accountRequired: Bool; let entitlementRequired: Bool
    }
    let schema: String; let schemaVersion: Int; let cardID: String
    let testOnly: Bool; let synthetic: Bool; let containsCustomerData: Bool; let containsSecrets: Bool
    let evidenceIDs: [String]; let golden: Golden; let alternate: Alternate
    let hostileCases: [String]; let interruptionCases: [String]; let recoveryCases: [String]
    let persistence: Persistence; let claims: Claims
}

private enum C38 {
    static let now = Date(timeIntervalSince1970: 1_804_000_000)
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "C3800000-0000-4000-8000-%012x", value))!
    }
    static func digest(_ value: Character) -> String { String(repeating: String(value), count: 64) }
    static let workspace = WorkspaceID(rawValue: id(1))
    static func mutation(_ value: Int) throws -> MutationIDV1 { try .init(rawValue: id(value)) }
    static func fixture() throws -> C38Corpus {
        let bundle = Bundle(for: V9_101AdvancedRecurrenceWorkflowTests.self)
        let url = bundle.url(
            forResource: "V23P04C38AdvancedRecurrenceWorkflowCorpusV1",
            withExtension: "json", subdirectory: "Fixtures/V23/Scheduling"
        ) ?? bundle.url(forResource: "V23P04C38AdvancedRecurrenceWorkflowCorpusV1", withExtension: "json")
        guard let url else { throw ScheduleFailureV1.invalidValue }
        return try JSONDecoder().decode(C38Corpus.self, from: Data(contentsOf: url))
    }
    static func actor(_ slot: Int = 10) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(slot), workspaceID: workspace, displayName: "C38 recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: id(slot + 1), workspaceID: workspace, actor: reference,
            responsibility: .recordedBy, displayNameAtTime: reference.displayName, capturedAt: now
        )
    }
    static func date(_ value: String) throws -> ScheduleLocalDateV1 { try .init(value) }
    static func range(_ start: String = "2025-01-01", _ end: String = "2025-12-31") throws
        -> ScheduleLocalDateRangeV1 {
        let value = ScheduleLocalDateRangeV1(startsOn: try date(start), endsOn: try date(end))
        try value.validate(); return value
    }
    static func anchor(hour: Int = 9, minute: Int = 0) -> ScheduleLocalAnchorV1 {
        .init(year: nil, month: nil, day: nil, weekday: nil, weekdayOrdinal: nil,
              hour: hour, minute: minute, second: 0)
    }
    static func timeBasis(
        ambiguous: AmbiguousLocalTimePolicyV1 = .earlierOffset,
        nonexistent: NonexistentLocalTimePolicyV1 = .shiftForwardByGap
    ) throws -> FrozenScheduleTimeBasisV1 {
        try .init(ianaTimeZoneIdentifier: "America/New_York", timeZoneRuleSetVersion: "2026a",
                  timeZoneRuleSetSHA256: digest("t"), ambiguousTimePolicy: ambiguous,
                  nonexistentTimePolicy: nonexistent, calendarBasisID: id(30).uuidString.lowercased(),
                  calendarBasisRevision: 1, calendarBasisSHA256: digest("c"))
    }
    static func calendar() throws -> ExceptionCalendarReleaseV1 {
        try .init(workspaceID: workspace, calendarID: id(30), releaseID: id(31), name: "C38 calendar",
                  ianaTimeZoneIdentifier: "America/New_York", effectiveRange: range(),
                  baseIncludedWeekdays: ScheduleWeekdayV1.allCases, excludedDates: [],
                  excludedRanges: [], includedOverrideDates: [], revision: 1,
                  mutationID: mutation(32), authoredBy: actor(33), authoredAt: now)
    }
    static func definition(
        recurrence: AdvancedRecurrenceRuleV1 = .daily(interval: 1)
    ) throws -> ScheduleDefinitionReleaseV1 {
        let calendar = try calendar()
        let fact = FactDefinitionV1(
            factID: "fact", labelLocalizationKey: "c38.fact", accessibilityLabelLocalizationKey: "c38.fact.a11y",
            helpLocalizationKey: "c38.fact.help", required: true, defaultValue: nil, visibility: nil,
            payload: .shortText(.init(maximumUTF8Bytes: 64))
        )
        let survey = try SurveyDefinitionReleaseV1(
            releaseID: id(40), workspaceID: workspace, definitionID: id(41), activityKind: .survey,
            ownerPackageID: ShippingIlluminatedSignAdapterV1.packageID,
            sections: [.init(sectionID: "section", titleLocalizationKey: "c38.section",
                             accessibilityHeadingLocalizationKey: "c38.section.a11y", ordinal: 0, facts: [fact])],
            completionRules: [.init(ruleID: "complete", expression: .allRequiredVisibleFactsAnswered,
                                    failureLocalizationKey: "c38.complete")],
            claimsProfile: .init(profileID: "claims", activityKind: .survey, allowedClaimKeys: [],
                                 forbiddenClaimKeys: ["approval"], limitationLocalizationKeys: ["c38.limit"]),
            reportProjection: .init(projectionID: "report", projectionVersion: "1",
                                    headingLocalizationKey: "c38.report", emptyValueLocalizationKey: "c38.empty",
                                    sectionIDs: ["section"], includedFactIDs: ["fact"]),
            localizationReleaseSHA256: digest("l"), revision: 1, mutationID: mutation(42),
            authoredBy: actor(43), authoredAt: now
        )
        let workflow = try WorkflowDefinitionV1(
            workflowID: "c38.workflow", entryNodeID: "start", declaredFieldIDs: [], nodes: [
                try .init(nodeID: "start", kind: .section, localizationKey: "c38.start", outgoingNodeIDs: ["end"]),
                try .init(nodeID: "end", kind: .terminal, localizationKey: "c38.end", outgoingNodeIDs: [])
            ])
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(), workflow: workflow
        )
        let package = try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(draft)
        ).release
        let configuration = AdvancedScheduleConfigurationV1(
            recurrence: recurrence, calendarRelease: calendar.reference,
            businessDayAdjustmentPolicy: .nextIncludedDay
        )
        let frozenTimeBasis = try FrozenScheduleTimeBasisV1(
            ianaTimeZoneIdentifier: calendar.ianaTimeZoneIdentifier,
            timeZoneRuleSetVersion: "2026a", timeZoneRuleSetSHA256: digest("t"),
            ambiguousTimePolicy: .earlierOffset, nonexistentTimePolicy: .shiftForwardByGap,
            calendarBasisID: calendar.calendarID.uuidString.lowercased(),
            calendarBasisRevision: calendar.revision, calendarBasisSHA256: calendar.releaseSHA256
        )
        return try ScheduleDefinitionReleaseV1(
            scheduleDefinitionID: id(50), releaseID: id(51), workspaceID: workspace,
            occurrenceIdentityNamespaceID: id(52), action: .create, lifecycleState: .active,
            recurrence: .advanced(configuration), timeBasis: frozenTimeBasis,
            startsAtUTC: Date(timeIntervalSince1970: 1_735_740_000), generationHorizonDays: 400,
            maximumGeneratedOccurrences: 64, readyLeadSeconds: 3_600, overdueGraceSeconds: 7_200,
            subject: .init(kind: .asset, subjectID: id(53), revision: 1, ownerAssetID: nil),
            workDefinition: try .init(kind: .roundSession, definition: survey, packageRelease: package),
            revision: 1, mutationID: mutation(54), authoredBy: actor(55), authoredAt: now
        )
    }
    static func basis(
        _ date: String, definition: ScheduleDefinitionReleaseV1,
        disposition: LocalTimeDispositionV1 = .unambiguous,
        resolved: Date? = now, offset: Int? = -14_400
    ) throws -> ResolvedOccurrenceBasisV1 {
        let value = ResolvedOccurrenceBasisV1(
            nominalLocalDate: date, nominalLocalTime: "09:00:00", resolvedAtUTC: resolved,
            utcOffsetSeconds: resolved == nil ? nil : offset, disposition: disposition,
            timeBasisSHA256: try definition.timeBasis.canonicalSHA256(),
            adjustmentProvenanceSHA256: disposition == .unambiguous ? nil : digest("a")
        )
        try value.validate(); return value
    }
    static func occurrence(
        _ basis: ResolvedOccurrenceBasisV1, definition: ScheduleDefinitionReleaseV1
    ) throws -> OccurrenceIDV1 {
        try .init(scheduleDefinitionID: definition.scheduleDefinitionID,
                  identityNamespaceID: definition.occurrenceIdentityNamespaceID,
                  nominalKey: basis.nominalKey)
    }
    static func event(
        definition: ScheduleDefinitionReleaseV1, basis: ResolvedOccurrenceBasisV1,
        action: OccurrenceHistoryActionV1 = .generated,
        predecessor: OccurrenceHistoryEventV1? = nil, mutationSlot: Int = 80
    ) throws -> OccurrenceHistoryEventV1 {
        try .init(eventID: id(mutationSlot), workspaceID: workspace,
                  occurrenceID: occurrence(basis, definition: definition),
                  scheduleRelease: .init(definition), action: action,
                  nominalBasis: basis, effectiveBasis: basis,
                  completedAt: action == .complete ? now : nil,
                  predecessor: predecessor, revision: (predecessor?.revision ?? 0) + 1,
                  mutationID: mutation(mutationSlot + 1), recordedBy: actor(mutationSlot + 2),
                  recordedAt: now)
    }
    static func scheduleBasis(
        _ date: String, definition: ScheduleDefinitionReleaseV1,
        calendar: ExceptionCalendarReleaseV1
    ) throws -> OccurrenceScheduleBasisV2 {
        try TimeContextRule.freezeScheduleBasisV2(
            nominalDate: self.date(date), effectiveDate: self.date(date),
            nominalWindow: anchor(), effectiveWindow: anchor(), calendarRelease: calendar.reference,
            timeBasis: definition.timeBasis, adjustmentReason: .none)
    }
    static func context(
        definition: ScheduleDefinitionReleaseV1,
        history: [OccurrenceHistoryEventV1] = [],
        previewOccurrences: [ScheduleChangeOccurrenceInputV1] = [],
        prior: Date? = nil,
        reminderLocalizationKey: String = "schedule.reminder"
    ) throws -> AdvancedRecurrenceWorkflowContextV1 {
        let calendar = try calendar()
        return AdvancedRecurrenceWorkflowContextV1(
            definition: definition, binding: try .init(definition), calendar: calendar,
            overrideEvents: [], previewOccurrences: previewOccurrences, definitions: [definition],
            history: history, completionHistory: history.filter { $0.action == .complete },
            releaseHistory: [definition], evaluatedRange: try range(),
            activeUpcomingWorkspaceCount: 0, priorEvaluationAt: prior,
            reminderLocalizationKey: reminderLocalizationKey
        )
    }
    static func override(
        definition: ScheduleDefinitionReleaseV1,
        occurrenceID: OccurrenceIDV1,
        kind: ScheduleOccurrenceOverrideKindV1,
        slot: Int,
        scope: ScheduleOverrideScopeV1 = .thisOccurrence
    ) throws -> ScheduleOverrideEventV1 {
        try .init(
            eventID: id(slot), workspaceID: workspace, scheduleRelease: .init(definition),
            target: .occurrence(occurrenceID, nominalDate: date("2025-02-28")),
            scope: scope, kind: kind, effectiveRange: range(),
            replacementDate: kind == .skip ? nil : date("2025-03-03"),
            replacementWindow: kind == .skip ? nil : anchor(hour: 10),
            reasonCode: "C38_OVERRIDE", expectedScheduleRevision: definition.revision,
            expectedOverrideFrontierSHA256: ScheduleOverridePrecedenceV1.closureSHA256([]),
            revision: 1, mutationID: mutation(slot + 1), recordedBy: actor(slot + 2),
            recordedAt: now
        )
    }
}

private struct C38Clock: ApplicationClock { let value: Date; func now() -> Date { value } }

@MainActor private final class C38Writer: ScheduleCanonicalWritingV1 {
    private var accepted: [MutationIDV1: (ScheduleMutationV1, ScheduleMutationReceiptV1)] = [:]
    private var interruptOnce: Bool
    private(set) var committedEffectCount = 0
    init(interruptOnce: Bool = false) { self.interruptOnce = interruptOnce }
    func acceptedScheduleMutation(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1? {
        guard let prior = accepted[mutation.mutationID] else { return nil }
        guard prior.0 == mutation else { throw ScheduleFailureV1.divergentReplay }
        return prior.1
    }
    func applySchedule(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1 {
        if let prior = try acceptedScheduleMutation(mutation) { return prior }
        let receipt = try makeReceipt(mutation)
        accepted[mutation.mutationID] = (mutation, receipt)
        committedEffectCount += 1
        if interruptOnce { interruptOnce = false; throw MutationJournalFailureV1.injected(.afterEffectBeforeReceipt) }
        return receipt
    }
    private func makeReceipt(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1 {
        let replica = ReplicaID(rawValue: C38.id(200))
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: mutation.workspaceID, replicaID: replica)
        let targets = try mutation.concurrencyIdentities
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: mutation.workspaceID, generationID: C38.id(201), writerInstanceID: C38.id(202),
            workspaceRevision: 0, entityRevisions: try targets.map {
                .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
            })
        let envelope = try MutationEnvelopeV1(request: .init(
            mutationID: mutation.mutationID, expectedRevision: expected, command: .applySchedule(mutation)
        ), identity: identity)
        let images = try mutation.mutationPostImages
        let resulting = try WorkspaceExpectedRevisionV1(
            workspaceID: mutation.workspaceID, generationID: expected.generationID,
            writerInstanceID: expected.writerInstanceID, workspaceRevision: 1,
            entityRevisions: try targets.map { target in
                .init(identity: target, revision: try images.first(where: { try $0.identity == target })?.revision
                      ?? mutation.expectedRevision(for: target))
            })
        let raw = try MutationReceiptV1(
            identity: .init(workspaceID: mutation.workspaceID, replicaID: replica, localSequence: 1),
            envelope: envelope, resultingRevision: try .init(resulting), postImages: images,
            committedAt: C38.now)
        return try .init(mutation: mutation, mutationReceipt: raw)
    }
}

private actor C38ReminderReconciler: ScheduleReminderReconcilingV1 {
    private var denialEnabled = false
    private(set) var rebuildAttempts: [ReminderProjectionV1] = []
    private(set) var acceptedRebuilds: [ReminderProjectionV1] = []
    private(set) var erasedWorkspaces: [WorkspaceID] = []

    func reconcile(_ projection: ReminderProjectionV1) async throws {
        rebuildAttempts.append(projection)
        guard !denialEnabled else { throw ScheduleFailureV1.invalidValue }
        acceptedRebuilds.append(projection)
    }
    func removeAll(workspaceID: WorkspaceID) async throws { erasedWorkspaces.append(workspaceID) }
    func enableDenial() { denialEnabled = true }
    func snapshot() -> (attempts: [ReminderProjectionV1], accepted: [ReminderProjectionV1],
                        erased: [WorkspaceID]) {
        (rebuildAttempts, acceptedRebuilds, erasedWorkspaces)
    }
}

@MainActor private func c38Coordinator(
    writer: C38Writer, now: Date = C38.now,
    reminderReconciler: C38ReminderReconciler? = nil
) -> AdvancedRecurrenceWorkflowCoordinatorV1 {
    AdvancedRecurrenceWorkflowCoordinatorV1(
        schedule: ScheduleCoordinatorV1(writer: writer),
        exceptions: ScheduleExceptionCoordinatorV1(projector: ScheduleExceptionLifecycleAdapterV1()),
        reminderLifecycle: reminderReconciler.map {
            ScheduleReminderLifecycleV1(reconciler: $0)
        },
        clock: C38Clock(value: now)
    )
}

final class V9_101AdvancedRecurrenceWorkflowTests: XCTestCase {
    @MainActor
    func testV23P04C38G01PatternsOverridesAndHistoryProjectDeterministically() async throws {
        let fixture = try C38.fixture()
        XCTAssertEqual(fixture.evidenceIDs.count, 5)
        let rules: [AdvancedRecurrenceRuleV1] = [
            .daily(interval: 365), .weekly(interval: 52, weekdays: [.monday]),
            .monthlyDay(interval: 12, day: 31, missingDayPolicy: .lastValidDay),
            .monthlyWeekday(interval: 12, ordinal: .last, weekday: .friday)
        ]
        for rule in rules { try rule.validate(); XCTAssertNoThrow(try AdvancedRecurrenceAuthoringPatternV1(recurrence: rule)) }
        XCTAssertEqual(
            fixture.golden.patterns.map { "\($0.kind):\($0.minimumInterval)-\($0.maximumInterval)" },
            ["DAILY:1-365", "WEEKLY:1-52", "CALENDAR_DAY:1-12",
             "WEEKDAY:1-12", "LAST_DAY:1-12"]
        )
        let definition = try C38.definition()
        let basis = try C38.basis("2025-02-28", definition: definition)
        let generated = try C38.event(definition: definition, basis: basis)
        let id = try C38.occurrence(basis, definition: definition)
        XCTAssertEqual(id, try C38.occurrence(basis, definition: definition))
        let writer = C38Writer()
        let coordinator = c38Coordinator(writer: writer)
        let projection = try coordinator.project(
            context: C38.context(definition: definition, history: [generated])
        )
        XCTAssertEqual(projection.history.first?.occurrenceID, id)
        XCTAssertTrue(projection.canCommitExceptionChange)
        XCTAssertFalse(fixture.persistence.addsDurableFamily)
        XCTAssertFalse(fixture.persistence.changesSchema)
        XCTAssertFalse(fixture.persistence.createsRecurrenceEngine)
        let input = ScheduleChangeOccurrenceInputV1(
            occurrenceID: id, state: .upcoming,
            basis: try C38.scheduleBasis("2025-02-28", definition: definition, calendar: C38.calendar())
        )
        let previewContext = try C38.context(definition: definition, previewOccurrences: [input])
        for (offset, kind) in ScheduleOccurrenceOverrideKindV1.allCases.enumerated() {
            let proposed = try C38.override(
                definition: definition, occurrenceID: id, kind: kind, slot: 120 + offset * 10
            )
            let result = try coordinator.project(context: previewContext, proposedOverride: proposed)
            XCTAssertTrue(result.exceptionPreview.effects.contains {
                switch kind {
                case .skip: return $0.disposition == .skipped
                case .move: return $0.disposition == .moved
                case .addOne: return $0.disposition == .created
                }
            })
        }
        let proposed = try C38.override(
            definition: definition, occurrenceID: id, kind: .move, slot: 180
        )
        let preview = try coordinator.project(context: previewContext, proposedOverride: proposed).exceptionPreview
        let command = AdvancedRecurrenceWorkflowCommandV1.commitException(
            preview: preview, currentFrontier: preview.frontier, predecessor: nil
        )
        guard case let .exceptionCommitted(receipt) = try await coordinator.execute(command, context: previewContext),
              case let .exceptionCommitted(replay) = try await coordinator.recover(command, context: previewContext)
        else { return XCTFail("Expected canonical exception receipt") }
        XCTAssertEqual(receipt, replay)
        XCTAssertEqual(writer.committedEffectCount, 1)
    }

    @MainActor
    func testV23P04C38A01LeapMonthEndLastWeekdayAndScopesPreview() async throws {
        let leap = AdvancedRecurrenceRuleV1.monthlyDay(interval: 12, day: 29, missingDayPolicy: .lastValidDay)
        let monthEnd = AdvancedRecurrenceRuleV1.monthlyDay(interval: 1, day: 31, missingDayPolicy: .lastValidDay)
        let lastWeekday = AdvancedRecurrenceRuleV1.monthlyWeekday(interval: 1, ordinal: .last, weekday: .friday)
        for rule in [leap, monthEnd, lastWeekday] { try rule.validate() }
        XCTAssertEqual(try AdvancedRecurrenceAuthoringPatternV1(recurrence: monthEnd), .lastDay(interval: 1))
        XCTAssertEqual(Set(ScheduleOverrideScopeV1.allCases), [.thisOccurrence, .thisAndFuture, .entireSeries])
        let fixture = try C38.fixture()
        XCTAssertEqual(Set(fixture.alternate.scopes), Set(ScheduleOverrideScopeV1.allCases.map(\.rawValue)))
        let definition = try C38.definition()
        let basis = try C38.basis("2025-02-28", definition: definition)
        let occurrenceID = try C38.occurrence(basis, definition: definition)
        let input = ScheduleChangeOccurrenceInputV1(
            occurrenceID: occurrenceID, state: .upcoming,
            basis: try C38.scheduleBasis("2025-02-28", definition: definition, calendar: C38.calendar())
        )
        let coordinator = c38Coordinator(writer: C38Writer())
        let context = try C38.context(definition: definition, previewOccurrences: [input])
        var slot = 700
        for scope in ScheduleOverrideScopeV1.allCases {
            for kind in ScheduleOccurrenceOverrideKindV1.allCases {
                if kind == .addOne && scope != .thisOccurrence { continue }
                let proposed = try C38.override(
                    definition: definition, occurrenceID: occurrenceID, kind: kind,
                    slot: slot, scope: scope
                )
                slot += 10
                let preview = try coordinator.project(context: context, proposedOverride: proposed)
                XCTAssertEqual(preview.exceptionPreview.proposedOverride, proposed)
            }
        }
    }

    @MainActor
    func testV23P04C38H01InvalidRulesStalePreviewAndIdentityDriftHaveNoEffects() async throws {
        XCTAssertThrowsError(try AdvancedRecurrenceRuleV1.daily(interval: 0).validate())
        XCTAssertThrowsError(try AdvancedRecurrenceRuleV1.monthlyDay(
            interval: 1, day: 32, missingDayPolicy: .lastValidDay
        ).validate())
        XCTAssertThrowsError(try AdvancedRecurrenceAuthoringPatternV1(
            recurrence: .yearly(interval: 1, month: 2, day: 29, missingDayPolicy: .lastValidDay)
        ))
        XCTAssertThrowsError(try AdvancedScheduleGenerationBudgetV1().validate(
            generatedCount: 513, activeUpcomingWorkspaceCount: 0
        ))
        let definition = try C38.definition()
        let writer = C38Writer()
        let coordinator = c38Coordinator(writer: writer)
        let context = try C38.context(definition: definition)
        let projected = try coordinator.project(context: context)
        let basis = try C38.basis("2025-02-28", definition: definition)
        let occurrenceID = try C38.occurrence(basis, definition: definition)
        let firstOverride = try C38.override(
            definition: definition, occurrenceID: occurrenceID, kind: .move, slot: 220
        )
        let conflictingOverride = try C38.override(
            definition: definition, occurrenceID: occurrenceID, kind: .skip, slot: 230
        )
        XCTAssertThrowsError(try ScheduleOverridePrecedenceV1.validateClosure(
            [firstOverride, conflictingOverride], for: try .init(definition)
        ))
        XCTAssertThrowsError(try ScheduleExceptionProjectionEngineV1.validateCommit(
            preview: projected.exceptionPreview,
            currentFrontier: ScheduleChangeFrontierV1(
                workspaceID: definition.workspaceID,
                scheduleRelease: try .init(definition), calendarRelease: context.calendar.reference,
                overrideEvents: [], occurrenceClosureSHA256: C38.digest("x"),
                evaluatedRange: context.evaluatedRange, budget: try .init()
            )))
        XCTAssertEqual(writer.committedEffectCount, 0)
    }

    @MainActor
    func testV23P04C38I01DSTClockReminderAndEffectBeforeReceiptRetryExactlyOnce() async throws {
        let definition = try C38.definition()
        let springResolution = try TimeContextRule.resolveScheduleCivilTime(
            date: C38.date("2025-03-09"), window: C38.anchor(hour: 2, minute: 30),
            timeBasis: definition.timeBasis
        )
        let fallResolution = try TimeContextRule.resolveScheduleCivilTime(
            date: C38.date("2025-11-02"), window: C38.anchor(hour: 1, minute: 30),
            timeBasis: definition.timeBasis
        )
        XCTAssertEqual(springResolution.disposition, .nonexistentGap)
        XCTAssertEqual(fallResolution.disposition, .ambiguousFold)
        let spring = try C38.basis(
            "2025-03-09", definition: definition, disposition: springResolution.disposition,
            resolved: springResolution.resolvedAtUTC, offset: springResolution.utcOffsetSeconds
        )
        let fall = try C38.basis(
            "2025-11-02", definition: definition, disposition: fallResolution.disposition,
            resolved: fallResolution.resolvedAtUTC, offset: fallResolution.utcOffsetSeconds
        )
        XCTAssertNotEqual(spring.nominalKey, fall.nominalKey)
        let writer = C38Writer(interruptOnce: true)
        let coordinator = c38Coordinator(writer: writer)
        let event = try C38.event(definition: definition, basis: spring, mutationSlot: 300)
        let context = try C38.context(definition: definition)
        guard case .projected = try await coordinator.execute(.previewException(nil), context: context)
        else { return XCTFail("Expected cancel-before-effect preview") }
        XCTAssertEqual(writer.committedEffectCount, 0)
        let command = AdvancedRecurrenceWorkflowCommandV1.recordOccurrence(event: event, predecessor: nil)
        await XCTAssertThrowsErrorAsync { try await coordinator.execute(command, context: context) }
        guard case let .occurrenceRecorded(receipt) = try await coordinator.recover(command, context: context),
              case let .occurrenceRecorded(replay) = try await coordinator.recover(command, context: context) else {
            return XCTFail("Expected exact occurrence recovery")
        }
        XCTAssertEqual(receipt, replay)
        XCTAssertEqual(writer.committedEffectCount, 1)
        let rollbackProjection = try c38Coordinator(writer: writer, now: C38.now).project(
            context: C38.context(definition: definition, prior: C38.now.addingTimeInterval(60))
        )
        XCTAssertEqual(rollbackProjection.clockDisposition, .rollbackDetected)
        if case .suppressedForClockRollback = rollbackProjection.reminders {} else { XCTFail() }
        let reminderReconciler = C38ReminderReconciler()
        let reminderCoordinator = c38Coordinator(
            writer: writer, now: definition.startsAtUTC, reminderReconciler: reminderReconciler
        )
        guard case .remindersReconciled = try await reminderCoordinator.execute(
            .reconcileReminders, context: try C38.context(definition: definition, history: [event])
        ) else { return XCTFail("Expected reminder rebuild") }
        guard case .remindersReconciled = try await reminderCoordinator.execute(
            .reconcileReminders,
            context: try C38.context(
                definition: definition, history: [event], reminderLocalizationKey: "schedule.changed"
            )
        ) else { return XCTFail("Expected changed reminder replacement") }
        let changedSnapshot = await reminderReconciler.snapshot()
        XCTAssertEqual(changedSnapshot.accepted.count, 2)
        XCTAssertNotEqual(
            changedSnapshot.accepted[0].projectionSHA256,
            changedSnapshot.accepted[1].projectionSHA256
        )
        await reminderReconciler.enableDenial()
        await XCTAssertThrowsErrorAsync {
            _ = try await reminderCoordinator.execute(
                .reconcileReminders, context: try C38.context(definition: definition, history: [event])
            )
        }
        let deniedSnapshot = await reminderReconciler.snapshot()
        XCTAssertEqual(deniedSnapshot.attempts.count, 3)
        XCTAssertEqual(deniedSnapshot.accepted.count, 2)
        let reminderLifecycle = ScheduleReminderLifecycleV1(reconciler: reminderReconciler)
        try await reminderLifecycle.erase(workspaceID: C38.workspace)
        let erasedSnapshot = await reminderReconciler.snapshot()
        XCTAssertEqual(erasedSnapshot.erased, [C38.workspace])
    }

    @MainActor
    func testV23P04C38R01CompletionScheduleChangeReplayAndRestoreRemainStable() async throws {
        let definition = try C38.definition()
        let basis = try C38.basis("2025-02-28", definition: definition)
        let generated = try C38.event(definition: definition, basis: basis, mutationSlot: 400)
        let work = ScheduledWorkInstanceReferenceV1.roundSession(
            sessionID: C38.id(401), revision: 1, sessionSHA256: C38.digest("w")
        )
        let started = try OccurrenceHistoryEventV1(
            eventID: C38.id(402), workspaceID: C38.workspace, occurrenceID: generated.occurrenceID,
            scheduleRelease: .init(definition), action: .start,
            nominalBasis: basis, effectiveBasis: basis, workInstance: work,
            predecessor: generated, revision: 2, mutationID: C38.mutation(403),
            recordedBy: C38.actor(404), recordedAt: C38.now
        )
        let completed = try OccurrenceHistoryEventV1(
            eventID: C38.id(406), workspaceID: C38.workspace, occurrenceID: generated.occurrenceID,
            scheduleRelease: .init(definition), action: .complete,
            nominalBasis: basis, effectiveBasis: basis, workInstance: work, completedAt: C38.now,
            predecessor: started, revision: 3, mutationID: C38.mutation(407),
            recordedBy: C38.actor(408), recordedAt: C38.now
        )
        let scheduleBasis = try C38.scheduleBasis("2025-02-28", definition: definition, calendar: C38.calendar())
        let immutable = ScheduleChangeOccurrenceInputV1(
            occurrenceID: generated.occurrenceID, state: .completed, basis: scheduleBasis
        )
        let writer = C38Writer()
        let coordinator = c38Coordinator(writer: writer)
        let context = try C38.context(
            definition: definition, history: [generated, started, completed], previewOccurrences: [immutable]
        )
        let scheduleChange = try C38.override(
            definition: definition, occurrenceID: generated.occurrenceID,
            kind: .skip, slot: 450, scope: .entireSeries
        )
        let first = try coordinator.project(context: context, proposedOverride: scheduleChange)
        let rebuilt = try coordinator.project(context: context, proposedOverride: scheduleChange)
        XCTAssertEqual(first, rebuilt)
        XCTAssertEqual(first.exceptionPreview.effects.first?.disposition, .unchanged)
        XCTAssertEqual(first.history.first?.state, .completed)
        XCTAssertNotEqual(OccurrenceStateV1.skipped, .completed)
        let command = AdvancedRecurrenceWorkflowCommandV1.recordOccurrence(
            event: generated, predecessor: nil
        )
        guard case let .occurrenceRecorded(receipt) = try await coordinator.execute(command, context: context),
              case let .occurrenceRecorded(replay) = try await coordinator.recover(command, context: context) else {
            return XCTFail("Expected exact replay")
        }
        XCTAssertEqual(receipt, replay)
        XCTAssertEqual(writer.committedEffectCount, 1)

        let generationWriter = C38Writer()
        let generationCoordinator = c38Coordinator(writer: generationWriter, now: definition.startsAtUTC)
        let generationContext = try C38.context(definition: definition)
        let window = OccurrenceGenerationWindowV1(
            startsAtUTC: definition.startsAtUTC,
            endsAtUTC: definition.startsAtUTC.addingTimeInterval(3 * 86_400),
            maximumOccurrences: 8
        )
        let plan = try generationCoordinator.previewGeneration(window: window, context: generationContext)
        XCTAssertFalse(plan.candidates.isEmpty)
        guard case let .generationPreview(commandPlan) = try await generationCoordinator.execute(
            .previewGeneration(window), context: generationContext
        ) else { return XCTFail("Expected frozen generation preview") }
        XCTAssertEqual(commandPlan, plan)
        let generationMutation = try C38.mutation(520)
        let generationEvents = try plan.candidates.enumerated().map { offset, candidate in
            try OccurrenceHistoryEventV1(
                eventID: C38.id(530 + offset), workspaceID: C38.workspace,
                occurrenceID: candidate.occurrenceID,
                identityPredecessorOccurrenceID: candidate.predecessorOccurrenceID,
                identityCompletionEventSHA256: candidate.completionEventSHA256,
                scheduleRelease: plan.scheduleRelease, action: .generated,
                nominalBasis: candidate.nominalBasis, effectiveBasis: candidate.effectiveBasis,
                predecessor: nil, revision: 1, mutationID: generationMutation,
                recordedBy: C38.actor(560), recordedAt: C38.now
            )
        }
        let generationCommand = AdvancedRecurrenceWorkflowCommandV1.generate(
            plan: plan, events: generationEvents
        )
        guard case let .occurrencesGenerated(generatedReceipt) = try await generationCoordinator.execute(
            generationCommand, context: generationContext
        ), case let .occurrencesGenerated(recoveredReceipt) = try await generationCoordinator.recover(
            generationCommand, context: generationContext
        ) else { return XCTFail("Expected frozen generation recovery") }
        XCTAssertEqual(generatedReceipt, recoveredReceipt)
        XCTAssertEqual(generationWriter.committedEffectCount, 1)
        let divergent = try OccurrenceHistoryEventV1(
            eventID: C38.id(499), workspaceID: C38.workspace,
            occurrenceID: generated.occurrenceID, scheduleRelease: .init(definition),
            action: .generated, nominalBasis: basis, effectiveBasis: basis,
            predecessor: nil, revision: 1, mutationID: generated.mutationID,
            recordedBy: C38.actor(498), recordedAt: C38.now
        )
        XCTAssertThrowsError(try writer.applySchedule(.init(
            workspaceID: definition.workspaceID, mutationID: generated.mutationID,
            payload: .appendOccurrenceEvent(divergent, predecessor: nil, release: definition)
        )))
        XCTAssertEqual(writer.committedEffectCount, 1)
        XCTAssertEqual(
            try ScheduleCanonicalCodecV1.decode(
                ScheduleDefinitionReleaseV1.self,
                from: ScheduleCanonicalCodecV1.data(definition)
            ), definition
        )
        let claims = try C38.fixture().claims
        XCTAssertTrue(claims.allFalse)
    }
}

private extension C38Corpus.Claims {
    var allFalse: Bool {
        !nativeCalendarIntegrated && !nativeReminderIntegrated
            && !hostedCalendarIntegrated && !hostedReminderIntegrated
            && !providerAdopted && !providerAccepted && !providerReleased
            && !networkRequired && !accountRequired && !entitlementRequired
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do { try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch {}
}

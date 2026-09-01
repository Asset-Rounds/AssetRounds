import Foundation
import XCTest
@testable import FieldEvidenceApp

private enum C22RecurringRoundTestSupport {
    static let now = Date(timeIntervalSince1970: 1_804_000_000)
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "c2200000-0000-4000-8000-%012x", n))!
    }
    static func digest(_ value: Character) -> String { String(repeating: value, count: 64) }
    static let workspace = WorkspaceID(rawValue: id(1))

    static func mutation(_ n: Int) throws -> MutationIDV1 { try .init(rawValue: id(n)) }

    static func actor(_ n: Int) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(n), workspaceID: workspace, displayName: "C22 local actor"
        )
        return try .init(
            snapshotID: id(n + 1), workspaceID: workspace, actor: reference,
            responsibility: .recordedBy, displayNameAtTime: reference.displayName,
            capturedAt: now
        )
    }

    static func definition() throws -> SurveyDefinitionReleaseV1 {
        let fact = FactDefinitionV1(
            factID: "c22.fact", labelLocalizationKey: "survey.fact.label",
            accessibilityLabelLocalizationKey: "survey.fact.accessibility",
            helpLocalizationKey: "survey.fact.help", required: true, defaultValue: nil,
            visibility: nil, payload: .shortText(.init(maximumUTF8Bytes: 64))
        )
        return try .init(
            releaseID: id(10), workspaceID: workspace, definitionID: id(11),
            activityKind: .survey, ownerPackageID: ShippingIlluminatedSignAdapterV1.packageID,
            sections: [.init(
                sectionID: "section", titleLocalizationKey: "survey.section.title",
                accessibilityHeadingLocalizationKey: "survey.section.heading", ordinal: 0,
                facts: [fact]
            )],
            completionRules: [.init(
                ruleID: "complete", expression: .allRequiredVisibleFactsAnswered,
                failureLocalizationKey: "survey.complete.failure"
            )],
            claimsProfile: .init(
                profileID: "claims", activityKind: .survey, allowedClaimKeys: [],
                forbiddenClaimKeys: ["approval"], limitationLocalizationKeys: ["survey.limit"]
            ),
            reportProjection: .init(
                projectionID: "report", projectionVersion: "1",
                headingLocalizationKey: "survey.report.heading",
                emptyValueLocalizationKey: "survey.report.empty", sectionIDs: ["section"],
                includedFactIDs: ["c22.fact"]
            ),
            localizationReleaseSHA256: digest("b"), revision: 1,
            mutationID: try mutation(20), authoredBy: try actor(30), authoredAt: now
        )
    }

    static func package() throws -> InspectionPackageReleaseV1 {
        let workflow = try WorkflowDefinitionV1(
            workflowID: "c22.recurring.workflow", entryNodeID: "start",
            declaredFieldIDs: [], nodes: [
                try .init(nodeID: "start", kind: .section,
                          localizationKey: "c22.start", outgoingNodeIDs: ["end"]),
                try .init(nodeID: "end", kind: .terminal,
                          localizationKey: "c22.end", outgoingNodeIDs: []),
            ]
        )
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(), workflow: workflow
        )
        return try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(draft)
        ).release
    }

    static func timeBasis() throws -> FrozenScheduleTimeBasisV1 {
        try .init(
            ianaTimeZoneIdentifier: "America/New_York", timeZoneRuleSetVersion: "2026a",
            timeZoneRuleSetSHA256: digest("c"), ambiguousTimePolicy: .earlierOffset,
            nonexistentTimePolicy: .shiftForwardByGap, calendarBasisSHA256: digest("d")
        )
    }

    static func release(
        recurrence: ScheduleRecurrenceV1, slot: Int, maximum: Int = 8
    ) throws -> ScheduleDefinitionReleaseV1 {
        try .init(
            scheduleDefinitionID: id(slot), releaseID: id(slot + 1), workspaceID: workspace,
            occurrenceIdentityNamespaceID: id(slot + 2), action: .create,
            lifecycleState: .active, recurrence: recurrence, timeBasis: try timeBasis(),
            startsAtUTC: now.addingTimeInterval(-86_400), generationHorizonDays: 30,
            maximumGeneratedOccurrences: maximum, readyLeadSeconds: 3_600,
            overdueGraceSeconds: 7_200,
            subject: .init(kind: .asset, subjectID: id(50), revision: 1, ownerAssetID: nil),
            workDefinition: try .init(
                kind: .roundSession, definition: definition(), packageRelease: package()
            ),
            revision: 1, mutationID: try mutation(slot + 10),
            authoredBy: try actor(slot + 20), authoredAt: now
        )
    }

    static func basis(_ release: ScheduleDefinitionReleaseV1) throws -> ResolvedOccurrenceBasisV1 {
        let value = ResolvedOccurrenceBasisV1(
            nominalLocalDate: "2027-03-14", nominalLocalTime: "02:30:00",
            resolvedAtUTC: now, utcOffsetSeconds: -14_400, disposition: .nonexistentGap,
            timeBasisSHA256: try release.timeBasis.canonicalSHA256(),
            adjustmentProvenanceSHA256: digest("e")
        )
        try value.validate()
        return value
    }

    static func event(
        release: ScheduleDefinitionReleaseV1, occurrenceID: OccurrenceIDV1,
        basis: ResolvedOccurrenceBasisV1, action: OccurrenceHistoryActionV1,
        predecessor: OccurrenceHistoryEventV1? = nil,
        work: ScheduledWorkInstanceReferenceV1? = nil, slot: Int
    ) throws -> OccurrenceHistoryEventV1 {
        try .init(
            eventID: id(slot), workspaceID: workspace, occurrenceID: occurrenceID,
            scheduleRelease: .init(release), action: action, nominalBasis: basis,
            effectiveBasis: basis, workInstance: work,
            completedAt: action == .complete ? now.addingTimeInterval(60) : nil,
            predecessor: predecessor, revision: (predecessor?.revision ?? 0) + 1,
            mutationID: try mutation(slot + 2_000), recordedBy: try actor(slot + 3_000),
            recordedAt: now
        )
    }

    static func roundSessions() throws -> (draft: RoundSessionV1, active: RoundSessionV1) {
        let requirement = try RoundPackageContentRequirementV1(
            packageRelease: .init(try package()), requiredContent: []
        )
        let item = try RoundItemV1(
            itemID: id(900), order: 0,
            selection: .init(assetID: id(901), siteID: id(902), labelAtSelection: "C22 asset"),
            requirement: requirement
        )
        let draft = try RoundSessionV1(
            workspaceID: workspace, sessionID: id(903), revision: 1,
            mutationID: try mutation(904), state: .draft, transition: .create,
            items: [item], recordedBy: try actor(905), recordedAt: now
        )
        let active = try RoundSessionV1(
            workspaceID: workspace, sessionID: draft.sessionID, predecessor: draft,
            revision: 2, mutationID: try mutation(906), state: .active,
            transition: .start, items: [item], recordedBy: try actor(907),
            recordedAt: now.addingTimeInterval(1)
        )
        return (draft, active)
    }

    static func readinessManifest(
        session: RoundSessionV1, protectedDataAvailable: Bool = true
    ) throws -> OfflineReadinessManifestV1 {
        let package = session.items[0].requirement.packageRelease
        let snapshot = try OfflineReadinessSnapshotV1(
            session: session.reference, expectedPackage: package, observedPackage: package,
            selectedAssets: session.selectedAssets,
            observedAssetIDs: Set(session.selectedAssets.map(\.assetID)),
            guidanceReferenceIDs: ["c22-guidance"],
            availableGuidanceReferenceIDs: ["c22-guidance"],
            contentRequirements: [], contentObservations: [], expectedFieldReferences: [],
            fieldReferenceReadiness: [],
            storage: .init(capacityState: .checked, availableBytes: 10_000),
            access: .init(protectedDataAvailable: protectedDataAvailable),
            checkedAt: now, timeZoneIdentifier: "America/New_York", clockState: .checked
        )
        return try OfflineReadinessManifestBuilderV1.build(snapshot: snapshot)
    }

    static func myDayPlan(session: RoundSessionV1) throws -> MyDayPlanV1 {
        let reference = MyDayEligibleReferenceV1.roundSession(
            workspaceID: workspace, sessionID: session.sessionID,
            revision: session.revision, sessionSHA256: session.sessionSHA256
        )
        let item = try MyDayItemV1(
            membershipID: id(920), reference: reference, manualOrder: 0
        )
        let key = try MyDayKeyV1(
            workspaceID: workspace, civilDate: .init("2027-03-14"),
            ianaTimeZoneIdentifier: "America/New_York"
        )
        return try MyDayPlanV1(
            planID: id(921), key: key, items: [item], revision: 1,
            mutationID: try mutation(922), authoredBy: try actor(923), authoredAt: now
        )
    }

    static func corpus() throws -> C22Corpus {
        let bundle = Bundle(for: V9_85RecurringRoundExperienceTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "V23P04C22RecurringRoundExperienceCorpusV1",
                       withExtension: "json", subdirectory: "Fixtures/V23/Schedules")
                ?? bundle.url(forResource: "V23P04C22RecurringRoundExperienceCorpusV1",
                              withExtension: "json")
        )
        return try JSONDecoder().decode(C22Corpus.self, from: Data(contentsOf: url))
    }
}

private struct C22Corpus: Decodable {
    let schema: String
    let selectors: [String]
    let recurrenceModes: [String]
    let occurrenceStates: [String]
    let dueReasons: [String]
    let editor: Editor
    let reminders: Reminders
    let hostileCases: [String]
    let interruptionBoundaries: [String]
    let recovery: Recovery
    let transformations: [Transformation]
    let accessibility: Accessibility
    let statusFlags: StatusFlags

    struct Editor: Decodable {
        let requiresExplicitSave: Bool
        let timeZoneAlwaysVisible: Bool
        let boundedHorizon: Bool
        let boundedOccurrenceCount: Bool
        let startOccurrenceRequiresExplicitAction: Bool
        let startCreatesAtMostOneWorkInstance: Bool
    }
    struct Reminders: Decodable {
        let authorizations: [String]
        let dispositions: [String]
        let stableIdentifiers: Bool
        let deliveryIsCompletion: Bool
        let denialChangesCanonicalDueQueue: Bool
        let evictionChangesCanonicalDueQueue: Bool
        let reconcileFromCanonicalQueue: Bool
    }
    struct Recovery: Decodable {
        let sameMutationIDReturnsSameReceipt: Bool
        let sameMutationIDDifferentPayloadRejected: Bool
        let effectBeforeReceipt: Bool
        let completedHistoryImmutable: Bool
    }
    struct Transformation: Decodable {
        let kind: String
        let derivedQueueArchived: Bool?
        let derivedQueueRebuilt: Bool?
        let historyImmutable: Bool
        let sourceScheduleAutomaticallyActive: Bool?
    }
    struct Accessibility: Decodable {
        let voiceOverOrderIsSourceOrder: Bool
        let voiceControlUsesVisibleNames: Bool
        let dynamicTypeMaximum: String
        let rightToLeftSupported: Bool
        let statusUsesTextAndIcon: Bool
        let reduceMotionUsesStaticPresentation: Bool
        let errorFocusIsDeterministic: Bool
        let permissionDenialKeepsManualDuePath: Bool
    }
    struct StatusFlags: Decodable {
        let shippingUIAdopted: Bool
        let requiresAcceptedS10_6Reconciliation: Bool
    }
}

@MainActor
private final class C22ScheduleWriterProbe: ScheduleCanonicalWritingV1 {
    private(set) var applyCount = 0
    private var accepted: [MutationIDV1: (ScheduleMutationV1, ScheduleMutationReceiptV1)] = [:]

    func acceptedScheduleMutation(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1? {
        guard let prior = accepted[mutation.mutationID] else { return nil }
        guard prior.0 == mutation else { throw ScheduleFailureV1.divergentReplay }
        return prior.1
    }

    func applySchedule(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1 {
        if let prior = try acceptedScheduleMutation(mutation) { return prior }
        applyCount += 1
        let receipt = try makeReceipt(mutation)
        accepted[mutation.mutationID] = (mutation, receipt)
        return receipt
    }

    private func makeReceipt(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1 {
        let replica = ReplicaID(rawValue: C22RecurringRoundTestSupport.id(9_100))
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: mutation.workspaceID, replicaID: replica
        )
        let targets = try mutation.concurrencyIdentities
        let expectedRows = try targets.map {
            WorkspaceEntityRevisionV1(identity: $0, revision: try mutation.expectedRevision(for: $0))
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: mutation.workspaceID,
            generationID: C22RecurringRoundTestSupport.id(9_101),
            writerInstanceID: C22RecurringRoundTestSupport.id(9_102),
            workspaceRevision: 0, entityRevisions: expectedRows
        )
        let envelope = try MutationEnvelopeV1(request: .init(
            mutationID: mutation.mutationID, expectedRevision: expected,
            command: .applySchedule(mutation)
        ), identity: identity)
        let images = try mutation.mutationPostImages
        let resultingRows = try targets.map { target -> WorkspaceEntityRevisionV1 in
            let revision = try images.first(where: { try $0.identity == target })?.revision
                ?? mutation.expectedRevision(for: target)
            return WorkspaceEntityRevisionV1(identity: target, revision: revision)
        }
        let resulting = try WorkspaceExpectedRevisionV1(
            workspaceID: mutation.workspaceID, generationID: expected.generationID,
            writerInstanceID: expected.writerInstanceID, workspaceRevision: 1,
            entityRevisions: resultingRows
        )
        let raw = try MutationReceiptV1(
            identity: .init(workspaceID: mutation.workspaceID, replicaID: replica, localSequence: 1),
            envelope: envelope, resultingRevision: try .init(resulting), postImages: images,
            committedAt: C22RecurringRoundTestSupport.now
        )
        return try .init(mutation: mutation, mutationReceipt: raw)
    }
}

@MainActor
private final class C22ReminderPortProbe: DeviceLocalScheduleReminderPortV1 {
    var currentAuthorization: LocalReminderAuthorizationV1 = .authorized
    var observed: [ReminderEntryV1] = []
    private(set) var applications: [(removed: [String], added: [ReminderEntryV1])] = []

    func authorization() async throws -> LocalReminderAuthorizationV1 { currentAuthorization }
    func scheduledReminders(workspaceID: WorkspaceID) async throws -> [ReminderEntryV1] { observed }
    func apply(workspaceID: WorkspaceID, remove notificationIDs: [String],
               add reminderEntries: [ReminderEntryV1]) async throws {
        applications.append((notificationIDs, reminderEntries))
        observed.removeAll { notificationIDs.contains($0.notificationID) }
        observed.append(contentsOf: reminderEntries)
        observed.sort()
    }
    func removeAll(workspaceID: WorkspaceID) async throws { observed = [] }
}

@MainActor
private final class C22MyDayWriterProbe: MyDayWritingV1 {
    func currentPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1? { nil }
    func result(workspaceID: WorkspaceID, mutationID: MutationIDV1) throws -> MyDayCommandResultV1? { nil }
    func commit(_ command: MyDayCommandV1) throws -> MyDayCommandResultV1 {
        throw MyDayFailureV1.divergentMutation
    }
}

@MainActor
private final class C22MyDaySourceProbe: MyDaySourceFrontierReadingV1 {
    func sourceFrontiers(for plan: MyDayPlanV1, evaluatedAt: Date) throws -> [MyDaySourceFrontierV1] {
        try plan.items.map {
            try MyDaySourceFrontierV1(
                membershipID: $0.membershipID, plannedReference: $0.reference,
                currentReference: $0.reference, state: .active, readiness: .ready,
                dueAt: evaluatedAt, evaluatedAt: evaluatedAt
            )
        }
    }
}

private struct C22AccessGateProbe: AppAccessGatePortV1 {
    func currentState() async -> AppAccessStateV1 { .disabled }
    func lock(reason: AppLockReasonV1) async {}
    func authenticate(trigger: LocalAuthenticationTriggerV1) async -> LocalAuthenticationOutcomeV1 { .authenticated }
    func requireContentAccess() async throws {}
    func requireContentAccess(for surface: AppAccessContentReadSurfaceV1) async throws -> AppAccessContentPermitV1 {
        try .init(surface: surface, state: .disabled)
    }
}

@MainActor
final class V9_85RecurringRoundExperienceTests: XCTestCase {
    func testV23P04C22G01FixedCompletionRelativeEditorDueAndStartOnce() throws {
        let corpus = try C22RecurringRoundTestSupport.corpus()
        XCTAssertEqual(corpus.selectors, [
            "V23-P04-C22-G01", "V23-P04-C22-A01", "V23-P04-C22-H01",
            "V23-P04-C22-I01", "V23-P04-C22-R01",
        ])
        let anchor = ScheduleLocalAnchorV1(
            year: nil, month: nil, day: nil, weekday: nil,
            weekdayOrdinal: nil, hour: 9, minute: 0, second: 0
        )
        let fixed = try C22RecurringRoundTestSupport.release(
            recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)),
            slot: 100
        )
        let relative = try C22RecurringRoundTestSupport.release(
            recurrence: .completionRelative(.init(
                interval: 1, unit: .calendarDays, firstAnchor: anchor
            )), slot: 200
        )
        let fixedEditor = try ScheduleEditorStateV1(release: fixed)
        let relativeEditor = try ScheduleEditorStateV1(release: relative)
        XCTAssertEqual(fixedEditor.recurrenceKind, .fixedCalendar)
        XCTAssertEqual(relativeEditor.recurrenceKind, .completionRelative)
        XCTAssertEqual(fixedEditor.visibleTimeBasis.ianaTimeZoneIdentifier, "America/New_York")
        XCTAssertTrue(fixedEditor.requiresExplicitSave)
        XCTAssertEqual(corpus.recurrenceModes, ScheduleEditorRecurrenceKindV1.allCases.map(\.rawValue))

        let basis = try C22RecurringRoundTestSupport.basis(fixed)
        let occurrenceID = try OccurrenceIDV1(
            scheduleDefinitionID: fixed.scheduleDefinitionID,
            identityNamespaceID: fixed.occurrenceIdentityNamespaceID,
            nominalKey: basis.nominalKey
        )
        let generated = try C22RecurringRoundTestSupport.event(
            release: fixed, occurrenceID: occurrenceID, basis: basis,
            action: .generated, slot: 300
        )
        let queueProjection = try DueQueueProjectionV1(
            workspaceID: fixed.workspaceID, evaluatedAt: C22RecurringRoundTestSupport.now,
            definitions: [fixed], history: [generated]
        )
        let queue = try OccurrenceDueQueueStateV1(projection: queueProjection)
        XCTAssertEqual(queue.items.map(\.reason), [.readyWindowOpen])

        let sessions = try C22RecurringRoundTestSupport.roundSessions()
        let work = ScheduledWorkInstanceReferenceV1.roundSession(
            sessionID: sessions.active.sessionID, revision: sessions.active.revision,
            sessionSHA256: sessions.active.sessionSHA256
        )
        let started = try C22RecurringRoundTestSupport.event(
            release: fixed, occurrenceID: occurrenceID, basis: basis,
            action: .start, predecessor: generated, work: work, slot: 401
        )
        let request = try RecurringRoundStartRequestV1(
            event: started, predecessor: generated, release: fixed,
            explicitUserConfirmation: true
        )
        XCTAssertEqual(request.event.workInstance, work)
        XCTAssertNoThrow(try RecurringRoundStartFrontierBoundaryV1.validate(
            request: request, currentRoundSession: sessions.active
        ))
        XCTAssertThrowsError(try RecurringRoundStartFrontierBoundaryV1.validate(
            request: request, currentRoundSession: sessions.draft
        ))
        let readyManifest = try C22RecurringRoundTestSupport.readinessManifest(session: sessions.active)
        let readiness = try RecurringRoundStartReadinessV1(
            request: request, roundManifest: readyManifest
        )
        XCTAssertNoThrow(try readiness.requireReady())
        let writer = C22ScheduleWriterProbe()
        let schedule = ScheduleCoordinatorV1(writer: writer)
        let reminderPort = C22ReminderPortProbe()
        let coordinator = RecurringRoundExperienceCoordinatorV1(
            schedule: schedule,
            reminders: DeviceLocalScheduleReminderReconcilerV1(port: reminderPort)
        )
        let firstReceipt = try coordinator.start(
            request, readiness: readiness, currentRoundSession: sessions.active
        )
        let repeatedReceipt = try coordinator.start(
            request, readiness: readiness, currentRoundSession: sessions.active
        )
        XCTAssertEqual(firstReceipt, repeatedReceipt)
        XCTAssertEqual(writer.applyCount, 1)
        let lifecycle = RecurringRoundExperienceLifecycleAdapterV1(writer: writer)
        let recovered = try XCTUnwrap(lifecycle.acceptedStart(
            request, readiness: readiness, currentRoundSession: sessions.active
        ))
        XCTAssertEqual(recovered, firstReceipt)
        XCTAssertEqual(writer.applyCount, 1)
        XCTAssertThrowsError(try RecurringRoundStartRequestV1(
            event: started, predecessor: generated, release: fixed,
            explicitUserConfirmation: false
        ))
        XCTAssertTrue(corpus.editor.startOccurrenceRequiresExplicitAction)
        XCTAssertTrue(corpus.editor.startCreatesAtMostOneWorkInstance)
    }

    func testV23P04C22A01ReminderDenialEvictionStableIDReconcileKeepsDueTruth() async throws {
        let fixed = try makeFixed(slot: 500)
        let (projection, _) = try dueProjection(fixed, slot: 520)
        let reminder = try ReminderProjectionV1(
            dueQueue: projection, localizationKey: ScheduleLocalizationKeyV1.reminder.rawValue
        )
        let denied = try LocalReminderReconciliationV1(
            projection: reminder, observedReminderEntries: reminder.reminders,
            authorization: .denied
        )
        XCTAssertEqual(denied.disposition, .denied)
        XCTAssertTrue(denied.reminderEntriesToApply.isEmpty)
        XCTAssertFalse(denied.canonicalDueTruthChanged)

        let evicted = try LocalReminderReconciliationV1(
            projection: reminder, observedReminderEntries: [], authorization: .authorized
        )
        let desiredIDs = reminder.reminders.map(\.notificationID).sorted()
        XCTAssertEqual(evicted.disposition, .applied)
        XCTAssertEqual(evicted.reminderEntriesToApply.map(\.notificationID), desiredIDs)
        XCTAssertFalse(evicted.canonicalDueTruthChanged)
        XCTAssertEqual(projection.projectionSHA256, denied.dueQueueSHA256)
        XCTAssertEqual(projection.projectionSHA256, evicted.dueQueueSHA256)

        let port = C22ReminderPortProbe()
        let reconciler = DeviceLocalScheduleReminderReconcilerV1(port: port)
        let initial = try await reconciler.reconcile(reminder)
        XCTAssertEqual(initial.disposition, .applied)
        XCTAssertEqual(port.applications.count, 1)
        let unchanged = try await reconciler.reconcile(reminder)
        XCTAssertEqual(unchanged.disposition, .noChange)
        XCTAssertEqual(port.applications.count, 1)
        if let desired = reminder.reminders.first {
            port.observed = [ReminderEntryV1(
                notificationID: desired.notificationID,
                occurrenceID: desired.occurrenceID,
                fireAtUTC: desired.fireAtUTC.addingTimeInterval(60),
                localizationKey: desired.localizationKey
            )]
            let replaced = try await reconciler.reconcile(reminder)
            XCTAssertEqual(replaced.notificationIDsToRemove, [desired.notificationID])
            XCTAssertEqual(replaced.reminderEntriesToApply, [desired])
            XCTAssertEqual(port.applications.count, 2)
        }

        let corpus = try C22RecurringRoundTestSupport.corpus()
        XCTAssertEqual(corpus.reminders.authorizations,
                       LocalReminderAuthorizationV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.reminders.dispositions,
                       LocalReminderReconciliationDispositionV1.allCases.map(\.rawValue))
        XCTAssertTrue(corpus.reminders.stableIdentifiers)
        XCTAssertFalse(corpus.reminders.deliveryIsCompletion)
        XCTAssertFalse(corpus.reminders.denialChangesCanonicalDueQueue)
        XCTAssertFalse(corpus.reminders.evictionChangesCanonicalDueQueue)
    }

    func testV23P04C22H01DSTTimeZoneActiveEditHorizonRetiredPartialPacketFailClosed() throws {
        let corpus = try C22RecurringRoundTestSupport.corpus()
        XCTAssertEqual(Set(corpus.hostileCases), Set([
            "DST_GAP", "DST_FOLD", "TIME_ZONE_CHANGED", "ACTIVE_OCCURRENCE_EDIT",
            "MISSED_HORIZON", "RETIRED_ASSET", "PARTIAL_OFFLINE_PACKET",
            "DUPLICATE_COMPLETION", "NOTIFICATION_LIMIT", "NOTIFICATION_EVICTED",
            "MISSING_READINESS", "STALE_READINESS", "WRONG_WORKSPACE_READINESS",
            "MISMATCHED_WORK_INSTANCE", "MISSING_ROUND_FRONTIER", "STALE_ROUND_FRONTIER",
            "MISMATCHED_WORK_PACKET_FRONTIER",
        ]))
        let fixed = try makeFixed(slot: 600, maximum: 1)
        let editor = try ScheduleEditorStateV1(release: fixed)
        XCTAssertEqual(editor.visibleTimeBasis.nonexistentTimePolicy, .shiftForwardByGap)
        XCTAssertEqual(editor.visibleTimeBasis.ambiguousTimePolicy, .earlierOffset)
        XCTAssertEqual(editor.visibleMaximumOccurrenceCount, 1)
        XCTAssertThrowsError(try OccurrenceGenerationWindowV1(
            startsAtUTC: fixed.startsAtUTC,
            endsAtUTC: fixed.startsAtUTC.addingTimeInterval(86_400),
            maximumOccurrences: 2
        ).validate(definition: fixed))
        XCTAssertEqual(corpus.occurrenceStates, OccurrenceStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.dueReasons, OccurrenceDueReasonV1.allCases.map(\.rawValue))
        XCTAssertTrue(ScheduleLocalizationKeyV1.allCases.contains(.offlinePartial))
        XCTAssertNoThrow(try ScheduleLocalizationPolicyV1.validate())
        XCTAssertNoThrow(try ScheduleAccessibilityPolicyV1.validateExperienceRequirements())
        let (queue, generated) = try dueProjection(fixed, slot: 620)
        XCTAssertFalse(queue.entries.isEmpty)
        let sessions = try C22RecurringRoundTestSupport.roundSessions()
        let work = ScheduledWorkInstanceReferenceV1.roundSession(
            sessionID: sessions.active.sessionID, revision: sessions.active.revision,
            sessionSHA256: sessions.active.sessionSHA256
        )
        let started = try C22RecurringRoundTestSupport.event(
            release: fixed, occurrenceID: generated.occurrenceID,
            basis: generated.nominalBasis, action: .start,
            predecessor: generated, work: work, slot: 622
        )
        let request = try RecurringRoundStartRequestV1(
            event: started, predecessor: generated, release: fixed,
            explicitUserConfirmation: true
        )
        XCTAssertThrowsError(try RecurringRoundStartFrontierBoundaryV1.validate(request: request))
        XCTAssertThrowsError(try RecurringRoundStartReadinessV1(request: request))
        XCTAssertThrowsError(try RecurringRoundStartReadinessV1(
            request: request,
            roundManifest: C22RecurringRoundTestSupport.readinessManifest(session: sessions.draft)
        ))
        let blocked = try RecurringRoundStartReadinessV1(
            request: request,
            roundManifest: C22RecurringRoundTestSupport.readinessManifest(
                session: sessions.active, protectedDataAvailable: false
            )
        )
        XCTAssertThrowsError(try blocked.requireReady())
        let exact = try RecurringRoundStartReadinessV1(
            request: request,
            roundManifest: C22RecurringRoundTestSupport.readinessManifest(session: sessions.active)
        )
        let writer = C22ScheduleWriterProbe()
        let coordinator = RecurringRoundExperienceCoordinatorV1(
            schedule: ScheduleCoordinatorV1(writer: writer),
            reminders: DeviceLocalScheduleReminderReconcilerV1(port: C22ReminderPortProbe())
        )
        XCTAssertThrowsError(try coordinator.start(
            request, readiness: exact, currentRoundSession: sessions.draft
        ))
        XCTAssertThrowsError(try coordinator.start(
            request, readiness: blocked, currentRoundSession: sessions.active
        ))
        XCTAssertEqual(writer.applyCount, 0)
        XCTAssertFalse(corpus.statusFlags.shippingUIAdopted)
        XCTAssertTrue(corpus.statusFlags.requiresAcceptedS10_6Reconciliation)
    }

    func testV23P04C22I01InterruptedWritesAndSameMutationIDRecoverIdempotently() throws {
        let fixed = try makeFixed(slot: 700)
        let (_, generated) = try dueProjection(fixed, slot: 720)
        let basis = generated.nominalBasis
        let work = ScheduledWorkInstanceReferenceV1.roundSession(
            sessionID: C22RecurringRoundTestSupport.id(730), revision: 1,
            sessionSHA256: C22RecurringRoundTestSupport.digest("8")
        )
        let started = try C22RecurringRoundTestSupport.event(
            release: fixed, occurrenceID: generated.occurrenceID, basis: basis,
            action: .start, predecessor: generated, work: work, slot: 731
        )
        let first = try RecurringRoundStartRequestV1(
            event: started, predecessor: generated, release: fixed,
            explicitUserConfirmation: true
        )
        let reopened = try ScheduleCanonicalCodecV1.decode(
            RecurringRoundStartRequestV1.self,
            from: ScheduleCanonicalCodecV1.data(first)
        )
        XCTAssertEqual(first, reopened)
        XCTAssertEqual(first.event.mutationID, reopened.event.mutationID)
        XCTAssertEqual(first.requestSHA256, reopened.requestSHA256)
        let corpus = try C22RecurringRoundTestSupport.corpus()
        XCTAssertEqual(corpus.interruptionBoundaries, [
            "BEFORE_PREPARE", "AFTER_PREPARE", "AFTER_EFFECT_BEFORE_RECEIPT",
            "AFTER_RECEIPT_BEFORE_RETURN",
        ])
        XCTAssertTrue(corpus.recovery.sameMutationIDReturnsSameReceipt)
        XCTAssertTrue(corpus.recovery.sameMutationIDDifferentPayloadRejected)
        XCTAssertTrue(corpus.recovery.effectBeforeReceipt)
        XCTAssertEqual(RecurringRoundExperiencePersistenceBoundaryV1.schemaVersion, 53)
        XCTAssertEqual(RecurringRoundExperiencePersistenceBoundaryV1.activeModelCount, 168)
        XCTAssertEqual(RecurringRoundExperiencePersistenceBoundaryV1.addedRowFamilyCount, 0)
    }

    func testV23P04C22R01BackupReplaceCloneForkRebuildAndHistoryRemainImmutable() async throws {
        let fixed = try makeFixed(slot: 800)
        let (queue, generated) = try dueProjection(fixed, slot: 820)
        let reminder = try ReminderProjectionV1(
            dueQueue: queue, localizationKey: ScheduleLocalizationKeyV1.reminder.rawValue
        )
        let restoredRelease = try ScheduleCanonicalCodecV1.decode(
            ScheduleDefinitionReleaseV1.self,
            from: ScheduleCanonicalCodecV1.data(fixed)
        )
        let restoredEvent = try ScheduleCanonicalCodecV1.decode(
            OccurrenceHistoryEventV1.self,
            from: ScheduleCanonicalCodecV1.data(generated)
        )
        let rebuiltQueue = try DueQueueProjectionV1(
            workspaceID: fixed.workspaceID, evaluatedAt: C22RecurringRoundTestSupport.now,
            definitions: [restoredRelease], history: [restoredEvent]
        )
        let rebuiltReminder = try ReminderProjectionV1(
            dueQueue: rebuiltQueue, localizationKey: ScheduleLocalizationKeyV1.reminder.rawValue
        )
        XCTAssertEqual(rebuiltQueue, queue)
        XCTAssertEqual(rebuiltReminder, reminder)
        XCTAssertEqual(restoredEvent.eventSHA256, generated.eventSHA256)

        let scheduleProjection = try ReportProjectionRegistryV1.scheduleProjection(
            definition: restoredRelease, dueQueue: rebuiltQueue,
            history: [restoredEvent]
        )
        let occurrence = try XCTUnwrap(scheduleProjection.occurrences.first)
        let searchRecord = try ScheduleOccurrenceSearchRecordV1(
            projection: scheduleProjection, occurrence: occurrence
        )
        let currentMatches = try await SearchCoordinatorV1.searchCurrentScheduleOccurrenceMetadata(
            query: occurrence.state.rawValue, workspaceID: fixed.workspaceID,
            records: [searchRecord], currentReleases: [.init(restoredRelease)],
            accessGate: C22AccessGateProbe()
        )
        XCTAssertEqual(currentMatches, [searchRecord])
        let reviewed = try ReportProjectionRegistryV1.recurringRoundReviewedHistory(
            definition: restoredRelease, dueQueue: rebuiltQueue,
            occurrenceHistory: [restoredEvent], roundSessions: []
        )
        XCTAssertEqual(reviewed.schedule, scheduleProjection)
        XCTAssertTrue(reviewed.roundProgress.isEmpty)

        let sessions = try C22RecurringRoundTestSupport.roundSessions()
        let plan = try C22RecurringRoundTestSupport.myDayPlan(session: sessions.active)
        let myDay = MyDayCoordinatorV1(
            writer: C22MyDayWriterProbe(), sourceReader: C22MyDaySourceProbe()
        )
        let experience = try myDay.recurringRoundExperience(
            for: plan, dueQueue: try OccurrenceDueQueueStateV1(projection: rebuiltQueue)
        )
        XCTAssertEqual(experience.dueQueueSHA256,
                       try OccurrenceDueQueueStateV1(projection: rebuiltQueue).stateSHA256)
        XCTAssertTrue(experience.hasPartialReadiness)

        let corpus = try C22RecurringRoundTestSupport.corpus()
        XCTAssertEqual(corpus.transformations.map(\.kind),
                       ["BACKUP", "REPLACE_RESTORE", "CLONE", "FORK"])
        XCTAssertTrue(corpus.transformations.allSatisfy(\.historyImmutable))
        XCTAssertFalse(try XCTUnwrap(corpus.transformations.first).derivedQueueArchived ?? true)
        XCTAssertTrue(corpus.accessibility.voiceOverOrderIsSourceOrder)
        XCTAssertTrue(corpus.accessibility.voiceControlUsesVisibleNames)
        XCTAssertEqual(corpus.accessibility.dynamicTypeMaximum, "AX5")
        XCTAssertTrue(corpus.accessibility.rightToLeftSupported)
        XCTAssertTrue(corpus.accessibility.statusUsesTextAndIcon)
        XCTAssertTrue(corpus.accessibility.reduceMotionUsesStaticPresentation)
        XCTAssertTrue(corpus.accessibility.errorFocusIsDeterministic)
        XCTAssertTrue(corpus.accessibility.permissionDenialKeepsManualDuePath)
    }

    private func makeFixed(slot: Int, maximum: Int = 8) throws -> ScheduleDefinitionReleaseV1 {
        let anchor = ScheduleLocalAnchorV1(
            year: nil, month: nil, day: nil, weekday: nil,
            weekdayOrdinal: nil, hour: 9, minute: 0, second: 0
        )
        return try C22RecurringRoundTestSupport.release(
            recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)),
            slot: slot, maximum: maximum
        )
    }

    private func dueProjection(
        _ release: ScheduleDefinitionReleaseV1, slot: Int
    ) throws -> (DueQueueProjectionV1, OccurrenceHistoryEventV1) {
        let basis = try C22RecurringRoundTestSupport.basis(release)
        let occurrenceID = try OccurrenceIDV1(
            scheduleDefinitionID: release.scheduleDefinitionID,
            identityNamespaceID: release.occurrenceIdentityNamespaceID,
            nominalKey: basis.nominalKey
        )
        let generated = try C22RecurringRoundTestSupport.event(
            release: release, occurrenceID: occurrenceID, basis: basis,
            action: .generated, slot: slot
        )
        let queue = try DueQueueProjectionV1(
            workspaceID: release.workspaceID, evaluatedAt: C22RecurringRoundTestSupport.now,
            definitions: [release], history: [generated]
        )
        return (queue, generated)
    }
}

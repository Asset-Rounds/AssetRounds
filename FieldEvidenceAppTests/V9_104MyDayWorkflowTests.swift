import XCTest
import SwiftData
@testable import FieldEvidenceApp

private enum C41 {
    static let workspace = WorkspaceID(rawValue: id(1))
    static let otherWorkspace = WorkspaceID(rawValue: id(2))
    static let now = Date(timeIntervalSince1970: 1_735_776_000)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "41000000-0000-4000-8000-%012d", value))!
    }
    static func digest(_ character: Character) -> String { String(repeating: String(character), count: 64) }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try .init(rawValue: id(value)) }
    static func key(_ day: String = "2026-09-01", workspaceID: WorkspaceID = workspace) throws -> MyDayKeyV1 {
        try .init(workspaceID: workspaceID, civilDate: .init(day), ianaTimeZoneIdentifier: "America/New_York")
    }
    static func actor(_ value: Int = 10, workspaceID: WorkspaceID = workspace) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(actorReferenceID: id(value), workspaceID: workspaceID,
                                                  displayName: "Synthetic My Day recorder")
        return try .init(snapshotID: id(value + 1), workspaceID: workspaceID, actor: reference,
                         responsibility: .recordedBy, displayNameAtTime: reference.displayName,
                         capturedAt: now)
    }
    static func round(_ value: Int, workspaceID: WorkspaceID = workspace,
                      revision: UInt64 = 1, sha: Character = "a") -> MyDayEligibleReferenceV1 {
        .roundSession(workspaceID: workspaceID, sessionID: id(100 + value), revision: revision,
                      sessionSHA256: digest(sha))
    }
    static func draft(_ value: Int, workspaceID: WorkspaceID = workspace) -> MyDayEligibleReferenceV1 {
        .resumableDraft(workspaceID: workspaceID, draftID: id(200 + value), revision: 1,
                        checkpointSHA256: digest("b"),
                        anchor: try! DraftResumeAnchorV1(sectionID: "summary"))
    }
    static func workPacket(_ value: Int, workspaceID: WorkspaceID = workspace) throws
        -> MyDayEligibleReferenceV1 {
        let packetItem = try WorkPacketItemV1(itemID: "c41-item-\(value)", kind: .inspection,
            expectedRevision: 1, itemSHA256: digest("w"))
        let manifest = try WorkPacketManifestV1(manifestID: id(230 + value),
            packetID: id(240 + value), packetVersion: 1, workspaceID: workspaceID,
            items: [packetItem], packageReleases: [], creationBasis: .explicitLocalSelection,
            creator: try actor(250 + value, workspaceID: workspaceID), createdAt: now)
        return .workPacket(try WorkPacketManifestReferenceV1(manifest))
    }
    static func item(_ value: Int, reference: MyDayEligibleReferenceV1,
                     estimate: Int? = nil) throws -> MyDayDraftItemV1 {
        try .init(membershipID: id(300 + value), reference: reference,
                  estimate: try estimate.map { try MyDayEstimateV1(wholeMinutes: $0) })
    }
    static func emptyDue(workspaceID: WorkspaceID = workspace, at: Date = now) throws -> OccurrenceDueQueueStateV1 {
        try DueQueueProjectionV1(workspaceID: workspaceID, evaluatedAt: at,
                                 definitions: [], history: []).recurringRoundState()
    }
    static func emptyExceptions(workspaceID: WorkspaceID = workspace) throws -> ExceptionQueueProjectionV1 {
        try .init(workspaceID: workspaceID,
                  registry: .init(registeredKinds: ExceptionQueueSourceKindV1.allCases.sorted { $0.rawValue < $1.rawValue }),
                  sources: [], resolver: C41EmptyExceptionResolver())
    }
    static func oneException(workspaceID: WorkspaceID = workspace) throws -> ExceptionQueueProjectionV1 {
        let source = try ExceptionQueueSourceSnapshotV1(workspaceID: workspaceID,
            kind: ExceptionQueueSourceKindV1.allCases[0], sourceID: "c41-exception",
            sourceRevision: 1, sourceSHA256: digest("e"), evidenceSHA256: digest("f"),
            severity: .warning, reasons: [ExceptionQueueReasonV1.allCases[0]],
            deepLink: ExceptionQueueDeepLinkV1.allCases[0])
        return try .init(workspaceID: workspaceID,
            registry: .init(registeredKinds: ExceptionQueueSourceKindV1.allCases.sorted { $0.rawValue < $1.rawValue }),
            sources: [source], resolver: C41ExactExceptionResolver(source: source))
    }
}

private struct C41Clock: ApplicationClock { func now() -> Date { C41.now } }
private struct C41FixedID: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}
private struct C41EmptyExceptionResolver: ExceptionQueueCanonicalSourceResolvingV1 {
    func resolveExceptionQueueSource(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1,
                                     sourceID: String, revision: UInt64) throws -> ExceptionQueueSourceSnapshotV1 {
        throw ReinspectionExceptionFailureV1.missingSource
    }
}
private struct C41ExactExceptionResolver: ExceptionQueueCanonicalSourceResolvingV1 {
    let source: ExceptionQueueSourceSnapshotV1
    func resolveExceptionQueueSource(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1,
                                     sourceID: String, revision: UInt64) throws -> ExceptionQueueSourceSnapshotV1 {
        guard source.workspaceID == workspaceID, source.kind == kind,
              source.sourceID == sourceID, source.sourceRevision == revision else {
            throw ReinspectionExceptionFailureV1.missingSource
        }
        return source
    }
}

@MainActor private final class C41SourceReader: MyDaySourceFrontierReadingV1 {
    var states: [UUID: MyDaySourceStateV1] = [:]
    var readiness: [UUID: MyDayReadinessV1] = [:]
    var current: [UUID: MyDayEligibleReferenceV1?] = [:]
    var due: [UUID: Date?] = [:]

    func sourceFrontiers(for plan: MyDayPlanV1, evaluatedAt: Date) throws -> [MyDaySourceFrontierV1] {
        try plan.items.map { item in
            let state = states[item.membershipID] ?? .active
            let resolved: MyDayEligibleReferenceV1?
            if let supplied = current[item.membershipID] { resolved = supplied }
            else { resolved = state == .missing ? nil : item.reference }
            return try .init(membershipID: item.membershipID, plannedReference: item.reference,
                             currentReference: resolved, state: state,
                             readiness: readiness[item.membershipID] ?? (resolved == nil ? .unavailable : .ready),
                             dueAt: due[item.membershipID] ?? nil, evaluatedAt: evaluatedAt)
        }
    }
}

private enum C41InjectedFailure: Error, Equatable { case afterEffectBeforeReceipt }

@MainActor private final class C41Writer: MyDayWritingV1 {
    var plans: [String: MyDayPlanV1] = [:]
    var results: [UUID: MyDayCommandResultV1] = [:]
    var committedCommands: [MyDayCommandV1] = []
    var interruptAfterEffectOnce = false

    func currentPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1? { plans[key.stableKey] }
    func result(workspaceID: WorkspaceID, mutationID: MutationIDV1) throws -> MyDayCommandResultV1? {
        guard let value = results[mutationID.rawValue] else { return nil }
        guard value.plan.key.workspaceID == workspaceID else { throw MyDayFailureV1.wrongWorkspace }
        return value
    }
    func commit(_ command: MyDayCommandV1) throws -> MyDayCommandResultV1 {
        try command.validate()
        if let prior = results[command.mutationID.rawValue] {
            _ = try MyDayCommandReplayResolutionV1.resolve(command: command, priorReceipt: prior.receipt)
            return prior
        }
        let plan: MyDayPlanV1
        let carry: MyDayCarryoverReceiptV1?
        switch command {
        case let .save(successor, _): plan = successor; carry = nil
        case let .carryover(_, _, target, receipt): plan = target; carry = receipt
        }
        let receipt = try MyDayMutationReceiptV1(command: command, resultingPlan: plan,
            carryoverReceipt: carry, disposition: .committed, committedAt: C41.now)
        let result = MyDayCommandResultV1(plan: plan, receipt: receipt)
        plans[plan.key.stableKey] = plan
        results[command.mutationID.rawValue] = result
        committedCommands.append(command)
        if interruptAfterEffectOnce {
            interruptAfterEffectOnce = false
            throw C41InjectedFailure.afterEffectBeforeReceipt
        }
        return result
    }
}

@MainActor private struct C41Harness {
    let writer: C41Writer
    let sources: C41SourceReader
    let workflow: MyDayWorkflowCoordinatorV1
    init() {
        writer = C41Writer(); sources = C41SourceReader()
        workflow = .init(canonical: .init(writer: writer, sourceReader: sources), clock: C41Clock())
    }
    func preview(items: [MyDayDraftItemV1], key: MyDayKeyV1 = try! C41.key(),
                 planID: UUID = C41.id(500), mutation: Int = 501,
                 predecessor: MyDayPlanV1? = nil) throws -> MyDaySavePreviewV1 {
        let draft = try workflow.draft(key: key, selectedItems: items,
                                       eligibleReferences: items.map(\.reference))
        return try workflow.previewSave(draft: draft, predecessor: predecessor, planID: planID,
                                        mutationID: C41.mutation(mutation), actor: C41.actor())
    }
}

@MainActor private final class C41RealWriterHarness {
    let root: URL
    let session: StoreGenerationSession
    let sources = C41SourceReader()
    let checkpoint: FieldDraftCheckpointV1
    let reference: MyDayEligibleReferenceV1

    init(_ name: String) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c41-\(name)-\(UUID().uuidString)")
        session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
        checkpoint = try FieldDraftCheckpointV1(
            draftID: C41.id(600), workspaceID: session.workspaceID,
            scope: .init(scopeKind: "MY_DAY_TEST", stableComponentIDs: ["synthetic-draft"]),
            purpose: .assetFieldEdit,
            codec: .init(codecID: "C41_SYNTHETIC", codecVersion: 1,
                         releaseSHA256: C41.digest("c")),
            baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: Data("synthetic".utf8), stageIDs: [],
            resumeAnchor: .init(sectionID: "my-day"), state: .active,
            updatedAt: C41.now, mutationID: C41.mutation(601)
        )
        session.modelContext.insert(try FieldDraftCheckpointRow(checkpoint))
        try session.modelContext.save()
        reference = .resumableDraft(workspaceID: session.workspaceID,
            draftID: checkpoint.draftID, revision: checkpoint.draftRevision,
            checkpointSHA256: checkpoint.checkpointSHA256, anchor: checkpoint.resumeAnchor)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func workflow(failure: MutationJournalFailureInjectionV1? = nil) throws
        -> MyDayWorkflowCoordinatorV1 {
        let writerID = C41.id(602)
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID,
            failureInjection: failure)
        let writer = try WorkspaceWriterV1(identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerID),
            clock: C41Clock(), idSource: C41FixedID(value: writerID),
            fileAuthority: SystemApplicationFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: journal)
        return .init(canonical: .init(writer: writer, sourceReader: sources), clock: C41Clock())
    }

    func preview(workflow: MyDayWorkflowCoordinatorV1, mutation: Int,
                 estimate: Int = 25) throws -> MyDaySavePreviewV1 {
        let item = try C41.item(90, reference: reference, estimate: estimate)
        let draft = try workflow.draft(key: C41.key(workspaceID: session.workspaceID),
                                       selectedItems: [item], eligibleReferences: [reference])
        return try workflow.previewSave(draft: draft, predecessor: nil,
            planID: C41.id(603), mutationID: C41.mutation(mutation),
            actor: C41.actor(604, workspaceID: session.workspaceID))
    }

    func planRowCount() throws -> Int {
        try session.modelContext.fetch(FetchDescriptor<MyDayPlanRowV1>()).count
    }
}

final class V9_104MyDayWorkflowTests: XCTestCase {
    private func corpus() throws -> [String: Any] {
        let name = "V23P04C41MyDayWorkflowCorpusV1"
        let bundled = Bundle(for: Self.self).url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/V23/MyDay"
        )
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/MyDay/\(name).json")
        return try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: bundled ?? source)
        ) as? [String: Any])
    }

    @MainActor
    func testV23P04C41G01SelectionOrderSummaryRoutesCarryoverAndReconcile() throws {
        let fixture = try corpus()
        XCTAssertEqual(fixture["cardID"] as? String, "V23-P04-C41")
        XCTAssertEqual(fixture["evidenceIDs"] as? [String], [
            "V23-P04-C41-G01", "V23-P04-C41-A01", "V23-P04-C41-H01",
            "V23-P04-C41-I01", "V23-P04-C41-R01"
        ])
        let h = C41Harness()
        let schedule = try C41MyDayScheduleFixtureV1.make(
            workspaceID: C41.workspace,
            actor: C41.actor(70)
        )
        let selected = try [
            C41.item(1, reference: C41.round(1), estimate: 30),
            C41.item(2, reference: C41.draft(2), estimate: 15),
            C41.item(3, reference: C41.workPacket(3), estimate: 15),
            C41.item(4, reference: schedule.reference, estimate: 20)
        ]
        let preview = try h.preview(items: selected)
        XCTAssertTrue(preview.zeroWrite)
        XCTAssertEqual(preview.successor.items.map(\.manualOrder), [0, 1, 2, 3])
        XCTAssertEqual(h.writer.committedCommands.count, 0)
        guard case let .saved(saved) = try h.workflow.execute(.save(preview)) else {
            return XCTFail("save outcome")
        }
        XCTAssertEqual(saved.plan.items.map(\.reference), selected.map(\.reference))
        let summary = try h.workflow.summary(plan: saved.plan, dueQueue: schedule.dueQueue,
                                             exceptionQueue: C41.oneException())
        XCTAssertEqual(summary.totalEstimatedMinutes, 80)
        XCTAssertEqual(summary.items.map(\.readiness), [.ready, .ready, .ready, .ready])
        XCTAssertEqual(summary.items.map(\.dueCue), [.none, .none, .none, .due])
        XCTAssertEqual(summary.unresolvedExceptionCount, 1)
        XCTAssertEqual(try h.workflow.routeIntent(from: summary,
            membershipID: saved.plan.items[0].membershipID).action, .start)
        XCTAssertEqual(try h.workflow.routeIntent(from: summary,
            membershipID: saved.plan.items[1].membershipID).action, .resume)
        let targetKey = try C41.key("2026-09-02")
        let carry = try h.workflow.previewCarryover(source: saved.plan, sourceSummary: summary,
            targetKey: targetKey, targetPredecessor: nil,
            membershipIDs: saved.plan.items.map(\.membershipID), targetPlanID: C41.id(510),
            mutationID: C41.mutation(511), actor: C41.actor())
        XCTAssertTrue(carry.zeroWrite)
        guard case let .carriedOver(result) = try h.workflow.execute(.carryover(carry)) else {
            return XCTFail("carryover outcome")
        }
        XCTAssertEqual(result.plan.items.map(\.membershipID), saved.plan.items.map(\.membershipID))
        XCTAssertEqual(h.writer.plans[saved.plan.key.stableKey], saved.plan)
    }

    @MainActor
    func testV23P04C41A01AccessibleMovesOptionalEstimatesAndLifecycleStates() throws {
        let h = C41Harness()
        let items = try [C41.item(11, reference: C41.round(11)),
                         C41.item(12, reference: C41.draft(12), estimate: 20),
                         C41.item(13, reference: C41.round(13), estimate: 40)]
        let draft = try h.workflow.draft(key: C41.key(), selectedItems: items,
                                         eligibleReferences: items.map(\.reference))
        let movedByButton = try h.workflow.move(draft, action: .up(membershipID: items[2].membershipID))
        let movedByIndex = try h.workflow.move(draft,
            action: .toIndex(membershipID: items[2].membershipID, index: 1))
        XCTAssertEqual(movedByButton, movedByIndex)
        XCTAssertNil(movedByButton.items[0].estimate)
        let preview = try h.workflow.previewSave(draft: movedByButton, predecessor: nil,
            planID: C41.id(520), mutationID: C41.mutation(521), actor: C41.actor())
        guard case let .saved(saved) = try h.workflow.execute(.save(preview)) else {
            return XCTFail("save")
        }
        h.sources.states[saved.plan.items[0].membershipID] = .completed
        h.sources.states[saved.plan.items[1].membershipID] = .cancelled
        h.sources.states[saved.plan.items[2].membershipID] = .reopened
        let summary = try h.workflow.summary(plan: saved.plan, dueQueue: C41.emptyDue(),
                                             exceptionQueue: C41.emptyExceptions())
        XCTAssertEqual(summary.items.map(\.status), [.completed, .cancelled, .reopened])
        XCTAssertNil(summary.items[0].routeIntent)
        XCTAssertNil(summary.items[1].routeIntent)
        XCTAssertEqual(summary.items[2].routeIntent?.action, .resume)
    }

    @MainActor
    func testV23P04C41H01HostileIdentityOrderFrontierAndMutationAttemptsHaveNoEffect() throws {
        let h = C41Harness()
        let valid = try C41.item(21, reference: C41.round(21))
        XCTAssertThrowsError(try h.workflow.draft(key: C41.key(), selectedItems: [valid],
            eligibleReferences: [C41.round(22)]))
        let foreign = try C41.item(22, reference: C41.round(22, workspaceID: C41.otherWorkspace))
        XCTAssertThrowsError(try MyDayPlanDraftV1(key: C41.key(), items: [foreign]))
        XCTAssertThrowsError(try MyDayPlanDraftV1(key: C41.key(), items: [valid, valid]))
        let draft = try h.workflow.draft(key: C41.key(), selectedItems: [valid],
                                         eligibleReferences: [valid.reference])
        XCTAssertThrowsError(try h.workflow.move(draft, action: .up(membershipID: valid.membershipID)))
        XCTAssertEqual(h.writer.committedCommands.count, 0)
        let preview = try h.workflow.previewSave(draft: draft, predecessor: nil,
            planID: C41.id(530), mutationID: C41.mutation(531), actor: C41.actor())
        guard case let .saved(first) = try h.workflow.execute(.save(preview)) else {
            return XCTFail("setup")
        }
        let stale = try h.preview(items: [valid], planID: first.plan.planID, mutation: 532)
        XCTAssertThrowsError(try h.workflow.execute(.save(stale)))
        h.sources.current[valid.membershipID] = C41.round(21, revision: 2, sha: "z")
        let successorDraft = try h.workflow.draft(key: first.plan.key, selectedItems: [valid],
                                                  eligibleReferences: [valid.reference])
        let successor = try h.workflow.previewSave(draft: successorDraft, predecessor: first.plan,
            planID: first.plan.planID, mutationID: C41.mutation(533), actor: C41.actor())
        XCTAssertThrowsError(try h.workflow.execute(.save(successor)))
        XCTAssertEqual(h.writer.committedCommands.count, 1)
        XCTAssertFalse(try h.workflow.summary(plan: first.plan, dueQueue: C41.emptyDue(),
            exceptionQueue: C41.emptyExceptions()).automaticPrioritizationApplied)

        let real = try C41RealWriterHarness("H-divergent")
        let realWorkflow = try real.workflow()
        let accepted = try real.preview(workflow: realWorkflow, mutation: 535, estimate: 25)
        _ = try realWorkflow.execute(.save(accepted))
        let divergent = try real.preview(workflow: realWorkflow, mutation: 535, estimate: 30)
        XCTAssertThrowsError(try realWorkflow.execute(.save(divergent))) { error in
            XCTAssertEqual(error as? MyDayFailureV1, .divergentMutation)
        }
        XCTAssertEqual(try real.planRowCount(), 1)
    }

    @MainActor
    func testV23P04C41I01EffectBeforeReceiptRecoveryUsesOneExactMutation() throws {
        let h = try C41RealWriterHarness("I-recovery")
        let faulted = try h.workflow(failure: .init(failOnceAt: .afterEffectBeforeReceipt))
        let preview = try h.preview(workflow: faulted, mutation: 541)
        do {
            _ = try faulted.execute(.save(preview))
            XCTFail("effect-before-receipt must interrupt")
        } catch {
            XCTAssertEqual(error as? MutationJournalFailureV1,
                           .injected(.afterEffectBeforeReceipt))
        }
        XCTAssertTrue([0, 1].contains(try h.planRowCount()))
        let recoveredWorkflow = try h.workflow()
        guard case let .saved(recovered) = try recoveredWorkflow.execute(.recoverSave(preview)),
              case let .saved(replayed) = try recoveredWorkflow.execute(.recoverSave(preview)) else {
            return XCTFail("recover/replay")
        }
        XCTAssertEqual(recovered, replayed)
        XCTAssertEqual(recovered.receipt.mutationID, preview.successor.mutationID)
        XCTAssertEqual(try h.planRowCount(), 1)
    }

    @MainActor
    func testV23P04C41R01RebuildAndCarryoverFilterPreserveHistoryAndNamespaces() throws {
        let h = C41Harness()
        let preview = try h.preview(items: try (0..<7).map {
            try C41.item(40 + $0, reference: C41.round(40 + $0), estimate: $0 == 0 ? 10 : nil)
        }, planID: C41.id(550), mutation: 551)
        guard case let .saved(saved) = try h.workflow.execute(.save(preview)) else {
            return XCTFail("save")
        }
        let states: [MyDaySourceStateV1] = [.active, .reopened, .completed, .cancelled,
                                            .retired, .missing, .stale]
        for (item, state) in zip(saved.plan.items, states) { h.sources.states[item.membershipID] = state }
        let staleItem = try XCTUnwrap(saved.plan.items.last)
        h.sources.current[staleItem.membershipID] = C41.round(
            46, revision: 2, sha: "z"
        )
        let due = try C41.emptyDue()
        let exceptions = try C41.emptyExceptions()
        let first = try h.workflow.summary(plan: saved.plan, dueQueue: due, exceptionQueue: exceptions)
        let rebuilt = try h.workflow.summary(plan: saved.plan, dueQueue: due, exceptionQueue: exceptions)
        XCTAssertEqual(first, rebuilt)
        XCTAssertEqual(first.carryoverEligibleMembershipIDs,
                       Array(saved.plan.items.prefix(2)).map(\.membershipID))
        XCTAssertNil(first.items.last?.routeIntent)
        let committedBeforeStaleAttempt = h.writer.committedCommands.count
        XCTAssertThrowsError(try h.workflow.previewCarryover(source: saved.plan,
            sourceSummary: first, targetKey: C41.key("2026-09-03"), targetPredecessor: nil,
            membershipIDs: [staleItem.membershipID], targetPlanID: C41.id(554),
            mutationID: C41.mutation(555), actor: C41.actor())) { error in
            XCTAssertEqual(error as? MyDayWorkflowFailureV1, .carryoverIneligible)
        }
        XCTAssertEqual(h.writer.committedCommands.count, committedBeforeStaleAttempt)
        let carry = try h.workflow.previewCarryover(source: saved.plan, sourceSummary: first,
            targetKey: C41.key("2026-09-03"), targetPredecessor: nil,
            membershipIDs: first.carryoverEligibleMembershipIDs, targetPlanID: C41.id(552),
            mutationID: C41.mutation(553), actor: C41.actor())
        guard case let .carriedOver(committed) = try h.workflow.execute(.carryover(carry)),
              case let .carriedOver(recovered) = try h.workflow.execute(.recoverCarryover(carry)) else {
            return XCTFail("carry recovery")
        }
        XCTAssertEqual(committed, recovered)
        XCTAssertEqual(h.writer.plans[saved.plan.key.stableKey], saved.plan)
        XCTAssertEqual(C57MyDayCoordinatorLifecycleBoundaryV1.sourceMutationCount, 0)
        XCTAssertEqual(C22RecurringRoundMyDayBoundaryV1.storedQueueProjectionCount, 0)
    }
}

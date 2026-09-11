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

/// Inactive in-memory active-schema fixture: every post-bootstrap mutation
/// goes through the actual adapter/journal/writer. This is not startup proof.
@MainActor private final class C41CanonicalWriterHarness {
    let container: ModelContainer
    let context: ModelContext
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1

    init(historicalPlans: [MyDayPlanV1] = []) throws {
        let schema = try PersistentSchemaReleaseRegistryV1.activeSchema()
        container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [
            ModelConfiguration("C41Canonical", schema: schema, isStoredInMemoryOnly: true,
                allowsSave: true, cloudKitDatabase: .none),
        ])
        context = container.mainContext
        context.autosaveEnabled = false
        for plan in historicalPlans {
            context.insert(try MyDayPlanRowV1(plan))
            let revision = EntityMutationRevisionRow(
                identity: try .init(kind: .myDayPlan, id: plan.planID), revision: plan.revision)
            revision.externalProjectionSHA256 = plan.planSHA256
            context.insert(revision)
        }
        try context.save()
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: C41.workspace,
            replicaID: ReplicaID(rawValue: C41.id(980)))
        let generation = C41.id(981), writerID = C41.id(982)
        journal = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: generation)
        // A historical missing source is a valid plan baseline, not deletion
        // or corruption of an existing journal's immutable source history.
        try journal.validateAll()
        writer = try WorkspaceWriterV1(identity: identity, generationID: generation,
            initialRevision: journal.currentRevision(writerInstanceID: writerID),
            clock: C41Clock(), idSource: C41FixedID(value: writerID),
            fileAuthority: SystemApplicationFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal)
    }

    func save(_ items: [MyDayItemV1], seed: Int, predecessor: MyDayPlanV1? = nil,
              key: MyDayKeyV1 = try! C41.key()) throws -> MyDayCommandResultV1 {
        let plan = try MyDayPlanV1(planID: predecessor?.planID ?? C41.id(seed), key: key,
            items: items, predecessor: predecessor, revision: (predecessor?.revision ?? 0) + 1,
            mutationID: C41.mutation(seed + 1), authoredBy: C41.actor(), authoredAt: C41.now)
        return try writer.commit(.save(successor: plan, predecessor: predecessor))
    }

    func planCount() throws -> Int { try context.fetch(FetchDescriptor<MyDayPlanRowV1>()).count }
    func receiptCount() throws -> Int { try context.fetch(FetchDescriptor<MutationReceiptRow>()).count }

    func carryCommand(source: MyDayPlanV1, predecessor: MyDayPlanV1,
                      membershipID: UUID, seed: Int) throws -> MyDayCommandV1 {
        let carry = try MyDayCarryoverPlanV1(sourcePlan: source, targetKey: predecessor.key,
            membershipIDs: [membershipID], expectedTargetPlan: predecessor)
        let selected = try XCTUnwrap(source.items.first { $0.membershipID == membershipID })
        var items = predecessor.items.filter { $0.membershipID != membershipID }
        items.append(try MyDayItemV1(membershipID: selected.membershipID,
            reference: selected.reference, manualOrder: items.count, estimate: selected.estimate))
        let target = try MyDayPlanV1(planID: predecessor.planID, key: predecessor.key, items: items,
            predecessor: predecessor, revision: predecessor.revision + 1,
            mutationID: C41.mutation(seed), authoredBy: C41.actor(), authoredAt: C41.now)
        let receipt = try MyDayCarryoverReceiptV1(plan: carry, source: source, target: target,
            mutationID: target.mutationID, committedAt: C41.now)
        return .carryover(plan: carry, source: source, target: target, receipt: receipt)
    }
}

final class V9_104MyDayWorkflowTests: XCTestCase {
    @MainActor
    func testActualWriterRetainsMissingHistoryAndRejectsNewOrReboundMembership() throws {
        let originalItem = try MyDayItemV1(membershipID: C41.id(1001), reference: C41.round(1001),
            manualOrder: 0, estimate: nil)
        let original = try MyDayPlanV1(planID: C41.id(1002), key: C41.key(), items: [originalItem],
            predecessor: nil, revision: 1, mutationID: C41.mutation(1003),
            authoredBy: C41.actor(), authoredAt: C41.now)
        let h = try C41CanonicalWriterHarness(historicalPlans: [original])
        XCTAssertTrue(try h.context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>()).isEmpty)
        XCTAssertEqual(try h.receiptCount(), 0)
        let changed = try MyDayItemV1(membershipID: originalItem.membershipID,
            reference: originalItem.reference, manualOrder: 0, estimate: .init(wholeMinutes: 45))
        let result = try h.save([changed], seed: 1010, predecessor: original)
        let command = MyDayCommandV1.save(successor: result.plan, predecessor: original)
        XCTAssertEqual(try h.writer.commit(command), result)
        XCTAssertEqual(try h.planCount(), 2)
        XCTAssertEqual(try h.receiptCount(), 1)
        for rebound in [false, true] {
            let invalid = try MyDayItemV1(
                membershipID: rebound ? changed.membershipID : C41.id(1020),
                reference: rebound ? C41.round(1001, revision: 2, sha: "c") : changed.reference,
                manualOrder: 0, estimate: nil)
            let before = try h.writer.currentRevision()
            XCTAssertThrowsError(try h.save([invalid], seed: rebound ? 1030 : 1040,
                predecessor: result.plan))
            XCTAssertEqual(try h.writer.currentRevision(), before)
            XCTAssertEqual(try h.planCount(), 2)
            XCTAssertEqual(try h.receiptCount(), 1)
        }
        XCTAssertThrowsError(try h.save([], seed: 1050, predecessor: original))
        let removed = try h.save([], seed: 1060, predecessor: result.plan)
        XCTAssertTrue(removed.plan.items.isEmpty)
        XCTAssertEqual(try h.writer.commit(.save(successor: removed.plan, predecessor: result.plan)), removed)
        XCTAssertEqual(try h.planCount(), 3)
        XCTAssertEqual(try h.receiptCount(), 2)
        XCTAssertTrue(try h.context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>()).isEmpty)
        try h.journal.validateAll()
    }

    @MainActor
    func testActualWriterRequiresCurrentNonterminalRoundTipWithoutMutatingRoundWork() throws {
        let h = try C41CanonicalWriterHarness()
        let requirement = try RoundPackageContentRequirementV1(packageRelease: .init(
            packageReleaseID: C41.digest("a"), packageID: "c41-round", packageContentVersion: 1,
            packageSHA256: C41.digest("b"), workflowSHA256: C41.digest("c")), requiredContent: [])
        let item = try RoundItemV1(itemID: C41.id(1100), order: 0,
            selection: .init(assetID: C41.id(1101), siteID: C41.id(1102),
                labelAtSelection: "My Day source round"), requirement: requirement)
        var history: [RoundSessionV1] = []
        var retainedPlan: MyDayPlanV1?
        let steps: [(RoundSessionStateV1, RoundSessionTransitionV1)] = [
            (.draft, .create), (.active, .start), (.paused, .pause), (.active, .resume),
            (.active, .skipItem), (.completed, .close), (.archived, .archive),
        ]
        for (index, step) in steps.enumerated() {
            let items = index >= 4 ? [try RoundItemV1(itemID: item.itemID, order: item.order,
                selection: item.selection, requirement: item.requirement,
                disposition: .skipped, reason: .notRequired)] : [item]
            let round = try RoundSessionV1(workspaceID: C41.workspace, sessionID: C41.id(1103),
                predecessor: history.last, revision: UInt64(index + 1), mutationID: C41.mutation(1110 + index),
                state: step.0, transition: step.1, transitionItemID: index == 4 ? item.itemID : nil,
                items: items, recordedBy: C41.actor(), recordedAt: C41.now)
            _ = try h.writer.commitRoundSession(.init(workspaceID: C41.workspace,
                expectedRevision: UInt64(index), mutationID: round.mutationID, session: round))
            history.append(round)
            let reference = MyDayEligibleReferenceV1.roundSession(workspaceID: round.workspaceID,
                sessionID: round.sessionID, revision: round.revision, sessionSHA256: round.sessionSHA256)
            let membership = try MyDayItemV1(membershipID: C41.id(1120 + index), reference: reference,
                manualOrder: 0, estimate: nil)
            let count = try h.planCount(), receipts = try h.receiptCount()
            if index < 5 {
                let saved = try h.save([membership], seed: 1200 + index * 10,
                    key: C41.key(String(format: "2026-09-%02d", index + 1)))
                if index == 0 { retainedPlan = saved.plan }
            } else {
                XCTAssertThrowsError(try h.save([membership], seed: 1200 + index * 10,
                    key: C41.key(String(format: "2026-09-%02d", index + 1))))
                XCTAssertEqual(try h.planCount(), count)
                XCTAssertEqual(try h.receiptCount(), receipts)
            }
            if index > 0 {
                let old = history[index - 1]
                let stale = try MyDayItemV1(membershipID: C41.id(1300 + index),
                    reference: .roundSession(workspaceID: old.workspaceID, sessionID: old.sessionID,
                        revision: old.revision, sessionSHA256: old.sessionSHA256),
                    manualOrder: 0, estimate: nil)
                let before = try h.writer.currentRevision()
                XCTAssertThrowsError(try h.save([stale], seed: 1400 + index * 10,
                    key: C41.key("2026-09-20")))
                XCTAssertEqual(try h.writer.currentRevision(), before)
            }
            XCTAssertEqual(try h.context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>())
                .map { try $0.value() }.sorted { $0.revision < $1.revision }, history)
        }
        let prior = try XCTUnwrap(retainedPlan)
        let changed = try MyDayItemV1(membershipID: prior.items[0].membershipID,
            reference: prior.items[0].reference, manualOrder: 0, estimate: .init(wholeMinutes: 10))
        let result = try h.save([changed], seed: 1500, predecessor: prior)
        XCTAssertEqual(result.plan.items[0].reference, prior.items[0].reference)
        XCTAssertEqual(try h.context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>())
            .map { try $0.value() }.sorted { $0.revision < $1.revision }, history)
        try h.journal.validateAll()
    }

    @MainActor
    func testActualWriterSelectsExactImmutablePacketVersions() throws {
        let h = try C41CanonicalWriterHarness()
        var manifests: [WorkPacketManifestV1] = []
        for version in 1...2 {
            let manifest = try WorkPacketManifestV1(manifestID: C41.id(1600 + version),
                packetID: C41.id(1600), packetVersion: UInt64(version), workspaceID: C41.workspace,
                items: [.init(itemID: "c41-packet-item", kind: .inspection, expectedRevision: 1,
                    itemSHA256: C41.digest(version == 1 ? "a" : "b"))], packageReleases: [],
                creationBasis: .explicitLocalSelection, creator: C41.actor(), createdAt: C41.now,
                mutationID: C41.mutation(1610 + version))
            let mutation = try WorkPacketMutationV1(workspaceID: C41.workspace, expectedRevision: 0,
                mutationID: manifest.mutationID, postImage: .appendManifest(manifest))
            _ = try h.writer.execute(.applyWorkPacket(mutation), mutationID: mutation.mutationID)
            manifests.append(manifest)
        }
        for (index, manifest) in manifests.enumerated() {
            let reference = MyDayEligibleReferenceV1.workPacket(try .init(manifest))
            let item = try MyDayItemV1(membershipID: C41.id(1620 + index), reference: reference,
                manualOrder: 0, estimate: nil)
            let result = try h.save([item], seed: 1630 + index * 10,
                key: C41.key(index == 0 ? "2026-09-01" : "2026-09-02"))
            XCTAssertEqual(result.plan.items[0].reference, reference)
        }
        XCTAssertEqual(try h.context.fetch(FetchDescriptor<WorkPacketManifestRow>())
            .map { try $0.value() }.sorted { $0.packetVersion < $1.packetVersion }, manifests)
        try h.journal.validateAll()
    }

    @MainActor
    func testActualWriterCarryoverChecksBothLiveTipsAndEverySelectedSource() throws {
        let manifest = try WorkPacketManifestV1(manifestID: C41.id(1700), packetID: C41.id(1701),
            packetVersion: 1, workspaceID: C41.workspace,
            items: [.init(itemID: "c41-carry", kind: .inspection, expectedRevision: 1,
                itemSHA256: C41.digest("a"))], packageReleases: [],
            creationBasis: .explicitLocalSelection, creator: C41.actor(), createdAt: C41.now,
            mutationID: C41.mutation(1702))
        let selected = try MyDayItemV1(membershipID: C41.id(1703),
            reference: .workPacket(.init(manifest)), manualOrder: 0, estimate: nil)
        let missing = try MyDayItemV1(membershipID: C41.id(1704), reference: C41.round(1704),
            manualOrder: 0, estimate: nil)
        func initial(_ item: MyDayItemV1, key: MyDayKeyV1, seed: Int) throws -> MyDayPlanV1 {
            try .init(planID: C41.id(seed), key: key, items: [item], predecessor: nil, revision: 1,
                mutationID: C41.mutation(seed + 1), authoredBy: C41.actor(), authoredAt: C41.now)
        }
        let source = try initial(selected, key: C41.key(), seed: 1710)
        let target = try initial(missing, key: C41.key("2026-09-02"), seed: 1720)
        let h = try C41CanonicalWriterHarness(historicalPlans: [source, target])
        let packetMutation = try WorkPacketMutationV1(workspaceID: C41.workspace, expectedRevision: 0,
            mutationID: manifest.mutationID, postImage: .appendManifest(manifest))
        _ = try h.writer.execute(.applyWorkPacket(packetMutation), mutationID: manifest.mutationID)
        let staleSourceCommand = try h.carryCommand(source: source, predecessor: target,
            membershipID: selected.membershipID, seed: 1730)
        let currentSource = try h.save(source.items, seed: 1740, predecessor: source).plan
        let beforeSource = try h.writer.currentRevision()
        XCTAssertThrowsError(try h.writer.commit(staleSourceCommand))
        XCTAssertEqual(try h.writer.currentRevision(), beforeSource)
        let staleTargetCommand = try h.carryCommand(source: currentSource, predecessor: target,
            membershipID: selected.membershipID, seed: 1750)
        let currentTarget = try h.save(target.items, seed: 1760, predecessor: target, key: target.key).plan
        let beforeTarget = try h.writer.currentRevision()
        XCTAssertThrowsError(try h.writer.commit(staleTargetCommand))
        XCTAssertEqual(try h.writer.currentRevision(), beforeTarget)
        let command = try h.carryCommand(source: currentSource, predecessor: currentTarget,
            membershipID: selected.membershipID, seed: 1770)
        let accepted = try h.writer.commit(command)
        let after = try h.writer.currentRevision(), count = try h.receiptCount()
        XCTAssertEqual(try h.writer.commit(command), accepted)
        XCTAssertEqual(try h.writer.currentRevision(), after)
        XCTAssertEqual(try h.receiptCount(), count)
        XCTAssertEqual(accepted.plan.items.map(\.membershipID), [missing.membershipID, selected.membershipID])
        XCTAssertEqual(try h.context.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>()).count, 1)
        XCTAssertEqual(try h.writer.currentPlan(for: source.key), currentSource)
        try h.journal.validateAll()

        // An explicitly carried membership is not exempt merely because the
        // target already contains that exact membership/reference.
        let absentSource = try initial(missing, key: C41.key(), seed: 1780)
        let absentTarget = try initial(missing, key: target.key, seed: 1790)
        let absent = try C41CanonicalWriterHarness(historicalPlans: [absentSource, absentTarget])
        let spoof = try absent.carryCommand(source: absentSource, predecessor: absentTarget,
            membershipID: missing.membershipID, seed: 1800)
        let baseline = try absent.writer.currentRevision()
        XCTAssertThrowsError(try absent.writer.commit(spoof))
        XCTAssertEqual(try absent.writer.currentRevision(), baseline)
        XCTAssertEqual(try absent.planCount(), 2)
        XCTAssertEqual(try absent.receiptCount(), 0)
        XCTAssertTrue(try absent.context.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>()).isEmpty)
        try absent.journal.validateAll()
    }

    @MainActor
    func testRetainedHistoricalDraftMembershipAndUnavailableRoutesRemainEditable() throws {
        let h = C41Harness()
        let selected = try C41.item(950, reference: C41.round(950), estimate: 20)
        let preview = try h.preview(items: [selected], mutation: 951)
        guard case let .saved(saved) = try h.workflow.execute(.save(preview)) else {
            return XCTFail("save")
        }
        for state in [MyDaySourceStateV1.completed, .cancelled, .retired, .missing, .stale] {
            h.sources.states[selected.membershipID] = state
            let summary = try h.workflow.summary(plan: saved.plan, dueQueue: C41.emptyDue(),
                exceptionQueue: C41.emptyExceptions())
            try summary.validate()
            XCTAssertNil(summary.items[0].routeIntent)
        }
        let retained = try h.workflow.draft(key: saved.plan.key, selectedItems: [selected],
            eligibleReferences: [C41.round(950, revision: 2, sha: "c")], predecessor: saved.plan)
        XCTAssertEqual(retained.eligibleReferences, [selected.reference])
        XCTAssertThrowsError(try h.workflow.draft(key: saved.plan.key, selectedItems: [selected],
            eligibleReferences: []))
        XCTAssertThrowsError(try h.workflow.draft(key: C41.key("2026-09-02"),
            selectedItems: [selected], eligibleReferences: [], predecessor: saved.plan))
        let rebound = try C41.item(950, reference: C41.round(950, revision: 2, sha: "c"))
        XCTAssertThrowsError(try h.workflow.draft(key: saved.plan.key, selectedItems: [rebound],
            eligibleReferences: [], predecessor: saved.plan))
        let newMembership = try C41.item(952, reference: selected.reference)
        XCTAssertThrowsError(try h.workflow.draft(key: saved.plan.key, selectedItems: [newMembership],
            eligibleReferences: [], predecessor: saved.plan))
        let empty = try h.workflow.draft(key: saved.plan.key, selectedItems: [],
            eligibleReferences: [], predecessor: saved.plan)
        let removal = try h.workflow.previewSave(draft: empty, predecessor: saved.plan,
            planID: saved.plan.planID, mutationID: C41.mutation(953), actor: C41.actor())
        guard case let .saved(removed) = try h.workflow.execute(.save(removal)) else {
            return XCTFail("remove")
        }
        XCTAssertTrue(removed.plan.items.isEmpty)
        XCTAssertEqual(h.writer.committedCommands.count, 2)
    }

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

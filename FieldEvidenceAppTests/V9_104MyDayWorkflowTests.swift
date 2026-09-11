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
            expectedRevision: 1, itemSHA256: digest("a"))
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
                  sources: [], evaluatedAt: C41.now, resolver: C41EmptyExceptionResolver())
    }
    static func oneException(workspaceID: WorkspaceID = workspace) throws -> ExceptionQueueProjectionV1 {
        let source = try ExceptionQueueSourceSnapshotV1(workspaceID: workspaceID,
            kind: ExceptionQueueSourceKindV1.allCases[0], sourceID: "c41-exception",
            sourceRevision: 1, sourceSHA256: digest("e"), evidenceSHA256: digest("f"),
            severity: .warning, reasons: [ExceptionQueueReasonV1.allCases[0]],
            deepLink: ExceptionQueueDeepLinkV1.allCases[0])
        return try .init(workspaceID: workspaceID,
            registry: .init(registeredKinds: ExceptionQueueSourceKindV1.allCases.sorted { $0.rawValue < $1.rawValue }),
            sources: [source], evaluatedAt: C41.now, resolver: C41ExactExceptionResolver(source: source))
    }
}

private struct C41Clock: ApplicationClock { func now() -> Date { C41.now } }
private final class C41CapacitySequence: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [Int64]
    private var next = 0
    init(_ values: [Int64]) { self.values = values }
    func read() -> Int64? {
        lock.withLock {
            guard !values.isEmpty else { return nil }
            let value = values[min(next, values.count - 1)]
            next += 1
            return value
        }
    }
    var count: Int { lock.withLock { next } }
}
private struct C41FixedID: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}
private struct C41EmptyExceptionResolver: ExceptionQueueCanonicalSourceResolvingV1 {
    func resolveExceptionQueueSource(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1,
                                     sourceID: String, revision: UInt64, evaluatedAt: Date) throws -> ExceptionQueueSourceSnapshotV1 {
        throw ReinspectionExceptionFailureV1.missingSource
    }
}
private struct C41ExactExceptionResolver: ExceptionQueueCanonicalSourceResolvingV1 {
    let source: ExceptionQueueSourceSnapshotV1
    func resolveExceptionQueueSource(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1,
                                     sourceID: String, revision: UInt64, evaluatedAt: Date) throws -> ExceptionQueueSourceSnapshotV1 {
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
            let initialState: MyDaySourceStateV1
            switch item.reference {
            case .roundSession, .resumableDraft: initialState = .draft
            default: initialState = .active
            }
            let state = states[item.membershipID] ?? initialState
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

private actor C41ReadAuthentication: LocalAuthenticationClient {
    private(set) var count = 0
    func availability() -> LocalAuthenticationAvailabilityV1 { .systemValue(status: .available, biometry: .faceID) }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        count += 1
        return .authenticated
    }
    func cancel(attemptID: UUID) {}
}

@MainActor private final class C41ProductionSourceHarness {
    let root: URL
    let store: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let authentication = C41ReadAuthentication()
    let gate: AppAccessGateV1
    let recorder: ActorSnapshotV1
    let holder: ActorSnapshotV1

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("c41-production-source-\(UUID().uuidString)")
        store = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
        coordinator = try StoreSessionCoordinator(validatingSession: store)
        gate = AppAccessGateV1(setting: .absentDisabled, authentication: authentication,
                               clock: C41Clock(), identifiers: SystemApplicationIDSource())
        recorder = try C41.actor(1900, workspaceID: store.workspaceID)
        holder = try ActorSnapshotV1(snapshotID: C41.id(1902), workspaceID: store.workspaceID,
            actor: recorder.actor, responsibility: .assignedTo, displayNameAtTime: recorder.displayNameAtTime,
            capturedAt: C41.now)
        _ = try coordinator.workspaceWriter.execute(.applyPartyAccountability(.appendActorSnapshot(recorder)),
                                                     mutationID: C41.mutation(1903))
        _ = try coordinator.workspaceWriter.execute(.applyPartyAccountability(.appendActorSnapshot(holder)),
                                                     mutationID: C41.mutation(1904))
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func packet(seed: Int, version: UInt64 = 1, packetID: UUID? = nil) throws -> WorkPacketManifestV1 {
        try .init(manifestID: C41.id(seed), packetID: packetID ?? C41.id(seed + 1), packetVersion: version,
            workspaceID: store.workspaceID,
            items: [.init(itemID: "source-item", kind: .inspection, expectedRevision: 1, itemSHA256: C41.digest("a"))],
            packageReleases: [], creationBasis: .explicitLocalSelection, creator: recorder,
            createdAt: C41.now, mutationID: C41.mutation(seed + 2))
    }
    func append(_ manifest: WorkPacketManifestV1) throws {
        try writePacket(.appendManifest(manifest), mutationID: manifest.mutationID)
    }
    func writePacket(_ payload: WorkPacketMutationPayloadV1, mutationID: MutationIDV1,
                     expectedRevision: UInt64 = 0) throws {
        let mutation = try WorkPacketMutationV1(workspaceID: store.workspaceID,
            expectedRevision: expectedRevision, mutationID: mutationID, postImage: payload)
        _ = try coordinator.workspaceWriter.execute(.applyWorkPacket(mutation), mutationID: mutationID)
    }
    func claim(item: WorkPacketItemReferenceV1, manifest: WorkPacketManifestV1, seed: Int,
               predecessor: WorkItemClaimV1? = nil) throws -> WorkItemClaimV1 {
        try .init(claimID: C41.id(seed), workspaceID: store.workspaceID, manifest: .init(manifest),
            item: item, holder: holder, claimSequence: (predecessor?.claimSequence ?? 0) + 1,
            claimedAt: C41.now, supersedesClaimID: predecessor?.claimID,
            revision: (predecessor?.revision ?? 0) + 1, mutationID: C41.mutation(seed + 1))
    }
    func lease(claim: WorkItemClaimV1, seed: Int) throws -> WorkLeaseV1 {
        try .init(leaseID: C41.id(seed), workspaceID: store.workspaceID, claimID: claim.claimID,
            item: claim.item, holder: holder, leaseSequence: 1, startsAt: C41.now,
            expiresAt: C41.now.addingTimeInterval(600), mutationID: C41.mutation(seed + 1))
    }
    func release(claim: WorkItemClaimV1, lease: WorkLeaseV1, reason: WorkReleaseReasonV1,
                 seed: Int) throws -> WorkReleaseV1 {
        let result = try WorkPacketResultLinkV1(resultID: C41.id(seed + 2), resultMutationID: C41.mutation(seed + 3),
            itemExpectedRevision: claim.item.expectedRevision, resultRevision: 1,
            resultSHA256: C41.digest("b"), evidence: [])
        return try .init(releaseID: C41.id(seed), workspaceID: store.workspaceID, claimID: claim.claimID,
            leaseID: lease.leaseID, item: claim.item, holder: holder, reason: reason,
            resultLinks: reason == .completed ? [result] : [],
            releasedAt: reason == .leaseExpired || reason == .reclaimed ? lease.expiresAt : C41.now,
            mutationID: C41.mutation(seed + 1))
    }
    func plan(items: [MyDayItemV1], seed: Int) throws -> MyDayPlanV1 {
        try .init(planID: C41.id(seed), key: C41.key(workspaceID: store.workspaceID), items: items,
            predecessor: nil, revision: 1, mutationID: C41.mutation(seed + 1), authoredBy: recorder, authoredAt: C41.now)
    }
    func draft(seed: Int, revision: UInt64, state: FieldDraftStateV1, mutation: Int,
               discardReceipt: DraftDiscardReceiptV1? = nil) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: C41.id(seed), workspaceID: store.workspaceID,
            scope: .init(scopeKind: "C41_SOURCE_TEST", stableComponentIDs: ["explicit-test-scope"]),
            purpose: .assetFieldEdit, codec: .init(codecID: "C41_SOURCE_TEST", codecVersion: 1,
                releaseSHA256: C41.digest("c")), baseCanonicalRevision: 0, draftRevision: revision,
            payloadData: Data("source checkpoint".utf8), stageIDs: [], resumeAnchor: .init(sectionID: "source"),
            state: state, lastDurableMutationID: discardReceipt?.mutationID,
            lastReceiptSHA256: discardReceipt?.receiptSHA256, updatedAt: C41.now, mutationID: C41.mutation(mutation))
    }

    struct Baseline: Equatable {
        let revision: WorkspaceRevisionV1
        let receipts: Int
        let files: [String: Data]
    }

    struct ReadinessFixture {
        let round: RoundSessionV1
        let promoted: PromotedPackageReleaseV1
        let content: ContentReferenceV1?
        let contentRequest: DraftImmutableContentWriteRequestV1?
        let originalBytes: Data
        var reference: MyDayEligibleReferenceV1 {
            .roundSession(workspaceID: round.workspaceID, sessionID: round.sessionID,
                          revision: round.revision, sessionSHA256: round.sessionSHA256)
        }
    }

    /// Published package/asset rows are explicit canonical test fixtures, not
    /// package-promotion qualification. Rounds use the actual writer and bytes
    /// use the real protected immutable-content owner.
    func readinessRound(seed: Int, withContent: Bool, unknownGuidance: Bool = false) async throws -> ReadinessFixture {
        let shipping = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let package = try InspectionPackageV2(packageID: shipping.packageID, contentVersion: shipping.contentVersion,
            minimumRegistryVersion: shipping.minimumRegistryVersion, maximumRegistryVersion: shipping.maximumRegistryVersion,
            capabilities: shipping.capabilities, permissions: shipping.permissions,
            advisoryGuidance: unknownGuidance ? [.init(guidanceID: "unknown-local-guidance", kind: .limitation,
                                                     localizationKey: "unknown.local.guidance")] : shipping.advisoryGuidance,
            presentation: shipping.presentation)
        let workflow = try WorkflowDefinitionV1(workflowID: "c41.readiness.\(seed)", entryNodeID: "readiness.section",
            declaredFieldIDs: [], nodes: [
                .init(nodeID: "readiness.section", kind: .section, localizationKey: "readiness.section", outgoingNodeIDs: ["readiness.terminal"]),
                .init(nodeID: "readiness.terminal", kind: .terminal, localizationKey: "readiness.terminal", outgoingNodeIDs: []),
            ])
        let release = try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(.makeDraft(package: package, workflow: workflow))).release
        let promoted = try PromotedPackageReleaseV1(releaseRecordID: C41.id(seed), workspaceID: store.workspaceID,
            packageRelease: release, mutationID: C41.mutation(seed + 1), promotedAt: C41.now)
        coordinator.modelContext.insert(try PromotedPackageReleaseRow(promoted))
        coordinator.modelContext.insert(Site(id: C41.id(seed + 2), label: "Readiness site", createdAt: C41.now))
        coordinator.modelContext.insert(Asset(id: C41.id(seed + 3), siteID: C41.id(seed + 2),
            packID: package.packageID, packSchemaVersion: package.schemaVersion, packContentVersion: package.contentVersion,
            label: "Readiness asset", createdAt: C41.now))
        try coordinator.modelContext.save()
        let bytes = Data("actual protected readiness original \(seed)".utf8)
        let reference: ContentReferenceV1?
        let request: DraftImmutableContentWriteRequestV1?
        if withContent {
            let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: KernelCanonicalHashV1.sha256(bytes))
            let value = try ContentReferenceV1(workspaceID: store.workspaceID.rawValue.uuidString.lowercased(),
                contentID: "readiness-\(seed)", byteLength: Int64(bytes.count), mediaType: "application/pdf",
                digests: .init([digest]), byteRole: .immutableOriginal, createdAt: "2025-01-02T00:00:00Z")
            let write = try DraftImmutableContentWriteRequestV1(workspaceID: store.workspaceID, contentID: value.contentID,
                digest: digest, byteLength: value.byteLength, mediaType: value.mediaType,
                mutationID: C41.mutation(seed + 4), createdAt: value.createdAt)
            let receipt = try await EvidenceBundleStore(generationRootURL: coordinator.generationRootURL)
                .persistImmutableOriginal(bytes: bytes, request: write)
            try receipt.validate(request: write, bytes: bytes)
            reference = value; request = write
        } else { reference = nil; request = nil }
        let requirement = try RoundPackageContentRequirementV1(packageRelease: .init(release), requiredContent: reference.map { [$0] } ?? [])
        let item = try RoundItemV1(itemID: C41.id(seed + 5), order: 0,
            selection: .init(assetID: C41.id(seed + 3), siteID: C41.id(seed + 2), labelAtSelection: "Readiness asset"), requirement: requirement)
        let round = try RoundSessionV1(workspaceID: store.workspaceID, sessionID: C41.id(seed + 6), predecessor: nil,
            revision: 1, mutationID: C41.mutation(seed + 7), state: .draft, transition: .create,
            items: [item], recordedBy: recorder, recordedAt: C41.now)
        _ = try coordinator.workspaceWriter.commitRoundSession(.init(workspaceID: store.workspaceID,
            expectedRevision: 0, mutationID: round.mutationID, session: round))
        return .init(round: round, promoted: promoted, content: reference, contentRequest: request, originalBytes: bytes)
    }

    func assessedProvider(ledger: OwnedStorageLedgerV1) -> ProductionMyDaySourceProviderV1 {
        coordinator.makeMyDaySourceProvider(accessGate: gate, ownedStorageLedger: ledger)
    }
    func baseline() throws -> Baseline {
        let revision = try coordinator.workspaceWriter.currentRevision()
        let receipts = try coordinator.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).count
        var files: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted() {
            let url = root.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            // SQLite's shared-memory reader marks are not canonical data.
            if values.isRegularFile == true && !path.hasSuffix("-shm") { files[path] = try Data(contentsOf: url) }
        }
        return .init(revision: revision, receipts: receipts, files: files)
    }
}

final class V9_104MyDayWorkflowTests: XCTestCase {
    @MainActor func testSummaryPresentationUsesExactMembershipEstimate() throws {
        // Exercise the view's actual formatter with validated canonical summary values.
        for minutes in [nil, 1, 37] as [Int?] {
            let item = try MyDayItemV1(membershipID: C41.id(310), reference: C41.round(1),
                manualOrder: 0, estimate: minutes.map { try MyDayEstimateV1(wholeMinutes: $0) })
            let frontier = try MyDaySourceFrontierV1(membershipID: item.membershipID,
                plannedReference: item.reference, currentReference: item.reference,
                state: .draft, readiness: .notReady, dueAt: nil, evaluatedAt: C41.now)
            let summary = try MyDaySummaryItemV1(item: item, frontier: frontier, dueReason: nil)
            try summary.validate()
            XCTAssertEqual(MyDayWorkflowView.summaryEstimateText(summary),
                minutes.map { "\($0) minute estimate" } ?? "no duration estimate")
            XCTAssertEqual(summary.item, item)
        }
    }

    @MainActor
    func testProductionMyDayReadinessPreservesExactCapacityDriftSemantics() async throws {
        let h = try C41ProductionSourceHarness()
        let fixture = try await h.readinessRound(seed: 3400, withContent: false)
        let plan = try h.plan(items: [.init(membershipID: C41.id(3410), reference: fixture.reference,
            manualOrder: 0, estimate: nil)], seed: 3411)
        try await h.coordinator.awaitSearchIndexLifecycle()
        let baseline = try h.baseline()
        // Both observations have ample capacity. The incumbent full-source
        // hash nevertheless marks their difference stale; later stable reads
        // may publish that stale result, never silently upgrade it to ready.
        let settles = C41CapacitySequence([1_000_000_000, 999_999_000, 999_999_000, 999_999_000])
        let settledLedger = try OwnedStorageLedgerV1(applicationSupportURL: h.root, capacityProvider: { _ in settles.read() })
        let settledBaseline = settledLedger.snapshot()
        let stale = try await h.assessedProvider(ledger: settledLedger).snapshot(for: plan, evaluatedAt: C41.now)
        guard case let .roundManifest(manifest)? = stale.readinessAssessments.first?.assessment else {
            return XCTFail("Missing capacity-drift manifest")
        }
        XCTAssertEqual(manifest.status, .stale)
        XCTAssertEqual(stale.frontiers.first?.readiness, .notReady)
        XCTAssertEqual(settles.count, 4)
        XCTAssertEqual(settledLedger.snapshot(), settledBaseline)
        XCTAssertEqual(try h.baseline(), baseline)
        // A healthy-but-different last publication sample is rejected by the
        // added freshness check. No rounding or constant-capacity substitution
        // is permitted; usable live behavior still requires native evidence.
        let drifts = C41CapacitySequence([1_000_000_000, 1_000_000_000, 1_000_000_000, 999_999_000])
        let driftingLedger = try OwnedStorageLedgerV1(applicationSupportURL: h.root, capacityProvider: { _ in drifts.read() })
        let driftingBaseline = driftingLedger.snapshot()
        do {
            _ = try await h.assessedProvider(ledger: driftingLedger).snapshot(for: plan, evaluatedAt: C41.now)
            XCTFail("Changed publication capacity was accepted")
        } catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sourcesChanged) }
        XCTAssertEqual(drifts.count, 4)
        XCTAssertEqual(driftingLedger.snapshot(), driftingBaseline)
        XCTAssertEqual(try h.baseline(), baseline)
    }

    @MainActor
    func testProductionMyDayAssessesRealRoundReadinessWithoutEffects() async throws {
        let h = try C41ProductionSourceHarness()
        let required = try await h.readinessRound(seed: 3000, withContent: true)
        let empty = try await h.readinessRound(seed: 3020, withContent: false)
        // Real ledger and reservations, injected stable capacity. Actual OS
        // capacity observation is covered separately; this is not a claim
        // that changing system free space always yields a ready manifest.
        let ledger = try OwnedStorageLedgerV1(applicationSupportURL: h.root, capacityProvider: { _ in 1_000_000_000 })
        _ = try ledger.reserve(attemptID: .init(workspaceID: h.store.workspaceID, generationID: h.store.generationID,
            mutationID: C41.mutation(3040)), requiredBytes: 4096)
        let provider = h.assessedProvider(ledger: ledger)
        let plan = try h.plan(items: [
            .init(membershipID: C41.id(3041), reference: required.reference, manualOrder: 0, estimate: nil),
            .init(membershipID: C41.id(3042), reference: empty.reference, manualOrder: 1, estimate: nil),
        ], seed: 3043)
        try await h.coordinator.awaitSearchIndexLifecycle()
        let baseline = try h.baseline(), storageBaseline = ledger.snapshot()
        let snapshot = try await provider.snapshot(for: plan, evaluatedAt: C41.now)
        XCTAssertEqual(snapshot.frontiers.map(\.readiness), [.ready, .ready])
        XCTAssertEqual(snapshot.readinessAssessments.count, 2)
        for record in snapshot.readinessAssessments {
            guard case let .roundManifest(manifest) = record.assessment else { return XCTFail("Missing actual round manifest") }
            try manifest.validate()
            XCTAssertEqual(manifest.status, .ready)
            XCTAssertFalse(manifest.guidanceReferenceIDs.isEmpty)
            XCTAssertTrue(manifest.expectedFieldReferences.isEmpty)
            XCTAssertEqual(manifest.storage.reservedBytes, 4096)
            XCTAssertEqual(manifest.storage.operationReserveBytes, StoragePreflightService.reserveBytes)
            XCTAssertEqual(manifest.contentRequirements.count, record.reference == required.reference ? 1 : 0)
        }
        XCTAssertEqual(try h.baseline(), baseline)
        XCTAssertEqual(ledger.snapshot(), storageBaseline)
        let authCalls = await h.authentication.count
        XCTAssertEqual(authCalls, 0)
        var prior = required.round
        for (index, state) in [RoundSessionStateV1.active, .paused].enumerated() {
            let successor = try RoundSessionV1(workspaceID: h.store.workspaceID, sessionID: prior.sessionID,
                predecessor: prior, revision: prior.revision + 1, mutationID: C41.mutation(3050 + index),
                state: state, transition: index == 0 ? .start : .pause, items: prior.items,
                recordedBy: h.recorder, recordedAt: C41.now)
            _ = try h.coordinator.workspaceWriter.commitRoundSession(.init(workspaceID: h.store.workspaceID,
                expectedRevision: prior.revision, mutationID: successor.mutationID, session: successor))
            prior = successor
            try await h.coordinator.awaitSearchIndexLifecycle()
            let stepBaseline = try h.baseline()
            let step = try await provider.snapshot(for: plan, evaluatedAt: C41.now)
            XCTAssertEqual(step.frontiers[0].plannedReference, required.reference)
            XCTAssertNotEqual(step.frontiers[0].currentReference, required.reference)
            XCTAssertEqual(step.frontiers[0].state, index == 0 ? .active : .paused)
            XCTAssertEqual(step.frontiers[0].readiness, .ready)
            XCTAssertEqual(try h.baseline(), stepBaseline)
            XCTAssertEqual(ledger.snapshot(), storageBaseline)
        }
    }

    @MainActor
    func testProductionMyDayReadinessRejectsMissingCorruptAndUnknownSources() async throws {
        let h = try C41ProductionSourceHarness()
        let fixture = try await h.readinessRound(seed: 3100, withContent: true)
        let unknown = try await h.readinessRound(seed: 3120, withContent: false, unknownGuidance: true)
        let ledger = try OwnedStorageLedgerV1(applicationSupportURL: h.root, capacityProvider: { _ in 1_000_000_000 })
        let provider = h.assessedProvider(ledger: ledger)
        func manifest(_ snapshot: MyDaySourceSnapshotV1, _ reference: MyDayEligibleReferenceV1) throws -> OfflineReadinessManifestV1 {
            let record = try XCTUnwrap(snapshot.readinessAssessments.first { $0.reference == reference })
            guard case let .roundManifest(value) = record.assessment else { throw MyDayFailureV1.invalidValue }
            return value
        }
        let first = try await provider.snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(try manifest(first, unknown.reference).status, .blocked)
        XCTAssertEqual(try manifest(first, fixture.reference).status, .ready)
        let request = try XCTUnwrap(fixture.contentRequest)
        let original = h.coordinator.generationRootURL.appendingPathComponent(request.relativePath)
        // Hostile byte changes are explicit test setup; the observer must not
        // restore, delete, or otherwise repair them.
        try FileManager.default.removeItem(at: original)
        try await h.coordinator.awaitSearchIndexLifecycle()
        let missingBaseline = try h.baseline()
        let missing = try await provider.snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(try manifest(missing, fixture.reference).status, .blocked)
        XCTAssertEqual(try manifest(missing, fixture.reference).contentObservations.first?.state, .missing)
        XCTAssertEqual(try h.baseline(), missingBaseline)
        _ = try await EvidenceBundleStore(generationRootURL: h.coordinator.generationRootURL)
            .persistImmutableOriginal(bytes: fixture.originalBytes, request: request)
        let handle = try FileHandle(forWritingTo: original)
        try handle.write(contentsOf: Data(repeating: 120, count: fixture.originalBytes.count))
        try handle.close()
        let corruptBaseline = try h.baseline()
        let corrupt = try await provider.snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(try manifest(corrupt, fixture.reference).status, .blocked)
        XCTAssertNotEqual(try manifest(corrupt, fixture.reference).contentObservations.first?.state, .present)
        XCTAssertEqual(try h.baseline(), corruptBaseline)
        let unavailable = try OwnedStorageLedgerV1(applicationSupportURL: h.root, capacityProvider: { _ in nil })
        let noCapacity = try await h.assessedProvider(ledger: unavailable).snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(try manifest(noCapacity, unknown.reference).storage.capacityState, .unavailable)
        let assetID = fixture.round.items[0].selection.assetID
        let asset = try XCTUnwrap(h.coordinator.modelContext.fetch(FetchDescriptor<Asset>()).first { $0.id == assetID })
        h.coordinator.modelContext.delete(asset); try h.coordinator.modelContext.save()
        let noAsset = try await provider.snapshot(evaluatedAt: C41.now)
        XCTAssertTrue(try manifest(noAsset, fixture.reference).observedAssetIDs.isEmpty)
        let releaseID = fixture.promoted.releaseRecordID
        let row = try XCTUnwrap(h.coordinator.modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).first { $0.releaseRecordID == releaseID })
        h.coordinator.modelContext.delete(row); try h.coordinator.modelContext.save()
        let noPackage = try await provider.snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(noPackage.readinessAssessments.first { $0.reference == fixture.reference }?.assessment, .unavailable(.missingExactPackage))
    }

    @MainActor
    func testProductionMyDayReadinessKeepsUnsupportedBindingsAndCompletionUnavailable() async throws {
        let h = try C41ProductionSourceHarness()
        let fixture = try await h.readinessRound(seed: 3200, withContent: true)
        let content = try XCTUnwrap(fixture.content)
        let release = try FieldReferenceReleaseV1(releaseID: C41.id(3220), workspaceID: h.store.workspaceID,
            referencePackID: "c41-readiness-reference", kind: .manual, semanticVersion: "1.0",
            provenance: .init(kind: .synthetic, sourceName: "Explicit test reference", sourceReleaseIdentifier: "v1", licenseScope: .localUseOnly),
            manifest: .init(manifestID: "c41-readiness-reference", workspaceID: content.workspaceID, manifestRevision: 1,
                entries: [.init(contentID: content.contentID, expectedByteLength: content.byteLength, mediaType: content.mediaType,
                    digest: XCTUnwrap(content.digests.digest(for: .sha256)), expectedLocatorRevision: 0, requiredForOpen: true)]),
            issuedAt: C41.now, mutationID: C41.mutation(3221))
        let binding = try FieldReferenceBindingV1(bindingID: C41.id(3222), workspaceID: h.store.workspaceID,
            subjectKind: .roundSession, subjectID: fixture.round.sessionID, subjectRevision: fixture.round.revision,
            subjectState: .active, release: release, boundAt: C41.now, mutationID: C41.mutation(3223))
        h.coordinator.modelContext.insert(try FieldReferenceReleaseRow(release))
        h.coordinator.modelContext.insert(try FieldReferenceBindingRow(binding, release: release))
        try h.coordinator.modelContext.save()
        let ledger = try OwnedStorageLedgerV1(applicationSupportURL: h.root, capacityProvider: { _ in 1_000_000_000 })
        let provider = h.assessedProvider(ledger: ledger)
        let bound = try await provider.snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(bound.readinessAssessments.first?.assessment, .unavailable(.fieldReferenceContentClosureUnavailable))
        var prior = fixture.round
        let item = prior.items[0]
        for (index, transition) in [RoundSessionTransitionV1.start, .visitItem, .completeItem].enumerated() {
            let visit = try RoundItemVisitV1(visitedAt: C41.now, recordedBy: h.recorder)
            let updated = try RoundItemV1(itemID: item.itemID, order: item.order, selection: item.selection,
                requirement: item.requirement, disposition: index == 0 ? .pending : (index == 1 ? .visited : .completed),
                visit: index == 0 ? nil : visit, completion: index == 2 ? .init(completionID: C41.id(3230), revision: 1, completionSHA256: C41.digest("d")) : nil)
            let round = try RoundSessionV1(workspaceID: h.store.workspaceID, sessionID: prior.sessionID, predecessor: prior,
                revision: prior.revision + 1, mutationID: C41.mutation(3231 + index), state: .active,
                transition: transition, transitionItemID: index == 0 ? nil : item.itemID,
                items: [updated], recordedBy: h.recorder, recordedAt: C41.now)
            _ = try h.coordinator.workspaceWriter.commitRoundSession(.init(workspaceID: h.store.workspaceID,
                expectedRevision: prior.revision, mutationID: round.mutationID, session: round))
            prior = round
        }
        try await h.coordinator.awaitSearchIndexLifecycle()
        let baseline = try h.baseline(), storage = ledger.snapshot()
        let completedItem = try await provider.snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(completedItem.readinessAssessments.first?.assessment, .unavailable(.completionAuthorityUnavailable))
        XCTAssertEqual(try h.baseline(), baseline)
        XCTAssertEqual(ledger.snapshot(), storage)
    }

    #if DEBUG
    @MainActor
    func testProductionMyDayAssessedPublicationRejectsAccessMetadataStorageAndSessionDrift() async throws {
        let h = try C41ProductionSourceHarness()
        let fixture = try await h.readinessRound(seed: 3300, withContent: false)
        let ledger = try OwnedStorageLedgerV1(applicationSupportURL: h.root, capacityProvider: { _ in 1_000_000_000 })
        let provider = h.assessedProvider(ledger: ledger)
        try await h.coordinator.awaitSearchIndexLifecycle()
        let baseline = try h.baseline()
        provider.afterSourceMaterializationForTesting = {
            await h.gate.markConfigurationUnknown()
            await h.gate.eraseAccessState()
        }
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("Access ABA published readiness") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        XCTAssertEqual(try h.baseline(), baseline)
        let assetID = fixture.round.items[0].selection.assetID
        let asset = try XCTUnwrap(h.coordinator.modelContext.fetch(FetchDescriptor<Asset>()).first { $0.id == assetID })
        let originalSite = asset.siteID
        provider.afterSourceMaterializationForTesting = {
            // Canonical constructed-fixture mutation deliberately bypasses the
            // writer revision, proving the expanded metadata hash is checked.
            asset.siteID = C41.id(3320)
            try h.coordinator.modelContext.save()
        }
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("Changed asset metadata published readiness") }
        catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sourcesChanged) }
        asset.siteID = originalSite; try h.coordinator.modelContext.save()
        let beforeReservation = ledger.snapshot()
        provider.afterSourceMaterializationForTesting = {
            _ = try ledger.reserve(attemptID: .init(workspaceID: h.store.workspaceID, generationID: h.store.generationID,
                mutationID: C41.mutation(3321)), requiredBytes: 4096)
        }
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("Changed live reservation published readiness") }
        catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sourcesChanged) }
        XCTAssertEqual(ledger.snapshot().activeReservationCount, beforeReservation.activeReservationCount + 1)
        provider.afterSourceMaterializationForTesting = {
            try h.coordinator.activateValidating(session: h.store)
        }
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("Replaced session published readiness") }
        catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sessionChanged) }
        provider.afterSourceMaterializationForTesting = nil
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("Stale assessed provider reused") }
        catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sessionChanged) }
        let fresh = try await h.assessedProvider(ledger: ledger).snapshot(evaluatedAt: C41.now)
        guard case let .roundManifest(manifest)? = fresh.readinessAssessments.first?.assessment else {
            return XCTFail("Fresh provider did not assess actual round")
        }
        XCTAssertEqual(manifest.status, .ready)
        XCTAssertEqual(manifest.storage.reservedBytes, 4096)
    }
    #endif

    @MainActor
    func testProductionMyDayReadsExactPacketHistoryWithoutEffects() async throws {
        let h = try C41ProductionSourceHarness()
        let first = try h.packet(seed: 2000, version: 1)
        let second = try h.packet(seed: 2010, version: 2, packetID: first.packetID)
        try h.append(first)
        try h.append(second)
        let provider = h.coordinator.makeMyDaySourceProvider(accessGate: h.gate)
        let selected = try MyDayItemV1(membershipID: C41.id(2020), reference: .workPacket(.init(first)),
                                      manualOrder: 0, estimate: nil)
        let plan = try h.plan(items: [selected], seed: 2021)
        try await h.coordinator.awaitSearchIndexLifecycle()
        let baseline = try h.baseline()
        let initial = try await provider.snapshot(for: plan, evaluatedAt: C41.now)
        XCTAssertEqual(initial.readinessAssessments.map(\.reference), initial.sources.map(\.reference))
        XCTAssertTrue(initial.readinessAssessments.allSatisfy { $0.assessment == .notAssessed })
        XCTAssertEqual(initial.eligibleReferences, [.workPacket(try .init(first)), .workPacket(try .init(second))])
        XCTAssertEqual(initial.frontiers[0].currentReference, selected.reference)
        XCTAssertEqual(initial.frontiers[0].readiness, .unavailable)
        XCTAssertEqual(try h.baseline(), baseline)
        let absentVersion = try h.packet(seed: 2015, version: 3, packetID: first.packetID)
        let absentMember = try MyDayItemV1(membershipID: C41.id(2018), reference: .workPacket(.init(absentVersion)),
                                         manualOrder: 0, estimate: nil)
        let absent = try await provider.snapshot(for: h.plan(items: [absentMember], seed: 2019), evaluatedAt: C41.now)
        XCTAssertEqual(absent.frontiers[0].state, .missing)
        XCTAssertNil(absent.frontiers[0].currentReference, "Never substitute another immutable packet version")
        XCTAssertEqual(try h.baseline(), baseline)

        let item = try WorkPacketItemReferenceV1(manifest: first, item: first.items[0])
        let claim = try h.claim(item: item, manifest: first, seed: 2030)
        let lease = try h.lease(claim: claim, seed: 2040)
        try h.writePacket(.appendClaim(claim), mutationID: claim.mutationID)
        try h.writePacket(.appendLease(lease), mutationID: lease.mutationID)
        let released = try h.release(claim: claim, lease: lease, reason: .deliberatelyReleased, seed: 2050)
        try h.writePacket(.recordRelease(released), mutationID: released.mutationID)
        let ordinary = try await provider.snapshot(for: plan, evaluatedAt: C41.now)
        XCTAssertEqual(ordinary.frontiers[0].state, .active, "Release is not completion")

        let nextClaim = try h.claim(item: item, manifest: first, seed: 2060, predecessor: claim)
        let nextLease = try h.lease(claim: nextClaim, seed: 2070)
        try h.writePacket(.supersedeClaim(nextClaim), mutationID: nextClaim.mutationID, expectedRevision: claim.revision)
        try h.writePacket(.appendLease(nextLease), mutationID: nextLease.mutationID)
        let completed = try h.release(claim: nextClaim, lease: nextLease, reason: .completed, seed: 2080)
        try h.writePacket(.recordRelease(completed), mutationID: completed.mutationID)
        let done = try await provider.snapshot(for: plan, evaluatedAt: C41.now)
        XCTAssertEqual(done.frontiers[0].state, .completed)
        XCTAssertFalse(done.eligibleReferences.contains(selected.reference))
        XCTAssertTrue(done.eligibleReferences.contains(.workPacket(try .init(second))))
        let reopened = try h.claim(item: item, manifest: first, seed: 2090, predecessor: nextClaim)
        try h.writePacket(.supersedeClaim(reopened), mutationID: reopened.mutationID, expectedRevision: nextClaim.revision)
        let open = try await provider.snapshot(for: plan, evaluatedAt: C41.now)
        XCTAssertEqual(open.frontiers[0].state, .reopened)
        let summary = try MyDaySummaryItemV1(item: selected, frontier: open.frontiers[0], dueReason: nil)
        try summary.validate()
        XCTAssertEqual(summary.routeIntent?.action, .resume)

        // A competing original claim is retained as a real owner-projected
        // conflict, never silently chosen as a current holder.
        let competing = try h.claim(item: item, manifest: first, seed: 2100)
        try h.writePacket(.appendClaim(competing), mutationID: competing.mutationID)
        try await h.coordinator.awaitSearchIndexLifecycle()
        let conflictBaseline = try h.baseline()
        let conflict = try await provider.snapshot(for: plan, evaluatedAt: C41.now)
        XCTAssertEqual(conflict.frontiers[0].state, .conflicted)
        XCTAssertFalse(conflict.eligibleReferences.contains(selected.reference))
        XCTAssertEqual(try h.baseline(), conflictBaseline)
        let repeated = try await provider.snapshot(for: plan, evaluatedAt: C41.now)
        XCTAssertEqual(repeated.sourceClosureSHA256, conflict.sourceClosureSHA256)
        XCTAssertEqual(try h.baseline(), conflictBaseline)
        let authenticationCount = await h.authentication.count
        XCTAssertEqual(authenticationCount, 0)
    }

    @MainActor
    func testProductionMyDayDoesNotCompleteExpiredReclaimedOrHandedOffPackets() async throws {
        let h = try C41ProductionSourceHarness()
        let nextActor = try C41.actor(1910, workspaceID: h.store.workspaceID)
        let nextHolder = try ActorSnapshotV1(snapshotID: C41.id(1912), workspaceID: h.store.workspaceID,
            actor: nextActor.actor, responsibility: .assignedTo, displayNameAtTime: nextActor.displayNameAtTime,
            capturedAt: C41.now)
        _ = try h.coordinator.workspaceWriter.execute(.applyPartyAccountability(.appendActorSnapshot(nextHolder)),
                                                      mutationID: C41.mutation(1913))
        let provider = h.coordinator.makeMyDaySourceProvider(accessGate: h.gate)
        for (index, reason) in [WorkReleaseReasonV1.leaseExpired, .reclaimed, .handoff].enumerated() {
            let seed = 2500 + index * 100
            let packet = try h.packet(seed: seed)
            try h.append(packet)
            let item = try WorkPacketItemReferenceV1(manifest: packet, item: packet.items[0])
            let claim = try h.claim(item: item, manifest: packet, seed: seed + 10)
            let lease = try h.lease(claim: claim, seed: seed + 20)
            try h.writePacket(.appendClaim(claim), mutationID: claim.mutationID)
            try h.writePacket(.appendLease(lease), mutationID: lease.mutationID)
            let release = try h.release(claim: claim, lease: lease, reason: reason, seed: seed + 30)
            try h.writePacket(.recordRelease(release), mutationID: release.mutationID)
            if reason == .handoff {
                let handoff = try WorkHandoffV1(handoffID: C41.id(seed + 40), workspaceID: h.store.workspaceID,
                    releaseID: release.releaseID, item: item, fromHolder: h.holder, toHolder: nextHolder,
                    resultLinks: [], reason: "Explicit local handoff", handedOffAt: C41.now,
                    mutationID: C41.mutation(seed + 41))
                try h.writePacket(.recordHandoff(handoff), mutationID: handoff.mutationID)
            }
            try await h.coordinator.awaitSearchIndexLifecycle()
            let baseline = try h.baseline()
            let snapshot = try await provider.snapshot(evaluatedAt: C41.now.addingTimeInterval(600))
            let reference = MyDayEligibleReferenceV1.workPacket(try .init(packet))
            let source = try XCTUnwrap(snapshot.sources.first { $0.reference == reference })
            XCTAssertEqual(source.state, .active)
            XCTAssertEqual(try h.baseline(), baseline)
        }
    }

    @MainActor
    func testProductionMyDayPreservesRoundAndDraftStates() async throws {
        let h = try C41ProductionSourceHarness()
        let provider = h.coordinator.makeMyDaySourceProvider(accessGate: h.gate)
        let requirement = try RoundPackageContentRequirementV1(packageRelease: .init(
            packageReleaseID: C41.digest("a"), packageID: "c41-source", packageContentVersion: 1,
            packageSHA256: C41.digest("b"), workflowSHA256: C41.digest("c")), requiredContent: [])
        let item = try RoundItemV1(itemID: C41.id(2200), order: 0,
            selection: .init(assetID: C41.id(2201), siteID: C41.id(2202), labelAtSelection: "Source round"),
            requirement: requirement)
        var previous: RoundSessionV1?
        var planned: MyDayItemV1?
        let steps: [(RoundSessionStateV1, RoundSessionTransitionV1, MyDaySourceStateV1)] = [
            (.draft, .create, .draft), (.active, .start, .active), (.paused, .pause, .paused),
            (.active, .resume, .active), (.active, .skipItem, .active),
            (.completed, .close, .completed), (.archived, .archive, .archived),
        ]
        for (index, step) in steps.enumerated() {
            let items = index >= 4 ? [try RoundItemV1(itemID: item.itemID, order: 0,
                selection: item.selection, requirement: requirement, disposition: .skipped, reason: .notRequired)] : [item]
            let round = try RoundSessionV1(workspaceID: h.coordinator.workspaceID, sessionID: C41.id(2203),
                predecessor: previous, revision: UInt64(index + 1), mutationID: C41.mutation(2210 + index),
                state: step.0, transition: step.1, transitionItemID: index == 4 ? item.itemID : nil,
                items: items, recordedBy: h.recorder, recordedAt: C41.now)
            _ = try h.coordinator.workspaceWriter.commitRoundSession(.init(workspaceID: h.coordinator.workspaceID,
                expectedRevision: previous?.revision ?? 0, mutationID: round.mutationID, session: round))
            previous = round
            let reference = MyDayEligibleReferenceV1.roundSession(workspaceID: round.workspaceID,
                sessionID: round.sessionID, revision: round.revision, sessionSHA256: round.sessionSHA256)
            let member = try MyDayItemV1(membershipID: C41.id(2220), reference: reference, manualOrder: 0, estimate: nil)
            if planned == nil { planned = member }
            let snapshot = try await provider.snapshot(for: h.plan(items: [member], seed: 2230), evaluatedAt: C41.now)
            XCTAssertEqual(snapshot.frontiers[0].state, step.2)
            let summary = try MyDaySummaryItemV1(item: member, frontier: snapshot.frontiers[0], dueReason: nil)
            try summary.validate()
            XCTAssertEqual(summary.routeIntent?.action, index == 0 ? .start : (index < 5 ? .resume : nil))
            XCTAssertEqual(snapshot.frontiers[0].readiness, .unavailable)
        }
        let historical = try XCTUnwrap(planned)
        let oldPlan = try h.plan(items: [historical], seed: 2240)
        let archived = try await provider.snapshot(for: oldPlan, evaluatedAt: C41.now)
        XCTAssertEqual(archived.frontiers[0].plannedReference, historical.reference)
        XCTAssertNotEqual(archived.frontiers[0].currentReference, historical.reference)
        XCTAssertEqual(archived.frontiers[0].state, .archived)

        var checkpoint: FieldDraftCheckpointV1?
        for (index, state) in [FieldDraftStateV1.active, .committing, .conflicted, .active,
                              .committing, .recoveryRequired, .discardPending].enumerated() {
            let next = try h.draft(seed: 2250, revision: UInt64(index + 1), state: state, mutation: 2260 + index)
            let mutation = try FieldDraftMutationV1(workspaceID: h.coordinator.workspaceID,
                expectedRevision: checkpoint?.draftRevision ?? 0, expectedBaseCanonicalRevision: 0,
                mutationID: next.mutationID, postImage: checkpoint == nil ? .createCheckpoint(next) : .reviseCheckpoint(next))
            _ = try h.coordinator.workspaceWriter.execute(.applyFieldDraft(mutation), mutationID: mutation.mutationID)
            checkpoint = next
            let snapshot = try await provider.snapshot(evaluatedAt: C41.now)
            let source = try XCTUnwrap(snapshot.sources.first { if case .resumableDraft = $0.reference { return true }; return false })
            let expected: [MyDaySourceStateV1] = [.draft, .committing, .conflicted, .draft, .committing, .recoveryRequired, .discardPending]
            XCTAssertEqual(source.state, expected[index])
            XCTAssertEqual(source.isSelectable, [.active, .conflicted, .recoveryRequired].contains(state))
        }
        let pending = try XCTUnwrap(checkpoint)
        let discardPlan = try DraftDiscardPlanV1(planID: C41.id(2271), workspaceID: h.store.workspaceID,
            draftID: pending.draftID, expectedDraftRevision: pending.draftRevision,
            nonemptyPayload: true, stageIDs: [], reservationIDs: [], estimatedBytes: Int64(pending.payloadData.count))
        let receipt = try DraftDiscardReceiptV1(receiptID: C41.id(2272), workspaceID: h.store.workspaceID,
            draftID: pending.draftID, planSHA256: discardPlan.planSHA256, disposedStageIDs: [],
            quarantinedReservationIDs: [], discardedAt: C41.now, mutationID: C41.mutation(2270))
        let discarded = try h.draft(seed: 2250, revision: pending.draftRevision + 1,
            state: .discarded, mutation: 2270, discardReceipt: receipt)
        let discardMutation = try FieldDraftMutationV1(workspaceID: h.store.workspaceID,
            expectedRevision: pending.draftRevision, expectedBaseCanonicalRevision: 0,
            mutationID: receipt.mutationID, postImage: .applyDiscardTerminal(.init(discardedCheckpoint: discarded, receipt: receipt)))
        _ = try h.coordinator.workspaceWriter.execute(.applyFieldDraft(discardMutation), mutationID: discardMutation.mutationID)
        let discardedSnapshot = try await provider.snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(discardedSnapshot.sources.first { if case .resumableDraft = $0.reference { return true }; return false }?.state, .discarded)
        try await h.coordinator.awaitSearchIndexLifecycle()
        let baseline = try h.baseline()
        _ = try await provider.snapshot(for: oldPlan, evaluatedAt: C41.now)
        XCTAssertEqual(try h.baseline(), baseline)
    }

    @MainActor
    func testProductionMyDayReadRejectsAccessSourceAndSessionDrift() async throws {
        let h = try C41ProductionSourceHarness()
        let provider = h.coordinator.makeMyDaySourceProvider(accessGate: h.gate)
        let packet = try h.packet(seed: 2300)
        try h.append(packet)
        try await h.coordinator.awaitSearchIndexLifecycle()
        let baseline = try h.baseline()
        #if DEBUG
        var didMaterialize = false
        provider.afterSourceMaterializationForTesting = { didMaterialize = true }
        await h.gate.markConfigurationUnknown()
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("locked read published") }
        catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
            XCTAssertFalse(didMaterialize)
        }
        XCTAssertEqual(try h.baseline(), baseline)
        await h.gate.eraseAccessState()
        provider.afterSourceMaterializationForTesting = {
            await h.gate.markConfigurationUnknown()
            await h.gate.eraseAccessState()
        }
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("access ABA published") }
        catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
            XCTAssertEqual(try h.baseline(), baseline)
        }
        provider.afterSourceMaterializationForTesting = {
            try h.append(h.packet(seed: 2310))
        }
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("source drift published") }
        catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sourcesChanged) }
        provider.afterSourceMaterializationForTesting = {
            try h.coordinator.activateValidating(session: h.store)
        }
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("session drift published") }
        catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sessionChanged) }
        provider.afterSourceMaterializationForTesting = nil
        do { _ = try await provider.snapshot(evaluatedAt: C41.now); XCTFail("retired provider reused") }
        catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sessionChanged) }
        #endif
        let fresh = h.coordinator.makeMyDaySourceProvider(accessGate: h.gate)
        let result = try await fresh.snapshot(evaluatedAt: C41.now)
        XCTAssertEqual(result.sources.count, 2)
        let pending = try h.packet(seed: 2320)
        h.coordinator.modelContext.insert(try WorkPacketManifestRow(pending))
        do { _ = try await fresh.snapshot(evaluatedAt: C41.now); XCTFail("unsaved source published") }
        catch { XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sourcesChanged) }
        XCTAssertTrue(h.coordinator.modelContext.hasChanges, "Reader must not rollback caller work")
        h.coordinator.modelContext.rollback()
        let authenticationCount = await h.authentication.count
        XCTAssertEqual(authenticationCount, 0)
    }

    @MainActor
    func testProductionMyDayReadsDueClosureAndRuleRetirementWithoutScheduling() async throws {
        let h = try C41ProductionSourceHarness()
        let fixture = try C41MyDayScheduleFixtureV1.make(workspaceID: h.store.workspaceID, actor: h.recorder)
        let definition = fixture.definition
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let beforeDST = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9)))
        let afterDST = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9)))
        XCTAssertEqual(afterDST.timeIntervalSince(beforeDST), 23 * 3_600)
        var events: [OccurrenceHistoryEventV1] = []
        for (index, date) in [beforeDST, afterDST].enumerated() {
            let basis = ResolvedOccurrenceBasisV1(nominalLocalDate: index == 0 ? "2026-03-07" : "2026-03-08",
                nominalLocalTime: "09:00:00", resolvedAtUTC: date,
                utcOffsetSeconds: calendar.timeZone.secondsFromGMT(for: date), disposition: .unambiguous,
                timeBasisSHA256: try definition.timeBasis.canonicalSHA256(), adjustmentProvenanceSHA256: nil)
            let occurrenceID = try OccurrenceIDV1(scheduleDefinitionID: definition.scheduleDefinitionID,
                identityNamespaceID: definition.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey)
            events.append(try .init(eventID: C41.id(2400 + index), workspaceID: h.store.workspaceID,
                occurrenceID: occurrenceID, scheduleRelease: .init(definition), action: .generated,
                nominalBasis: basis, effectiveBasis: basis, predecessor: nil, revision: 1,
                mutationID: C41.mutation(2410 + index), recordedBy: h.recorder, recordedAt: C41.now))
        }
        try ScheduleLifecycleClosureV1(definitions: [definition], history: events).validate()
        // Explicit canonical read fixtures, not writer/receipt acceptance. Their
        // coherent recorded instants cross DST; this test does not qualify a
        // schedule generator or reuse the old helper's inconsistent time basis.
        h.coordinator.modelContext.insert(try ScheduleDefinitionReleaseRow(definition))
        for event in events { h.coordinator.modelContext.insert(try OccurrenceHistoryEventRow(event)) }
        try h.coordinator.modelContext.save()
        let provider = h.coordinator.makeMyDaySourceProvider(accessGate: h.gate)
        let offsets: [(TimeInterval, OccurrenceDueReasonV1)] = [
            (-3_601, .beforeReadyWindow), (-3_600, .readyWindowOpen), (0, .dueWithinGrace),
            (7_201, .overdueAfterGrace),
        ]
        try await h.coordinator.awaitSearchIndexLifecycle()
        let baseline = try h.baseline()
        for (offset, reason) in offsets {
            let snapshot = try await provider.snapshot(evaluatedAt: afterDST.addingTimeInterval(offset))
            XCTAssertEqual(snapshot.dueQueue.items.first { $0.entry.occurrenceID == events[1].occurrenceID }?.reason, reason)
            XCTAssertEqual(snapshot.sources.first { if case let .scheduleOccurrence(anchor, _) = $0.reference {
                return anchor.occurrenceID == events[1].occurrenceID
            }; return false }?.dueAt, afterDST)
            XCTAssertEqual(try h.baseline(), baseline)
        }
        var predecessor = events[0]
        for (index, kind) in [ScheduleExceptionKindV1.deferred, .skipped, .missed, .cancelled, .retiredForRuleChange].enumerated() {
            let replacement = kind == .deferred ? events[1].effectiveBasis : nil
            let exception = try ScheduleExceptionV1(exceptionID: C41.id(2420 + index), kind: kind,
                priorEffectiveBasisSHA256: ScheduleCanonicalCodecV1.sha256(predecessor.effectiveBasis),
                replacementBasis: replacement,
                replacementOccurrenceID: kind == .retiredForRuleChange ? events[1].occurrenceID : nil,
                reasonCode: "C41_EXPLICIT_SOURCE_FIXTURE", recordedBy: h.recorder, recordedAt: C41.now)
            let event = try OccurrenceHistoryEventV1(eventID: C41.id(2430 + index), workspaceID: h.store.workspaceID,
                occurrenceID: predecessor.occurrenceID, scheduleRelease: predecessor.scheduleRelease,
                action: .applyException, nominalBasis: predecessor.nominalBasis,
                effectiveBasis: replacement ?? predecessor.effectiveBasis, exception: exception,
                predecessor: predecessor, revision: predecessor.revision + 1,
                mutationID: C41.mutation(2440 + index), recordedBy: h.recorder, recordedAt: C41.now)
            h.coordinator.modelContext.insert(try OccurrenceHistoryEventRow(event))
            try h.coordinator.modelContext.save()
            predecessor = event
            let captured = try h.baseline()
            let snapshot = try await provider.snapshot(evaluatedAt: beforeDST)
            let source = try XCTUnwrap(snapshot.sources.first { if case let .scheduleOccurrence(anchor, _) = $0.reference {
                return anchor.occurrenceID == event.occurrenceID
            }; return false })
            XCTAssertEqual(source.state, [MyDaySourceStateV1.active, .skipped, .missed, .cancelled, .ruleRetired][index])
            XCTAssertEqual(source.replacementOccurrenceID, kind == .retiredForRuleChange ? events[1].occurrenceID : nil)
            XCTAssertEqual(try h.baseline(), captured)
        }
        // Broken history must throw, not disappear into an empty queue.
        let original = try XCTUnwrap(h.coordinator.modelContext.fetch(FetchDescriptor<OccurrenceHistoryEventRow>())
            .first { $0.eventID == events[0].eventID })
        h.coordinator.modelContext.delete(original)
        try h.coordinator.modelContext.save()
        let corruptBaseline = try h.baseline()
        do { _ = try await provider.snapshot(evaluatedAt: beforeDST); XCTFail("broken closure published") }
        catch { XCTAssertEqual(try h.baseline(), corruptBaseline) }
    }

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
        _ = try h.writer.execute(.applyPartyAccountability(.appendActorSnapshot(C41.actor())),
                                 mutationID: C41.mutation(1590))
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
        _ = try h.writer.execute(.applyPartyAccountability(.appendActorSnapshot(C41.actor())),
                                 mutationID: C41.mutation(1690))
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
                         C41.item(12, reference: C41.workPacket(12), estimate: 20),
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
            try C41.item(40 + $0, reference: $0 == 1 ? C41.workPacket(41) : C41.round(40 + $0),
                         estimate: $0 == 0 ? 10 : nil)
        }, planID: C41.id(550), mutation: 551)
        guard case let .saved(saved) = try h.workflow.execute(.save(preview)) else {
            return XCTFail("save")
        }
        let states: [MyDaySourceStateV1] = [.active, .reopened, .completed, .cancelled,
                                            .retired, .missing, .stale]
        for (item, state) in zip(saved.plan.items, states) { h.sources.states[item.membershipID] = state }
        let staleItem = try XCTUnwrap(saved.plan.items.last)
        h.sources.current[staleItem.membershipID] = C41.round(
            46, revision: 2, sha: "c"
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

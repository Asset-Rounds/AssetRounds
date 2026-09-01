import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_96InstallationWorkflowTests: XCTestCase {
    func testV23P04C33G01ReadinessStartOrderedExecutionAsBuiltVariationCloseoutAndReport() async throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "G01", "GOLDEN")
        let fixture = try C33GoldenHarness()
        var projection = try fixture.projection()
        XCTAssertTrue(projection.canStart)
        XCTAssertEqual(projection.nextTaskID, "install")
        XCTAssertEqual(projection.tasks.map(\.definition.taskID), ["install", "verify"])
        XCTAssertNil(projection.nextCloseoutAction)
        XCTAssertEqual(projection.reportReadiness, .fieldWorkIncomplete)
        XCTAssertFalse(projection.reportReady)

        try await fixture.accept(.start(try fixture.lifecycleMutation(to: .inProgress, slot: 501)))
        projection = try fixture.projection()
        XCTAssertEqual(projection.envelope.state, .inProgress)
        XCTAssertEqual(projection.nextTaskID, "install")
        XCTAssertNil(projection.nextCloseoutAction)
        XCTAssertFalse(projection.reportReady)

        for (offset, task) in fixture.release.tasks.sorted().enumerated() {
            try await fixture.accept(.recordTaskResult(try fixture.taskMutation(taskID: task.taskID, slot: 510 + offset)))
            projection = try fixture.projection()
            XCTAssertEqual(projection.nextTaskID, offset == 0 ? "verify" : nil)
            XCTAssertNil(projection.nextCloseoutAction)
            XCTAssertFalse(projection.reportReady)
        }

        try await fixture.accept(.recordAsBuilt(try fixture.asBuiltMutation(slot: 520)))
        projection = try fixture.projection()
        XCTAssertEqual(projection.nextCloseoutAction, .recordFieldComplete)
        XCTAssertEqual(projection.report.asBuiltSnapshotSHA256, fixture.asBuiltSnapshot?.snapshotSHA256)
        XCTAssertFalse(projection.reportReady)

        try await fixture.accept(.closeout(try fixture.lifecycleMutation(to: .fieldComplete, slot: 530)))
        projection = try fixture.projection()
        XCTAssertEqual(projection.nextCloseoutAction, .submitForReview)
        XCTAssertEqual(projection.reportReadiness, .reviewRequired)
        XCTAssertFalse(projection.reportReady)

        try await fixture.accept(.closeout(try fixture.lifecycleMutation(to: .readyForReview, slot: 531)))
        projection = try fixture.projection()
        XCTAssertEqual(projection.nextCloseoutAction, .finalizeRecordedCloseout)
        XCTAssertEqual(projection.reportReadiness, .reviewRequired)
        XCTAssertFalse(projection.reportReady)

        let closeout = try InstallationCloseoutV1(
            completion: .completedAsRecorded,
            asBuiltSnapshotSHA256: try XCTUnwrap(fixture.asBuiltSnapshot).snapshotSHA256
        )
        let completedReference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(
            fixture.completedReportFixture(sourceRevision: Int(fixture.context.envelope.revision + 1)),
            activityCloseoutSHA256: closeout.closeoutSHA256
        )
        try await fixture.accept(.closeout(try fixture.lifecycleMutation(
            to: .finalized, slot: 532, closeout: closeout, completedReference: completedReference
        )))
        projection = try fixture.projection()
        XCTAssertEqual(projection.envelope.state, .finalized)
        XCTAssertEqual(projection.envelope.reviewState, .acceptedRecordedFacts)
        XCTAssertEqual(projection.envelope.installationCloseout, closeout)
        XCTAssertEqual(projection.envelope.completedSnapshotReference, completedReference)
        XCTAssertEqual(projection.report.closeoutSHA256, closeout.closeoutSHA256)
        XCTAssertEqual(projection.tasks.compactMap(\.currentResult), fixture.taskHistory.sorted())
        XCTAssertEqual(projection.reportReadiness, .readyForExistingRenderer)
        XCTAssertTrue(projection.reportReady)
        XCTAssertTrue(projection.closeoutRecorded)
        XCTAssertNil(projection.nextCloseoutAction)
        XCTAssertEqual(fixture.memory.effectCounts.count, 7)
        XCTAssertTrue(fixture.memory.effectCounts.values.allSatisfy { $0 == 1 })
        XCTAssertEqual(fixture.memory.receiptCount, 7)
        XCTAssertFalse(projection.report.claimsSafe)
        XCTAssertFalse(projection.report.claimsCompliant)
        XCTAssertFalse(projection.report.claimsPermitted)
        XCTAssertFalse(projection.report.claimsCommissioned)
        XCTAssertFalse(projection.report.claimsApproved)
        XCTAssertFalse(projection.report.claimsInService)
        XCTAssertTrue(ActivityStateMachineV2.permits(from: .inProgress, to: .fieldComplete))
        XCTAssertTrue(ActivityStateMachineV2.permits(from: .fieldComplete, to: .readyForReview))
        XCTAssertTrue(ActivityStateMachineV2.permits(from: .readyForReview, to: .finalized))
        XCTAssertTrue(InstallationWorkflowCoordinatorBoundaryV1.delegatesSoleCanonicalSeam)
        XCTAssertFalse(InstallationWorkflowProjectionBoundaryV1.reportRendererAdded)
    }

    func testV23P04C33A01ManualNoPlanUnavailableOptionalCapabilitiesAndAlternateTruth() throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "A01", "ALTERNATE")
        let fixture = try C33Fixture()
        let fallback = try NoPlanFallbackV1(limitation: "Manual subject selection is required.")
        let plan = try InstallationPlanCapabilityV1(disposition: .manualFallback, noPlanFallback: fallback)
        let scan = try InstallationScanCapabilityV1(
            disposition: .manualFallback,
            manualFallback: try C33Fixture.manualFallback(workspaceID: fixture.workspaceID)
        )
        let blocked = try fixture.envelope(readiness: [
            try .init(facetID: "access", kind: .access, disposition: .blocked, reason: "Access is not recorded.")
        ])
        let context = try InstallationWorkflowContextV1(
            envelope: blocked, release: fixture.release, basis: fixture.basis, planCapability: plan, scanCapability: scan
        )
        let projection = try fixture.workflow.projection(for: context)
        XCTAssertFalse(projection.canStart)
        XCTAssertEqual(projection.planDisposition, .manualFallback)
        XCTAssertEqual(projection.scanDisposition, .manualFallback)
        XCTAssertEqual(projection.blockers.map(\.kind), [.access])
        XCTAssertTrue(fallback.manualSubjectSelectionRequired)
        XCTAssertFalse(fallback.planRequired)
        XCTAssertFalse(fallback.scanRequired)
    }

    func testV23P04C33H01WrongStaleDuplicateOrderMalformedBoundsUnicodeAndIdentityFailClosed() async throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "H01", "HOSTILE")
        let fixture = try C33Fixture()
        XCTAssertThrowsError(try NoPlanFallbackV1(limitation: "unsafe\u{202e}"))
        XCTAssertThrowsError(try InstallationPlanCapabilityV1(disposition: .available, noPlanFallback: fixture.fallback))
        XCTAssertThrowsError(try InstallationWorkflowContextV1(
            envelope: try fixture.envelope(workspaceID: C33Fixture.workspace(99)), release: fixture.release,
            basis: fixture.basis, planCapability: fixture.plan, scanCapability: fixture.scan
        ))
        let duplicate = try InstallationTaskResultV1(
            resultID: C33Fixture.id(81), workspaceID: fixture.workspaceID, activityID: fixture.activityID,
            taskID: "install", outcome: .completed, revision: 1, mutationID: try C33Fixture.mutation(81)
        )
        XCTAssertThrowsError(try InstallationWorkflowContextV1(
            envelope: fixture.envelope, release: fixture.release, taskHistory: [duplicate, duplicate],
            basis: fixture.basis, planCapability: fixture.plan, scanCapability: fixture.scan
        ))
        let differentRelease = try InstallationWorkflowDefinitionReleaseV1(
            releaseID: C33Fixture.id(82), workspaceID: fixture.workspaceID, tasks: fixture.release.tasks,
            readinessPolicy: fixture.release.readinessPolicy, revision: fixture.release.revision + 1,
            mutationID: try C33Fixture.mutation(82)
        )
        XCTAssertThrowsError(try InstallationWorkflowContextV1(
            envelope: fixture.envelope, release: differentRelease, basis: fixture.basis,
            planCapability: fixture.plan, scanCapability: fixture.scan
        ))

        let ordered = try C33GoldenHarness()
        try await ordered.accept(.start(try ordered.lifecycleMutation(to: .inProgress, slot: 801)))
        let effectsBeforeRejectedOrder = ordered.memory.effectCounts
        let laterTaskID = try XCTUnwrap(ordered.release.tasks.sorted().dropFirst().first?.taskID)
        do {
            _ = try await ordered.workflow.execute(
                .recordTaskResult(try ordered.taskMutation(taskID: laterTaskID, slot: 802)),
                context: ordered.context
            )
            XCTFail("A known later task must not execute before the current next task")
        } catch {
            XCTAssertEqual(error as? InstallationWorkflowFailureV1, .invalidCommand)
        }
        XCTAssertEqual(ordered.memory.effectCounts, effectsBeforeRejectedOrder)
        XCTAssertEqual(ordered.memory.receiptCount, 1)
        XCTAssertEqual(try ordered.projection().nextTaskID, "install")
        XCTAssertFalse(InstallationWorkflowProjectionBoundaryV1.parallelKernelAdded)
    }

    func testV23P04C33I01CancellationInterruptionEffectBeforeReceiptAndRelaunchResumeAreBounded() async throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "I01", "INTERRUPTION")
        let harness = try C33RecoveryHarness()
        do {
            _ = try await harness.workflow.execute(.start(harness.start), context: harness.context)
            XCTFail("The first write must surface the simulated effect-before-receipt interruption")
        } catch {
            XCTAssertEqual(error as? C33MemoryFailure, .afterEffectBeforeReceipt)
        }
        XCTAssertEqual(harness.memory.effectCount, 1)
        XCTAssertEqual(harness.memory.envelope, harness.start.successorEnvelope)
        let recovered = try await harness.workflow.recover(.start(harness.start), context: harness.context)
        XCTAssertEqual(recovered.mutationID, harness.start.mutationID)
        XCTAssertEqual(harness.memory.effectCount, 1)
        XCTAssertEqual(recovered.durableReceipt, try XCTUnwrap(harness.memory.receipt(for: harness.start.mutationID)))
        XCTAssertTrue(InstallationWorkflowCoordinatorBoundaryV1.effectBeforeReceiptRecoverySupported)
        XCTAssertTrue(InstallationWorkflowCoordinatorBoundaryV1.expectedRevisionAndMutationIDRequired)
        XCTAssertFalse(InstallationWorkflowCoordinatorBoundaryV1.automaticCompletionFromEvidenceCount)
        XCTAssertFalse(InstallationWorkflowProjectionBoundaryV1.optionalPlanOrScanTruthFabricated)
    }

    func testV23P04C33R01RetryReplayReceiptRecoveryImmutableHistoryAndDeterministicReportRebuild() async throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "R01", "RECOVERY")
        let harness = try C33RecoveryHarness()
        _ = try await harness.workflow.recover(.start(harness.start), context: harness.context)
        let replay = try await harness.workflow.recover(.start(harness.start), context: harness.context)
        XCTAssertEqual(replay.durableReceipt, try XCTUnwrap(harness.memory.receipt(for: harness.start.mutationID)))
        XCTAssertEqual(harness.memory.effectCount, 1)
        do {
            _ = try await harness.workflow.recover(.start(try harness.divergentStart()), context: harness.context)
            XCTFail("A divergent stale command must not receive the prior receipt")
        } catch {
            XCTAssertEqual(error as? ActivityContractCoordinatorFailureV2, .staleExpectedRevision)
        }
        do {
            _ = try await harness.workflow.execute(.recordVariation(try harness.unboundVariation()), context: try harness.postStartContext())
            XCTFail("An arbitrary variation without a successor C47 basis must fail closed")
        } catch {
            XCTAssertEqual(error as? InstallationWorkflowFailureV1, .invalidCommand)
        }

        let finalized = try C33GoldenHarness()
        try await finalized.accept(.start(try finalized.lifecycleMutation(to: .inProgress, slot: 901)))
        for (offset, task) in finalized.release.tasks.sorted().enumerated() {
            try await finalized.accept(.recordTaskResult(
                try finalized.taskMutation(taskID: task.taskID, slot: 910 + offset)
            ))
        }
        try await finalized.accept(.recordAsBuilt(try finalized.asBuiltMutation(slot: 920)))
        try await finalized.accept(.closeout(try finalized.lifecycleMutation(to: .fieldComplete, slot: 930)))
        try await finalized.accept(.closeout(try finalized.lifecycleMutation(to: .readyForReview, slot: 931)))
        let closeout = try InstallationCloseoutV1(
            completion: .completedAsRecorded,
            asBuiltSnapshotSHA256: try XCTUnwrap(finalized.asBuiltSnapshot).snapshotSHA256
        )
        let completedReference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(
            finalized.completedReportFixture(sourceRevision: Int(finalized.context.envelope.revision + 1)),
            activityCloseoutSHA256: closeout.closeoutSHA256
        )
        try await finalized.accept(.closeout(try finalized.lifecycleMutation(
            to: .finalized, slot: 932, closeout: closeout, completedReference: completedReference
        )))
        let immutableHistory = finalized.taskHistory
        let effectsAfterFinalization = finalized.memory.effectCounts
        let firstRebuild = try finalized.projection()
        let equivalentContext = try InstallationWorkflowContextV1(
            envelope: finalized.context.envelope, release: finalized.context.release,
            basis: finalized.context.basis, taskHistory: immutableHistory,
            asBuiltSnapshot: finalized.asBuiltSnapshot,
            planCapability: finalized.context.planCapability,
            scanCapability: finalized.context.scanCapability
        )
        let secondRebuild = try finalized.workflow.projection(for: equivalentContext)
        XCTAssertEqual(firstRebuild.report, secondRebuild.report)
        XCTAssertEqual(firstRebuild.report.projectionSHA256, secondRebuild.report.projectionSHA256)
        XCTAssertEqual(finalized.taskHistory, immutableHistory)
        XCTAssertEqual(finalized.memory.effectCounts, effectsAfterFinalization)
        XCTAssertEqual(finalized.memory.effectCounts.count, 7)
        XCTAssertTrue(finalized.memory.effectCounts.values.allSatisfy { $0 == 1 })
        XCTAssertTrue(firstRebuild.reportReady)
        XCTAssertEqual(firstRebuild.envelope.completedSnapshotReference, completedReference)
        XCTAssertTrue(InstallationWorkflowCoordinatorBoundaryV1.replayReturnsSameReceiptOrNoAdditionalEffect)
        XCTAssertFalse(InstallationWorkflowProjectionBoundaryV1.persistentFamilyAdded)
        XCTAssertFalse(InstallationWorkflowProjectionBoundaryV1.schemaOrStoreAdded)
        XCTAssertFalse(InstallationWorkflowProjectionBoundaryV1.writerOrBackendAdded)
    }

    private func loadCorpus() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Activities/V23P04C33InstallationWorkflowCorpusV1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func assertScenario(_ corpus: [String: Any], _ id: String, _ kind: String) {
        XCTAssertEqual(corpus["schema"] as? String, "V23P04C33InstallationWorkflowCorpusV1")
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P04-C33")
        XCTAssertEqual(corpus["ordinal"] as? Int, 118)
        XCTAssertEqual((corpus["persistence"] as? [String: Any])?["persistentSchemaVersion"] as? Int, 36)
        XCTAssertEqual((corpus["persistence"] as? [String: Any])?["recordsSchemaVersion"] as? Int, 35)
        let scenarios = corpus["scenarios"] as? [[String: Any]]
        XCTAssertTrue(scenarios?.contains { $0["id"] as? String == id && $0["kind"] as? String == kind } == true)
    }

}

@MainActor
private final class C33Fixture {
    static func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "96000000-0000-4000-8000-%012d", value))! }
    static func workspace(_ value: Int) -> WorkspaceID { WorkspaceID(rawValue: id(value)) }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(value)) }

    let workspaceID = C33Fixture.workspace(1)
    let activityID = C33Fixture.id(2)
    let fallback: NoPlanFallbackV1
    let plan: InstallationPlanCapabilityV1
    let scan: InstallationScanCapabilityV1
    let release: InstallationWorkflowDefinitionReleaseV1
    let basis: InstallationBasisSnapshotV1
    let envelope: ActivitySessionEnvelopeV2
    let workflow: InstallationWorkflowCoordinatorV1

    init() throws {
        fallback = try NoPlanFallbackV1(limitation: "No plan is required; manual selection is explicit.")
        plan = try InstallationPlanCapabilityV1(disposition: .manualFallback, noPlanFallback: fallback)
        scan = try InstallationScanCapabilityV1(
            disposition: .manualFallback,
            manualFallback: try Self.manualFallback(workspaceID: workspaceID)
        )
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let registry = try InspectionPackageRegistryV2(packages: [package])
        let selected = try registry.bundledActivityWorkflowRelease(kind: .installation, packageID: ShippingIlluminatedSignAdapterV1.packageID, workspaceID: workspaceID)
        guard case let .installation(selectedRelease) = selected.release else { throw InstallationWorkflowFailureV1.invalidContext }
        release = selectedRelease
        basis = try .init(basisID: Self.id(3), workspaceID: workspaceID, activityID: activityID, subjectID: Self.id(4),
                          workflowReleaseReference: try .init(installation: selectedRelease, package: package), source: .noPlan(fallback),
                          capturedAt: Date(timeIntervalSince1970: 2_300_000_000), revision: 1, mutationID: try Self.mutation(3))
        envelope = try Self.makeEnvelope(
            workspaceID: workspaceID, activityID: activityID,
            readiness: try selectedRelease.readinessPolicy.requiredFacets.map { try .init(facetID: "ready-\($0.rawValue.lowercased())", kind: $0, disposition: .ready) },
            basis: basis, policy: selectedRelease.readinessPolicy
        )
        let authority = try ActivityContractConformanceAuthorityV2(
            sharedReceipt: try .init(sharedContractSHA256: String(repeating: "a", count: 64)),
            installationContractSHA256: String(repeating: "b", count: 64),
            punchContractSHA256: String(repeating: "c", count: 64), noPlanFallback: fallback
        )
        let coordinator = ActivityContractCoordinatorV2(query: C33UnavailableQuery(), writer: C33UnavailableWriter(), conformanceAuthority: authority)
        workflow = try InstallationWorkflowCoordinatorV1(contractCoordinator: coordinator, installationContractSHA256: authority.installationContractSHA256, noPlanFallback: fallback)
    }

    func context() throws -> InstallationWorkflowContextV1 {
        try .init(envelope: envelope, release: release, basis: basis, planCapability: plan, scanCapability: scan)
    }

    func envelope(workspaceID: WorkspaceID? = nil, readiness: [ActivityReadinessFacetV1]? = nil) throws -> ActivitySessionEnvelopeV2 {
        try Self.makeEnvelope(workspaceID: workspaceID ?? self.workspaceID, activityID: activityID, readiness: readiness,
                              basis: workspaceID == nil ? basis : nil, policy: release.readinessPolicy)
    }

    private static func makeEnvelope(workspaceID: WorkspaceID, activityID: UUID,
                                     readiness: [ActivityReadinessFacetV1]? = nil,
                                     basis: InstallationBasisSnapshotV1? = nil,
                                     policy: InstallationReadinessPolicyV1? = nil) throws -> ActivitySessionEnvelopeV2 {
        try .init(activityID: activityID, workspaceID: workspaceID, kind: .installation,
                  state: .ready, reviewState: .notRequested, subjectID: Self.id(4), title: "Recorded installation",
                  readiness: readiness ?? [try .init(facetID: "access", kind: .access, disposition: .ready)],
                  readinessPolicy: try .installation(policy ?? .init(requiredFacets: [.access])),
                  currentBasisReference: try basis.map { .installation(.init($0)) }, revision: 1, mutationID: try Self.mutation(4))
    }

    static func manualFallback(workspaceID: WorkspaceID) throws -> ManualLookupFallbackV1 {
        try .init(workspaceID: workspaceID, inputSHA256: String(repeating: "d", count: 64), reason: .notFound)
    }
}

@MainActor
private final class C33GoldenHarness {
    private static let fixedDate = Date(timeIntervalSince1970: 2_300_000_000)

    let release: InstallationWorkflowDefinitionReleaseV1
    let workflow: InstallationWorkflowCoordinatorV1
    let memory: C33GoldenMemory
    private(set) var context: InstallationWorkflowContextV1
    private(set) var taskHistory: [InstallationTaskResultV1] = []
    private(set) var asBuiltSnapshot: InstallationAsBuiltSnapshotV1?

    init() throws {
        let seed = try C33Fixture()
        release = seed.release
        context = try seed.context()
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: seed.workspaceID,
            generationID: C33Fixture.id(490),
            writerInstanceID: C33Fixture.id(491),
            workspaceRevision: 1,
            entityRevisions: [try .init(
                identity: .init(kind: .activitySessionEnvelope, id: seed.activityID),
                revision: seed.envelope.revision
            )]
        )
        memory = C33GoldenMemory(envelope: seed.envelope, expected: expected)
        let authority = try ActivityContractConformanceAuthorityV2(
            sharedReceipt: try .init(sharedContractSHA256: String(repeating: "a", count: 64)),
            installationContractSHA256: String(repeating: "b", count: 64),
            punchContractSHA256: String(repeating: "c", count: 64),
            noPlanFallback: seed.fallback
        )
        workflow = try InstallationWorkflowCoordinatorV1(
            contractCoordinator: ActivityContractCoordinatorV2(
                query: memory, writer: memory, conformanceAuthority: authority
            ),
            installationContractSHA256: authority.installationContractSHA256,
            noPlanFallback: seed.fallback
        )
    }

    func projection() throws -> InstallationWorkflowProjectionV1 {
        try workflow.projection(for: context)
    }

    func accept(_ command: InstallationWorkflowCommandV1) async throws {
        let prior = context
        let mutation = command.mutation
        let accepted = try await workflow.execute(command, context: prior)
        let replayed = try await workflow.execute(command, context: prior)
        guard accepted == replayed,
              accepted.expectedRevision == mutation.expectedRevision,
              accepted.durableReceipt.resultingRevision == (try MutationPortableExpectedRevisionV1(memory.expected)) else {
            throw InstallationWorkflowFailureV1.invalidContext
        }
        taskHistory.append(contentsOf: mutation.installationTaskResults)
        if let snapshot = mutation.installationAsBuiltSnapshot { asBuiltSnapshot = snapshot }
        context = try .init(
            envelope: mutation.successorEnvelope,
            release: prior.release,
            basis: mutation.installationBasisSnapshot ?? prior.basis,
            taskHistory: taskHistory,
            asBuiltSnapshot: asBuiltSnapshot,
            planCapability: prior.planCapability,
            scanCapability: prior.scanCapability
        )
    }

    func taskMutation(taskID: String, slot: Int) throws -> ActivityContractMutationV2 {
        let mutationID = try C33Fixture.mutation(slot)
        let result = try InstallationTaskResultV1(
            resultID: C33Fixture.id(slot + 100), workspaceID: context.envelope.workspaceID,
            activityID: context.envelope.activityID, taskID: taskID, outcome: .completed,
            note: "The released \(taskID) task was completed as recorded.", revision: 1,
            mutationID: mutationID
        )
        return try mutation(
            successor: envelope(from: context.envelope, state: context.envelope.state, mutationID: mutationID),
            mutationID: mutationID, taskResults: [result]
        )
    }

    func asBuiltMutation(slot: Int) throws -> ActivityContractMutationV2 {
        let mutationID = try C33Fixture.mutation(slot)
        let heads = try InstallationTaskResultLineageV1.validateAndCurrentHeads(taskHistory)
        let snapshot = try InstallationAsBuiltSnapshotV1(
            snapshotID: C33Fixture.id(slot + 100), workspaceID: context.envelope.workspaceID,
            activityID: context.envelope.activityID,
            basisReference: try InstallationBasisReferenceV1(context.basis),
            taskResultSHA256s: heads.values.map(\.resultSHA256),
            completion: .completedAsRecorded, revision: 1, mutationID: mutationID
        )
        return try mutation(
            successor: envelope(from: context.envelope, state: context.envelope.state, mutationID: mutationID),
            mutationID: mutationID, asBuilt: snapshot
        )
    }

    func lifecycleMutation(
        to state: ActivityStateV2,
        slot: Int,
        closeout: InstallationCloseoutV1? = nil,
        completedReference: CompletedActivitySnapshotV2CompatibilityReferenceV1? = nil
    ) throws -> ActivityContractMutationV2 {
        let mutationID = try C33Fixture.mutation(slot)
        let successor = try envelope(
            from: context.envelope, state: state, mutationID: mutationID,
            closeout: closeout, completedReference: completedReference
        )
        return try mutation(
            successor: successor, mutationID: mutationID,
            transition: try transition(from: context.envelope, to: successor, slot: slot)
        )
    }

    private func mutation(
        successor: ActivitySessionEnvelopeV2,
        mutationID: MutationIDV1,
        transition: ActivityStateTransitionV2? = nil,
        taskResults: [InstallationTaskResultV1] = [],
        asBuilt: InstallationAsBuiltSnapshotV1? = nil
    ) throws -> ActivityContractMutationV2 {
        try .init(
            workspaceID: context.envelope.workspaceID, expectedRevision: memory.expected,
            mutationID: mutationID, predecessorEnvelope: context.envelope, successorEnvelope: successor,
            transition: transition, completedSnapshotReference: successor.completedSnapshotReference,
            installationTaskResults: taskResults, installationAsBuiltSnapshot: asBuilt
        )
    }

    private func envelope(
        from predecessor: ActivitySessionEnvelopeV2,
        state: ActivityStateV2,
        mutationID: MutationIDV1,
        closeout: InstallationCloseoutV1? = nil,
        completedReference: CompletedActivitySnapshotV2CompatibilityReferenceV1? = nil
    ) throws -> ActivitySessionEnvelopeV2 {
        try .init(
            activityID: predecessor.activityID, workspaceID: predecessor.workspaceID, kind: .installation,
            state: state,
            reviewState: state == .readyForReview ? .pending : state == .finalized ? .acceptedRecordedFacts : .notRequested,
            subjectID: predecessor.subjectID, title: predecessor.title, readiness: predecessor.readiness,
            readinessPolicy: predecessor.readinessPolicy, variations: predecessor.variations,
            currentBasisReference: predecessor.currentBasisReference,
            installationCloseout: closeout ?? predecessor.installationCloseout,
            completedSnapshotReference: completedReference ?? predecessor.completedSnapshotReference,
            startedAt: predecessor.startedAt ?? (state.hasStarted ? Self.fixedDate : nil),
            finalizedAt: state == .finalized ? Self.fixedDate.addingTimeInterval(60) : predecessor.finalizedAt,
            revision: predecessor.revision + 1, mutationID: mutationID,
            predecessorEnvelopeSHA256: predecessor.envelopeSHA256
        )
    }

    private func transition(
        from predecessor: ActivitySessionEnvelopeV2,
        to successor: ActivitySessionEnvelopeV2,
        slot: Int
    ) throws -> ActivityStateTransitionV2 {
        try .init(
            transitionID: C33Fixture.id(slot + 200), workspaceID: predecessor.workspaceID,
            activityID: predecessor.activityID, kind: .installation, fromState: predecessor.state,
            toState: successor.state, actor: try Self.actor(workspaceID: predecessor.workspaceID),
            occurredAt: Self.fixedDate, revision: successor.revision, mutationID: successor.mutationID
        )
    }

    private static func actor(workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        try .init(
            snapshotID: C33Fixture.id(700), workspaceID: workspaceID,
            actor: .init(actorReferenceID: C33Fixture.id(701), workspaceID: workspaceID, displayName: "C33 recorder"),
            responsibility: .recordedBy, displayNameAtTime: "C33 recorder", capturedAt: fixedDate
        )
    }

    func completedReportFixture(sourceRevision: Int) throws -> CompletedActivitySnapshotV2 {
        let formats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
        let sections = try ["identity", "limitations", "provenance", "supersession", "manifest"].enumerated().map {
            try ReportSectionDefinitionV1(
                sectionID: $0.element, version: 1, required: true, supportedFormats: formats,
                privacyClass: .mandatoryPublicTruth, requiresHeading: true,
                requiresTextAlternative: true, order: $0.offset
            )
        }
        let registry = try ReportSectionRegistryV1(
            registryID: "c33-section-registry-v1", registryVersion: 1, sections: sections
        )
        let manifest = try ContractManifestV1(
            manifestID: "c33-completed-activity-v2", manifestVersion: 1,
            codec: ContractCodecRuleV1(codecVersion: 1),
            compatibility: .init(minimumReaderVersion: 1, maximumReaderVersion: 1, unknownObjectFields: .reject),
            objects: [try .init(
                typeID: "completed-snapshot", version: 1, unknownFieldPolicy: .reject,
                fields: [try .init(fieldID: "snapshot-id", jsonName: "snapshotID", kind: .string, required: true, maximumUTF8Bytes: 128)]
            )], enums: [], reportSectionRegistry: registry
        )
        let layout = try ReportLayoutProfileV1(
            profileID: "c33-customer-complete-v1", profileRelease: 1, audience: .customerSafe,
            detail: .complete, sectionIDs: sections.map(\.sectionID), mediaLayout: .standardGrid,
            orientation: .portrait, localeIdentifier: "en_US", unitsProfileID: "units-si-v1",
            displayProfileID: "display-v1", registry: registry
        )
        let export = try ExportProfileV1(
            exportProfileID: "c33-portable-v1", exportProfileRelease: 1, formats: formats,
            packaging: .combined, privacyTransformID: "customer-safe-v1", maximumMediaItems: 32,
            maximumArchiveBytes: Int64(SnapshotProjectionLimitsV1.maximumProjectionBytes)
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let workspaceToken = context.envelope.workspaceID.rawValue.uuidString.lowercased()
        let snapshotID = "c33-completed-snapshot-v1"
        let binding = try FinalizedReportProfileBindingV1(
            workspaceID: workspaceToken, snapshotID: snapshotID, outputScopeID: "c33-output-scope-v1",
            reportProfileID: layout.profileID, reportProfileRelease: layout.profileRelease,
            reportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(layout)),
            exportProfileID: export.exportProfileID, exportProfileRelease: export.exportProfileRelease,
            exportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(export)),
            sectionRegistryID: registry.registryID, sectionRegistryVersion: registry.registryVersion,
            sectionRegistrySHA256: KernelCanonicalHashV1.sha256(try encoder.encode(registry)),
            contractManifestID: manifest.manifestID, contractManifestVersion: manifest.manifestVersion,
            contractManifestSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(manifest)),
            sectionIDs: layout.sectionIDs, audience: .customerSafe, detail: .complete,
            privacyTransformID: export.privacyTransformID, localeIdentifier: layout.localeIdentifier,
            unitsProfileID: layout.unitsProfileID, displayProfileID: layout.displayProfileID,
            orientation: layout.orientation, mediaLayout: layout.mediaLayout,
            rendererVersion: ReportSemanticProjectorV1.rendererVersion, projectionVersion: "c47-activity-contract-v2"
        )
        let activity = try CompletedActivitySnapshotPayloadV1(
            workspaceID: workspaceToken, snapshotID: snapshotID, snapshotRevision: 1,
            sourceActivityID: context.envelope.activityID.uuidString.lowercased(), sourceRevision: sourceRevision,
            reportID: "c33-report-v1", packageReleaseID: "c33-bundled-workflow-v1",
            generatedAt: "2027-01-15T08:00:00.000Z", completedAt: "2027-01-15T08:00:00.000Z",
            supersedesSnapshotID: nil, supersededSnapshotSHA256: nil, amendmentReason: nil,
            profileBinding: binding, serviceFacts: [], evidenceCards: [],
            limitations: ["Recorded completion is not approval, certification, or authorization."]
        )
        let siteID = C33Fixture.id(710)
        let path = try LocationPathSnapshotV1(siteID: siteID, siteDisplay: "Recorded site", nodes: [])
        let placement = try AssetPlacementEventV1(
            id: C33Fixture.id(711), workspaceID: context.envelope.workspaceID,
            assetID: context.envelope.subjectID, siteID: siteID, locationNodeID: nil,
            predecessorEventID: nil, source: .migratedBaseline,
            physicalEpisodeID: .init(rawValue: C33Fixture.id(712)), continuity: .samePhysicalInstallation,
            pathSnapshot: path, mutationID: C33Fixture.mutation(713), occurredAt: Self.fixedDate
        )
        let location = try CompletedLocationCompositionSnapshotV1.build(
            workspaceID: context.envelope.workspaceID, assetID: context.envelope.subjectID,
            currentLocationPath: path, currentPlacementByAssetID: [context.envelope.subjectID: placement],
            activeCompositionEdges: [], frozenAtRevision: 1
        )
        return try CompletedActivitySnapshotV2.freezeOriginal(.init(
            activity: activity, assetID: context.envelope.subjectID, locationComposition: location
        ))
    }
}

@MainActor
private final class C33GoldenMemory: ActivityContractCurrentStateQueryingV2, ActivityContractCanonicalWorkspaceWritingV2 {
    private(set) var envelope: ActivitySessionEnvelopeV2
    private(set) var expected: WorkspaceExpectedRevisionV1
    private var receipts: [MutationIDV1: MutationReceiptV1] = [:]
    private(set) var effectCounts: [MutationIDV1: Int] = [:]
    var receiptCount: Int { receipts.count }

    init(envelope: ActivitySessionEnvelopeV2, expected: WorkspaceExpectedRevisionV1) {
        self.envelope = envelope; self.expected = expected
    }

    func currentActivityContract(workspaceID: WorkspaceID, activityID: UUID) async throws -> ActivityContractCurrentStateV2? {
        guard workspaceID == envelope.workspaceID, activityID == envelope.activityID else { return nil }
        return try .init(workspaceID: workspaceID, activityID: activityID, expectedRevision: expected, envelope: envelope)
    }

    func durableActivityContractReceipt(workspaceID: WorkspaceID, mutationID: MutationIDV1) async throws -> MutationReceiptV1? {
        guard workspaceID == envelope.workspaceID else { return nil }
        return receipts[mutationID]
    }

    func commitActivityContract(_ mutation: ActivityContractMutationV2) async throws -> MutationReceiptV1 {
        if let receipt = receipts[mutation.mutationID] { return receipt }
        let postImages = try mutation.mutationPostImages
        let next = try WorkspaceExpectedRevisionV1(
            workspaceID: mutation.workspaceID, generationID: expected.generationID,
            writerInstanceID: expected.writerInstanceID, workspaceRevision: expected.workspaceRevision + 1,
            entityRevisions: try postImages.map {
                try .init(identity: $0.identity, revision: $0.revision)
            }
        )
        let replica = ReplicaID(rawValue: C33Fixture.id(492))
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: mutation.workspaceID, replicaID: replica)
        let request = try WorkspaceMutationRequestV1(
            mutationID: mutation.mutationID, expectedRevision: mutation.expectedRevision,
            command: .applyActivityContract(mutation)
        )
        let envelope = try MutationEnvelopeV1(request: request, identity: identity)
        let receipt = try MutationReceiptV1(
            identity: .init(
                workspaceID: mutation.workspaceID, replicaID: replica,
                localSequence: UInt64(receipts.count + 1)
            ),
            envelope: envelope, resultingRevision: .init(next),
            postImages: postImages, committedAt: Date(timeIntervalSince1970: 2_300_000_000)
        )
        self.envelope = mutation.successorEnvelope
        expected = next
        effectCounts[mutation.mutationID, default: 0] += 1
        receipts[mutation.mutationID] = receipt
        return receipt
    }
}

@MainActor private final class C33UnavailableQuery: ActivityContractCurrentStateQueryingV2 {
    func currentActivityContract(workspaceID: WorkspaceID, activityID: UUID) async throws -> ActivityContractCurrentStateV2? { nil }
}

@MainActor private final class C33UnavailableWriter: ActivityContractCanonicalWorkspaceWritingV2 {
    func commitActivityContract(_ mutation: ActivityContractMutationV2) async throws -> MutationReceiptV1 { throw C33MemoryFailure.afterEffectBeforeReceipt }
    func durableActivityContractReceipt(workspaceID: WorkspaceID, mutationID: MutationIDV1) async throws -> MutationReceiptV1? { nil }
}

private enum C33MemoryFailure: Error, Equatable { case afterEffectBeforeReceipt }

@MainActor
private final class C33RecoveryHarness {
    let context: InstallationWorkflowContextV1
    let start: ActivityContractMutationV2
    let workflow: InstallationWorkflowCoordinatorV1
    let memory: C33MemoryState

    init() throws {
        let workspaceID = C33Fixture.workspace(301)
        let activityID = C33Fixture.id(302)
        let fallback = try NoPlanFallbackV1(limitation: "Manual selection is the explicit fallback.")
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let registry = try InspectionPackageRegistryV2(packages: [package])
        let selected = try registry.bundledActivityWorkflowRelease(
            kind: .installation, packageID: ShippingIlluminatedSignAdapterV1.packageID, workspaceID: workspaceID
        )
        guard case let .installation(release) = selected.release else { throw C33MemoryFailure.afterEffectBeforeReceipt }
        let readiness = try release.readinessPolicy.requiredFacets.map {
            try ActivityReadinessFacetV1(facetID: "ready-\($0.rawValue.lowercased())", kind: $0, disposition: .ready)
        }
        let mutationID = try C33Fixture.mutation(305)
        let basis = try InstallationBasisSnapshotV1(
            basisID: C33Fixture.id(306), workspaceID: workspaceID, activityID: activityID,
            subjectID: C33Fixture.id(304), workflowReleaseReference: try .init(installation: release, package: package),
            source: .noPlan(fallback), capturedAt: Date(timeIntervalSince1970: 2_300_000_000),
            revision: 1, mutationID: mutationID
        )
        let initialMutationID = try C33Fixture.mutation(303)
        let initial = try ActivitySessionEnvelopeV2(
            activityID: activityID, workspaceID: workspaceID, kind: .installation, state: .ready,
            reviewState: .notRequested, subjectID: C33Fixture.id(304), title: "C33 recovery installation",
            readiness: readiness, readinessPolicy: .installation(release.readinessPolicy),
            currentBasisReference: .installation(try .init(basis)), revision: 1, mutationID: initialMutationID
        )
        let expected = try Self.expected(workspaceID: workspaceID, activityID: activityID)
        let successor = try Self.successor(
            from: initial, state: .inProgress, mutationID: mutationID,
            currentBasisReference: .installation(try .init(basis))
        )
        let transition = try Self.transition(from: initial, to: successor, mutationID: mutationID)
        start = try ActivityContractMutationV2(
            workspaceID: workspaceID, expectedRevision: expected, mutationID: mutationID,
            predecessorEnvelope: initial, successorEnvelope: successor, transition: transition
        )
        let plan = try InstallationPlanCapabilityV1(disposition: .manualFallback, noPlanFallback: fallback)
        let scan = try InstallationScanCapabilityV1(
            disposition: .manualFallback,
            manualFallback: try .init(workspaceID: workspaceID, inputSHA256: String(repeating: "d", count: 64), reason: .notFound)
        )
        context = try .init(envelope: initial, release: release, basis: basis, planCapability: plan, scanCapability: scan)
        memory = C33MemoryState(envelope: initial, expected: expected)
        let authority = try ActivityContractConformanceAuthorityV2(
            sharedReceipt: try .init(sharedContractSHA256: String(repeating: "a", count: 64)),
            installationContractSHA256: String(repeating: "b", count: 64),
            punchContractSHA256: String(repeating: "c", count: 64), noPlanFallback: fallback
        )
        let coordinator = ActivityContractCoordinatorV2(query: memory, writer: memory, conformanceAuthority: authority)
        workflow = try InstallationWorkflowCoordinatorV1(
            contractCoordinator: coordinator, installationContractSHA256: authority.installationContractSHA256,
            noPlanFallback: fallback
        )
    }

    func divergentStart() throws -> ActivityContractMutationV2 {
        let mutationID = try C33Fixture.mutation(307)
        let successor = try Self.successor(from: context.envelope, state: .inProgress, mutationID: mutationID,
                                           currentBasisReference: context.envelope.currentBasisReference)
        return try .init(workspaceID: context.envelope.workspaceID, expectedRevision: start.expectedRevision,
                         mutationID: mutationID, predecessorEnvelope: context.envelope, successorEnvelope: successor,
                         transition: try Self.transition(from: context.envelope, to: successor, mutationID: mutationID))
    }

    func postStartContext() throws -> InstallationWorkflowContextV1 {
        try .init(envelope: start.successorEnvelope, release: context.release, basis: start.installationBasisSnapshot ?? context.basis,
                  planCapability: context.planCapability, scanCapability: context.scanCapability)
    }

    func unboundVariation() throws -> ActivityContractMutationV2 {
        let mutationID = try C33Fixture.mutation(314)
        let predecessor = start.successorEnvelope
        let actor = try Self.actor(workspaceID: predecessor.workspaceID)
        let arbitrary = try ActivityVariationV1(
            variationID: C33Fixture.id(315), workspaceID: predecessor.workspaceID, revision: 1,
            kind: .basisCorrected, predecessorBasisSHA256: String(repeating: "e", count: 64),
            successorBasisSHA256: String(repeating: "f", count: 64), reason: "Arbitrary unbound variation.",
            actor: actor, occurredAt: Date(timeIntervalSince1970: 2_300_000_000), mutationID: mutationID
        )
        let successor = try ActivitySessionEnvelopeV2(
            activityID: predecessor.activityID, workspaceID: predecessor.workspaceID, kind: .installation,
            state: .inProgress, reviewState: .notRequested, subjectID: predecessor.subjectID, title: predecessor.title,
            readiness: predecessor.readiness, readinessPolicy: predecessor.readinessPolicy, variations: [arbitrary],
            currentBasisReference: predecessor.currentBasisReference, startedAt: predecessor.startedAt,
            revision: predecessor.revision + 1, mutationID: mutationID, predecessorEnvelopeSHA256: predecessor.envelopeSHA256
        )
        return try .init(workspaceID: predecessor.workspaceID, expectedRevision: start.expectedRevision,
                         mutationID: mutationID, predecessorEnvelope: predecessor, successorEnvelope: successor)
    }

    private static func expected(workspaceID: WorkspaceID, activityID: UUID) throws -> WorkspaceExpectedRevisionV1 {
        try .init(workspaceID: workspaceID, generationID: C33Fixture.id(308), writerInstanceID: C33Fixture.id(309),
                  workspaceRevision: 1, entityRevisions: [.init(identity: try .init(kind: .activitySessionEnvelope, id: activityID), revision: 1)])
    }

    private static func successor(from predecessor: ActivitySessionEnvelopeV2, state: ActivityStateV2,
                                  mutationID: MutationIDV1, currentBasisReference: ActivityBasisHeadReferenceV2?) throws -> ActivitySessionEnvelopeV2 {
        try .init(activityID: predecessor.activityID, workspaceID: predecessor.workspaceID, kind: .installation,
                  state: state, reviewState: .notRequested, subjectID: predecessor.subjectID, title: predecessor.title,
                  readiness: predecessor.readiness, readinessPolicy: predecessor.readinessPolicy,
                  currentBasisReference: currentBasisReference, startedAt: Date(timeIntervalSince1970: 2_300_000_000),
                  revision: predecessor.revision + 1, mutationID: mutationID, predecessorEnvelopeSHA256: predecessor.envelopeSHA256)
    }

    private static func transition(from predecessor: ActivitySessionEnvelopeV2, to successor: ActivitySessionEnvelopeV2,
                                   mutationID: MutationIDV1) throws -> ActivityStateTransitionV2 {
        let actor = try Self.actor(workspaceID: predecessor.workspaceID)
        return try .init(transitionID: C33Fixture.id(312), workspaceID: predecessor.workspaceID, activityID: predecessor.activityID,
                         kind: .installation, fromState: predecessor.state, toState: successor.state, actor: actor,
                         occurredAt: Date(timeIntervalSince1970: 2_300_000_000), revision: successor.revision, mutationID: mutationID)
    }

    private static func actor(workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        try .init(snapshotID: C33Fixture.id(310), workspaceID: workspaceID,
                  actor: .init(actorReferenceID: C33Fixture.id(311), workspaceID: workspaceID, displayName: "C33 recorder"),
                  responsibility: .recordedBy, displayNameAtTime: "C33 recorder", capturedAt: Date(timeIntervalSince1970: 2_300_000_000))
    }
}

@MainActor
private final class C33MemoryState: ActivityContractCurrentStateQueryingV2, ActivityContractCanonicalWorkspaceWritingV2 {
    private(set) var envelope: ActivitySessionEnvelopeV2
    private let expected: WorkspaceExpectedRevisionV1
    private var effectBeforeReceiptMutationID: MutationIDV1?
    private var receipts: [MutationIDV1: MutationReceiptV1] = [:]
    private var shouldThrowAfterEffect = true
    private(set) var effectCount = 0

    init(envelope: ActivitySessionEnvelopeV2, expected: WorkspaceExpectedRevisionV1) { self.envelope = envelope; self.expected = expected }

    func currentActivityContract(workspaceID: WorkspaceID, activityID: UUID) async throws -> ActivityContractCurrentStateV2? {
        guard workspaceID == envelope.workspaceID, activityID == envelope.activityID else { return nil }
        return try .init(workspaceID: workspaceID, activityID: activityID, expectedRevision: expected, envelope: envelope)
    }

    func durableActivityContractReceipt(workspaceID: WorkspaceID, mutationID: MutationIDV1) async throws -> MutationReceiptV1? {
        guard workspaceID == envelope.workspaceID else { return nil }
        return receipts[mutationID]
    }

    func receipt(for mutationID: MutationIDV1) -> MutationReceiptV1? { receipts[mutationID] }

    func commitActivityContract(_ mutation: ActivityContractMutationV2) async throws -> MutationReceiptV1 {
        if let receipt = receipts[mutation.mutationID] { return receipt }
        if effectBeforeReceiptMutationID == mutation.mutationID, envelope == mutation.successorEnvelope {
            let receipt = try Self.receipt(for: mutation)
            receipts[mutation.mutationID] = receipt
            effectBeforeReceiptMutationID = nil
            return receipt
        }
        let receipt = try Self.receipt(for: mutation)
        envelope = mutation.successorEnvelope
        effectCount += 1
        if shouldThrowAfterEffect {
            shouldThrowAfterEffect = false
            effectBeforeReceiptMutationID = mutation.mutationID
            throw C33MemoryFailure.afterEffectBeforeReceipt
        }
        receipts[mutation.mutationID] = receipt
        return receipt
    }

    private static func receipt(for mutation: ActivityContractMutationV2) throws -> MutationReceiptV1 {
        let replica = ReplicaID(rawValue: C33Fixture.id(313))
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: mutation.workspaceID, replicaID: replica)
        let envelope = try MutationEnvelopeV1(request: .init(mutationID: mutation.mutationID, expectedRevision: mutation.expectedRevision,
                                                              command: .applyActivityContract(mutation)), identity: identity)
        let result = try WorkspaceExpectedRevisionV1(workspaceID: mutation.workspaceID, generationID: mutation.expectedRevision.generationID,
                                                      writerInstanceID: mutation.expectedRevision.writerInstanceID,
                                                      workspaceRevision: mutation.expectedRevision.workspaceRevision + 1,
                                                      entityRevisions: [try .init(identity: .init(kind: .activitySessionEnvelope, id: mutation.successorEnvelope.activityID), revision: mutation.successorEnvelope.revision)])
        return try .init(identity: .init(workspaceID: mutation.workspaceID, replicaID: replica, localSequence: 1), envelope: envelope,
                         resultingRevision: .init(result), postImages: try mutation.mutationPostImages,
                         committedAt: Date(timeIntervalSince1970: 2_300_000_000))
    }
}

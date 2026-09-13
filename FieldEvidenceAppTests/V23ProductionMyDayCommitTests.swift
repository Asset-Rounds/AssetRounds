import Combine
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23ProductionMyDayCommitTests: XCTestCase {
    @MainActor
    func testProductionSavePersistsExactCommitRowsReceiptsAndNoContentReservations() async throws {
        let fixture = try await diagnoseMyDayFailure(phase: "fixture") {
            try await makeFixture("complete-save")
        }
        defer { fixture.cleanUp() }
        let access = try diagnoseMyDayPreparation(phase: "access") {
            try XCTUnwrap(fixture.presentation.myDayAccess)
        }
        let request = try diagnoseMyDayPreparation(phase: "request") {
            try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        }
        let before = try diagnoseMyDayPreparation(phase: "pre-save-revision") {
            try fixture.coordinator.workspaceWriter.currentRevision()
        }
        let beforeReceiptCount = try diagnoseMyDayPreparation(phase: "pre-save-receipts") {
            try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext)
        }

        let outcome = try await diagnoseMyDayFailure(phase: "production-save") {
            try await access.savePlan(request)
        }

        try diagnoseMyDayPreparation(phase: "post-save-commit-assertions") {
            try assertCommitted(outcome, in: fixture.coordinator)
        }
        let after = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertEqual(after.revision, before.revision + 8)
        XCTAssertEqual(try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext),
                       beforeReceiptCount + 8)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: fixture.coordinator.modelContext), 1)
        XCTAssertEqual(try count(DraftCommitSagaRow.self, in: fixture.coordinator.modelContext), 5)
        XCTAssertEqual(try count(DraftCommitReceiptRow.self, in: fixture.coordinator.modelContext), 1)
        XCTAssertEqual(try count(AttachmentStagingItemRow.self, in: fixture.coordinator.modelContext), 0)
        XCTAssertEqual(try count(DraftContentReservationRow.self, in: fixture.coordinator.modelContext), 0)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), 1)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)

        let revisionBeforeReplay = try fixture.coordinator.workspaceWriter.currentRevision()
        let replay = try await diagnoseMyDayFailure(phase: "production-save-retry") {
            try await access.retryPlanSave(draftID: outcome.checkpoint.draftID)
        }
        XCTAssertEqual(replay, outcome)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revisionBeforeReplay)
    }

    @MainActor
    func testProductionSaveReadsEligibleDraftAndRetainsItsFrozenReferenceForMetadataEdit() async throws {
        let fixture = try await makeFixture("eligible-source-and-retained-edit")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let adapter = try writer.makeFieldDraftLifecycleAdapter(
            modelContext: fixture.coordinator.modelContext
        )
        let key = try makeKey(workspaceID: fixture.coordinator.workspaceID)
        let source = try makeSourceCheckpoint(
            workspaceID: fixture.coordinator.workspaceID,
            writer: writer,
            revision: 1
        )
        _ = try adapter.compareAndSwap(
            checkpoint: source,
            expectedDraftRevision: 0,
            expectedBaseRevision: 0
        )
        let reference = MyDayEligibleReferenceV1.resumableDraft(
            workspaceID: source.workspaceID,
            draftID: source.draftID,
            revision: source.draftRevision,
            checkpointSHA256: source.checkpointSHA256,
            anchor: source.resumeAnchor
        )
        let membershipID = UUID()

        let initial = try await access.savePlan(makeRequest(
            workspaceID: fixture.coordinator.workspaceID,
            key: key,
            reference: reference,
            membershipID: membershipID,
            estimateMinutes: 30
        ))
        try assertCommitted(initial, in: fixture.coordinator)
        XCTAssertEqual(initial.targetResult.plan.items.map(\.reference), [reference])

        let advancedSource = try makeSourceCheckpoint(
            workspaceID: source.workspaceID,
            writer: writer,
            draftID: source.draftID,
            revision: 2
        )
        _ = try adapter.compareAndSwap(
            checkpoint: advancedSource,
            expectedDraftRevision: 1,
            expectedBaseRevision: 0
        )

        let edited = try await access.savePlan(makeRequest(
            workspaceID: fixture.coordinator.workspaceID,
            key: key,
            reference: reference,
            predecessor: initial.targetResult.plan,
            membershipID: membershipID,
            estimateMinutes: 45
        ))

        try assertCommitted(
            edited,
            in: fixture.coordinator,
            expectedPredecessor: initial.targetResult.plan
        )
        XCTAssertEqual(edited.targetResult.plan.planID, initial.targetResult.plan.planID)
        XCTAssertEqual(edited.targetResult.plan.revision, 2)
        XCTAssertEqual(edited.targetResult.plan.predecessorPlanSHA256,
                       initial.targetResult.plan.planSHA256)
        XCTAssertEqual(edited.targetResult.plan.items.map(\.membershipID), [membershipID])
        XCTAssertEqual(edited.targetResult.plan.items.map(\.reference), [reference])
        let editedEstimate = try MyDayEstimateV1(wholeMinutes: 45)
        XCTAssertEqual(edited.targetResult.plan.items.first?.estimate, editedEstimate)
        XCTAssertEqual(try writer.currentPlan(for: key), edited.targetResult.plan)
        let storedPlans = try fixture.coordinator.modelContext.fetch(
            FetchDescriptor<MyDayPlanRowV1>()
        ).map { try $0.value() }
            .filter { $0.planID == edited.targetResult.plan.planID }
            .sorted { $0.revision < $1.revision }
        XCTAssertEqual(storedPlans, [initial.targetResult.plan, edited.targetResult.plan])
        XCTAssertEqual(try count(AttachmentStagingItemRow.self, in: fixture.coordinator.modelContext), 0)
        XCTAssertEqual(try count(DraftContentReservationRow.self, in: fixture.coordinator.modelContext), 0)
    }

    @MainActor
    func testPlanningRequiresItsExactGateAndSessionBeforeAnyDraftWrite() async throws {
        let local = try await makeFixture("binding-local")
        let foreign = try await makeFixture("binding-foreign")
        defer {
            local.cleanUp()
            foreign.cleanUp()
        }
        let localAccess = try XCTUnwrap(local.presentation.renderAccess)
        let foreignAccess = try XCTUnwrap(foreign.presentation.renderAccess)
        let localProvider = local.coordinator.makeMyDaySourceProvider(
            accessGate: local.session.gate
        )
        let wrongGateService = local.coordinator.makeMyDayPlanningCommitService(
            sourceProvider: localProvider
        )
        let localRevision = try local.coordinator.workspaceWriter.currentRevision()
        let foreignRevision = try foreign.coordinator.workspaceWriter.currentRevision()
        let localReceiptCount = try count(
            MutationReceiptRow.self,
            in: local.coordinator.modelContext
        )
        let foreignReceiptCount = try count(
            MutationReceiptRow.self,
            in: foreign.coordinator.modelContext
        )

        do {
            _ = try await wrongGateService.savePlan(
                makeRequest(workspaceID: local.coordinator.workspaceID),
                authorizing: foreignAccess
            )
            XCTFail("A ContentAccess from another concrete gate must be rejected")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }

        let foreignSessionProvider = foreign.coordinator.makeMyDaySourceProvider(
            accessGate: local.session.gate
        )
        let wrongSessionService = local.coordinator.makeMyDayPlanningCommitService(
            sourceProvider: foreignSessionProvider
        )
        do {
            _ = try await wrongSessionService.savePlan(
                makeRequest(workspaceID: local.coordinator.workspaceID),
                authorizing: localAccess
            )
            XCTFail("A provider from another concrete store session must be rejected")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }

        XCTAssertEqual(try local.coordinator.workspaceWriter.currentRevision(), localRevision)
        XCTAssertEqual(try foreign.coordinator.workspaceWriter.currentRevision(), foreignRevision)
        XCTAssertEqual(try count(MutationReceiptRow.self, in: local.coordinator.modelContext),
                       localReceiptCount)
        XCTAssertEqual(try count(MutationReceiptRow.self, in: foreign.coordinator.modelContext),
                       foreignReceiptCount)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: local.coordinator.modelContext), 0)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: foreign.coordinator.modelContext), 0)
    }

    #if DEBUG
    @MainActor
    func testEveryAcknowledgedEffectRetriesTheFrozenAttemptWithoutResampling() async throws {
        let points: [MyDayPlanningEffectPointV1] = [
            .editingCheckpoint,
            .committingCheckpoint,
            .preparedSaga,
            .contentPromotedSaga,
            .targetCommit,
            .targetCommittedSaga,
            .retirePendingSaga,
            .terminalBundle
        ]
        for point in points {
            let fixture = try await makeFixture("effect-\(point.rawValue.lowercased())")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            var injected = false
            access.setPlanningEffectHookForTesting { observed in
                guard observed == point, !injected else { return }
                injected = true
                throw V23MyDayCommitTestInterruption.injected
            }

            let draftID = try await interruptedDraftID(
                from: access,
                request: makeRequest(workspaceID: fixture.coordinator.workspaceID)
            )
            XCTAssertTrue(injected, "The requested durable effect hook was not reached: \(point.rawValue)")
            access.setPlanningEffectHookForTesting(nil)
            let interrupted = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
            let frozenAttempt = try preparedAttemptIfPresent(in: interrupted)
            let frozenPayload = frozenAttempt == nil ? nil : interrupted.payloadData

            let outcome = try await access.retryPlanSave(draftID: draftID)

            try assertCommitted(outcome, in: fixture.coordinator)
            if let frozenAttempt, let frozenPayload {
                XCTAssertEqual(outcome.checkpoint.payloadData, frozenPayload)
                XCTAssertEqual(try preparedAttempt(in: outcome.checkpoint), frozenAttempt)
            }
            let after = try fixture.coordinator.workspaceWriter.currentRevision()
            let replay = try await access.retryPlanSave(draftID: draftID)
            XCTAssertEqual(replay, outcome)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), after)
            XCTAssertEqual(try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext), 8)
        }
    }

    @MainActor
    func testCommittingAttemptRetriesAfterGenuineProductionAuthorityReopen() async throws {
        let fixture = try await makeFixture("cold-retry")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        var injected = false
        original.setPlanningEffectHookForTesting { point in
            guard point == .contentPromotedSaga, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        let draftID = try await interruptedDraftID(
            from: original,
            request: makeRequest(workspaceID: fixture.coordinator.workspaceID)
        )
        XCTAssertTrue(injected)
        original.setPlanningEffectHookForTesting(nil)
        let frozen = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
        let attempt = try preparedAttempt(in: frozen)
        let oldWriterID = try fixture.coordinator.workspaceWriter.currentRevision().writerInstanceID

        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(
            testCase: self,
            support: fixture.support,
            defaults: fixture.defaults
        )
        let authority = try XCTUnwrap(reopened)
        XCTAssertNotEqual(try authority.coordinator.workspaceWriter.currentRevision().writerInstanceID,
                          oldWriterID)
        let access = try XCTUnwrap(authority.presentation.myDayAccess)

        let outcome = try await access.retryPlanSave(draftID: draftID)

        try assertCommitted(outcome, in: authority.coordinator)
        XCTAssertEqual(outcome.checkpoint.payloadData, frozen.payloadData)
        XCTAssertEqual(try preparedAttempt(in: outcome.checkpoint), attempt)
        XCTAssertEqual(try count(MutationReceiptRow.self, in: authority.coordinator.modelContext), 8)
    }

    @MainActor
    func testCoverDuringZeroStagePromotionDeniesOriginalPublicationAndFreshAccessResumes() async throws {
        let fixture = try await makeFixture("promotion-cover")
        defer { fixture.cleanUp() }
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        let presentation = fixture.presentation
        original.setPlanningPromotionHookForTesting {
            presentation.receive(.sceneInactive)
        }

        let failure: MyDayPlanningSaveFailureV1
        do {
            _ = try await original.savePlan(
                makeRequest(workspaceID: fixture.coordinator.workspaceID)
            )
            return XCTFail("Cover during promotion must stop the next guarded durable effect")
        } catch let caught as MyDayPlanningSaveFailureV1 {
            failure = caught
        }
        original.setPlanningPromotionHookForTesting(nil)
        XCTAssertEqual(failure.underlying as? AppAccessContractFailureV1, .accessDenied)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        XCTAssertNil(fixture.presentation.myDayAccess)
        let interrupted = try checkpoint(draftID: failure.draftID,
                                         in: fixture.coordinator.modelContext)
        XCTAssertEqual(interrupted.state, .committing)
        let attempt = try preparedAttempt(in: interrupted)
        XCTAssertNil(try fixture.coordinator.workspaceWriter.durableReceipt(
            mutationID: attempt.command.mutationID
        ))
        do {
            _ = try await original.retryPlanSave(draftID: failure.draftID)
            XCTFail("A retained access from the covered publication must remain denied")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }

        let published = expectation(description: "Foreground republishes My Day commit access")
        let observation = fixture.presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in published.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [published], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(fixture.presentation.myDayAccess)
        let outcome = try await fresh.retryPlanSave(draftID: failure.draftID)
        try assertCommitted(outcome, in: fixture.coordinator)
        XCTAssertEqual(try preparedAttempt(in: outcome.checkpoint), attempt)
        do {
            _ = try await original.retryPlanSave(draftID: failure.draftID)
            XCTFail("Foreground publication must not revive the original access")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
    }

    @MainActor
    func testChangedSourceAndChangedPlanFrontierFailBeforeTargetCommit() async throws {
        for drift in V23MyDayCommitDrift.allCases {
            let fixture = try await makeFixture("stale-\(drift.rawValue)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let key = try makeKey(workspaceID: fixture.coordinator.workspaceID)
            let source: FieldDraftCheckpointV1?
            let reference: MyDayEligibleReferenceV1?
            if drift == .source {
                let created = try makeSourceCheckpoint(
                    workspaceID: fixture.coordinator.workspaceID,
                    writer: fixture.coordinator.workspaceWriter,
                    revision: 1
                )
                let adapter = try fixture.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(
                    modelContext: fixture.coordinator.modelContext
                )
                _ = try adapter.compareAndSwap(
                    checkpoint: created,
                    expectedDraftRevision: 0,
                    expectedBaseRevision: 0
                )
                source = created
                reference = .resumableDraft(
                    workspaceID: created.workspaceID,
                    draftID: created.draftID,
                    revision: created.draftRevision,
                    checkpointSHA256: created.checkpointSHA256,
                    anchor: created.resumeAnchor
                )
            } else {
                source = nil
                reference = nil
            }
            var injected = false
            access.setPlanningEffectHookForTesting { point in
                guard point == .committingCheckpoint, !injected else { return }
                injected = true
                throw V23MyDayCommitTestInterruption.injected
            }
            let draftID = try await interruptedDraftID(
                from: access,
                request: makeRequest(
                    workspaceID: fixture.coordinator.workspaceID,
                    key: key,
                    reference: reference
                )
            )
            XCTAssertTrue(injected)
            access.setPlanningEffectHookForTesting(nil)
            let committing = try checkpoint(draftID: draftID,
                                            in: fixture.coordinator.modelContext)
            let attempt = try preparedAttempt(in: committing)

            switch drift {
            case .source:
                let prior = try XCTUnwrap(source)
                let successor = try makeSourceCheckpoint(
                    workspaceID: prior.workspaceID,
                    writer: fixture.coordinator.workspaceWriter,
                    draftID: prior.draftID,
                    revision: 2
                )
                let adapter = try fixture.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(
                    modelContext: fixture.coordinator.modelContext
                )
                _ = try adapter.compareAndSwap(
                    checkpoint: successor,
                    expectedDraftRevision: 1,
                    expectedBaseRevision: 0
                )
            case .planFrontier:
                _ = try commitCompetingPlan(key: key, in: fixture.coordinator)
            }

            do {
                _ = try await access.retryPlanSave(draftID: draftID)
                XCTFail("A changed \(drift.rawValue) must fail before the frozen target command")
            } catch {
                XCTAssertEqual(error as? MyDayFailureV1, .staleRevision)
            }
            XCTAssertNil(try fixture.coordinator.workspaceWriter.durableReceipt(
                mutationID: attempt.command.mutationID
            ))
            XCTAssertEqual(try checkpoint(draftID: draftID,
                                          in: fixture.coordinator.modelContext).state, .committing)
            XCTAssertEqual(try count(DraftCommitSagaRow.self,
                                     in: fixture.coordinator.modelContext), 2)
            XCTAssertEqual(try count(DraftCommitReceiptRow.self,
                                     in: fixture.coordinator.modelContext), 0)
            if case let .save(successor, _) = attempt.command {
                let matching = try fixture.coordinator.modelContext.fetch(
                    FetchDescriptor<MyDayPlanRowV1>()
                ).map { try $0.value() }.filter { $0.planID == successor.planID }
                XCTAssertTrue(matching.isEmpty)
            }
        }
    }
    #else
    @MainActor
    func testEveryAcknowledgedEffectRetriesTheFrozenAttemptWithoutResampling() throws {
        throw XCTSkip("Planning effect injection is DEBUG-only")
    }

    @MainActor
    func testCommittingAttemptRetriesAfterGenuineProductionAuthorityReopen() throws {
        throw XCTSkip("Planning effect injection is DEBUG-only")
    }

    @MainActor
    func testCoverDuringZeroStagePromotionDeniesOriginalPublicationAndFreshAccessResumes() throws {
        throw XCTSkip("Planning promotion injection is DEBUG-only")
    }

    @MainActor
    func testChangedSourceAndChangedPlanFrontierFailBeforeTargetCommit() throws {
        throw XCTSkip("Planning effect injection is DEBUG-only")
    }
    #endif

    @MainActor
    func testZeroStageContentPortAcceptsOnlyItsExactEmptyMyDayPlan() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let payloadSHA = try FieldDraftCanonicalCodecV1.sha256(Data("zero-stage".utf8))
        let plan = try DraftCommitPlanV1(
            planID: UUID(),
            workspaceID: workspaceID,
            draftID: UUID(),
            draftRevision: 2,
            baseCanonicalRevision: 0,
            payloadSHA256: payloadSHA,
            stageDigests: [],
            targetCommandKind: .applyMyDay,
            expectedTargetRevision: 0,
            mutationID: .init(rawValue: UUID()),
            outputKeys: ["MY_DAY_PLAN|\(UUID().uuidString.lowercased())"]
        )
        let port = ProductionMyDayZeroStageContentPortV1(
            expectedPlan: plan,
            afterPromotion: nil
        )
        let promoted = try await port.promote(
            plan: plan,
            items: [],
            reservationMutationIDs: [:]
        )
        XCTAssertEqual(promoted, [])

        let wrongPlan = try DraftCommitPlanV1(
            planID: UUID(),
            workspaceID: workspaceID,
            draftID: plan.draftID,
            draftRevision: plan.draftRevision,
            baseCanonicalRevision: plan.baseCanonicalRevision,
            payloadSHA256: plan.payloadSHA256,
            stageDigests: [],
            targetCommandKind: .applyMyDay,
            expectedTargetRevision: 0,
            mutationID: plan.mutationID,
            outputKeys: plan.outputKeys
        )
        do {
            _ = try await port.promote(plan: wrongPlan, items: [], reservationMutationIDs: [:])
            XCTFail("A different commit plan must not use this zero-stage authority")
        } catch {
            XCTAssertEqual(error as? FieldDraftFailureV1, .invalidValue)
        }
        do {
            _ = try await port.promote(
                plan: plan,
                items: [],
                reservationMutationIDs: [UUID(): .init(rawValue: UUID())]
            )
            XCTFail("A nonempty reservation input must be rejected")
        } catch {
            XCTAssertEqual(error as? FieldDraftFailureV1, .invalidValue)
        }
        let stagedPlan = try DraftCommitPlanV1(
            planID: UUID(),
            workspaceID: workspaceID,
            draftID: UUID(),
            draftRevision: 2,
            baseCanonicalRevision: 0,
            payloadSHA256: payloadSHA,
            stageDigests: [try FieldDraftCanonicalCodecV1.sha256(Data("stage".utf8))],
            targetCommandKind: .applyMyDay,
            expectedTargetRevision: 0,
            mutationID: .init(rawValue: UUID()),
            outputKeys: ["MY_DAY_PLAN|\(UUID().uuidString.lowercased())"]
        )
        let stagedPort = ProductionMyDayZeroStageContentPortV1(
            expectedPlan: stagedPlan,
            afterPromotion: nil
        )
        do {
            _ = try await stagedPort.promote(
                plan: stagedPlan,
                items: [],
                reservationMutationIDs: [:]
            )
            XCTFail("My Day must reject a commit plan containing stage digests")
        } catch {
            XCTAssertEqual(error as? FieldDraftFailureV1, .invalidValue)
        }
        let promotionProbe = V23MyDayPromotionProbe()
        let guardedPort = ProductionMyDayZeroStageContentPortV1(
            expectedPlan: plan,
            afterPromotion: { promotionProbe.callCount += 1 }
        )
        let actualItem = try AttachmentStagingItemV1(
            stageID: UUID(),
            draftID: plan.draftID,
            workspaceID: plan.workspaceID,
            attachmentKind: .photo,
            scratchLeaseID: UUID(),
            expectedByteCount: 1,
            actualByteCount: 1,
            contentDigest: .init(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "b", count: 64)
            ),
            retryClass: .none,
            state: .readyLocal,
            protectionState: .available,
            revision: 1,
            mutationID: .init(rawValue: UUID())
        )
        do {
            _ = try await guardedPort.promote(
                plan: plan,
                items: [actualItem],
                reservationMutationIDs: [:]
            )
            XCTFail("A nonempty actual staging input must be rejected")
        } catch {
            XCTAssertEqual(error as? FieldDraftFailureV1, .invalidValue)
        }
        XCTAssertEqual(promotionProbe.callCount, 0)

        let nonMyDayPlan = try DraftCommitPlanV1(
            planID: UUID(),
            workspaceID: workspaceID,
            draftID: UUID(),
            draftRevision: 2,
            baseCanonicalRevision: 0,
            payloadSHA256: payloadSHA,
            stageDigests: [],
            targetCommandKind: .applyFieldDraft,
            expectedTargetRevision: 0,
            mutationID: .init(rawValue: UUID()),
            outputKeys: ["FIELD_DRAFT_CHECKPOINT|\(UUID().uuidString.lowercased())"]
        )
        let nonMyDayPort = ProductionMyDayZeroStageContentPortV1(
            expectedPlan: nonMyDayPlan,
            afterPromotion: { promotionProbe.callCount += 1 }
        )
        do {
            _ = try await nonMyDayPort.promote(
                plan: nonMyDayPlan,
                items: [],
                reservationMutationIDs: [:]
            )
            XCTFail("A non-My-Day target kind must be rejected")
        } catch {
            XCTAssertEqual(error as? FieldDraftFailureV1, .invalidValue)
        }
        XCTAssertEqual(promotionProbe.callCount, 0)
    }


    @MainActor
    func testProductionCarryoverCreatesOneAtomicReceiptAndPreservesSourceForNewAndExistingTarget() async throws {
        for existingTarget in [false, true] {
            let fixture = try await makeFixture("carryover-target-\(existingTarget)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let seed = try await seedCarryover(in: fixture, existingTarget: existingTarget)
            let writer = fixture.coordinator.workspaceWriter
            let before = try writer.currentRevision()
            let receiptCount = try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext)
            let sourceRows = try carryoverPlanHistory(seed.source, in: fixture.coordinator)

            let outcome = try await access.saveCarryover(seed.request)

            try assertCarryoverCommitted(outcome, source: seed.source, in: fixture.coordinator)
            XCTAssertEqual(try writer.currentRevision().revision, before.revision + 8)
            XCTAssertEqual(try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext), receiptCount + 8)
            XCTAssertEqual(try carryoverPlanHistory(seed.source, in: fixture.coordinator), sourceRows)
            XCTAssertEqual(try checkpoint(draftID: seed.work.draftID, in: fixture.coordinator.modelContext), seed.work)
            let target = outcome.targetResult.plan
            XCTAssertEqual(target.key, seed.request.confirmedContext.key)
            XCTAssertEqual(target.authoredBy, seed.request.confirmedContext.recordedBy)
            XCTAssertEqual(target.items.map(\.membershipID),
                (seed.target?.items.map(\.membershipID) ?? []) + seed.source.items.map(\.membershipID))
            XCTAssertEqual(target.items.map(\.reference),
                (seed.target?.items.map(\.reference) ?? []) + seed.source.items.map(\.reference))
            XCTAssertEqual(target.items.map(\.estimate),
                (seed.target?.items.map(\.estimate) ?? []) + seed.source.items.map(\.estimate))
            XCTAssertEqual(target.items.map(\.manualOrder), Array(0..<target.items.count))
            XCTAssertEqual(target.revision, (seed.target?.revision ?? 0) + 1)
            XCTAssertEqual(target.predecessorPlanSHA256, seed.target?.planSHA256)
            XCTAssertEqual(try count(AttachmentStagingItemRow.self, in: fixture.coordinator.modelContext), 0)
            XCTAssertEqual(try count(DraftContentReservationRow.self, in: fixture.coordinator.modelContext), 0)
            let after = try writer.currentRevision()
            let replay = try await access.retryPlanningCommit(draftID: outcome.checkpoint.draftID)
            XCTAssertEqual(replay, outcome)
            XCTAssertEqual(try writer.currentRevision(), after)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testCarryoverRetriesEveryAcknowledgedEffectWithFrozenCommandAndNoDuplicateTarget() async throws {
        #if DEBUG
        let points: [MyDayPlanningEffectPointV1] = [.editingCheckpoint, .committingCheckpoint,
            .preparedSaga, .contentPromotedSaga, .targetCommit, .targetCommittedSaga,
            .retirePendingSaga, .terminalBundle]
        for point in points {
            let fixture = try await makeFixture("carryover-effect-\(point.rawValue)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let seed = try await seedCarryover(in: fixture)
            let beforeReceipts = try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext)
            var injected = false
            access.setPlanningEffectHookForTesting { observed in
                guard observed == point, !injected else { return }
                injected = true
                throw V23MyDayCommitTestInterruption.injected
            }
            let draftID = try await interruptedCarryoverID(from: access, request: seed.request)
            XCTAssertTrue(injected)
            access.setPlanningEffectHookForTesting(nil)
            let interrupted = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
            let frozenAttempt = try preparedAttemptIfPresent(in: interrupted)
            let revisionBeforeWrongKind = try fixture.coordinator.workspaceWriter.currentRevision()
            do {
                _ = try await access.retryPlanSave(draftID: draftID)
                XCTFail("A carryover checkpoint must not enter the plan-specific retry API")
            } catch {
                XCTAssertEqual(error as? MyDayPlanningExecutionFailureV1, .unsupportedCommand)
            }
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revisionBeforeWrongKind)

            let outcome = try await access.retryPlanningCommit(draftID: draftID)
            try assertCarryoverCommitted(outcome, source: seed.source, in: fixture.coordinator)
            if let frozenAttempt {
                XCTAssertEqual(try preparedAttempt(in: outcome.checkpoint), frozenAttempt)
                XCTAssertEqual(outcome.checkpoint.payloadData, interrupted.payloadData)
            }
            XCTAssertEqual(try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext), beforeReceipts + 8)
            XCTAssertEqual(try checkpoint(draftID: seed.work.draftID, in: fixture.coordinator.modelContext), seed.work)
            let after = try fixture.coordinator.workspaceWriter.currentRevision()
            let replay = try await access.retryPlanningCommit(draftID: draftID)
            XCTAssertEqual(replay, outcome)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), after)
        }
        #else
        throw MyDayPlanningExecutionFailureV1.unsupportedState
        #endif
    }

    @MainActor
    func testCarryoverTargetReceiptSurvivesLaterIndependentSourcePlanEdit() async throws {
        #if DEBUG
        let fixture = try await makeFixture("carryover-later-source-plan")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryover(in: fixture)
        var injected = false
        access.setPlanningEffectHookForTesting { point in
            guard point == .targetCommit, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        let draftID = try await interruptedCarryoverID(from: access, request: seed.request)
        XCTAssertTrue(injected)
        access.setPlanningEffectHookForTesting(nil)
        let frozen = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
        let attempt = try preparedAttempt(in: frozen)
        let writer = fixture.coordinator.workspaceWriter
        XCTAssertEqual(try writer.currentPlan(for: seed.source.key), seed.source)
        let targetReceipt = try XCTUnwrap(writer.durableReceipt(mutationID: attempt.command.mutationID))
        let targetResult = try XCTUnwrap(writer.result(workspaceID: seed.source.key.workspaceID,
            mutationID: attempt.command.mutationID))
        let sourceItem = try XCTUnwrap(seed.source.items.first)
        let sourceEdit = try await access.savePlan(makeRequest(workspaceID: seed.source.key.workspaceID,
            key: seed.source.key, reference: sourceItem.reference, predecessor: seed.source,
            membershipID: sourceItem.membershipID, estimateMinutes: 45))
        XCTAssertNotEqual(sourceEdit.targetResult.plan, seed.source)
        let targetHistory = try carryoverPlanHistory(targetResult.plan, in: fixture.coordinator)
        let carryoverRows = try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext)

        let outcome = try await access.retryPlanningCommit(draftID: draftID)

        try assertCarryoverCommitted(outcome, source: seed.source, in: fixture.coordinator,
            currentSource: sourceEdit.targetResult.plan)
        XCTAssertEqual(outcome.targetResult, targetResult)
        XCTAssertEqual(outcome.targetReceipt, targetReceipt)
        XCTAssertEqual(try preparedAttempt(in: outcome.checkpoint), attempt)
        XCTAssertEqual(outcome.checkpoint.payloadData, frozen.payloadData)
        XCTAssertEqual(try carryoverPlanHistory(targetResult.plan, in: fixture.coordinator), targetHistory)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), carryoverRows)
        XCTAssertEqual(try checkpoint(draftID: seed.work.draftID, in: fixture.coordinator.modelContext), seed.work)
        let after = try writer.currentRevision()
        let replay = try await access.retryPlanningCommit(draftID: draftID)
        XCTAssertEqual(replay, outcome)
        XCTAssertEqual(try writer.currentRevision(), after)
        #else
        throw MyDayPlanningExecutionFailureV1.unsupportedState
        #endif
    }

    @MainActor
    func testCarryoverCommittingCheckpointResumesAfterRealProductionAuthorityReopen() async throws {
        #if DEBUG
        let fixture = try await makeFixture("carryover-cold-target-retry")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryover(in: fixture)
        var injected = false
        original.setPlanningEffectHookForTesting { point in
            guard point == .targetCommit, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        let draftID = try await interruptedCarryoverID(from: original, request: seed.request)
        XCTAssertTrue(injected)
        original.setPlanningEffectHookForTesting(nil)
        let frozen = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
        let attempt = try preparedAttempt(in: frozen)
        let oldWriterID = try fixture.coordinator.workspaceWriter.currentRevision().writerInstanceID
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(testCase: self,
            support: fixture.support, defaults: fixture.defaults)
        let authority = try XCTUnwrap(reopened)
        XCTAssertNotEqual(try authority.coordinator.workspaceWriter.currentRevision().writerInstanceID, oldWriterID)
        let access = try XCTUnwrap(authority.presentation.myDayAccess)
        let outcome = try await access.retryPlanningCommit(draftID: draftID)
        try assertCarryoverCommitted(outcome, source: seed.source, in: authority.coordinator)
        XCTAssertEqual(outcome.checkpoint.payloadData, frozen.payloadData)
        XCTAssertEqual(try preparedAttempt(in: outcome.checkpoint), attempt)
        let after = try authority.coordinator.workspaceWriter.currentRevision()
        let replay = try await access.retryPlanningCommit(draftID: draftID)
        XCTAssertEqual(replay, outcome)
        XCTAssertEqual(try authority.coordinator.workspaceWriter.currentRevision(), after)
        #else
        throw MyDayPlanningExecutionFailureV1.unsupportedState
        #endif
    }

    @MainActor
    func testCarryoverRejectsChangedSourcePlanTargetPlanAndSourceWorkBeforeCommitting() async throws {
        for drift in ["source-plan", "target-plan", "source-work"] {
            let fixture = try await makeFixture("carryover-stale-\(drift)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let seed = try await seedCarryover(in: fixture)
            let write = try access.prepareCarryoverEditingWrite(seed.request, replacing: nil,
                resumeAnchor: .init(sectionID: "carryover"))
            let acknowledgement = try access.persistEditingWrite(write)
            if drift == "source-plan" {
                let item = try XCTUnwrap(seed.source.items.first)
                _ = try await access.savePlan(makeRequest(workspaceID: seed.source.key.workspaceID,
                    key: seed.source.key, reference: item.reference, predecessor: seed.source,
                    membershipID: item.membershipID, estimateMinutes: 45))
            } else if drift == "target-plan" {
                _ = try await access.savePlan(makeRequest(workspaceID: seed.source.key.workspaceID,
                    key: seed.request.confirmedContext.key))
            } else {
                let advanced = try makeSourceCheckpoint(workspaceID: seed.work.workspaceID,
                    writer: fixture.coordinator.workspaceWriter, draftID: seed.work.draftID, revision: 2)
                let adapter = try fixture.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(
                    modelContext: fixture.coordinator.modelContext)
                _ = try adapter.compareAndSwap(checkpoint: advanced,
                    expectedDraftRevision: 1, expectedBaseRevision: 0)
            }
            let before = try fixture.coordinator.workspaceWriter.currentRevision()
            let planCount = try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext)
            let receiptCount = try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext)
            do {
                _ = try await access.retryPlanningCommit(draftID: write.checkpoint.draftID)
                XCTFail("Changed source/target facts cannot be silently rebound")
            } catch {
                if drift == "source-work" {
                    XCTAssertEqual(error as? MyDayWorkflowFailureV1, .carryoverIneligible)
                } else {
                    XCTAssertEqual(error as? MyDayFailureV1, .staleRevision)
                }
            }
            XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: write.checkpoint.draftID), acknowledgement.checkpoint)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), planCount)
            XCTAssertEqual(try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext), receiptCount)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), 0)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testCarryoverCoverDuringPromotionDeniesOriginalAndFreshPublicationRetriesFrozenAttempt() async throws {
        #if DEBUG
        let fixture = try await makeFixture("carryover-cover")
        defer { fixture.cleanUp() }
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryover(in: fixture)
        let presentation = fixture.presentation
        original.setPlanningPromotionHookForTesting { presentation.receive(.sceneInactive) }
        let failure: MyDayPlanningSaveFailureV1
        do {
            _ = try await original.saveCarryover(seed.request)
            return XCTFail("Covered publication must not continue a carryover")
        } catch let caught as MyDayPlanningSaveFailureV1 { failure = caught }
        original.setPlanningPromotionHookForTesting(nil)
        XCTAssertEqual(failure.underlying as? AppAccessContractFailureV1, .accessDenied)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.myDayAccess)
        let frozen = try checkpoint(draftID: failure.draftID, in: fixture.coordinator.modelContext)
        let attempt = try preparedAttempt(in: frozen)
        XCTAssertNil(try fixture.coordinator.workspaceWriter.durableReceipt(mutationID: attempt.command.mutationID))
        do {
            _ = try await original.retryPlanningCommit(draftID: failure.draftID)
            XCTFail("Original covered capability cannot retry")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        let published = expectation(description: "Fresh carryover publication")
        let observation = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        presentation.receive(.sceneActive)
        await fulfillment(of: [published], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(presentation.myDayAccess)
        let outcome = try await fresh.retryPlanningCommit(draftID: failure.draftID)
        try assertCarryoverCommitted(outcome, source: seed.source, in: fixture.coordinator)
        XCTAssertEqual(try preparedAttempt(in: outcome.checkpoint), attempt)
        do {
            _ = try await original.retryPlanningCommit(draftID: failure.draftID)
            XCTFail("Fresh publication cannot revive old carryover access")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        #else
        throw MyDayPlanningExecutionFailureV1.unsupportedState
        #endif
    }


    @MainActor
    private func seedCarryover(in fixture: V23ProductionMyDayPresentationHarness,
                               existingTarget: Bool = false) async throws
        -> (work: FieldDraftCheckpointV1, source: MyDayPlanV1,
            request: MyDayPlanningCarryoverRequestV1, target: MyDayPlanV1?) {
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let workspace = fixture.coordinator.workspaceID
        let adapter = try writer.makeFieldDraftLifecycleAdapter(modelContext: fixture.coordinator.modelContext)
        let work = try makeSourceCheckpoint(workspaceID: workspace, writer: writer, revision: 1)
        _ = try adapter.compareAndSwap(checkpoint: work, expectedDraftRevision: 0, expectedBaseRevision: 0)
        let reference = MyDayEligibleReferenceV1.resumableDraft(workspaceID: workspace,
            draftID: work.draftID, revision: work.draftRevision,
            checkpointSHA256: work.checkpointSHA256, anchor: work.resumeAnchor)
        let source = try await access.savePlan(makeRequest(workspaceID: workspace,
            reference: reference, estimateMinutes: 30)).targetResult.plan
        let targetKey = try MyDayKeyV1(workspaceID: workspace,
            civilDate: .init("2026-09-13"), ianaTimeZoneIdentifier: "America/New_York")
        var target: MyDayPlanV1?
        if existingTarget {
            let otherWork = try makeSourceCheckpoint(workspaceID: workspace, writer: writer, revision: 1)
            _ = try adapter.compareAndSwap(checkpoint: otherWork, expectedDraftRevision: 0, expectedBaseRevision: 0)
            let otherReference = MyDayEligibleReferenceV1.resumableDraft(workspaceID: workspace,
                draftID: otherWork.draftID, revision: otherWork.draftRevision,
                checkpointSHA256: otherWork.checkpointSHA256, anchor: otherWork.resumeAnchor)
            target = try await access.savePlan(makeRequest(workspaceID: workspace, key: targetKey,
                reference: otherReference, estimateMinutes: 15)).targetResult.plan
        }
        let confirmed = try access.captureConfirmedPlanningContext(for: targetKey, recordedByName: "Carryover recorder")
        let targetReference = try target.map { try MyDayPlanReferenceV1($0) }
        let request = try MyDayPlanningCarryoverRequestV1(confirmedContext: confirmed,
            sourcePlan: MyDayPlanReferenceV1(source), selectedMembershipIDs: source.items.map(\.membershipID),
            targetPredecessor: targetReference)
        return (work, source, request, target)
    }

    @MainActor
    private func interruptedCarryoverID(from access: AppAccessPresentationV1.MyDayAccess,
                                       request: MyDayPlanningCarryoverRequestV1) async throws -> UUID {
        do {
            _ = try await access.saveCarryover(request)
            throw V23MyDayCommitTestFailure.missingInterruption
        } catch let failure as MyDayPlanningSaveFailureV1 {
            XCTAssertTrue(failure.underlying is V23MyDayCommitTestInterruption)
            return failure.draftID
        }
    }

    @MainActor
    private func carryoverPlanHistory(_ plan: MyDayPlanV1,
                                      in coordinator: StoreSessionCoordinator) throws -> [MyDayPlanV1] {
        try coordinator.modelContext.fetch(FetchDescriptor<MyDayPlanRowV1>()).map { try $0.value() }
            .filter { $0.planID == plan.planID }.sorted { $0.revision < $1.revision }
    }

    @MainActor
    private func assertCarryoverCommitted(_ outcome: MyDayPlanningCommitOutcomeV1,
                                         source: MyDayPlanV1, in coordinator: StoreSessionCoordinator,
                                         currentSource: MyDayPlanV1? = nil) throws {
        XCTAssertEqual(outcome.checkpoint.state, .committed)
        let attempt = try preparedAttempt(in: outcome.checkpoint)
        guard case let .carryover(plan, frozenSource, target, receipt) = attempt.command else {
            return XCTFail("Committed carryover must retain its original typed command")
        }
        XCTAssertEqual(frozenSource, source)
        XCTAssertEqual(try coordinator.workspaceWriter.currentPlan(for: source.key), currentSource ?? source)
        XCTAssertEqual(outcome.targetResult.plan, target)
        XCTAssertEqual(try coordinator.workspaceWriter.currentPlan(for: target.key), target)
        try receipt.validate(plan: plan, source: source, target: target)
        try outcome.targetResult.receipt.validate(command: attempt.command)
        XCTAssertEqual(outcome.targetResult.receipt.carryoverReceiptSHA256, receipt.receiptSHA256)
        let stored = try coordinator.modelContext.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>())
            .map { try $0.value() }.filter { $0.mutationID == attempt.command.mutationID }
        XCTAssertEqual(stored, [receipt])
        let sagas = try coordinator.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>())
            .map { try $0.value() }.filter { $0.draftID == outcome.checkpoint.draftID }
            .sorted { $0.revision < $1.revision }
        XCTAssertEqual(sagas.count, 5)
        XCTAssertEqual(sagas.map(\.state), [.prepared, .contentPromotedUnbound,
            .targetCommitted, .draftRetirePending, .draftRetired])
        let expectedKeys = [try WorkspaceEntityIdentityV1(kind: .myDayPlan, id: target.planID).stableKey,
            try WorkspaceEntityIdentityV1(kind: .myDayCarryoverReceipt, id: attempt.command.mutationID.rawValue).stableKey].sorted()
        XCTAssertTrue(sagas.allSatisfy { $0.plan.outputKeys == expectedKeys })
        XCTAssertEqual(outcome.draftReceipt.sagaEventSHA256Chain, sagas.map(\.sagaSHA256))
        XCTAssertEqual(outcome.draftReceipt.targetReceiptSHA256, outcome.targetReceipt.resultSHA256)
        XCTAssertEqual(outcome.draftReceipt.committedAt, outcome.targetReceipt.committedAt)
        XCTAssertTrue(outcome.draftReceipt.consumedStageToContentID.isEmpty)
        XCTAssertEqual(try coordinator.workspaceWriter.durableReceipt(mutationID: attempt.command.mutationID), outcome.targetReceipt)
        XCTAssertEqual(try coordinator.workspaceWriter.durableReceipt(mutationID: attempt.terminalBundleMutationID), outcome.terminalReceipt)
        XCTAssertFalse(coordinator.modelContext.hasChanges)
    }

    @MainActor
    private func makeFixture(_ name: String) async throws
        -> V23ProductionMyDayPresentationHarness {
        try await V23ProductionMyDayPresentationHarness.start(
            testCase: self,
            name: "commit-\(name)"
        )
    }

    @MainActor
    private func diagnoseMyDayPreparation<Value>(phase: String,
                                                 _ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch {
            print("V23 My Day diagnostic phase=\(phase) error=\(String(reflecting: error))")
            throw error
        }
    }

    @MainActor
    private func diagnoseMyDayFailure<Value>(phase: String,
                                             _ operation: () async throws -> Value) async throws -> Value {
        do {
            return try await operation()
        } catch {
            print("V23 My Day diagnostic phase=\(phase) error=\(String(reflecting: error))")
            throw error
        }
    }

    @MainActor
    private func makeRequest(
        workspaceID: WorkspaceID,
        key suppliedKey: MyDayKeyV1? = nil,
        reference: MyDayEligibleReferenceV1? = nil,
        predecessor: MyDayPlanV1? = nil,
        membershipID: UUID = UUID(),
        estimateMinutes: Int = 30
    ) throws -> MyDayPlanningPlanSaveRequestV1 {
        let key = try suppliedKey ?? makeKey(workspaceID: workspaceID)
        let actor = try makeActor(workspaceID: workspaceID)
        let context = try MyDayPlanningConfirmedContextV1(
            key: key,
            recordedBy: actor,
            keyWasExplicitlyConfirmed: true,
            recordedByWasExplicitlySelectedOrCaptured: true
        )
        let items: [MyDayDraftItemV1]
        let eligible: [MyDayEligibleReferenceV1]
        if let reference {
            items = [try .init(
                membershipID: membershipID,
                reference: reference,
                estimate: .init(wholeMinutes: estimateMinutes)
            )]
            eligible = [reference]
        } else {
            items = []
            eligible = []
        }
        return try .init(
            confirmedContext: context,
            draft: .init(key: key, items: items, eligibleReferences: eligible),
            predecessor: predecessor
        )
    }

    @MainActor
    private func makeKey(workspaceID: WorkspaceID) throws -> MyDayKeyV1 {
        try .init(
            workspaceID: workspaceID,
            civilDate: .init("2026-09-12"),
            ianaTimeZoneIdentifier: "America/New_York"
        )
    }

    @MainActor
    private func makeActor(workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let capturedAt = Date(timeIntervalSince1970: 1_789_084_800)
        let reference = try LocalActorReferenceV1(
            actorReferenceID: UUID(),
            workspaceID: workspaceID,
            displayName: "Production My Day recorder"
        )
        return try .init(
            snapshotID: UUID(),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: .recordedBy,
            displayNameAtTime: reference.displayName,
            capturedAt: capturedAt
        )
    }

    @MainActor
    private func checkpoint(
        draftID: UUID,
        in context: ModelContext
    ) throws -> FieldDraftCheckpointV1 {
        let rows = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
            predicate: #Predicate { $0.draftID == draftID }
        ))
        guard rows.count == 1, let row = rows.first else {
            throw V23MyDayCommitTestFailure.missingCheckpoint
        }
        return try row.value()
    }

    @MainActor
    private func preparedAttempt(
        in checkpoint: FieldDraftCheckpointV1
    ) throws -> MyDayPlanningCommitAttemptInputsV1 {
        guard let attempt = try preparedAttemptIfPresent(in: checkpoint) else {
            throw V23MyDayCommitTestFailure.missingAttempt
        }
        return attempt
    }

    @MainActor
    private func preparedAttemptIfPresent(
        in checkpoint: FieldDraftCheckpointV1
    ) throws -> MyDayPlanningCommitAttemptInputsV1? {
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
        return payload.commitAttempt
    }

    #if DEBUG
    @MainActor
    private func interruptedDraftID(
        from access: AppAccessPresentationV1.MyDayAccess,
        request: MyDayPlanningPlanSaveRequestV1
    ) async throws -> UUID {
        do {
            _ = try await access.savePlan(request)
            throw V23MyDayCommitTestFailure.missingInterruption
        } catch let failure as MyDayPlanningSaveFailureV1 {
            XCTAssertTrue(failure.underlying is V23MyDayCommitTestInterruption)
            return failure.draftID
        }
    }
    #endif

    @MainActor
    private func assertCommitted(
        _ outcome: MyDayPlanningCommitOutcomeV1,
        in coordinator: StoreSessionCoordinator,
        expectedPredecessor: MyDayPlanV1? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(outcome.checkpoint.state, .committed, file: file, line: line)
        XCTAssertEqual(outcome.checkpoint.purpose, .myDayPlanning, file: file, line: line)
        XCTAssertEqual(outcome.checkpoint.codec, try MyDayPlanningDraftCodecV1.release(),
                       file: file, line: line)
        XCTAssertTrue(outcome.checkpoint.stageIDs.isEmpty, file: file, line: line)
        let attempt = try preparedAttempt(in: outcome.checkpoint)
        guard case let .save(successor, predecessor) = attempt.command else {
            return XCTFail("Expected a frozen save command", file: file, line: line)
        }
        XCTAssertEqual(predecessor, expectedPredecessor, file: file, line: line)
        XCTAssertEqual(outcome.targetResult.plan, successor, file: file, line: line)
        XCTAssertEqual(outcome.targetResult.receipt.mutationID, attempt.command.mutationID,
                       file: file, line: line)
        XCTAssertEqual(outcome.targetReceipt.mutationID, attempt.command.mutationID,
                       file: file, line: line)
        XCTAssertEqual(outcome.draftReceipt.targetMutationID, attempt.command.mutationID,
                       file: file, line: line)
        XCTAssertEqual(outcome.draftReceipt.targetReceiptSHA256,
                       outcome.targetReceipt.resultSHA256, file: file, line: line)
        XCTAssertEqual(outcome.draftReceipt.committedAt,
                       outcome.targetReceipt.committedAt, file: file, line: line)
        XCTAssertTrue(outcome.draftReceipt.consumedStageToContentID.isEmpty,
                      file: file, line: line)
        XCTAssertEqual(outcome.terminalReceipt.mutationID,
                       attempt.terminalBundleMutationID, file: file, line: line)
        XCTAssertEqual(outcome.checkpoint.lastDurableMutationID,
                       attempt.terminalBundleMutationID, file: file, line: line)
        XCTAssertEqual(outcome.checkpoint.lastReceiptSHA256,
                       outcome.draftReceipt.receiptSHA256, file: file, line: line)
        XCTAssertEqual(try coordinator.workspaceWriter.durableReceipt(
            mutationID: attempt.command.mutationID
        ), outcome.targetReceipt, file: file, line: line)

        let sagas = try coordinator.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>())
            .map { try $0.value() }
            .filter { $0.draftID == outcome.checkpoint.draftID }
            .sorted { $0.revision < $1.revision }
        XCTAssertEqual(sagas.map(\.state), [
            .prepared,
            .contentPromotedUnbound,
            .targetCommitted,
            .draftRetirePending,
            .draftRetired
        ], file: file, line: line)
        XCTAssertEqual(sagas.map(\.sagaID), [
            attempt.preparedSagaID,
            attempt.contentPromotedSagaID,
            attempt.targetCommittedSagaID,
            attempt.draftRetirePendingSagaID,
            attempt.draftRetiredSagaID
        ], file: file, line: line)
        XCTAssertEqual(sagas.map(\.mutationID),
                       attempt.sagaMutationIDs + [attempt.terminalBundleMutationID],
                       file: file, line: line)
        XCTAssertEqual(sagas.map(\.updatedAt), attempt.sagaUpdatedAts,
                       file: file, line: line)
        XCTAssertEqual(outcome.draftReceipt.sagaEventSHA256Chain, sagas.map(\.sagaSHA256),
                       file: file, line: line)
    }

    @MainActor
    private func makeSourceCheckpoint(
        workspaceID: WorkspaceID,
        writer: WorkspaceWriterV1,
        draftID: UUID = UUID(),
        revision: UInt64
    ) throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(
            draftID: draftID,
            workspaceID: workspaceID,
            scope: .init(scopeKind: "V23_MY_DAY_COMMIT_SOURCE", stableComponentIDs: ["source"]),
            purpose: .assetFieldEdit,
            codec: .init(
                codecID: "v23.my-day.commit-source.v1",
                codecVersion: 1,
                releaseSHA256: String(repeating: "a", count: 64)
            ),
            baseCanonicalRevision: 0,
            draftRevision: revision,
            payloadData: Data("source-revision-\(revision)".utf8),
            stageIDs: [],
            resumeAnchor: .init(sectionID: "source"),
            state: .active,
            updatedAt: Date(timeIntervalSince1970: 1_789_084_800 + Double(revision)),
            mutationID: try writer.makeMutationID()
        )
    }

    @MainActor
    private func commitCompetingPlan(
        key: MyDayKeyV1,
        in coordinator: StoreSessionCoordinator
    ) throws -> MyDayPlanV1 {
        let writer = coordinator.workspaceWriter
        let plan = try MyDayPlanV1(
            planID: UUID(),
            key: key,
            items: [],
            revision: 1,
            mutationID: writer.makeMutationID(),
            authoredBy: makeActor(workspaceID: key.workspaceID),
            authoredAt: Date(timeIntervalSince1970: 1_789_084_900)
        )
        let current = try writer.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: .myDayPlan, id: plan.planID)
        let byIdentity = Dictionary(uniqueKeysWithValues: current.entityRevisions.map {
            ($0.identity, $0.revision)
        })
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [
                .init(identity: identity, revision: byIdentity[identity, default: 0])
            ]
        )
        _ = try writer.commitMyDay(.init(
            command: .save(successor: plan, predecessor: nil),
            expectedRevision: expected
        ))
        return plan
    }

    @MainActor
    private func count<Row: PersistentModel>(
        _ type: Row.Type,
        in context: ModelContext
    ) throws -> Int {
        try context.fetchCount(FetchDescriptor<Row>())
    }
}

private enum V23MyDayCommitTestInterruption: Error {
    case injected
}

private enum V23MyDayCommitTestFailure: Error {
    case missingCheckpoint
    case missingAttempt
    case missingInterruption
}

private enum V23ProductionReviewedResolutionHistoryFixtureV1 {
    static func next(_ previous: FieldDraftCheckpointV1, state: FieldDraftStateV1 = .active,
                     anchor: DraftResumeAnchorV1? = nil) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: previous.draftID, workspaceID: previous.workspaceID,
            scope: previous.scope, purpose: previous.purpose, codec: previous.codec,
            baseCanonicalRevision: previous.baseCanonicalRevision,
            draftRevision: previous.draftRevision + 1, payloadData: previous.payloadData,
            stageIDs: previous.stageIDs, resumeAnchor: anchor ?? previous.resumeAnchor,
            state: state, updatedAt: previous.updatedAt, mutationID: .init(rawValue: UUID()))
    }
}

@MainActor
private final class V23MyDayPromotionProbe {
    var callCount = 0
}

#if DEBUG
private enum V23MyDayCommitDrift: String, CaseIterable {
    case source
    case planFrontier = "plan-frontier"
}
#endif

@MainActor
private struct V23ProductionMyDayReopenedAuthority {
    let router: StartupRouter
    let session: ProductionAppAccessSessionV1
    let presentation: AppAccessPresentationV1
    let coordinator: StoreSessionCoordinator

    static func start(
        testCase: XCTestCase,
        support: URL,
        defaults: UserDefaults
    ) async throws -> Self {
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support,
            startupRouter: router,
            defaults: defaults,
            authenticationClient: V23ProductionMyDayCommitAuthentication(),
            notificationSystem: V23ProductionMyDayCommitNotificationSystem()
        )
        let presentation = AppAccessPresentationV1(
            startupRouter: router,
            sessionFactory: { session }
        )
        let published = testCase.expectation(
            description: "Reopened production authority publishes My Day access"
        )
        let observation = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in published.fulfill() }
        await presentation.bootstrapIfNeeded()
        await testCase.fulfillment(of: [published], timeout: 30)
        observation.cancel()
        guard case .ready(let coordinator, _, _) = router.route else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return .init(
            router: router,
            session: session,
            presentation: presentation,
            coordinator: coordinator
        )
    }
}

private actor V23ProductionMyDayCommitAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }

    func authenticate(_ attempt: LocalAuthenticationAttemptV1)
        -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }

    func cancel(attemptID: UUID) {}
}

@MainActor
private final class V23ProductionMyDayCommitNotificationSystem: NotificationSystemPortV1 {
    private var requests: [NotificationSystemRequestV1] = []

    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }

    func observations() async throws -> [NotificationSystemObservationV1] {
        requests.map {
            .init(requestID: $0.notification.requestID, request: $0, delivered: false)
        }
    }

    func add(_ request: NotificationSystemRequestV1) async throws {
        requests.append(request)
    }

    func remove(_ requestIDs: [String]) async throws {
        requests.removeAll { requestIDs.contains($0.notification.requestID) }
    }
}

extension V23ProductionMyDayCommitTests {
    #if DEBUG
    @MainActor
    func testFirstOrdinaryPreparedConflictUsesRealSagaPrefixAndExplicitRebase() async throws {
        let fixture = try await makeFixture("prepared-first-origin")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        var injected = false
        access.setPlanningEffectHookForTesting { point in
            // targetCommit follows the target write but precedes its saga, so
            // it is recovery-only.  This is the legal no-target prepared prefix.
            guard point == .contentPromotedSaga, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        let draftID = try await interruptedDraftID(from: access, request: request)
        XCTAssertTrue(injected)
        access.setPlanningEffectHookForTesting(nil)
        let committing = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
        XCTAssertEqual(committing.state, .committing)
        let attempt = try preparedAttempt(in: committing)
        let classified = try V23ProductionReviewedResolutionHistoryFixtureV1.next(
            committing, state: .conflicted
        )
        let classification = try FieldDraftMutationV1(
            workspaceID: committing.workspaceID,
            expectedRevision: committing.draftRevision,
            expectedBaseCanonicalRevision: committing.baseCanonicalRevision,
            mutationID: classified.mutationID,
            postImage: .reviseCheckpoint(classified)
        )
        _ = try writer.commitFieldDraft(classification)
        XCTAssertEqual(try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext), classified)
        XCTAssertEqual(try preparedAttempt(in: classified), attempt)
        let payload = try MyDayPlanningDraftPayloadV1(
            editing: request.confirmedContext,
            intent: .plan(draft: request.draft, predecessor: request.predecessor)
        )
        let successor = try FieldDraftCheckpointV1(
            draftID: draftID, workspaceID: classified.workspaceID, scope: classified.scope,
            purpose: classified.purpose, codec: classified.codec,
            baseCanonicalRevision: classified.baseCanonicalRevision,
            draftRevision: classified.draftRevision + 1,
            payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: classified.stageIDs,
            resumeAnchor: classified.resumeAnchor, state: .active, updatedAt: classified.updatedAt,
            mutationID: writer.makeMutationID()
        )
        let resolution = try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase, expectedCheckpoint: classified,
            reviewedTargetBasis: .absent(key: request.confirmedContext.key,
                expectedWorkspaceRevision: writer.currentRevision().revision),
            successorCheckpoint: successor
        )
        let rebase = try FieldDraftMutationV1(workspaceID: classified.workspaceID,
            expectedRevision: classified.draftRevision,
            expectedBaseCanonicalRevision: classified.baseCanonicalRevision,
            mutationID: successor.mutationID, postImage: .resolveConflict(resolution))
        let receipt = try writer.commitFieldDraft(rebase)
        XCTAssertEqual(try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext), successor)
        XCTAssertEqual(try writer.fieldDraftEvidence(mutationID: rebase.mutationID)?.receipt, receipt)
        let original = try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(
            mutationID: rebase.mutationID))
        XCTAssertEqual(original.original.mutation, rebase)
        XCTAssertEqual(original.original.receipt, receipt)
        XCTAssertEqual(original.resolution, resolution)
        XCTAssertEqual(try preparedAttempt(in: classified), attempt)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPreviouslyReviewedOriginRetainsRepeatedPreparedEpochsAcrossReopen() async throws {
        let fixture = try await makeFixture("prepared-reviewed-repeated")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let original = try seedReviewedResolution(in: fixture.coordinator, existingTarget: false)
        var originals = [original]
        let draftID = original.resolution.successorCheckpoint.draftID

        for _ in 0..<2 {
            let editing = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
            let editingPayload = try MyDayPlanningDraftCodecV1.decode(editing.payloadData)
            let context = try XCTUnwrap(editingPayload.confirmedContext)
            let intent = try XCTUnwrap(editingPayload.editingIntent)
            var injected = false
            access.setPlanningEffectHookForTesting { point in
                guard point == .contentPromotedSaga, !injected else { return }
                injected = true
                throw V23MyDayCommitTestInterruption.injected
            }
            do {
                _ = try await access.retryPlanSave(draftID: draftID)
                XCTFail("Expected actual production interruption")
            } catch {
                XCTAssertTrue(error is V23MyDayCommitTestInterruption)
            }
            XCTAssertTrue(injected)
            access.setPlanningEffectHookForTesting(nil)

            let committing = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
            let attempt = try preparedAttempt(in: committing)
            let classified = try V23ProductionReviewedResolutionHistoryFixtureV1.next(committing, state: .conflicted)
            let classification = try FieldDraftMutationV1(workspaceID: committing.workspaceID,
                expectedRevision: committing.draftRevision,
                expectedBaseCanonicalRevision: committing.baseCanonicalRevision,
                mutationID: classified.mutationID, postImage: .reviseCheckpoint(classified))
            _ = try writer.commitFieldDraft(classification)

            let successorPayload = try MyDayPlanningDraftPayloadV1(editing: context, intent: intent)
            let successor = try FieldDraftCheckpointV1(draftID: draftID,
                workspaceID: classified.workspaceID, scope: classified.scope, purpose: classified.purpose,
                codec: classified.codec, baseCanonicalRevision: classified.baseCanonicalRevision,
                draftRevision: classified.draftRevision + 1,
                payloadData: MyDayPlanningDraftCodecV1.encode(successorPayload),
                stageIDs: classified.stageIDs, resumeAnchor: classified.resumeAnchor, state: .active,
                updatedAt: classified.updatedAt, mutationID: writer.makeMutationID())
            let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
                expectedCheckpoint: classified,
                reviewedTargetBasis: .absent(key: context.key,
                    expectedWorkspaceRevision: writer.currentRevision().revision),
                successorCheckpoint: successor)
            let rebase = try FieldDraftMutationV1(workspaceID: classified.workspaceID,
                expectedRevision: classified.draftRevision,
                expectedBaseCanonicalRevision: classified.baseCanonicalRevision,
                mutationID: successor.mutationID, postImage: .resolveConflict(resolution))
            _ = try writer.commitFieldDraft(rebase)
            let evidence = try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(
                mutationID: rebase.mutationID))
            XCTAssertEqual(evidence.resolution, resolution)
            XCTAssertEqual(try preparedAttempt(in: classified), attempt)
            originals.append(evidence)
        }

        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<DraftCommitSagaRow>()), 4)
        for evidence in originals {
            XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: evidence.original.mutation.mutationID), evidence)
        }
        let revision = try writer.currentRevision()
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(
            testCase: self, support: fixture.support, defaults: fixture.defaults)
        let coldWriter = try XCTUnwrap(reopened).coordinator.workspaceWriter
        XCTAssertNotEqual(try coldWriter.currentRevision().writerInstanceID, revision.writerInstanceID)
        for evidence in originals {
            XCTAssertEqual(try coldWriter.reviewedFieldDraftResolutionEvidence(
                mutationID: evidence.original.mutation.mutationID), evidence)
        }
        XCTAssertEqual(try coldWriter.currentRevision().revision, revision.revision)
        XCTAssertFalse(try XCTUnwrap(reopened).coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testRecordedTargetPreparedEpochRebasesThenOrdinaryEditSavesAndReopens() async throws {
        let fixture = try await makeFixture("prepared-target-save")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        var injected = false
        access.setPlanningEffectHookForTesting { point in
            guard point == .targetCommittedSaga, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        let draftID = try await interruptedDraftID(from: access, request: request)
        XCTAssertTrue(injected)
        access.setPlanningEffectHookForTesting(nil)
        let committing = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
        let attempt = try preparedAttempt(in: committing)
        guard case let .save(recordedTarget, _) = attempt.command else {
            return XCTFail("The production plan request must reconstruct a save target")
        }
        XCTAssertEqual(try writer.currentPlan(for: request.confirmedContext.key), recordedTarget)
        let priorSagas = try fixture.coordinator.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>())
            .map { try $0.value() }
            .filter { $0.draftID == draftID }
            .sorted { $0.revision < $1.revision }
        XCTAssertEqual(priorSagas.map(\.state), [.prepared, .contentPromotedUnbound, .targetCommitted])
        let classified = try V23ProductionReviewedResolutionHistoryFixtureV1.next(committing, state: .conflicted)
        _ = try writer.commitFieldDraft(FieldDraftMutationV1(workspaceID: committing.workspaceID,
            expectedRevision: committing.draftRevision,
            expectedBaseCanonicalRevision: committing.baseCanonicalRevision,
            mutationID: classified.mutationID, postImage: .reviseCheckpoint(classified)))
        let payload = try MyDayPlanningDraftPayloadV1(editing: request.confirmedContext,
            intent: .plan(draft: request.draft, predecessor: recordedTarget))
        let successor = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: classified.workspaceID,
            scope: classified.scope, purpose: classified.purpose, codec: classified.codec,
            baseCanonicalRevision: recordedTarget.revision, draftRevision: classified.draftRevision + 1,
            payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: classified.stageIDs,
            resumeAnchor: classified.resumeAnchor, state: .active, updatedAt: classified.updatedAt,
            mutationID: writer.makeMutationID())
        let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
            expectedCheckpoint: classified, reviewedTargetBasis: .existing(
                identity: try .init(kind: .myDayPlan, id: recordedTarget.planID), key: recordedTarget.key,
                revision: recordedTarget.revision, canonicalSHA256: recordedTarget.planSHA256),
            successorCheckpoint: successor)
        let rebase = try FieldDraftMutationV1(workspaceID: classified.workspaceID,
            expectedRevision: classified.draftRevision,
            expectedBaseCanonicalRevision: classified.baseCanonicalRevision,
            mutationID: successor.mutationID, postImage: .resolveConflict(resolution))
        _ = try writer.commitFieldDraft(rebase)
        let original = try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutationID))
        XCTAssertEqual(try writer.currentPlan(for: request.confirmedContext.key), recordedTarget)
        let laterRequest = try MyDayPlanningPlanSaveRequestV1(confirmedContext: request.confirmedContext,
            draft: request.draft, predecessor: recordedTarget)
        let edit = try access.prepareEditingWrite(laterRequest, replacing: successor,
            resumeAnchor: try DraftResumeAnchorV1())
        let edited = try access.persistEditingWrite(edit).checkpoint
        let outcome = try await access.retryPlanSave(draftID: edited.draftID)
        XCTAssertEqual(outcome.checkpoint.state, .committed)
        let finalAttempt = try preparedAttempt(in: outcome.checkpoint)
        guard case let .save(finalTarget, finalPredecessor) = finalAttempt.command else {
            return XCTFail("The retained successor must finish with a save command")
        }
        XCTAssertEqual(finalPredecessor, recordedTarget)
        XCTAssertEqual(outcome.targetResult.plan, finalTarget)
        XCTAssertEqual(outcome.targetReceipt.mutationID, finalAttempt.command.mutationID)
        XCTAssertEqual(outcome.draftReceipt.targetMutationID, finalAttempt.command.mutationID)
        XCTAssertEqual(outcome.draftReceipt.targetReceiptSHA256, outcome.targetReceipt.resultSHA256)
        XCTAssertEqual(outcome.terminalReceipt.mutationID, finalAttempt.terminalBundleMutationID)
        XCTAssertEqual(try writer.durableReceipt(mutationID: finalAttempt.command.mutationID), outcome.targetReceipt)
        let allSagas = try fixture.coordinator.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>())
            .map { try $0.value() }
            .filter { $0.draftID == draftID }
        let finalSagaMutationIDs = Set(finalAttempt.sagaMutationIDs + [finalAttempt.terminalBundleMutationID])
        let finalSagas = allSagas.filter { finalSagaMutationIDs.contains($0.mutationID) }
            .sorted { $0.revision < $1.revision }
        XCTAssertEqual(finalSagas.map(\.state), [.prepared, .contentPromotedUnbound,
            .targetCommitted, .draftRetirePending, .draftRetired])
        XCTAssertEqual(finalSagas.map(\.sagaID), [finalAttempt.preparedSagaID,
            finalAttempt.contentPromotedSagaID, finalAttempt.targetCommittedSagaID,
            finalAttempt.draftRetirePendingSagaID, finalAttempt.draftRetiredSagaID])
        XCTAssertEqual(finalSagas.map(\.mutationID), finalAttempt.sagaMutationIDs + [finalAttempt.terminalBundleMutationID])
        XCTAssertEqual(finalSagas.map(\.updatedAt), finalAttempt.sagaUpdatedAts)
        XCTAssertEqual(outcome.draftReceipt.sagaEventSHA256Chain, finalSagas.map(\.sagaSHA256))
        XCTAssertEqual(allSagas.count, 8)
        XCTAssertEqual(Set(allSagas.map(\.sagaID)).count, 8)
        XCTAssertEqual(Set(allSagas.map(\.sagaID)), Set(priorSagas.map(\.sagaID) + finalSagas.map(\.sagaID)))
        XCTAssertEqual(allSagas.filter { priorSagas.map(\.sagaID).contains($0.sagaID) }
            .sorted { $0.revision < $1.revision }, priorSagas)
        XCTAssertEqual(outcome.targetResult.plan.revision, recordedTarget.revision + 1)
        XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutationID), original)
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        let revision = try writer.currentRevision()
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(
            testCase: self, support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened).coordinator
        XCTAssertEqual(try cold.workspaceWriter.reviewedFieldDraftResolutionEvidence(
            mutationID: rebase.mutationID), original)
        XCTAssertEqual(try cold.workspaceWriter.currentPlan(for: request.confirmedContext.key), outcome.targetResult.plan)
        XCTAssertEqual(try cold.workspaceWriter.currentRevision().revision, revision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.modelContext), rows)
        XCTAssertFalse(cold.modelContext.hasChanges)
    }

    @MainActor
    func testPreparedRebaseThenOrdinaryEditDiscardsAndRetainsOriginalAcrossReopen() async throws {
        let fixture = try await makeFixture("prepared-discard")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        var injected = false
        access.setPlanningEffectHookForTesting { point in
            guard point == .contentPromotedSaga, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        let draftID = try await interruptedDraftID(from: access, request: request)
        XCTAssertTrue(injected)
        access.setPlanningEffectHookForTesting(nil)
        let committing = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
        let classified = try V23ProductionReviewedResolutionHistoryFixtureV1.next(committing, state: .conflicted)
        _ = try writer.commitFieldDraft(FieldDraftMutationV1(workspaceID: committing.workspaceID,
            expectedRevision: committing.draftRevision,
            expectedBaseCanonicalRevision: committing.baseCanonicalRevision,
            mutationID: classified.mutationID, postImage: .reviseCheckpoint(classified)))
        let payload = try MyDayPlanningDraftPayloadV1(editing: request.confirmedContext,
            intent: .plan(draft: request.draft, predecessor: nil))
        let successor = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: classified.workspaceID,
            scope: classified.scope, purpose: classified.purpose, codec: classified.codec,
            baseCanonicalRevision: classified.baseCanonicalRevision,
            draftRevision: classified.draftRevision + 1,
            payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: classified.stageIDs,
            resumeAnchor: classified.resumeAnchor, state: .active, updatedAt: classified.updatedAt,
            mutationID: writer.makeMutationID())
        let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
            expectedCheckpoint: classified, reviewedTargetBasis: .absent(key: request.confirmedContext.key,
                expectedWorkspaceRevision: writer.currentRevision().revision), successorCheckpoint: successor)
        let rebase = try FieldDraftMutationV1(workspaceID: classified.workspaceID,
            expectedRevision: classified.draftRevision,
            expectedBaseCanonicalRevision: classified.baseCanonicalRevision,
            mutationID: successor.mutationID, postImage: .resolveConflict(resolution))
        _ = try writer.commitFieldDraft(rebase)
        let original = try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutationID))
        let edit = try access.prepareEditingWrite(request, replacing: successor,
            resumeAnchor: try DraftResumeAnchorV1())
        let edited = try access.persistEditingWrite(edit).checkpoint
        let discard = try access.preparePlanningDiscard(expectedCheckpoint: edited)
        let outcome = try await access.discardPlanningDraft(discard)
        XCTAssertEqual(outcome.checkpoint.state, .discarded)
        XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutationID), original)
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        let revision = try writer.currentRevision()
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(
            testCase: self, support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened).coordinator
        XCTAssertEqual(try cold.workspaceWriter.reviewedFieldDraftResolutionEvidence(
            mutationID: rebase.mutationID), original)
        XCTAssertEqual(try cold.workspaceWriter.currentRevision().revision, revision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.modelContext), rows)
        XCTAssertFalse(cold.modelContext.hasChanges)
    }

    @MainActor
    func testTargetWrittenBeforeTargetCommittedSagaRejectsPreparedRebaseWithoutWrites() async throws {
        let fixture = try await makeFixture("prepared-target-before-marker")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        var injected = false
        access.setPlanningEffectHookForTesting { point in
            guard point == .targetCommit, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        let draftID = try await interruptedDraftID(from: access, request: request)
        XCTAssertTrue(injected)
        access.setPlanningEffectHookForTesting(nil)
        let committing = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
        let attempt = try preparedAttempt(in: committing)
        guard case let .save(target, _) = attempt.command else {
            return XCTFail("The production plan request must reconstruct a save target")
        }
        XCTAssertEqual(try writer.currentPlan(for: request.confirmedContext.key), target)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<DraftCommitSagaRow>()), 2)
        let classified = try V23ProductionReviewedResolutionHistoryFixtureV1.next(committing, state: .conflicted)
        _ = try writer.commitFieldDraft(FieldDraftMutationV1(workspaceID: committing.workspaceID,
            expectedRevision: committing.draftRevision,
            expectedBaseCanonicalRevision: committing.baseCanonicalRevision,
            mutationID: classified.mutationID, postImage: .reviseCheckpoint(classified)))
        let payload = try MyDayPlanningDraftPayloadV1(editing: request.confirmedContext,
            intent: .plan(draft: request.draft, predecessor: target))
        let successor = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: classified.workspaceID,
            scope: classified.scope, purpose: classified.purpose, codec: classified.codec,
            baseCanonicalRevision: target.revision, draftRevision: classified.draftRevision + 1,
            payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: classified.stageIDs,
            resumeAnchor: classified.resumeAnchor, state: .active, updatedAt: classified.updatedAt,
            mutationID: writer.makeMutationID())
        let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
            expectedCheckpoint: classified, reviewedTargetBasis: .existing(
                identity: try .init(kind: .myDayPlan, id: target.planID), key: target.key,
                revision: target.revision, canonicalSHA256: target.planSHA256), successorCheckpoint: successor)
        let rebase = try FieldDraftMutationV1(workspaceID: classified.workspaceID,
            expectedRevision: classified.draftRevision,
            expectedBaseCanonicalRevision: classified.baseCanonicalRevision,
            mutationID: successor.mutationID, postImage: .resolveConflict(resolution))
        let revision = try writer.currentRevision()
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try writer.commitFieldDraft(rebase))
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext), classified)
        XCTAssertEqual(try writer.currentPlan(for: request.confirmedContext.key), target)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPreparedPrefixClassificationAndPhysicalPartitionCorruptionDenyRebaseWithoutWrites() async throws {
        for corruption in 0..<2 {
            let fixture = try await makeFixture("prepared-corruption-\(corruption)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let coordinator = fixture.coordinator
            let writer = coordinator.workspaceWriter
            let context = coordinator.modelContext
            let request = try makeRequest(workspaceID: coordinator.workspaceID)
            var injected = false
            access.setPlanningEffectHookForTesting { point in
                guard point == .contentPromotedSaga, !injected else { return }
                injected = true
                throw V23MyDayCommitTestInterruption.injected
            }
            let draftID = try await interruptedDraftID(from: access, request: request)
            XCTAssertTrue(injected)
            access.setPlanningEffectHookForTesting(nil)
            let committing = try checkpoint(draftID: draftID, in: context)
            let classified = try V23ProductionReviewedResolutionHistoryFixtureV1.next(committing, state: .conflicted)
            _ = try writer.commitFieldDraft(FieldDraftMutationV1(workspaceID: committing.workspaceID,
                expectedRevision: committing.draftRevision,
                expectedBaseCanonicalRevision: committing.baseCanonicalRevision,
                mutationID: classified.mutationID, postImage: .reviseCheckpoint(classified)))

            switch corruption {
            case 0:
                let receipt = try XCTUnwrap(context.fetch(FetchDescriptor<MutationReceiptRow>())
                    .first { $0.mutationID == classified.mutationID.rawValue })
                context.delete(receipt)
            default:
                let first = try XCTUnwrap(context.fetch(FetchDescriptor<DraftCommitSagaRow>()).first).value()
                context.insert(try DraftCommitSagaRow(DraftCommitSagaV1(sagaID: UUID(),
                    workspaceID: first.workspaceID, draftID: first.draftID, plan: first.plan,
                    state: .prepared, revision: 1, mutationID: .init(rawValue: UUID()),
                    updatedAt: first.updatedAt)))
            }
            try context.save()

            let payload = try MyDayPlanningDraftPayloadV1(editing: request.confirmedContext,
                intent: .plan(draft: request.draft, predecessor: nil))
            let successor = try FieldDraftCheckpointV1(draftID: draftID,
                workspaceID: classified.workspaceID, scope: classified.scope, purpose: classified.purpose,
                codec: classified.codec, baseCanonicalRevision: classified.baseCanonicalRevision,
                draftRevision: classified.draftRevision + 1,
                payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: classified.stageIDs,
                resumeAnchor: classified.resumeAnchor, state: .active, updatedAt: classified.updatedAt,
                mutationID: writer.makeMutationID())
            let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
                expectedCheckpoint: classified, reviewedTargetBasis: .absent(key: request.confirmedContext.key,
                    expectedWorkspaceRevision: writer.currentRevision().revision), successorCheckpoint: successor)
            let rebase = try FieldDraftMutationV1(workspaceID: classified.workspaceID,
                expectedRevision: classified.draftRevision,
                expectedBaseCanonicalRevision: classified.baseCanonicalRevision,
                mutationID: successor.mutationID, postImage: .resolveConflict(resolution))
            let revision = try writer.currentRevision()
            let rows = try reviewedSaveRowCounts(in: context)
            let targetCount = try context.fetchCount(FetchDescriptor<MyDayPlanRowV1>())
            XCTAssertThrowsError(try writer.commitFieldDraft(rebase))
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try checkpoint(draftID: draftID, in: context), classified)
            XCTAssertEqual(try reviewedSaveRowCounts(in: context), rows)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), targetCount)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testPendingReviewedConflictReadAuthenticatesEveryActualPreparedPrefixWithoutWrites() async throws {
        let prefixes: [(MyDayPlanningEffectPointV1, Int)] = [
            (.committingCheckpoint, 0),
            (.preparedSaga, 1),
            (.contentPromotedSaga, 2),
            (.targetCommittedSaga, 3),
            (.retirePendingSaga, 4)
        ]
        for (point, expectedPrefixCount) in prefixes {
            let fixture = try await makeFixture("pending-read-prefix-\(point.rawValue)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
            let state = try await classifyActualPendingConflict(
                access: access,
                coordinator: fixture.coordinator,
                request: request,
                interruption: point
            )
            let writer = fixture.coordinator.workspaceWriter
            let revision = try writer.currentRevision()
            let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)

            let pending = try writer.pendingReviewedMyDayConflictEvidence(draftID: state.draftID)

            XCTAssertEqual(pending.conflict, state.conflict)
            XCTAssertEqual(pending.conflictedCheckpoint, state.conflicted)
            XCTAssertEqual(pending.editing, state.editing)
            XCTAssertEqual(pending.editingCheckpoint, state.editingCheckpoint)
            let epoch = try XCTUnwrap(pending.preparedEpoch)
            XCTAssertEqual(epoch.committing, state.committing)
            XCTAssertEqual(epoch.committingCheckpoint, state.committingCheckpoint)
            XCTAssertEqual(epoch.sagaPrefix, state.sagaPrefix)
            XCTAssertEqual(epoch.sagaPrefix.count, expectedPrefixCount)
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testPendingReviewedConflictReadUsesLatestRepeatedEditingEpochAcrossHotAndColdAuthority() async throws {
        let fixture = try await makeFixture("pending-read-repeated")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let first = try await classifyActualPendingConflict(
            access: access,
            coordinator: fixture.coordinator,
            request: makeRequest(workspaceID: fixture.coordinator.workspaceID),
            interruption: .contentPromotedSaga
        )
        let draftID = first.draftID
        let firstClassified = first.conflicted
        let firstPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(
            first.editingCheckpoint
        )
        let firstContext = try XCTUnwrap(firstPayload.confirmedContext)
        let firstIntent = try XCTUnwrap(firstPayload.editingIntent)
        let successor = try FieldDraftCheckpointV1(
            draftID: draftID, workspaceID: firstClassified.workspaceID, scope: firstClassified.scope,
            purpose: firstClassified.purpose, codec: firstClassified.codec,
            baseCanonicalRevision: firstClassified.baseCanonicalRevision,
            draftRevision: firstClassified.draftRevision + 1,
            payloadData: MyDayPlanningDraftCodecV1.encode(.init(editing: firstContext, intent: firstIntent)),
            stageIDs: firstClassified.stageIDs, resumeAnchor: firstClassified.resumeAnchor,
            state: .active, updatedAt: firstClassified.updatedAt, mutationID: writer.makeMutationID()
        )
        let resolution = try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase, expectedCheckpoint: firstClassified,
            reviewedTargetBasis: .absent(key: firstContext.key,
                expectedWorkspaceRevision: writer.currentRevision().revision), successorCheckpoint: successor
        )
        _ = try writer.commitFieldDraft(FieldDraftMutationV1(
            workspaceID: firstClassified.workspaceID, expectedRevision: firstClassified.draftRevision,
            expectedBaseCanonicalRevision: firstClassified.baseCanonicalRevision,
            mutationID: successor.mutationID, postImage: .resolveConflict(resolution)
        ))

        let latest = try await classifyActualPendingConflict(
            access: access,
            coordinator: fixture.coordinator,
            request: makeRequest(workspaceID: fixture.coordinator.workspaceID),
            interruption: .retirePendingSaga,
            existingDraftID: draftID
        )
        XCTAssertEqual(latest.draftID, draftID)
        let revision = try writer.currentRevision()
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        let hot = try writer.pendingReviewedMyDayConflictEvidence(draftID: draftID)
        XCTAssertEqual(hot.conflict, latest.conflict)
        XCTAssertEqual(hot.conflictedCheckpoint, latest.conflicted)
        XCTAssertEqual(hot.editing, latest.editing)
        XCTAssertEqual(hot.editingCheckpoint, latest.editingCheckpoint)
        XCTAssertEqual(try XCTUnwrap(hot.preparedEpoch).committing, latest.committing)
        XCTAssertEqual(try XCTUnwrap(hot.preparedEpoch).sagaPrefix, latest.sagaPrefix)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)

        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(
            testCase: self, support: fixture.support, defaults: fixture.defaults
        )
        let cold = try XCTUnwrap(reopened).coordinator
        let coldWriter = cold.workspaceWriter
        XCTAssertNotEqual(try coldWriter.currentRevision().writerInstanceID, revision.writerInstanceID)
        XCTAssertEqual(try coldWriter.pendingReviewedMyDayConflictEvidence(draftID: draftID), hot)
        XCTAssertEqual(try coldWriter.currentRevision().revision, revision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.modelContext), rows)
        XCTAssertFalse(cold.modelContext.hasChanges)
    }

    @MainActor
    func testPendingReviewedConflictReadRejectsActualTargetWithoutCommittedSagaMarkerWithoutWrites() async throws {
        let fixture = try await makeFixture("pending-read-unmarked-target")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let state = try await classifyActualPendingConflict(
            access: access,
            coordinator: fixture.coordinator,
            request: request,
            interruption: .targetCommit
        )
        let writer = fixture.coordinator.workspaceWriter
        let attempt = try preparedAttempt(in: state.committingCheckpoint)
        guard case let .save(target, _) = attempt.command else {
            return XCTFail("The actual target-commit interruption must have written a save target")
        }
        XCTAssertEqual(try writer.currentPlan(for: request.confirmedContext.key), target)
        XCTAssertEqual(state.sagaPrefix.count, 2)
        let revision = try writer.currentRevision()
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)

        XCTAssertThrowsError(try writer.pendingReviewedMyDayConflictEvidence(draftID: state.draftID))

        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try writer.currentPlan(for: request.confirmedContext.key), target)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    private func classifyActualPendingConflict(
        access: AppAccessPresentationV1.MyDayAccess,
        coordinator: StoreSessionCoordinator,
        request: MyDayPlanningPlanSaveRequestV1,
        interruption: MyDayPlanningEffectPointV1,
        existingDraftID: UUID? = nil
    ) async throws -> (
        draftID: UUID,
        conflict: FieldDraftCommittedEvidenceV1,
        conflicted: FieldDraftCheckpointV1,
        editing: FieldDraftCommittedEvidenceV1,
        editingCheckpoint: FieldDraftCheckpointV1,
        committing: FieldDraftCommittedEvidenceV1,
        committingCheckpoint: FieldDraftCheckpointV1,
        sagaPrefix: [FieldDraftCommittedEvidenceV1]
    ) {
        var injected = false
        access.setPlanningEffectHookForTesting { point in
            guard point == interruption, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        let draftID: UUID
        do {
            if let existingDraftID {
                do {
                    _ = try await access.retryPlanSave(draftID: existingDraftID)
                    throw V23MyDayCommitTestFailure.missingInterruption
                } catch is V23MyDayCommitTestInterruption {
                    draftID = existingDraftID
                }
            } else {
                draftID = try await interruptedDraftID(from: access, request: request)
            }
        } catch {
            access.setPlanningEffectHookForTesting(nil)
            throw error
        }
        XCTAssertTrue(injected, "The requested actual durable effect hook was not reached")
        access.setPlanningEffectHookForTesting(nil)
        let writer = coordinator.workspaceWriter
        let committingCheckpoint = try checkpoint(draftID: draftID, in: coordinator.modelContext)
        let fieldDraftRows = try coordinator.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
            .filter { row in
                guard case .applyFieldDraft = try MutationEnvelopeV1.decodeCanonical(
                    from: row.envelopeData
                ).command else {
                    return false
                }
                return true
            }
        let draftHistory = try fieldDraftRows.compactMap { row -> FieldDraftCommittedEvidenceV1? in
            try writer.fieldDraftEvidence(mutationID: .init(rawValue: row.mutationID))
        }
            .filter { evidence in
                switch evidence.mutation.postImage {
                case let .createCheckpoint(checkpoint), let .reviseCheckpoint(checkpoint):
                    return checkpoint.draftID == draftID
                case let .resolveConflict(resolution):
                    return resolution.successorCheckpoint.draftID == draftID
                default:
                    return false
                }
            }
            .sorted { $0.receipt.resultingRevision.workspaceRevision
                < $1.receipt.resultingRevision.workspaceRevision }
        let editing = try XCTUnwrap(draftHistory.last { evidence in
            switch evidence.mutation.postImage {
            case let .createCheckpoint(checkpoint), let .reviseCheckpoint(checkpoint):
                return checkpoint.state == .active
            case let .resolveConflict(resolution):
                return resolution.successorCheckpoint.state == .active
            default:
                return false
            }
        })
        let editingCheckpoint: FieldDraftCheckpointV1
        switch editing.mutation.postImage {
        case let .createCheckpoint(checkpoint), let .reviseCheckpoint(checkpoint):
            editingCheckpoint = checkpoint
        case let .resolveConflict(resolution):
            editingCheckpoint = resolution.successorCheckpoint
        default:
            XCTFail("The actual editing evidence must carry its exact active checkpoint")
            throw V23MyDayCommitTestInterruption.injected
        }
        let committing = try XCTUnwrap(try writer.fieldDraftEvidence(
            mutationID: committingCheckpoint.mutationID
        ))
        let classified = try V23ProductionReviewedResolutionHistoryFixtureV1.next(
            committingCheckpoint, state: .conflicted
        )
        let receipt = try writer.commitFieldDraft(FieldDraftMutationV1(
            workspaceID: committingCheckpoint.workspaceID,
            expectedRevision: committingCheckpoint.draftRevision,
            expectedBaseCanonicalRevision: committingCheckpoint.baseCanonicalRevision,
            mutationID: classified.mutationID,
            postImage: .reviseCheckpoint(classified)
        ))
        let conflict = try XCTUnwrap(try writer.fieldDraftEvidence(mutationID: classified.mutationID))
        XCTAssertEqual(conflict.receipt, receipt)
        let currentAttempt = try preparedAttempt(in: committingCheckpoint)
        let currentSagaMutationIDs = Set(currentAttempt.sagaMutationIDs)
        let sagaPrefix = try coordinator.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>())
            .map { try $0.value() }
            .filter { $0.draftID == draftID && currentSagaMutationIDs.contains($0.mutationID) }
            .sorted { $0.revision < $1.revision }
            .compactMap { try writer.fieldDraftEvidence(mutationID: $0.mutationID) }
        return (draftID, conflict, classified, editing, editingCheckpoint, committing,
                committingCheckpoint, sagaPrefix)
    }

    @MainActor
    func testPlanningConflictReviewCapturesOrdinaryOriginalAndAbsentTargetWithoutWrites() async throws {
        let fixture = try await makeFixture("review-ordinary-capture")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: try fixture.coordinator.workspaceID)
        let conflict = try classifyOrdinaryPlanningConflict(access: access, coordinator: fixture.coordinator,
                                                            request: request)
        let writer = fixture.coordinator.workspaceWriter
        let revision = try writer.currentRevision()
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        let review = try access.planningConflictReview(draftID: conflict.draftID)
        XCTAssertEqual(review.pending.conflictedCheckpoint, conflict.checkpoint)
        XCTAssertEqual(review.originalEditingRequest, request)
        XCTAssertEqual(review.reviewRequest.confirmedContext, request.confirmedContext)
        XCTAssertEqual(review.reviewRequest.draft, request.draft)
        XCTAssertNil(review.reviewRequest.predecessor)
        XCTAssertEqual(review.capturedTargetBasis, .absent(key: request.confirmedContext.key,
            expectedWorkspaceRevision: revision.revision))
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningConflictReviewAbsentRebaseExecutesReplaysAndColdReopens() async throws {
        let fixture = try await makeFixture("review-ordinary-rebase")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer { try? reopened?.coordinator.invalidateAndReleaseWriter(); fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let conflict = try classifyOrdinaryPlanningConflict(access: access, coordinator: fixture.coordinator,
                                                            request: request)
        let review = try access.planningConflictReview(draftID: conflict.draftID)
        let beforePrepareRevision = try fixture.coordinator.workspaceWriter.currentRevision()
        let beforePrepareRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        let write = try access.prepareReviewedPlanRebase(review, editedDraft: request.draft)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforePrepareRevision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforePrepareRows)
        XCTAssertEqual(write.review, review)
        XCTAssertEqual(write.resolution.reviewedTargetBasis, review.capturedTargetBasis)
        XCTAssertEqual(write.resolution.successorCheckpoint.payloadData,
                       try MyDayPlanningDraftCodecV1.encode(.init(editing: request.confirmedContext,
                                                               intent: review.reviewRequest.editingIntent)))
        fixture.presentation.receive(.sceneInactive)
        XCTAssertThrowsError(try access.prepareReviewedPlanRebase(review, editedDraft: request.draft)) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertThrowsError(try access.executeReviewedPlanRebase(write)) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        fixture.presentation.receive(.sceneActive)
        let fresh = try XCTUnwrap(fixture.presentation.myDayAccess)
        let acknowledgement = try fresh.executeReviewedPlanRebase(write)
        XCTAssertEqual(acknowledgement.checkpoint, write.resolution.successorCheckpoint)
        let beforeReplayRevision = try fixture.coordinator.workspaceWriter.currentRevision()
        let beforeReplayRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertEqual(try fresh.retryReviewedPlanRebase(write), acknowledgement)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeReplayRevision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforeReplayRows)
        let revision = beforeReplayRevision
        let rows = beforeReplayRows
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(testCase: self,
            support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened).coordinator
        let coldAccess = try XCTUnwrap(reopened?.presentation.myDayAccess)
        XCTAssertEqual(try coldAccess.retryReviewedPlanRebase(write), acknowledgement)
        XCTAssertEqual(try cold.workspaceWriter.currentRevision().revision, revision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.modelContext), rows)
    }

    @MainActor
    func testPlanningConflictReviewPreparedPrefixesCaptureOriginalAndRebaseToProductionSave() async throws {
        for point in [MyDayPlanningEffectPointV1.committingCheckpoint, .targetCommittedSaga] {
            let fixture = try await makeFixture("review-prepared-\(point.rawValue)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
            let state = try await classifyActualPendingConflict(access: access, coordinator: fixture.coordinator,
                request: request, interruption: point)
            let review = try access.planningConflictReview(draftID: state.draftID)
            XCTAssertEqual(review.pending, try fixture.coordinator.workspaceWriter
                .pendingReviewedMyDayConflictEvidence(draftID: state.draftID))
            XCTAssertEqual(review.originalEditingRequest.confirmedContext, request.confirmedContext)
            XCTAssertEqual(review.originalEditingRequest.draft, request.draft)
            XCTAssertEqual(review.reviewRequest.confirmedContext, request.confirmedContext)
            if point == .committingCheckpoint { XCTAssertNil(review.reviewRequest.predecessor) }
            else { XCTAssertNotNil(review.reviewRequest.predecessor) }
            let beforePrepareRevision = try fixture.coordinator.workspaceWriter.currentRevision()
            let beforePrepareRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            let write = try access.prepareReviewedPlanRebase(review, editedDraft: request.draft)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforePrepareRevision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforePrepareRows)
            let acknowledgement = try access.executeReviewedPlanRebase(write)
            let originalPrefixMutationIDs = state.sagaPrefix.map(\.mutation.mutationID)
            let original = try XCTUnwrap(fixture.coordinator.workspaceWriter
                .reviewedFieldDraftResolutionEvidence(mutationID: write.mutation.mutationID))
            XCTAssertEqual(original.resolution, write.resolution)
            let outcome = try await access.retryPlanSave(draftID: state.draftID)
            let finalAttempt = try preparedAttempt(in: outcome.checkpoint)
            let allSagas = try fixture.coordinator.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>())
                .map { try $0.value() }.filter { $0.draftID == state.draftID }
            let finalIDs = Set(finalAttempt.sagaMutationIDs + [finalAttempt.terminalBundleMutationID])
            let finalSagas = allSagas.filter { finalIDs.contains($0.mutationID) }
                .sorted { $0.revision < $1.revision }
            XCTAssertEqual(allSagas.filter { originalPrefixMutationIDs.contains($0.mutationID) }
                .sorted { $0.revision < $1.revision }.map(\.mutationID), originalPrefixMutationIDs)
            XCTAssertEqual(finalSagas.map(\.state), [.prepared, .contentPromotedUnbound,
                .targetCommitted, .draftRetirePending, .draftRetired])
            XCTAssertEqual(finalSagas.map(\.mutationID), finalAttempt.sagaMutationIDs + [finalAttempt.terminalBundleMutationID])
            XCTAssertEqual(finalSagas.map(\.sagaSHA256), outcome.draftReceipt.sagaEventSHA256Chain)
            XCTAssertEqual(outcome.draftReceipt.sagaEventSHA256Chain.count, 5)
            XCTAssertEqual(acknowledgement.checkpoint, write.resolution.successorCheckpoint)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.reviewedFieldDraftResolutionEvidence(
                mutationID: write.mutation.mutationID), original)
            XCTAssertEqual(outcome.checkpoint.state, .committed)
            XCTAssertEqual(outcome.targetReceipt.mutationID, finalAttempt.command.mutationID)
            XCTAssertEqual(outcome.draftReceipt.targetMutationID, finalAttempt.command.mutationID)
            guard case let .save(_, predecessor) = finalAttempt.command else {
                return XCTFail("The rebase successor must finish through the production save command")
            }
            XCTAssertEqual(predecessor, review.reviewRequest.predecessor)
        }
    }

    @MainActor
    func testPlanningConflictReviewRejectsChangedTargetAndChangedPhysicalTipWithoutWrites() async throws {
        let fixture = try await makeFixture("review-stale-target")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let conflict = try classifyOrdinaryPlanningConflict(access: access, coordinator: fixture.coordinator,
                                                            request: request)
        let review = try access.planningConflictReview(draftID: conflict.draftID)
        let write = try access.prepareReviewedPlanRebase(review, editedDraft: request.draft)
        let wrongKey = try MyDayKeyV1(workspaceID: fixture.coordinator.workspaceID,
            civilDate: .init("2026-09-13"), ianaTimeZoneIdentifier: "America/New_York")
        let wrongDraft = try makeRequest(workspaceID: fixture.coordinator.workspaceID, key: wrongKey).draft
        let beforeWrongKeyRevision = try fixture.coordinator.workspaceWriter.currentRevision()
        let beforeWrongKeyRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try access.prepareReviewedPlanRebase(review, editedDraft: wrongDraft))
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeWrongKeyRevision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforeWrongKeyRows)
        _ = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID,
                                                   key: request.confirmedContext.key))
        let writer = fixture.coordinator.workspaceWriter
        let afterTargetRevision = try writer.currentRevision()
        let afterTargetRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try access.prepareReviewedPlanRebase(review, editedDraft: request.draft))
        XCTAssertThrowsError(try access.executeReviewedPlanRebase(write))
        XCTAssertEqual(try writer.currentRevision(), afterTargetRevision)
        XCTAssertEqual(try checkpoint(draftID: conflict.draftID, in: fixture.coordinator.modelContext),
                       conflict.checkpoint)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), afterTargetRows)

        let successor = try V23ProductionReviewedResolutionHistoryFixtureV1.next(conflict.checkpoint, state: .active)
        _ = try writer.commitFieldDraft(FieldDraftMutationV1(workspaceID: successor.workspaceID,
            expectedRevision: conflict.checkpoint.draftRevision,
            expectedBaseCanonicalRevision: conflict.checkpoint.baseCanonicalRevision,
            mutationID: successor.mutationID, postImage: .reviseCheckpoint(successor)))
        let afterTipRevision = try writer.currentRevision()
        let afterTipRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try access.prepareReviewedPlanRebase(review, editedDraft: request.draft))
        XCTAssertThrowsError(try access.executeReviewedPlanRebase(write))
        XCTAssertEqual(try writer.currentRevision(), afterTipRevision)
        XCTAssertEqual(try checkpoint(draftID: conflict.draftID, in: fixture.coordinator.modelContext), successor)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), afterTipRows)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    private func classifyOrdinaryPlanningConflict(
        access: AppAccessPresentationV1.MyDayAccess,
        coordinator: StoreSessionCoordinator,
        request: MyDayPlanningPlanSaveRequestV1
    ) throws -> (draftID: UUID, checkpoint: FieldDraftCheckpointV1) {
        let write = try access.prepareEditingWrite(request, replacing: nil,
            resumeAnchor: try DraftResumeAnchorV1())
        let active = try access.persistEditingWrite(write).checkpoint
        let conflict = try V23ProductionReviewedResolutionHistoryFixtureV1.next(active, state: .conflicted)
        _ = try coordinator.workspaceWriter.commitFieldDraft(FieldDraftMutationV1(
            workspaceID: active.workspaceID, expectedRevision: active.draftRevision,
            expectedBaseCanonicalRevision: active.baseCanonicalRevision,
            mutationID: conflict.mutationID, postImage: .reviseCheckpoint(conflict)
        ))
        return (active.draftID, conflict)
    }


    @MainActor
    func testStalePlanPredecessorClassificationAuthenticatesActualActiveAndPrefixesZeroToTwo() async throws {
        for point in [nil, .committingCheckpoint, .preparedSaga, .contentPromotedSaga] as [MyDayPlanningEffectPointV1?] {
            let fixture = try await makeFixture("classify-positive-\(point?.rawValue ?? "active")")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let setup = try await staleClassificationSetup(access: access, coordinator: fixture.coordinator,
                                                            interruption: point)
            let writer = fixture.coordinator.workspaceWriter
            let beforePrepareRevision = try writer.currentRevision()
            let beforePrepareRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            let write = try access.prepareStalePlanPredecessorConflict(draftID: setup.draftID)
            XCTAssertEqual(try writer.currentRevision(), beforePrepareRevision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforePrepareRows)
            XCTAssertEqual(write.evidence.editingCheckpoint, setup.editingCheckpoint)
            let originalPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(write.evidence.editingCheckpoint)
            XCTAssertEqual(originalPayload.confirmedContext, setup.request.confirmedContext)
            XCTAssertEqual(originalPayload.editingIntent, setup.request.editingIntent)
            XCTAssertEqual(write.observedTarget, setup.changedTarget)
            XCTAssertEqual(write.evidence.preparedEpoch?.sagaPrefix.count, point == nil ? nil :
                (point == .committingCheckpoint ? 0 : point == .preparedSaga ? 1 : 2))
            let acknowledgement = try access.executeStalePlanPredecessorConflict(write)
            let beforeReplayRevision = try writer.currentRevision()
            let beforeReplayRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertEqual(try access.retryStalePlanPredecessorConflict(write), acknowledgement)
            XCTAssertEqual(try writer.currentRevision(), beforeReplayRevision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforeReplayRows)
            let review = try access.planningConflictReview(draftID: setup.draftID)
            XCTAssertEqual(review.pending.conflictedCheckpoint, acknowledgement.checkpoint)
            XCTAssertEqual(review.originalEditingRequest.confirmedContext, setup.request.confirmedContext)
            XCTAssertEqual(review.originalEditingRequest.draft, setup.request.draft)
            XCTAssertEqual(review.reviewRequest.predecessor, setup.changedTarget)
            let rebase = try access.prepareReviewedPlanRebase(review, editedDraft: setup.request.draft)
            _ = try access.executeReviewedPlanRebase(rebase)
            let completion = try await access.retryPlanSave(draftID: setup.draftID)
            let finalAttempt = try preparedAttempt(in: completion.checkpoint)
            let rows = try fixture.coordinator.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>())
                .map { try $0.value() }.filter { $0.draftID == setup.draftID }
            let retainedIDs = write.evidence.preparedEpoch?.sagaPrefix.map(\.mutation.mutationID) ?? []
            let finalIDs = finalAttempt.sagaMutationIDs + [finalAttempt.terminalBundleMutationID]
            let finalSagas = rows.filter { Set(finalIDs).contains($0.mutationID) }.sorted { $0.revision < $1.revision }
            let retainedSagas = rows.filter { retainedIDs.contains($0.mutationID) }
                .sorted { $0.revision < $1.revision }
            XCTAssertEqual(retainedSagas.map(\.mutationID), retainedIDs)
            XCTAssertEqual(rows.count, retainedSagas.count + 5)
            XCTAssertEqual(finalSagas.map(\.state), [.prepared, .contentPromotedUnbound, .targetCommitted,
                .draftRetirePending, .draftRetired])
            XCTAssertEqual(finalSagas.map(\.mutationID), finalIDs)
            XCTAssertEqual(finalSagas.map(\.sagaSHA256), completion.draftReceipt.sagaEventSHA256Chain)
            XCTAssertEqual(completion.draftReceipt.sagaEventSHA256Chain.count, 5)
        }
    }

    @MainActor
    func testStalePlanPredecessorClassificationReplaysExactWriteAfterColdAuthorityReopen() async throws {
        let fixture = try await makeFixture("classify-cold-replay")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer { try? reopened?.coordinator.invalidateAndReleaseWriter(); fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let setup = try await staleClassificationSetup(access: access, coordinator: fixture.coordinator,
                                                        interruption: .preparedSaga)
        let write = try access.prepareStalePlanPredecessorConflict(draftID: setup.draftID)
        let acknowledgement = try access.executeStalePlanPredecessorConflict(write)
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        fixture.presentation.receive(.sceneInactive)
        XCTAssertThrowsError(try access.prepareStalePlanPredecessorConflict(draftID: setup.draftID))
        XCTAssertThrowsError(try access.executeStalePlanPredecessorConflict(write))
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(testCase: self,
            support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened).coordinator
        let coldAccess = try XCTUnwrap(reopened?.presentation.myDayAccess)
        XCTAssertEqual(try coldAccess.retryStalePlanPredecessorConflict(write), acknowledgement)
        XCTAssertEqual(try cold.workspaceWriter.currentRevision().revision, revision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.modelContext), rows)
    }

    @MainActor
    func testStalePlanPredecessorClassificationRejectsUnchangedAndTargetEffectHistories() async throws {
        let unchanged = try await makeFixture("classify-unchanged")
        defer { unchanged.cleanUp() }
        let unchangedAccess = try XCTUnwrap(unchanged.presentation.myDayAccess)
        let seed = try await unchangedAccess.savePlan(makeRequest(workspaceID: unchanged.coordinator.workspaceID))
        let request = try makeRequest(workspaceID: unchanged.coordinator.workspaceID,
            key: seed.targetResult.plan.key, predecessor: seed.targetResult.plan)
        let activeID = try await staleClassificationDraftID(access: unchangedAccess, request: request, interruption: nil)
        let unchangedWriter = unchanged.coordinator.workspaceWriter
        let before = try unchangedWriter.currentRevision(), beforeRows = try reviewedSaveRowCounts(in: unchanged.coordinator.modelContext)
        XCTAssertThrowsError(try unchangedAccess.prepareStalePlanPredecessorConflict(draftID: activeID))
        XCTAssertEqual(try unchangedWriter.currentRevision(), before)
        XCTAssertEqual(try reviewedSaveRowCounts(in: unchanged.coordinator.modelContext), beforeRows)

        for point in [MyDayPlanningEffectPointV1.targetCommit, .targetCommittedSaga, .retirePendingSaga] {
            let fixture = try await makeFixture("classify-target-effect-\(point.rawValue)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let initial = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID))
            let retained = try makeRequest(workspaceID: fixture.coordinator.workspaceID,
                key: initial.targetResult.plan.key, predecessor: initial.targetResult.plan)
            let denied = try await staleClassificationDraftID(access: access, request: retained, interruption: point)
            let writer = fixture.coordinator.workspaceWriter
            let revision = try writer.currentRevision(), rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertThrowsError(try access.prepareStalePlanPredecessorConflict(draftID: denied))
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
        }
    }

    @MainActor
    func testStalePlanPredecessorClassificationRejectsTargetChangedAfterPrepareWithoutEffect() async throws {
        let fixture = try await makeFixture("classify-target-race")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let setup = try await staleClassificationSetup(access: access, coordinator: fixture.coordinator,
                                                        interruption: .contentPromotedSaga)
        let write = try access.prepareStalePlanPredecessorConflict(draftID: setup.draftID)
        _ = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID,
            key: setup.request.confirmedContext.key, predecessor: setup.changedTarget))
        let writer = fixture.coordinator.workspaceWriter
        let revision = try writer.currentRevision(), rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        let physical = try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try access.executeStalePlanPredecessorConflict(write))
        XCTAssertThrowsError(try access.retryStalePlanPredecessorConflict(write))
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext), physical)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
    }

    @MainActor
    private func staleClassificationSetup(access: AppAccessPresentationV1.MyDayAccess,
        coordinator: StoreSessionCoordinator, interruption: MyDayPlanningEffectPointV1?) async throws ->
        (draftID: UUID, editingCheckpoint: FieldDraftCheckpointV1, request: MyDayPlanningPlanSaveRequestV1,
         changedTarget: MyDayPlanV1) {
        let seed = try await access.savePlan(makeRequest(workspaceID: coordinator.workspaceID))
        let request = try makeRequest(workspaceID: coordinator.workspaceID, key: seed.targetResult.plan.key,
            predecessor: seed.targetResult.plan)
        let draftID = try await staleClassificationDraftID(access: access, request: request, interruption: interruption)
        let editingCheckpoint = try authenticatedOriginalEditingCheckpoint(
            draftID: draftID, coordinator: coordinator
        )
        let changed = try await access.savePlan(makeRequest(workspaceID: coordinator.workspaceID,
            key: seed.targetResult.plan.key, predecessor: seed.targetResult.plan))
        return (draftID, editingCheckpoint, request, changed.targetResult.plan)
    }

    @MainActor
    private func authenticatedOriginalEditingCheckpoint(draftID: UUID,
        coordinator: StoreSessionCoordinator) throws -> FieldDraftCheckpointV1 {
        let writer = coordinator.workspaceWriter
        let fieldDraftEvidence = try coordinator.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
            .filter { row in
                guard case .applyFieldDraft = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData).command else {
                    return false
                }
                return true
            }
            .compactMap { try writer.fieldDraftEvidence(mutationID: .init(rawValue: $0.mutationID)) }
            .filter { evidence in
                switch evidence.mutation.postImage {
                case let .createCheckpoint(checkpoint), let .reviseCheckpoint(checkpoint):
                    return checkpoint.draftID == draftID && checkpoint.state == .active
                default:
                    return false
                }
            }
            .sorted { $0.receipt.resultingRevision.workspaceRevision < $1.receipt.resultingRevision.workspaceRevision }
        let editing = try XCTUnwrap(fieldDraftEvidence.last)
        guard case let .createCheckpoint(checkpoint) = editing.mutation.postImage else {
            guard case let .reviseCheckpoint(checkpoint) = editing.mutation.postImage else {
                throw V23MyDayCommitTestFailure.missingCheckpoint
            }
            return checkpoint
        }
        return checkpoint
    }

    @MainActor
    private func staleClassificationDraftID(access: AppAccessPresentationV1.MyDayAccess,
        request: MyDayPlanningPlanSaveRequestV1, interruption: MyDayPlanningEffectPointV1?) async throws -> UUID {
        guard let interruption else {
            let write = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: try DraftResumeAnchorV1())
            return try access.persistEditingWrite(write).checkpoint.draftID
        }
        var injected = false
        access.setPlanningEffectHookForTesting { point in
            guard point == interruption, !injected else { return }
            injected = true
            throw V23MyDayCommitTestInterruption.injected
        }
        defer { access.setPlanningEffectHookForTesting(nil) }
        let draftID = try await interruptedDraftID(from: access, request: request)
        XCTAssertTrue(injected)
        return draftID
    }

    @MainActor
    func testStaleCarryoverTargetClassificationAuthenticatesActiveAndPreparedPrefixes() async throws {
        for point in [nil, .committingCheckpoint, .preparedSaga, .contentPromotedSaga] as [MyDayPlanningEffectPointV1?] {
            let fixture = try await makeFixture("carryover-classify-\(point?.rawValue ?? "active")")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let seed = try await seedCarryover(in: fixture, existingTarget: point != nil)
            let draftID: UUID
            if let point {
                var injected = false
                access.setPlanningEffectHookForTesting { observed in
                    guard observed == point, !injected else { return }
                    injected = true; throw V23MyDayCommitTestInterruption.injected
                }
                draftID = try await interruptedCarryoverID(from: access, request: seed.request)
                access.setPlanningEffectHookForTesting(nil); XCTAssertTrue(injected)
            } else {
                let editing = try access.prepareCarryoverEditingWrite(seed.request, replacing: nil, resumeAnchor: .init(sectionID: "carryover"))
                draftID = try access.persistEditingWrite(editing).checkpoint.draftID
            }
            let changed = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID, key: seed.request.confirmedContext.key, predecessor: seed.target)).targetResult.plan
            let writer = fixture.coordinator.workspaceWriter
            let revision = try writer.currentRevision()
            let plans = try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext)
            let carryovers = try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext)
            let physical = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
            let beforeRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            let write = try access.prepareStaleCarryoverTargetConflict(draftID: draftID)
            XCTAssertEqual(write.evidence.currentCheckpoint, physical)
            XCTAssertEqual(write.observedTarget, changed)
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforeRows)
            XCTAssertEqual(write.evidence.preparedEpoch?.sagaPrefix.count, point == nil ? nil : (point == .committingCheckpoint ? 0 : point == .preparedSaga ? 1 : 2))
            let ack = try access.executeStaleCarryoverTargetConflict(write)
            XCTAssertEqual(ack.checkpoint.draftID, draftID)
            XCTAssertEqual(ack.checkpoint, write.checkpoint)
            XCTAssertEqual(ack.checkpoint.state, .conflicted)
            XCTAssertEqual(ack.checkpoint.payloadData, physical.payloadData)
            let afterWrite = try writer.currentRevision()
            XCTAssertEqual(afterWrite.revision, revision.revision + 1)
            let afterRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertEqual(try access.retryStaleCarryoverTargetConflict(write), ack)
            XCTAssertEqual(try writer.currentRevision(), afterWrite)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), afterRows)
            XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), plans)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), carryovers)
            let review = try access.carryoverConflictReview(draftID: draftID)
            XCTAssertEqual(review.originalEditingRequest, seed.request)
            XCTAssertEqual(review.reviewRequest.sourcePlan, seed.request.sourcePlan)
            XCTAssertEqual(review.reviewRequest.selectedMembershipIDs, seed.request.selectedMembershipIDs)
            XCTAssertEqual(review.reviewRequest.targetPredecessor, try MyDayPlanReferenceV1(changed))
            XCTAssertEqual(review.reviewRequest.confirmedContext, seed.request.confirmedContext)
            XCTAssertEqual(review.capturedTarget, changed)
            XCTAssertEqual(review.pending.conflictedCheckpoint, ack.checkpoint)
            XCTAssertEqual(review.pending.conflict.receipt, ack.receipt)
            XCTAssertEqual(try writer.currentPlan(for: seed.source.key), seed.source)
            XCTAssertEqual(try writer.currentRevision(), afterWrite)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), afterRows)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testStaleCarryoverTargetClassificationRejectsUnchangedAndPostTargetHistoryWithoutEffects() async throws {
        let fixture = try await makeFixture("carryover-classify-denial")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryover(in: fixture)
        let write = try access.prepareCarryoverEditingWrite(seed.request, replacing: nil, resumeAnchor: .init(sectionID: "carryover"))
        _ = try access.persistEditingWrite(write)
        let writer = fixture.coordinator.workspaceWriter; let before = try writer.currentRevision()
        let beforeRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try access.prepareStaleCarryoverTargetConflict(draftID: write.checkpoint.draftID))
        XCTAssertEqual(try writer.currentRevision(), before)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforeRows)
        XCTAssertEqual(try checkpoint(draftID: write.checkpoint.draftID, in: fixture.coordinator.modelContext), write.checkpoint)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        for point in [MyDayPlanningEffectPointV1.targetCommit, .targetCommittedSaga, .retirePendingSaga] {
            let next = try await makeFixture("carryover-classify-post-\(point.rawValue)")
            defer { next.cleanUp() }
            let nextAccess = try XCTUnwrap(next.presentation.myDayAccess); let nextSeed = try await seedCarryover(in: next)
            var injected = false
            nextAccess.setPlanningEffectHookForTesting { observed in if observed == point && !injected { injected = true; throw V23MyDayCommitTestInterruption.injected } }
            let id = try await interruptedCarryoverID(from: nextAccess, request: nextSeed.request)
            nextAccess.setPlanningEffectHookForTesting(nil)
            XCTAssertTrue(injected)
            let physical = try checkpoint(draftID: id, in: next.coordinator.modelContext)
            let counts = try reviewedSaveRowCounts(in: next.coordinator.modelContext)
            let carryovers = try count(MyDayCarryoverReceiptRowV1.self, in: next.coordinator.modelContext)
            let revision = try next.coordinator.workspaceWriter.currentRevision()
            XCTAssertThrowsError(try nextAccess.prepareStaleCarryoverTargetConflict(draftID: id))
            XCTAssertEqual(try next.coordinator.workspaceWriter.currentRevision(), revision)
            XCTAssertEqual(try checkpoint(draftID: id, in: next.coordinator.modelContext), physical)
            XCTAssertEqual(try reviewedSaveRowCounts(in: next.coordinator.modelContext), counts)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: next.coordinator.modelContext), carryovers)
            XCTAssertFalse(next.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testStaleCarryoverTargetClassificationRejectsSourcePlanAndSourceWorkDriftBeforePrepare() async throws {
        for sourceWork in [false, true] {
            let fixture = try await makeFixture("carryover-classify-source-\(sourceWork)")
            defer { fixture.cleanUp() }
            let setup = try await carryoverConflictSetup(in: fixture, interruption: nil)
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            if sourceWork { try advanceCarryoverSourceWork(setup.seed, coordinator: fixture.coordinator) }
            else {
                let item = try XCTUnwrap(setup.seed.source.items.first)
                _ = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID, key: setup.seed.source.key, reference: item.reference, predecessor: setup.seed.source, membershipID: item.membershipID, estimateMinutes: 45))
            }
            let writer = fixture.coordinator.workspaceWriter; let revision = try writer.currentRevision()
            let physical = try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext)
            let counts = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertThrowsError(try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)) { error in
                if sourceWork { XCTAssertEqual(error as? MyDayWorkflowFailureV1, .carryoverIneligible) }
            }
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext), physical)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), counts)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), 0)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testStaleCarryoverTargetClassificationRejectsTargetSourcePlanAndSourceWorkChangesAfterPrepare() async throws {
        for kind in ["target", "plan", "work"] {
            let fixture = try await makeFixture("carryover-classify-race-\(kind)")
            defer { fixture.cleanUp() }
            let setup = try await carryoverConflictSetup(in: fixture, interruption: .contentPromotedSaga)
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let write = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
            if kind == "target" { _ = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID, key: setup.seed.request.confirmedContext.key, predecessor: setup.target)) }
            else if kind == "plan" { let item = try XCTUnwrap(setup.seed.source.items.first); _ = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID, key: setup.seed.source.key, reference: item.reference, predecessor: setup.seed.source, membershipID: item.membershipID, estimateMinutes: 45)) }
            else { try advanceCarryoverSourceWork(setup.seed, coordinator: fixture.coordinator) }
            let writer = fixture.coordinator.workspaceWriter; let revision = try writer.currentRevision(); let physical = try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext)
            let counts = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertThrowsError(try access.executeStaleCarryoverTargetConflict(write))
            XCTAssertThrowsError(try access.retryStaleCarryoverTargetConflict(write))
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext), physical)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), counts)
            XCTAssertNil(try writer.fieldDraftReceipt(for: write.mutation))
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), 0)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testStaleCarryoverTargetConflictRevocationAndColdReopenReplayExactCommittedWrite() async throws {
        let fixture = try await makeFixture("carryover-classify-cold")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer { try? reopened?.coordinator.invalidateAndReleaseWriter(); fixture.cleanUp() }
        let setup = try await carryoverConflictSetup(in: fixture, interruption: .preparedSaga)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess); let write = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
        let acknowledgement = try access.executeStaleCarryoverTargetConflict(write)
        let hotRevision = try fixture.coordinator.workspaceWriter.currentRevision()
        let hotRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        fixture.presentation.receive(.sceneInactive)
        XCTAssertThrowsError(try access.retryStaleCarryoverTargetConflict(write))
        XCTAssertThrowsError(try access.carryoverConflictReview(draftID: setup.draftID))
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(testCase: self, support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened); let coldAccess = try XCTUnwrap(cold.presentation.myDayAccess)
        XCTAssertEqual(try coldAccess.retryStaleCarryoverTargetConflict(write), acknowledgement)
        XCTAssertEqual(try coldAccess.carryoverConflictReview(draftID: setup.draftID).originalEditingRequest, setup.seed.request)
        XCTAssertNotEqual(try cold.coordinator.workspaceWriter.currentRevision().writerInstanceID, hotRevision.writerInstanceID)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision().revision, hotRevision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.coordinator.modelContext), hotRows)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentPlan(for: setup.seed.source.key), setup.seed.source)
        XCTAssertThrowsError(try access.retryStaleCarryoverTargetConflict(write))
        XCTAssertFalse(cold.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testStaleCarryoverTargetConflictReviewDeniesSourceWorkDriftWhileCommittedRetryRemainsExact() async throws {
        let fixture = try await makeFixture("carryover-classify-review-work")
        defer { fixture.cleanUp() }
        let setup = try await carryoverConflictSetup(in: fixture, interruption: nil)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess); let write = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
        let acknowledgement = try access.executeStaleCarryoverTargetConflict(write)
        try advanceCarryoverSourceWork(setup.seed, coordinator: fixture.coordinator)
        let writer = fixture.coordinator.workspaceWriter; let revision = try writer.currentRevision()
        let counts = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try access.carryoverConflictReview(draftID: setup.draftID)) { XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .carryoverIneligible) }
        XCTAssertEqual(try access.retryStaleCarryoverTargetConflict(write), acknowledgement)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), counts)
        XCTAssertEqual(try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext), acknowledgement.checkpoint)
        XCTAssertEqual(try writer.currentPlan(for: setup.seed.source.key), setup.seed.source)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    private func carryoverConflictSetup(in fixture: V23ProductionMyDayPresentationHarness, interruption: MyDayPlanningEffectPointV1?) async throws -> (draftID: UUID, seed: (work: FieldDraftCheckpointV1, source: MyDayPlanV1, request: MyDayPlanningCarryoverRequestV1, target: MyDayPlanV1?), target: MyDayPlanV1) {
        let access = try XCTUnwrap(fixture.presentation.myDayAccess); let seed = try await seedCarryover(in: fixture)
        let draftID: UUID
        if let interruption { var injected = false; access.setPlanningEffectHookForTesting { point in if point == interruption && !injected { injected = true; throw V23MyDayCommitTestInterruption.injected } }; draftID = try await interruptedCarryoverID(from: access, request: seed.request); access.setPlanningEffectHookForTesting(nil); XCTAssertTrue(injected) }
        else { let write = try access.prepareCarryoverEditingWrite(seed.request, replacing: nil, resumeAnchor: .init(sectionID: "carryover")); draftID = try access.persistEditingWrite(write).checkpoint.draftID }
        let target = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID, key: seed.request.confirmedContext.key, predecessor: seed.target)).targetResult.plan
        return (draftID, seed, target)
    }

    @MainActor
    private func advanceCarryoverSourceWork(_ seed: (work: FieldDraftCheckpointV1, source: MyDayPlanV1, request: MyDayPlanningCarryoverRequestV1, target: MyDayPlanV1?), coordinator: StoreSessionCoordinator) throws {
        let writer = coordinator.workspaceWriter; let next = try makeSourceCheckpoint(workspaceID: seed.work.workspaceID, writer: writer, draftID: seed.work.draftID, revision: seed.work.draftRevision + 1)
        let adapter = try writer.makeFieldDraftLifecycleAdapter(modelContext: coordinator.modelContext)
        _ = try adapter.compareAndSwap(checkpoint: next, expectedDraftRevision: seed.work.draftRevision, expectedBaseRevision: seed.work.baseCanonicalRevision)
    }

    @MainActor
    func testReviewedCarryoverRebaseRetainsOriginalSelectionAndReplaysExactResolution() async throws {
        for point in [nil, .committingCheckpoint, .preparedSaga, .contentPromotedSaga] as [MyDayPlanningEffectPointV1?] {
            let fixture = try await makeFixture("carryover-rebase-\(point?.rawValue ?? "active")")
            defer { fixture.cleanUp() }
            let setup = try await carryoverConflictSetup(in: fixture, interruption: point)
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let classification = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
            _ = try access.executeStaleCarryoverTargetConflict(classification)
            let review = try access.carryoverConflictReview(draftID: setup.draftID)
            let writer = fixture.coordinator.workspaceWriter
            let before = try writer.currentRevision()
            let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            let write = try access.prepareReviewedCarryoverRebase(review)
            XCTAssertEqual(try writer.currentRevision(), before)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
            XCTAssertNil(try writer.fieldDraftReceipt(for: write.mutation))
            XCTAssertEqual(write.review.originalEditingRequest, setup.seed.request)
            XCTAssertEqual(write.resolution.successorCheckpoint.draftID, setup.draftID)
            let acknowledgement = try access.executeReviewedCarryoverRebase(write)
            XCTAssertEqual(try writer.currentRevision().revision, before.revision + 1)
            let after = try writer.currentRevision()
            let afterRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertEqual(try access.retryReviewedCarryoverRebase(write), acknowledgement)
            XCTAssertEqual(try writer.currentRevision(), after)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), afterRows)
            XCTAssertEqual(try writer.currentPlan(for: setup.seed.source.key), setup.seed.source)
            XCTAssertEqual(try writer.currentPlan(for: setup.target.key), setup.target)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), 0)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(acknowledgement.checkpoint)
            XCTAssertEqual(payload.confirmedContext, setup.seed.request.confirmedContext)
            XCTAssertEqual(review.reviewRequest.sourcePlan, setup.seed.request.sourcePlan)
            XCTAssertEqual(review.reviewRequest.selectedMembershipIDs, setup.seed.request.selectedMembershipIDs)
        }
    }

    @MainActor
    func testReviewedCarryoverRebaseRejectsTargetSourceAndAccessRacesWithoutEffects() async throws {
        for race in ["target", "source", "sourcePlan", "access"] {
            let fixture = try await makeFixture("carryover-rebase-race-\(race)")
            defer { fixture.cleanUp() }
            let setup = try await carryoverConflictSetup(in: fixture, interruption: nil)
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let classified = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
            _ = try access.executeStaleCarryoverTargetConflict(classified)
            let review = try access.carryoverConflictReview(draftID: setup.draftID)
            let write = try access.prepareReviewedCarryoverRebase(review)
            if race == "target" { _ = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID, key: setup.seed.request.confirmedContext.key, predecessor: setup.target)) }
            else if race == "source" { try advanceCarryoverSourceWork(setup.seed, coordinator: fixture.coordinator) }
            else if race == "sourcePlan" {
                let item = try XCTUnwrap(setup.seed.source.items.first)
                _ = try await access.savePlan(makeRequest(workspaceID: fixture.coordinator.workspaceID,
                    key: setup.seed.source.key, reference: item.reference, predecessor: setup.seed.source,
                    membershipID: item.membershipID, estimateMinutes: 45))
            }
            else { fixture.presentation.receive(.sceneInactive) }
            let writer = fixture.coordinator.workspaceWriter; let revision = try writer.currentRevision(); let physical = try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext)
            let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertThrowsError(try access.prepareReviewedCarryoverRebase(review))
            XCTAssertThrowsError(try access.executeReviewedCarryoverRebase(write))
            XCTAssertThrowsError(try access.retryReviewedCarryoverRebase(write))
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext), physical)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
            XCTAssertNil(try writer.fieldDraftReceipt(for: write.mutation))
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), 0)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testReviewedCarryoverRebaseSavesOnceAndOriginalResolutionReplaysAfterColdReopenAndLaterSourceAdvance() async throws {
        let fixture = try await makeFixture("carryover-rebase-save-cold")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer { try? reopened?.coordinator.invalidateAndReleaseWriter(); fixture.cleanUp() }
        let setup = try await carryoverConflictSetup(in: fixture, interruption: nil)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let classified = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
        _ = try access.executeStaleCarryoverTargetConflict(classified)
        let rebase = try access.prepareReviewedCarryoverRebase(try access.carryoverConflictReview(draftID: setup.draftID))
        let acknowledgement = try access.executeReviewedCarryoverRebase(rebase)
        let outcome = try await access.retryPlanningCommit(draftID: setup.draftID)
        try assertCarryoverCommitted(outcome, source: setup.seed.source, in: fixture.coordinator)
        let writer = fixture.coordinator.workspaceWriter
        let revision = try writer.currentRevision()
        let carryovers = try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext)
        let replay = try await access.retryPlanningCommit(draftID: setup.draftID)
        XCTAssertEqual(replay, outcome)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), carryovers)
        let original = try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutation.mutationID))
        XCTAssertEqual(original.resolution.successorCheckpoint, acknowledgement.checkpoint)
        XCTAssertEqual(original.original.mutation, rebase.mutation)
        XCTAssertEqual(original.original.receipt, acknowledgement.receipt)
        XCTAssertEqual(try access.retryReviewedCarryoverRebase(rebase), acknowledgement)
        XCTAssertEqual(carryovers, 1)
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(testCase: self, support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened); let coldAccess = try XCTUnwrap(cold.presentation.myDayAccess)
        let coldReplay = try await coldAccess.retryPlanningCommit(draftID: setup.draftID)
        XCTAssertEqual(coldReplay, outcome)
        XCTAssertNotEqual(try cold.coordinator.workspaceWriter.currentRevision().writerInstanceID, revision.writerInstanceID)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision().revision, revision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.coordinator.modelContext), rows)
        XCTAssertEqual(try coldAccess.retryReviewedCarryoverRebase(rebase), acknowledgement)
        XCTAssertThrowsError(try access.retryReviewedCarryoverRebase(rebase))
        let item = try XCTUnwrap(setup.seed.source.items.first)
        _ = try await coldAccess.savePlan(makeRequest(workspaceID: cold.coordinator.workspaceID, key: setup.seed.source.key, reference: item.reference, predecessor: setup.seed.source, membershipID: item.membershipID, estimateMinutes: 45))
        let afterAdvance = try cold.coordinator.workspaceWriter.currentRevision()
        let afterRows = try reviewedSaveRowCounts(in: cold.coordinator.modelContext)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutation.mutationID), original)
        XCTAssertEqual(try coldAccess.retryReviewedCarryoverRebase(rebase), acknowledgement)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision(), afterAdvance)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.coordinator.modelContext), afterRows)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentPlan(for: outcome.targetResult.plan.key), outcome.targetResult.plan)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: cold.coordinator.modelContext), 1)
        XCTAssertFalse(cold.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testReviewedCarryoverRebaseDiscardPreservesOriginalResolutionWithoutTargetEffect() async throws {
        let fixture = try await makeFixture("carryover-rebase-discard")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer { try? reopened?.coordinator.invalidateAndReleaseWriter(); fixture.cleanUp() }
        let setup = try await carryoverConflictSetup(in: fixture, interruption: nil)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let classified = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
        _ = try access.executeStaleCarryoverTargetConflict(classified)
        let rebase = try access.prepareReviewedCarryoverRebase(try access.carryoverConflictReview(draftID: setup.draftID))
        let acknowledgement = try access.executeReviewedCarryoverRebase(rebase)
        let writer = fixture.coordinator.workspaceWriter
        let plans = try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext)
        let carryovers = try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext)
        let discard = try access.preparePlanningDiscard(expectedCheckpoint: acknowledgement.checkpoint)
        let outcome = try await access.discardPlanningDraft(discard)
        XCTAssertEqual(outcome.checkpoint.state, .discarded)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), plans)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), carryovers)
        let original = try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutation.mutationID))
        XCTAssertEqual(try access.retryReviewedCarryoverRebase(rebase), acknowledgement)
        XCTAssertEqual(carryovers, 0)
        XCTAssertEqual(try writer.currentPlan(for: setup.target.key), setup.target)
        let revision = try writer.currentRevision()
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23ProductionMyDayReopenedAuthority.start(testCase: self,
            support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened), coldAccess = try XCTUnwrap(reopened?.presentation.myDayAccess)
        XCTAssertEqual(try coldAccess.retryReviewedCarryoverRebase(rebase), acknowledgement)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision().revision, revision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.coordinator.modelContext), rows)
        let item = try XCTUnwrap(setup.seed.source.items.first)
        _ = try await coldAccess.savePlan(makeRequest(workspaceID: cold.coordinator.workspaceID,
            key: setup.seed.source.key, reference: item.reference, predecessor: setup.seed.source,
            membershipID: item.membershipID, estimateMinutes: 45))
        let after = try cold.coordinator.workspaceWriter.currentRevision()
        let afterRows = try reviewedSaveRowCounts(in: cold.coordinator.modelContext)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutation.mutationID), original)
        XCTAssertEqual(try coldAccess.retryReviewedCarryoverRebase(rebase), acknowledgement)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision(), after)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.coordinator.modelContext), afterRows)
        XCTAssertEqual(try checkpoint(draftID: setup.draftID, in: cold.coordinator.modelContext), outcome.checkpoint)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentPlan(for: setup.target.key), setup.target)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: cold.coordinator.modelContext), 0)
        XCTAssertFalse(cold.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testReviewedCarryoverRebaseTargetCommitInterruptionRetriesExactlyOnce() async throws {
        for interruption in [MyDayPlanningEffectPointV1.committingCheckpoint, .preparedSaga,
                             .contentPromotedSaga, .targetCommit, .targetCommittedSaga, .retirePendingSaga] {
        let fixture = try await makeFixture("carryover-rebase-partial-\(interruption.rawValue)")
        defer { fixture.cleanUp() }
        let setup = try await carryoverConflictSetup(in: fixture, interruption: nil)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let conflict = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
        _ = try access.executeStaleCarryoverTargetConflict(conflict)
        let rebase = try access.prepareReviewedCarryoverRebase(try access.carryoverConflictReview(draftID: setup.draftID))
        _ = try access.executeReviewedCarryoverRebase(rebase)
        var injected = false
        access.setPlanningEffectHookForTesting { point in if point == interruption && !injected { injected = true; throw V23MyDayCommitTestInterruption.injected } }
        do { _ = try await access.retryPlanningCommit(draftID: setup.draftID); XCTFail("expected target-commit interruption") } catch { XCTAssertTrue(error is V23MyDayCommitTestInterruption) }
        access.setPlanningEffectHookForTesting(nil)
        XCTAssertTrue(injected)
        let beforeRecovery = try fixture.coordinator.workspaceWriter.currentRevision()
        let partialRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        let partial = try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext)
        XCTAssertEqual(partial.state, .committing)
        XCTAssertNotNil(try fixture.coordinator.workspaceWriter.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutation.mutationID))
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeRecovery)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), partialRows)
        let outcome = try await access.retryPlanningCommit(draftID: setup.draftID)
        try assertCarryoverCommitted(outcome, source: setup.seed.source, in: fixture.coordinator)
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let replay = try await access.retryPlanningCommit(draftID: setup.draftID)
        XCTAssertEqual(replay, outcome)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), 1)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    @MainActor
    func testReviewedCarryoverRebaseRepeatsAgainstLatestTargetAndRetainsOriginalSelectionUntilOneActualSave() async throws {
        let fixture = try await makeFixture("carryover-rebase-repeat-latest-target")
        defer { fixture.cleanUp() }
        let setup = try await carryoverConflictSetup(in: fixture, interruption: nil)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter

        let firstClassification = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
        _ = try access.executeStaleCarryoverTargetConflict(firstClassification)
        let firstReview = try access.carryoverConflictReview(draftID: setup.draftID)
        let firstRebase = try access.prepareReviewedCarryoverRebase(firstReview)
        let firstAcknowledgement = try access.executeReviewedCarryoverRebase(firstRebase)
        XCTAssertEqual(firstRebase.review.originalEditingRequest, setup.seed.request)
        XCTAssertEqual(firstRebase.review.reviewRequest.selectedMembershipIDs, setup.seed.request.selectedMembershipIDs)

        let latestTarget = try await access.savePlan(makeRequest(
            workspaceID: fixture.coordinator.workspaceID,
            key: setup.seed.request.confirmedContext.key,
            predecessor: setup.target
        )).targetResult.plan
        let secondClassification = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
        _ = try access.executeStaleCarryoverTargetConflict(secondClassification)
        let secondReview = try access.carryoverConflictReview(draftID: setup.draftID)
        let secondRebase = try access.prepareReviewedCarryoverRebase(secondReview)
        XCTAssertEqual(secondRebase.review.originalEditingRequest, firstReview.reviewRequest)
        XCTAssertEqual(secondRebase.review.reviewRequest.confirmedContext, setup.seed.request.confirmedContext)
        XCTAssertEqual(secondRebase.review.reviewRequest.sourcePlan, setup.seed.request.sourcePlan)
        XCTAssertEqual(secondRebase.review.reviewRequest.selectedMembershipIDs, setup.seed.request.selectedMembershipIDs)
        XCTAssertEqual(secondRebase.review.reviewRequest.targetPredecessor, try MyDayPlanReferenceV1(latestTarget))
        XCTAssertEqual(secondRebase.review.capturedTarget, latestTarget)
        let secondAcknowledgement = try access.executeReviewedCarryoverRebase(secondRebase)

        let beforeOriginalReplay = try writer.currentRevision()
        let beforeOriginalReplayRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(mutationID: firstRebase.mutation.mutationID)?.resolution.successorCheckpoint,
                       firstAcknowledgement.checkpoint)
        XCTAssertEqual(try access.retryReviewedCarryoverRebase(firstRebase), firstAcknowledgement)
        XCTAssertEqual(try writer.currentRevision(), beforeOriginalReplay)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), beforeOriginalReplayRows)
        XCTAssertEqual(try writer.currentPlan(for: latestTarget.key), latestTarget)

        let outcome = try await access.retryPlanningCommit(draftID: setup.draftID)
        try assertCarryoverCommitted(outcome, source: setup.seed.source, in: fixture.coordinator)
        XCTAssertEqual(outcome.targetResult.plan.key, latestTarget.key)
        XCTAssertEqual(try writer.currentPlan(for: outcome.targetResult.plan.key), outcome.targetResult.plan)
        let afterSave = try writer.currentRevision()
        let afterSaveRows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), 1)
        let savedReplay = try await access.retryPlanningCommit(draftID: setup.draftID)
        XCTAssertEqual(savedReplay, outcome)
        XCTAssertEqual(try writer.currentRevision(), afterSave)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), afterSaveRows)
        XCTAssertEqual(try access.retryReviewedCarryoverRebase(secondRebase), secondAcknowledgement)
        XCTAssertEqual(try writer.currentRevision(), afterSave)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), afterSaveRows)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testReviewedCarryoverRebaseTerminalHistoryRejectsMissingPhysicalCarryoverReceipt() async throws {
        for corruption in 0..<5 {
        let fixture = try await makeFixture("carryover-rebase-terminal-receipt-hostile-\(corruption)")
        defer { fixture.cleanUp() }
        let setup = try await carryoverConflictSetup(in: fixture, interruption: nil)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let classification = try access.prepareStaleCarryoverTargetConflict(draftID: setup.draftID)
        _ = try access.executeStaleCarryoverTargetConflict(classification)
        let rebase = try access.prepareReviewedCarryoverRebase(try access.carryoverConflictReview(draftID: setup.draftID))
        let acknowledgement = try access.executeReviewedCarryoverRebase(rebase)
        let outcome = try await access.retryPlanningCommit(draftID: setup.draftID)
        try assertCarryoverCommitted(outcome, source: setup.seed.source, in: fixture.coordinator)
        XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutation.mutationID)?.resolution.successorCheckpoint,
                       acknowledgement.checkpoint)
        XCTAssertEqual(try access.retryReviewedCarryoverRebase(rebase), acknowledgement)

        let attempt = try preparedAttempt(in: outcome.checkpoint)
        let receiptRows = try fixture.coordinator.modelContext.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>())
            .filter { $0.mutationID == attempt.command.mutationID.rawValue }
        XCTAssertEqual(receiptRows.count, 1)
        let context = fixture.coordinator.modelContext
        let actual = try XCTUnwrap(receiptRows.first)
        switch corruption {
        case 0: context.delete(actual)
        case 1:
            guard case let .carryover(plan, source, target, receipt) = attempt.command else {
                return XCTFail("Expected genuine carryover command")
            }
            let duplicate = try MyDayCarryoverReceiptV1(plan: plan, source: source, target: target,
                mutationID: receipt.mutationID, committedAt: receipt.committedAt.addingTimeInterval(1))
            XCTAssertNotEqual(duplicate.receiptSHA256, receipt.receiptSHA256)
            try duplicate.validate(plan: plan, source: source, target: target)
            context.insert(try MyDayCarryoverReceiptRowV1(duplicate))
        case 2: actual.canonicalData = Data("{}".utf8)
        case 3: actual.mutationID = UUID()
        default:
            context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                $0.mutationID == attempt.command.mutationID.rawValue
            }))
        }
        try context.save()

        let revision = try XCTUnwrap(context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first).workspaceRevision
        let carryovers = try count(MyDayCarryoverReceiptRowV1.self, in: context)
        let terminalCheckpoint = try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext)
        let plans = try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext)
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try writer.reviewedFieldDraftResolutionEvidence(mutationID: rebase.mutation.mutationID))
        XCTAssertThrowsError(try access.retryReviewedCarryoverRebase(rebase))
        do {
            _ = try await access.retryPlanningCommit(draftID: setup.draftID)
            XCTFail("Missing terminal carryover receipt must deny history replay")
        } catch {
            XCTAssertFalse(error is V23MyDayCommitTestInterruption)
        }
        XCTAssertEqual(try XCTUnwrap(context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first).workspaceRevision, revision)
        XCTAssertEqual(try checkpoint(draftID: setup.draftID, in: fixture.coordinator.modelContext), terminalCheckpoint)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), plans)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), carryovers)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
    }

    #endif

    @MainActor
    func testReviewedResolutionSurvivesProductionSaveLaterTargetAndGenuineAuthorityReopen() async throws {
        for existingTarget in [false, true] {
            let fixture = try await makeFixture("reviewed-save-\(existingTarget)")
            var reopened: V23ProductionMyDayReopenedAuthority?
            defer {
                try? reopened?.coordinator.invalidateAndReleaseWriter()
                fixture.cleanUp()
            }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let writer = fixture.coordinator.workspaceWriter
            let original = try seedReviewedResolution(in: fixture.coordinator, existingTarget: existingTarget)
            let draftID = original.resolution.successorCheckpoint.draftID

            let outcome = try await access.retryPlanSave(draftID: draftID)
            try assertCommitted(outcome, in: fixture.coordinator)
            XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
            let beforeReplay = try writer.currentRevision()
            let rowsBeforeReplay = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            let replay = try await access.retryPlanSave(draftID: draftID)
            XCTAssertEqual(replay, outcome)
            XCTAssertEqual(try writer.currentRevision(), beforeReplay)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rowsBeforeReplay)

            let later = try await access.savePlan(makeRequest(
                workspaceID: fixture.coordinator.workspaceID, key: outcome.targetResult.plan.key,
                predecessor: outcome.targetResult.plan))
            XCTAssertEqual(later.targetResult.plan.revision, outcome.targetResult.plan.revision + 1)
            XCTAssertNotEqual(later.targetResult.plan, outcome.targetResult.plan)
            let revision = try writer.currentRevision()
            let rowCounts = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
            XCTAssertEqual(try writer.commitFieldDraft(original.original.mutation), original.original.receipt)
            XCTAssertEqual(try writer.currentPlan(for: later.targetResult.plan.key), later.targetResult.plan)
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rowCounts)

            try fixture.coordinator.invalidateAndReleaseWriter()
            reopened = try await V23ProductionMyDayReopenedAuthority.start(
                testCase: self, support: fixture.support, defaults: fixture.defaults)
            let cold = try XCTUnwrap(reopened).coordinator
            let coldWriter = cold.workspaceWriter
            XCTAssertNotEqual(try coldWriter.currentRevision().writerInstanceID, revision.writerInstanceID)
            XCTAssertEqual(try coldWriter.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
            let adapter = try coldWriter.makeFieldDraftLifecycleAdapter(modelContext: cold.modelContext)
            XCTAssertEqual(try adapter.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
            XCTAssertEqual(try coldWriter.commitFieldDraft(original.original.mutation), original.original.receipt)
            XCTAssertEqual(try coldWriter.currentPlan(for: later.targetResult.plan.key), later.targetResult.plan)
            XCTAssertEqual(try checkpoint(draftID: draftID, in: cold.modelContext), outcome.checkpoint)
            XCTAssertEqual(try coldWriter.currentRevision().revision, revision.revision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: cold.modelContext), rowCounts)
            XCTAssertFalse(cold.modelContext.hasChanges)
        }
    }

    @MainActor
    func testReviewedResolutionRejectsPartialProductionSaveUntilRealTerminalReceiptExists() async throws {
        for point in [MyDayPlanningEffectPointV1.committingCheckpoint, .targetCommit, .retirePendingSaga] {
            let fixture = try await makeFixture("reviewed-partial-\(point.rawValue)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let writer = fixture.coordinator.workspaceWriter
            let original = try seedReviewedResolution(in: fixture.coordinator, existingTarget: false)
            let draftID = original.resolution.successorCheckpoint.draftID
            var injected = false
            access.setPlanningEffectHookForTesting { observed in
                guard observed == point, !injected else { return }
                injected = true
                throw V23MyDayCommitTestInterruption.injected
            }
            do {
                _ = try await access.retryPlanSave(draftID: draftID)
                XCTFail("Expected actual production interruption")
            } catch {
                XCTAssertTrue(error is V23MyDayCommitTestInterruption)
            }
            XCTAssertTrue(injected)
            access.setPlanningEffectHookForTesting(nil)
            let revision = try writer.currentRevision()
            let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            XCTAssertThrowsError(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID))
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)

            let completed = try await access.retryPlanSave(draftID: draftID)
            try assertCommitted(completed, in: fixture.coordinator)
            XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
        }
    }

    @MainActor
    func testReviewedResolutionRejectsMissingOrUnjournaledPhysicalSaveEvidenceWithoutWrites() async throws {
        for corruption in 0..<6 {
            let fixture = try await makeFixture("reviewed-save-corruption-\(corruption)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let coordinator = fixture.coordinator, context = coordinator.modelContext
            let writer = coordinator.workspaceWriter
            let original = try seedReviewedResolution(in: coordinator, existingTarget: false)
            let outcome = try await access.retryPlanSave(draftID: original.resolution.successorCheckpoint.draftID)
            XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
            let sagas = try context.fetch(FetchDescriptor<DraftCommitSagaRow>())
                .sorted { $0.revision < $1.revision }
            let first = try XCTUnwrap(sagas.first).value()
            switch corruption {
            case 0: context.delete(try XCTUnwrap(sagas.first))
            case 1: context.delete(try XCTUnwrap(sagas.last))
            case 2:
                context.insert(try DraftCommitSagaRow(DraftCommitSagaV1(
                    sagaID: UUID(), workspaceID: first.workspaceID, draftID: first.draftID,
                    plan: first.plan, state: .prepared, revision: 1,
                    mutationID: .init(rawValue: UUID()), updatedAt: first.updatedAt)))
            case 3:
                context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<DraftCommitReceiptRow>()).first))
            case 4:
                context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<MyDayPlanRowV1>()).first))
            default:
                let receipt = outcome.draftReceipt
                context.insert(try DraftCommitReceiptRow(DraftCommitReceiptV1(
                    receiptID: UUID(), workspaceID: receipt.workspaceID, draftID: receipt.draftID,
                    sagaID: receipt.sagaID, commitPlanSHA256: receipt.commitPlanSHA256,
                    sagaEventSHA256Chain: receipt.sagaEventSHA256Chain,
                    targetMutationID: receipt.targetMutationID, targetReceiptSHA256: receipt.targetReceiptSHA256,
                    consumedStageToContentID: receipt.consumedStageToContentID,
                    committedAt: receipt.committedAt, revision: receipt.revision,
                    mutationID: .init(rawValue: UUID()))))
            }
            try context.save()
            let revision = try writer.currentRevision()
            let rows = try reviewedSaveRowCounts(in: context)
            XCTAssertThrowsError(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID))
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: context), rows)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testCarryoverEvidenceReadsActualActiveAndPreTargetPrefixesWithoutEffects() async throws {
        #if DEBUG
        for point in [nil, .committingCheckpoint, .preparedSaga, .contentPromotedSaga] as [MyDayPlanningEffectPointV1?] {
            let fixture = try await makeFixture("carryover-evidence-prefix-\(point?.rawValue ?? "active")")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let seed = try await seedCarryover(in: fixture)
            let draftID: UUID
            let expected: FieldDraftCheckpointV1
            if let point {
                var injected = false
                access.setPlanningEffectHookForTesting { observed in
                    guard observed == point, !injected else { return }
                    injected = true
                    throw V23MyDayCommitTestInterruption.injected
                }
                draftID = try await interruptedCarryoverID(from: access, request: seed.request)
                access.setPlanningEffectHookForTesting(nil)
                XCTAssertTrue(injected)
                expected = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
            } else {
                let write = try access.prepareCarryoverEditingWrite(seed.request, replacing: nil,
                    resumeAnchor: .init(sectionID: "carryover-evidence"))
                expected = try access.persistEditingWrite(write).checkpoint
                draftID = expected.draftID
            }
            let writer = fixture.coordinator.workspaceWriter
            let revision = try writer.currentRevision()
            let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
            let first = try writer.classifiableMyDayCarryoverEvidence(draftID: draftID)
            let second = try writer.classifiableMyDayCarryoverEvidence(draftID: draftID)
            XCTAssertEqual(first, second)
            XCTAssertEqual(first.currentCheckpoint, expected)
            XCTAssertEqual(first.editingCheckpoint.draftID, draftID)
            XCTAssertEqual(first.preparedEpoch?.sagaPrefix.count, point == nil ? nil :
                (point == .committingCheckpoint ? 0 : point == .preparedSaga ? 1 : 2))
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
        #else
        throw XCTSkip("Carryover prepared-prefix hooks require DEBUG.")
        #endif
    }

    @MainActor
    func testCarryoverEvidenceRejectsRealSourceAdvanceWithoutEffects() async throws {
        let fixture = try await makeFixture("carryover-evidence-source-drift")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryover(in: fixture)
        let write = try access.prepareCarryoverEditingWrite(seed.request, replacing: nil,
            resumeAnchor: .init(sectionID: "carryover-evidence"))
        let checkpoint = try access.persistEditingWrite(write).checkpoint
        let item = try XCTUnwrap(seed.source.items.first)
        _ = try await access.savePlan(makeRequest(workspaceID: seed.source.key.workspaceID,
            key: seed.source.key, reference: item.reference, predecessor: seed.source,
            membershipID: item.membershipID, estimateMinutes: 45))
        let writer = fixture.coordinator.workspaceWriter
        let revision = try writer.currentRevision()
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try writer.classifiableMyDayCarryoverEvidence(draftID: checkpoint.draftID))
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
        XCTAssertEqual(try self.checkpoint(draftID: checkpoint.draftID, in: fixture.coordinator.modelContext), checkpoint)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testCarryoverEvidenceAllowsAdvancedTargetWhenRetainedSourceIsExactWithoutEffects() async throws {
        let fixture = try await makeFixture("carryover-evidence-target-advance")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryover(in: fixture, existingTarget: true)
        let previousTarget = try XCTUnwrap(seed.target)
        let write = try access.prepareCarryoverEditingWrite(seed.request, replacing: nil,
            resumeAnchor: .init(sectionID: "carryover-evidence"))
        let checkpoint = try access.persistEditingWrite(write).checkpoint
        let writer = fixture.coordinator.workspaceWriter
        let before = try writer.classifiableMyDayCarryoverEvidence(draftID: checkpoint.draftID)
        let revisionBeforeAdvance = try writer.currentRevision()
        let advanced = try await access.savePlan(makeRequest(workspaceID: seed.source.key.workspaceID,
            key: seed.request.confirmedContext.key, predecessor: previousTarget))
        XCTAssertNotEqual(advanced.targetResult.plan, previousTarget)
        let revisionAfterAdvance = try writer.currentRevision()
        XCTAssertNotEqual(revisionAfterAdvance, revisionBeforeAdvance)
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        let after = try writer.classifiableMyDayCarryoverEvidence(draftID: checkpoint.draftID)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.editingCheckpoint, checkpoint)
        XCTAssertEqual(try writer.currentPlan(for: seed.source.key), seed.source)
        XCTAssertEqual(try writer.currentPlan(for: seed.request.confirmedContext.key), advanced.targetResult.plan)
        XCTAssertEqual(try writer.currentRevision(), revisionAfterAdvance)
        XCTAssertEqual(try reviewedSaveRowCounts(in: fixture.coordinator.modelContext), rows)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testCarryoverEvidenceRejectsActualPostTargetEffectsWithoutMutatingTheirRows() async throws {
        #if DEBUG
        for point in [MyDayPlanningEffectPointV1.targetCommit, .targetCommittedSaga, .retirePendingSaga] {
            let fixture = try await makeFixture("carryover-evidence-post-target-\(point.rawValue)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let seed = try await seedCarryover(in: fixture)
            var injected = false
            access.setPlanningEffectHookForTesting { observed in
                guard observed == point, !injected else { return }
                injected = true
                throw V23MyDayCommitTestInterruption.injected
            }
            let draftID = try await interruptedCarryoverID(from: access, request: seed.request)
            access.setPlanningEffectHookForTesting(nil)
            XCTAssertTrue(injected)
            let writer = fixture.coordinator.workspaceWriter
            let physical = try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext)
            let revision = try writer.currentRevision()
            let planRows = try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext)
            let receiptRows = try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext)
            let sagaRows = try count(DraftCommitSagaRow.self, in: fixture.coordinator.modelContext)
            XCTAssertThrowsError(try writer.classifiableMyDayCarryoverEvidence(draftID: draftID))
            XCTAssertEqual(try checkpoint(draftID: draftID, in: fixture.coordinator.modelContext), physical)
            XCTAssertEqual(try writer.currentPlan(for: seed.source.key), seed.source)
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), planRows)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, in: fixture.coordinator.modelContext), receiptRows)
            XCTAssertEqual(try count(DraftCommitSagaRow.self, in: fixture.coordinator.modelContext), sagaRows)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
        #else
        throw XCTSkip("Carryover post-target interruption hooks require DEBUG.")
        #endif
    }

    @MainActor
    func testCarryoverEvidenceSurvivesColdReopenAndOldWriterRejectsRead() async throws {
        let fixture = try await makeFixture("carryover-evidence-cold-read")
        var reopened: V23ProductionMyDayReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryover(in: fixture)
        let write = try access.prepareCarryoverEditingWrite(seed.request, replacing: nil,
            resumeAnchor: .init(sectionID: "carryover-evidence"))
        let checkpoint = try access.persistEditingWrite(write).checkpoint
        let oldWriter = fixture.coordinator.workspaceWriter
        let hot = try oldWriter.classifiableMyDayCarryoverEvidence(draftID: checkpoint.draftID)
        let revision = try oldWriter.currentRevision()
        let rows = try reviewedSaveRowCounts(in: fixture.coordinator.modelContext)
        try fixture.coordinator.invalidateAndReleaseWriter()
        XCTAssertThrowsError(try oldWriter.classifiableMyDayCarryoverEvidence(draftID: checkpoint.draftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        reopened = try await V23ProductionMyDayReopenedAuthority.start(testCase: self,
            support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened).coordinator
        let coldWriter = cold.workspaceWriter
        XCTAssertNotEqual(try coldWriter.currentRevision().writerInstanceID, revision.writerInstanceID)
        let first = try coldWriter.classifiableMyDayCarryoverEvidence(draftID: checkpoint.draftID)
        let second = try coldWriter.classifiableMyDayCarryoverEvidence(draftID: checkpoint.draftID)
        XCTAssertEqual(first, hot)
        XCTAssertEqual(second, hot)
        XCTAssertEqual(first.editingCheckpoint, checkpoint)
        XCTAssertEqual(try coldWriter.currentRevision().revision, revision.revision)
        XCTAssertEqual(try reviewedSaveRowCounts(in: cold.modelContext), rows)
        XCTAssertFalse(cold.modelContext.hasChanges)
    }

    @MainActor
    private func seedReviewedResolution(in coordinator: StoreSessionCoordinator,
                                        existingTarget: Bool) throws -> ReviewedFieldDraftResolutionEvidenceV1 {
        let instant = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let fixture = try ReviewedResolutionTestFixtureV1(workspaceID: coordinator.workspaceID, now: instant)
        let writer = coordinator.workspaceWriter
        _ = try writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        if existingTarget {
            _ = try writer.commit(MyDayCommandV1.save(successor: fixture.target, predecessor: nil))
        }
        _ = try writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
        let command = try fixture.resolution(target: existingTarget ? fixture.target : nil,
            workspaceRevision: writer.currentRevision().revision)
        let receipt = try writer.commitFieldDraft(command)
        let original = try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(mutationID: command.mutationID))
        XCTAssertEqual(original.original.receipt, receipt)
        XCTAssertFalse(coordinator.modelContext.hasChanges)
        return original
    }

    @MainActor
    private func reviewedSaveRowCounts(in context: ModelContext) throws -> [Int] {
        try [context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
             context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()),
             context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()),
             context.fetchCount(FetchDescriptor<DraftCommitReceiptRow>()),
             context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()),
             context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()),
             context.fetchCount(FetchDescriptor<DraftContentReservationRow>())]
    }
}


extension V23ProductionMyDayCommitTests {
    @MainActor
    func testMyDayWriterQuantizesFractionalCommitClockAndReplaysExactJournalTime() throws {
        for seconds in [1_789_084_801.123456, 1_789_084_801.987654, 1_789_084_801.125] {
            let workspace = WorkspaceID(rawValue: UUID())
            let harness = try MyDayReceiptTimeHarness(workspaceID: workspace, clockInstant: Date(timeIntervalSince1970: seconds))
            defer { harness.removeFiles() }
            let request = try makeRequest(workspaceID: workspace)
            let plan = try MyDayPlanV1(planID: UUID(), key: request.draft.key, items: [], revision: 1,
                mutationID: .init(rawValue: UUID()), authoredBy: request.confirmedContext.recordedBy,
                authoredAt: request.confirmedContext.recordedBy.capturedAt)
            let command = MyDayCommandV1.save(successor: plan, predecessor: nil)
            let expectedTime = Date(timeIntervalSince1970: (seconds * 1_000).rounded(.toNearestOrAwayFromZero) / 1_000)
            let result = try harness.writer.commit(command)
            let journalReceipt = try XCTUnwrap(harness.store.receipt(mutationID: command.mutationID))
            try result.validate()
            XCTAssertEqual(result.plan, plan)
            XCTAssertEqual(result.receipt.committedAt, expectedTime)
            XCTAssertEqual(result.receipt.committedAt, journalReceipt.committedAt)
            try MyDayLimitsV1.millisecondInstant(journalReceipt.committedAt)
            let after = try harness.writer.currentRevision()
            XCTAssertEqual(try harness.writer.commit(command), result)
            XCTAssertEqual(try harness.writer.result(workspaceID: workspace, mutationID: command.mutationID), result)
            XCTAssertEqual(try harness.writer.currentRevision(), after)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
            let reopened = try harness.reopen()
            let reopenedBefore = try reopened.writer.currentRevision()
            XCTAssertEqual(try reopened.writer.result(workspaceID: workspace, mutationID: command.mutationID), result)
            XCTAssertEqual(try reopened.writer.commit(command), result)
            XCTAssertEqual(try reopened.writer.currentRevision(), reopenedBefore)
            XCTAssertEqual(try harness.store.receipt(mutationID: command.mutationID), journalReceipt)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    @MainActor
    func testMyDayWriterRejectsInvalidCommitClockBeforeAnyCanonicalEffect() throws {
        for seconds in [Double.nan, Double.infinity, 10_000_000_000_000.0] {
            let workspace = WorkspaceID(rawValue: UUID())
            let harness = try MyDayReceiptTimeHarness(workspaceID: workspace, clockInstant: Date(timeIntervalSince1970: seconds))
            defer { harness.removeFiles() }
            let request = try makeRequest(workspaceID: workspace)
            let plan = try MyDayPlanV1(planID: UUID(), key: request.draft.key, items: [], revision: 1,
                mutationID: .init(rawValue: UUID()), authoredBy: request.confirmedContext.recordedBy,
                authoredAt: request.confirmedContext.recordedBy.capturedAt)
            let command = MyDayCommandV1.save(successor: plan, predecessor: nil)
            let before = try harness.writer.currentRevision()
            XCTAssertThrowsError(try harness.writer.commit(command))
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 0)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
            XCTAssertNil(try harness.store.receipt(mutationID: command.mutationID))
            XCTAssertFalse(harness.context.hasChanges)
        }
    }
}
@MainActor
private final class MyDayReceiptTimeHarness {
    let root: URL; let container: ModelContainer; let context: ModelContext
    let registry: GenerationLeaseRegistryV1; let fence: StaleWriterFenceV1
    let identity: WorkspaceReplicaIdentityV1; let generationID: UUID
    let store: MutationJournalStoreV1; let writer: WorkspaceWriterV1
    var adapter: FieldDraftLifecycleAdapterV1 { .init(writer: writer, journal: store, modelContext: context) }
    let clock: MyDayReceiptTimeClock
    init(workspaceID: WorkspaceID, clockInstant: Date) throws {
        clock = MyDayReceiptTimeClock(instant: clockInstant)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("V23-myday-receipt-time-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        container = try ModelContainer(for: schema, migrationPlan: nil,
            configurations: [ModelConfiguration("MyDayReceiptTime", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        context = container.mainContext; context.autosaveEnabled = false
        identity = try .init(workspaceID: workspaceID, replicaID: .init(rawValue: UUID()))
        generationID = UUID()
        let epoch = try GenerationEpochV1(generationID: generationID, generationManifestSHA256: String(repeating: "a", count: 64))
        registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let lease = try registry.acquire(epoch: epoch, role: .writer)
        fence = try StaleWriterFenceV1(expectedGenerationEpoch: epoch, writerLeaseToken: lease,
                                      registry: registry, currentGenerationEpoch: { epoch })
        store = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: generationID, staleWriterFence: fence)
        let id = UUID()
        writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: id), clock: clock,
            idSource: MyDayReceiptTimeIDs(value: id), fileAuthority: MyDayReceiptTimeFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: store)
    }
    func reopen() throws -> (writer: WorkspaceWriterV1, adapter: FieldDraftLifecycleAdapterV1) {
        let context = ModelContext(container); context.autosaveEnabled = false
        let store = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: generationID, allowStateBootstrap: false, staleWriterFence: fence)
        let id = UUID()
        let writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: id), clock: clock,
            idSource: MyDayReceiptTimeIDs(value: id), fileAuthority: MyDayReceiptTimeFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: store)
        return (writer, .init(writer: writer, journal: store, modelContext: context))
    }
    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}
private struct MyDayReceiptTimeClock: ApplicationClock { let instant: Date; func now() -> Date { instant } }
private struct MyDayReceiptTimeIDs: ApplicationIDSource { let value: UUID; func makeID() -> UUID { value } }
private struct MyDayReceiptTimeFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "myday-receipt-time/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

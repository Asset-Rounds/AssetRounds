import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23FieldDraftAsyncCommitTests: XCTestCase {
    func testAsyncTargetSuccessUsesExactReceiptAndOneIncumbentSagaBody() async throws {
        let harness = try C36AsyncCommitHarness()

        let result = try await harness.commit()

        XCTAssertEqual(result.targetMutationID, harness.fixture.plan.mutationID)
        XCTAssertEqual(result.targetReceiptSHA256, harness.target.receipt.resultSHA256)
        XCTAssertEqual(harness.target.commitCount, 1)
        XCTAssertEqual(harness.target.effectCount, 1)
        XCTAssertEqual(harness.target.readBackCount, 1)
        XCTAssertEqual(harness.target.receivedReservations, harness.content.reservations)
        XCTAssertEqual(harness.writer.sagas, [
            harness.fixture.preparedSaga,
            harness.fixture.promotedSaga,
            harness.fixture.targetCommittedSaga,
            harness.fixture.retirePendingSaga,
            harness.fixture.retiredSaga
        ])
        XCTAssertEqual(harness.writer.reservations, harness.content.reservations)
        XCTAssertEqual(harness.writer.commitApplyCount, 1)
        XCTAssertEqual(harness.writer.lastCommitBundle?.receipt, result)
    }

    func testContentSuspensionRequiresSameCurrentCommittingCheckpointBeforeFurtherWrites() async throws {
        for loss in C36AsyncCheckpointLoss.allCases {
            let harness = try C36AsyncCommitHarness(contentSuspends: true)
            let task = Task { @MainActor in try await harness.commit() }
            await harness.content.waitUntilEntered()
            harness.writer.apply(loss, fixture: harness.fixture)
            await harness.content.release()

            do {
                _ = try await task.value
                XCTFail("Content suspension must revalidate the durable committing checkpoint")
            } catch {
                if loss == .writerFailure {
                    XCTAssertEqual(error as? C36AsyncCommitTestError, .writerLost)
                } else {
                    XCTAssertEqual(error as? FieldDraftFailureV1, .staleDraftRevision)
                }
            }
            XCTAssertEqual(harness.writer.sagas, [harness.fixture.preparedSaga])
            XCTAssertTrue(harness.writer.reservations.isEmpty)
            XCTAssertEqual(harness.target.commitCount, 0)
            XCTAssertEqual(harness.target.readBackCount, 0)
            XCTAssertEqual(harness.writer.commitApplyCount, 0)
        }
    }

    func testTargetSuspensionRequiresSameCurrentCommittingCheckpointBeforeReadBackOrSagaAdvance() async throws {
        for loss in C36AsyncCheckpointLoss.allCases {
            let harness = try C36AsyncCommitHarness(targetSuspends: true)
            let task = Task { @MainActor in try await harness.commit() }
            await harness.target.waitUntilEntered()
            harness.writer.apply(loss, fixture: harness.fixture)
            await harness.target.release()

            do {
                _ = try await task.value
                XCTFail("Target suspension must revalidate the durable committing checkpoint")
            } catch {
                if loss == .writerFailure {
                    XCTAssertEqual(error as? C36AsyncCommitTestError, .writerLost)
                } else {
                    XCTAssertEqual(error as? FieldDraftFailureV1, .staleDraftRevision)
                }
            }
            XCTAssertEqual(harness.target.effectCount, 1)
            XCTAssertEqual(harness.target.retainedReceipt, harness.target.receipt)
            XCTAssertEqual(harness.target.readBackCount, 0)
            XCTAssertEqual(harness.writer.sagas, [
                harness.fixture.preparedSaga,
                harness.fixture.promotedSaga
            ])
            XCTAssertEqual(harness.writer.reservations, harness.content.reservations)
            XCTAssertEqual(harness.writer.commitApplyCount, 0)
        }
    }

    func testAsyncTargetRejectsWrongMutationAndWorkspaceReceiptsBeforeReadBack() async throws {
        let fixture = try C36FieldDraftTestSupportV1.makeFixture(seed: 161_000)
        let receipts = [
            try C36AsyncReceiptFactory.receipt(
                workspaceID: fixture.workspaceID,
                mutationID: C36FieldDraftTestSupportV1.mutation(161_900),
                seed: 161_910
            ),
            try C36AsyncReceiptFactory.receipt(
                workspaceID: fixture.otherWorkspaceID,
                mutationID: fixture.plan.mutationID,
                seed: 161_920
            )
        ]

        for receipt in receipts {
            let harness = try C36AsyncCommitHarness(fixture: fixture, targetReceipt: receipt)
            do {
                _ = try await harness.commit()
                XCTFail("A receipt outside the plan identity must be rejected")
            } catch {
                XCTAssertEqual(error as? FieldDraftFailureV1, .missingReceipt)
            }
            XCTAssertEqual(harness.target.readBackCount, 0)
            XCTAssertEqual(harness.writer.sagas, [fixture.preparedSaga, fixture.promotedSaga])
            XCTAssertEqual(harness.writer.commitApplyCount, 0)
        }
    }

    func testAsyncTargetSaveThenThrowRetainsEffectAndExactRetryCompletesOnce() async throws {
        let harness = try C36AsyncCommitHarness(
            targetSuspends: true,
            targetFailureOnce: .saveThenThrow
        )
        let first = Task { @MainActor in try await harness.commit() }
        await harness.target.waitUntilEntered()
        await harness.target.release()

        do {
            _ = try await first.value
            XCTFail("The first target acknowledgement must be lost")
        } catch {
            XCTAssertEqual(error as? C36AsyncCommitTestError, .saveThenThrow)
        }
        XCTAssertEqual(harness.target.effectCount, 1)
        XCTAssertEqual(harness.target.readBackCount, 0)
        XCTAssertEqual(harness.writer.sagas, [
            harness.fixture.preparedSaga,
            harness.fixture.promotedSaga
        ])
        XCTAssertEqual(harness.writer.commitApplyCount, 0)

        let retained = try XCTUnwrap(harness.target.retainedReceipt)
        let result = try await harness.commit()
        XCTAssertEqual(harness.target.retainedReceipt, retained)
        XCTAssertEqual(result.targetReceiptSHA256, retained.resultSHA256)
        XCTAssertEqual(harness.target.commitCount, 2)
        XCTAssertEqual(harness.target.effectCount, 1)
        XCTAssertEqual(harness.target.readBackCount, 1)
        XCTAssertEqual(harness.writer.commitApplyCount, 1)
        XCTAssertEqual(harness.writer.sagas.count, 5)
    }

    func testAsyncTargetCancellationAfterSaveRetainsEffectAndExactRetryCompletesOnce() async throws {
        let harness = try C36AsyncCommitHarness(targetSuspends: true)
        let first = Task { @MainActor in try await harness.commit() }
        await harness.target.waitUntilEntered()
        XCTAssertEqual(harness.target.effectCount, 1)
        first.cancel()

        do {
            _ = try await first.value
            XCTFail("Cancellation after the target effect must leave an uncertain acknowledgement")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(harness.target.effectCount, 1)
        XCTAssertEqual(harness.target.readBackCount, 0)
        XCTAssertEqual(harness.writer.sagas, [
            harness.fixture.preparedSaga,
            harness.fixture.promotedSaga
        ])
        XCTAssertEqual(harness.writer.commitApplyCount, 0)

        let retained = try XCTUnwrap(harness.target.retainedReceipt)
        let result = try await harness.commit()
        XCTAssertEqual(harness.target.retainedReceipt, retained)
        XCTAssertEqual(result.targetReceiptSHA256, retained.resultSHA256)
        XCTAssertEqual(harness.target.commitCount, 2)
        XCTAssertEqual(harness.target.effectCount, 1)
        XCTAssertEqual(harness.target.readBackCount, 1)
        XCTAssertEqual(harness.writer.commitApplyCount, 1)
    }

    func testSynchronousTargetInitializersPreserveExistingOrderingAndFailureBehavior() async throws {
        for initializer in C36SyncInitializer.allCases {
            let fixture = try C36FieldDraftTestSupportV1.makeFixture(
                seed: 162_000 + initializer.rawValue * 1_000
            )
            let writer = C36AsyncWriterProbeV1(checkpoint: fixture.committingCheckpoint)
            let content = try C36AsyncContentProbeV1(fixture: fixture)
            let receipt = try C36AsyncReceiptFactory.receipt(
                workspaceID: fixture.workspaceID,
                mutationID: fixture.plan.mutationID,
                seed: 162_800 + initializer.rawValue * 1_000
            )
            let target = C36SyncTargetProbeV1(receipt: receipt)
            let coordinator: FieldDraftCoordinatorV1
            switch initializer {
            case .registry:
                coordinator = FieldDraftCoordinatorV1(
                    registry: fixture.registry, writer: writer, content: content, target: target
                )
            case .purposeAuthority:
                coordinator = FieldDraftCoordinatorV1(
                    purposeAuthority: fixture.registry, writer: writer,
                    content: content, target: target
                )
            }

            let result = try await C36AsyncCommitHarness.commit(
                coordinator: coordinator, fixture: fixture
            )
            XCTAssertEqual(result.targetReceiptSHA256, receipt.resultSHA256)
            XCTAssertEqual(target.commitCount, 1)
            XCTAssertEqual(target.readBackCount, 1)
            XCTAssertEqual(target.receivedReservations, content.reservations)
            XCTAssertEqual(writer.sagas.count, 5)
            XCTAssertEqual(writer.commitApplyCount, 1)

            let throwingWriter = C36AsyncWriterProbeV1(checkpoint: fixture.committingCheckpoint)
            let throwingTarget = C36SyncTargetProbeV1(
                receipt: receipt, failure: .synchronousTarget
            )
            let throwingContent = try C36AsyncContentProbeV1(fixture: fixture)
            let throwingCoordinator: FieldDraftCoordinatorV1
            switch initializer {
            case .registry:
                throwingCoordinator = FieldDraftCoordinatorV1(
                    registry: fixture.registry, writer: throwingWriter,
                    content: throwingContent, target: throwingTarget
                )
            case .purposeAuthority:
                throwingCoordinator = FieldDraftCoordinatorV1(
                    purposeAuthority: fixture.registry, writer: throwingWriter,
                    content: throwingContent, target: throwingTarget
                )
            }
            do {
                _ = try await C36AsyncCommitHarness.commit(
                    coordinator: throwingCoordinator, fixture: fixture
                )
                XCTFail("The incumbent synchronous target error must propagate")
            } catch {
                XCTAssertEqual(error as? C36AsyncCommitTestError, .synchronousTarget)
            }
            XCTAssertEqual(throwingTarget.readBackCount, 0)
            XCTAssertEqual(throwingWriter.sagas, [fixture.preparedSaga, fixture.promotedSaga])
            XCTAssertEqual(throwingWriter.commitApplyCount, 0)
        }
    }
}

private enum C36AsyncCheckpointLoss: CaseIterable, Equatable {
    case missing
    case changed
    case writerFailure
}

private enum C36SyncInitializer: Int, CaseIterable {
    case registry
    case purposeAuthority
}

private enum C36AsyncCommitTestError: Error, Equatable {
    case writerLost
    case saveThenThrow
    case synchronousTarget
}

private actor C36AsyncCommitGate {
    private var didEnter = false
    private var didRelease = false
    private var didCancel = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspension: CheckedContinuation<Void, Error>?

    func waitUntilEntered() async {
        if didEnter { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func suspend() async throws {
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if didRelease { return }
        if didCancel { throw CancellationError() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if didCancel {
                    continuation.resume(throwing: CancellationError())
                } else if didRelease {
                    continuation.resume()
                } else {
                    suspension = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func release() {
        guard !didRelease, !didCancel else { return }
        didRelease = true
        suspension?.resume()
        suspension = nil
    }

    private func cancel() {
        guard !didCancel, !didRelease else { return }
        didCancel = true
        suspension?.resume(throwing: CancellationError())
        suspension = nil
    }
}

private actor C36AsyncContentProbeV1: DraftContentPromotionPortV1 {
    nonisolated let reservations: [DraftContentReservationV1]
    private let expectedPlan: DraftCommitPlanV1
    private let expectedItems: [AttachmentStagingItemV1]
    private let expectedMutationIDs: [UUID: MutationIDV1]
    private let gate: C36AsyncCommitGate?
    private(set) var promoteCount = 0

    init(fixture: C36FieldDraftTestSupportV1.Fixture, suspends: Bool = false) throws {
        expectedPlan = fixture.plan
        expectedItems = [fixture.readyItem, fixture.alternateReadyItem]
        expectedMutationIDs = fixture.rowMutationIDs.reservationByStageID
        guard let readyMutationID = expectedMutationIDs[fixture.readyItem.stageID],
              let alternateMutationID = expectedMutationIDs[fixture.alternateReadyItem.stageID] else {
            throw FieldDraftFailureV1.missingContent
        }
        reservations = try [
            Self.reservation(
                from: fixture.reservation,
                mutationID: readyMutationID
            ),
            Self.reservation(
                from: fixture.associatedReservation,
                mutationID: alternateMutationID
            )
        ]
        gate = suspends ? C36AsyncCommitGate() : nil
    }

    func promote(
        plan: DraftCommitPlanV1,
        items: [AttachmentStagingItemV1],
        reservationMutationIDs: [UUID: MutationIDV1]
    ) async throws -> [DraftContentReservationV1] {
        guard plan == expectedPlan, items == expectedItems,
              reservationMutationIDs == expectedMutationIDs else {
            throw FieldDraftFailureV1.missingContent
        }
        promoteCount += 1
        try await gate?.suspend()
        return reservations
    }

    func quarantine(
        reservations: [DraftContentReservationV1],
        for plan: DraftDiscardPlanV1
    ) async throws {
        _ = reservations
        _ = plan
        throw FieldDraftFailureV1.invalidValue
    }

    func waitUntilEntered() async { await gate?.waitUntilEntered() }
    func release() async { await gate?.release() }

    private static func reservation(
        from source: DraftContentReservationV1,
        mutationID: MutationIDV1
    ) throws -> DraftContentReservationV1 {
        try DraftContentReservationV1(
            reservationID: source.reservationID,
            workspaceID: source.workspaceID,
            draftID: source.draftID,
            stageID: source.stageID,
            commitPlanSHA256: source.commitPlanSHA256,
            mutationID: mutationID,
            contentDigest: source.contentDigest,
            locator: source.locator,
            createdAt: source.createdAt,
            reviewAfter: source.reviewAfter,
            reconciliationState: .reserved,
            revision: 1
        )
    }
}

@MainActor
private final class C36AsyncWriterProbeV1: FieldDraftWritingV1 {
    func publish(readyStage bundle: FieldDraftStagePublicationBundleV1) throws -> MutationReceiptV1 {
        throw FieldDraftFailureV1.invalidValue
    }

    private var checkpointResult: Result<FieldDraftCheckpointV1?, Error>
    private(set) var sagas: [DraftCommitSagaV1] = []
    private(set) var reservations: [DraftContentReservationV1] = []
    private(set) var commitApplyCount = 0
    private(set) var lastCommitBundle: DraftCommitTerminalBundleV1?

    init(checkpoint: FieldDraftCheckpointV1) {
        checkpointResult = .success(checkpoint)
    }

    func apply(
        _ loss: C36AsyncCheckpointLoss,
        fixture: C36FieldDraftTestSupportV1.Fixture
    ) {
        switch loss {
        case .missing:
            checkpointResult = .success(nil)
        case .changed:
            checkpointResult = .success(fixture.activeCheckpoint)
        case .writerFailure:
            checkpointResult = .failure(C36AsyncCommitTestError.writerLost)
        }
    }

    func currentCheckpoint(
        workspaceID: WorkspaceID,
        draftID: UUID
    ) throws -> FieldDraftCheckpointV1? {
        let value = try checkpointResult.get()
        guard let value else { return nil }
        guard value.workspaceID == workspaceID, value.draftID == draftID else {
            throw FieldDraftFailureV1.wrongWorkspace
        }
        return value
    }

    func compareAndSwap(
        checkpoint: FieldDraftCheckpointV1,
        expectedDraftRevision: UInt64,
        expectedBaseRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = expectedDraftRevision
        _ = expectedBaseRevision
        checkpointResult = .success(checkpoint)
        return try C36AsyncReceiptFactory.receipt(
            workspaceID: checkpoint.workspaceID, mutationID: checkpoint.mutationID,
            seed: 165_001
        )
    }

    func append(
        stagingItem: AttachmentStagingItemV1,
        expectedRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = expectedRevision
        return try C36AsyncReceiptFactory.receipt(
            workspaceID: stagingItem.workspaceID, mutationID: stagingItem.mutationID,
            seed: 165_002
        )
    }

    func append(
        saga: DraftCommitSagaV1,
        expectedRevision: UInt64
    ) throws -> MutationReceiptV1 {
        if let existing = sagas.first(where: { $0.revision == saga.revision }) {
            guard existing == saga else { throw FieldDraftFailureV1.conflictRequired }
        } else {
            guard UInt64(sagas.count) == expectedRevision else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            sagas.append(saga)
        }
        return try C36AsyncReceiptFactory.receipt(
            workspaceID: saga.workspaceID, mutationID: saga.mutationID,
            seed: 165_100 + Int(saga.revision)
        )
    }

    func append(
        reservation: DraftContentReservationV1,
        expectedRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = expectedRevision
        if let existing = reservations.first(where: { $0.stageID == reservation.stageID }) {
            guard existing == reservation else { throw FieldDraftFailureV1.conflictRequired }
        } else {
            reservations.append(reservation)
        }
        return try C36AsyncReceiptFactory.receipt(
            workspaceID: reservation.workspaceID, mutationID: reservation.mutationID,
            seed: 165_200 + reservations.count
        )
    }

    func apply(
        commitTerminalBundle: DraftCommitTerminalBundleV1,
        expectedDraftRevision: UInt64,
        expectedSagaRevision: UInt64
    ) throws -> MutationReceiptV1 {
        guard expectedDraftRevision + 1 == commitTerminalBundle.committedCheckpoint.draftRevision,
              expectedSagaRevision + 1 == commitTerminalBundle.retiredSaga.revision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        if let prior = lastCommitBundle {
            guard prior == commitTerminalBundle else { throw FieldDraftFailureV1.conflictRequired }
        } else {
            commitApplyCount += 1
            lastCommitBundle = commitTerminalBundle
            sagas.append(commitTerminalBundle.retiredSaga)
            checkpointResult = .success(commitTerminalBundle.committedCheckpoint)
        }
        return try C36AsyncReceiptFactory.receipt(
            workspaceID: commitTerminalBundle.workspaceID,
            mutationID: commitTerminalBundle.mutationID,
            seed: 165_300
        )
    }

    func apply(
        discardTerminalBundle: DraftDiscardTerminalBundleV1,
        expectedDraftRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = discardTerminalBundle
        _ = expectedDraftRevision
        throw FieldDraftFailureV1.invalidValue
    }
}

@MainActor
private final class C36AsyncTargetProbeV1: DraftAsyncCanonicalCommitPortV1 {
    let receipt: MutationReceiptV1
    private let gate: C36AsyncCommitGate?
    private var failureOnce: C36AsyncCommitTestError?
    private(set) var commitCount = 0
    private(set) var effectCount = 0
    private(set) var readBackCount = 0
    private(set) var retainedReceipt: MutationReceiptV1?
    private(set) var receivedReservations: [DraftContentReservationV1]?
    private var retainedPlan: DraftCommitPlanV1?

    init(
        receipt: MutationReceiptV1,
        suspends: Bool = false,
        failureOnce: C36AsyncCommitTestError? = nil
    ) {
        self.receipt = receipt
        gate = suspends ? C36AsyncCommitGate() : nil
        self.failureOnce = failureOnce
    }

    func commit(
        plan: DraftCommitPlanV1,
        reservations: [DraftContentReservationV1]
    ) async throws -> MutationReceiptV1 {
        commitCount += 1
        if retainedReceipt == nil {
            retainedReceipt = receipt
            retainedPlan = plan
            receivedReservations = reservations
            effectCount += 1
        } else if retainedPlan != plan || receivedReservations != reservations {
            throw FieldDraftFailureV1.conflictRequired
        }
        if commitCount == 1 { try await gate?.suspend() }
        if let failureOnce {
            self.failureOnce = nil
            throw failureOnce
        }
        return try XCTUnwrap(retainedReceipt)
    }

    func readBackMatches(
        plan: DraftCommitPlanV1,
        receipt: MutationReceiptV1
    ) throws -> Bool {
        readBackCount += 1
        return retainedPlan == plan && retainedReceipt == receipt
    }

    func waitUntilEntered() async { await gate?.waitUntilEntered() }
    func release() async { await gate?.release() }
}

@MainActor
private final class C36SyncTargetProbeV1: DraftCanonicalCommitPortV1 {
    let receipt: MutationReceiptV1
    let failure: C36AsyncCommitTestError?
    private(set) var commitCount = 0
    private(set) var readBackCount = 0
    private var plan: DraftCommitPlanV1?
    private(set) var receivedReservations: [DraftContentReservationV1]?

    init(receipt: MutationReceiptV1, failure: C36AsyncCommitTestError? = nil) {
        self.receipt = receipt
        self.failure = failure
    }

    func commit(
        plan: DraftCommitPlanV1,
        reservations: [DraftContentReservationV1]
    ) throws -> MutationReceiptV1 {
        commitCount += 1
        self.plan = plan
        receivedReservations = reservations
        if let failure { throw failure }
        return receipt
    }

    func readBackMatches(
        plan: DraftCommitPlanV1,
        receipt: MutationReceiptV1
    ) throws -> Bool {
        readBackCount += 1
        return self.plan == plan && self.receipt == receipt
    }
}

@MainActor
private final class C36AsyncCommitHarness {
    let fixture: C36FieldDraftTestSupportV1.Fixture
    let writer: C36AsyncWriterProbeV1
    let content: C36AsyncContentProbeV1
    let target: C36AsyncTargetProbeV1
    let coordinator: FieldDraftCoordinatorV1

    init(
        fixture suppliedFixture: C36FieldDraftTestSupportV1.Fixture? = nil,
        contentSuspends: Bool = false,
        targetSuspends: Bool = false,
        targetReceipt suppliedReceipt: MutationReceiptV1? = nil,
        targetFailureOnce: C36AsyncCommitTestError? = nil
    ) throws {
        let fixture = try suppliedFixture ?? C36FieldDraftTestSupportV1.makeFixture(seed: 160_000)
        self.fixture = fixture
        writer = C36AsyncWriterProbeV1(checkpoint: fixture.committingCheckpoint)
        content = try C36AsyncContentProbeV1(fixture: fixture, suspends: contentSuspends)
        let receipt = try suppliedReceipt ?? C36AsyncReceiptFactory.receipt(
            workspaceID: fixture.workspaceID,
            mutationID: fixture.plan.mutationID,
            seed: 160_900
        )
        target = C36AsyncTargetProbeV1(
            receipt: receipt, suspends: targetSuspends, failureOnce: targetFailureOnce
        )
        coordinator = FieldDraftCoordinatorV1(
            purposeAuthority: fixture.registry,
            writer: writer,
            content: content,
            asyncTarget: target
        )
    }

    func commit() async throws -> DraftCommitReceiptV1 {
        try await Self.commit(coordinator: coordinator, fixture: fixture)
    }

    static func commit(
        coordinator: FieldDraftCoordinatorV1,
        fixture: C36FieldDraftTestSupportV1.Fixture
    ) async throws -> DraftCommitReceiptV1 {
        try await coordinator.commit(
            plan: fixture.plan,
            checkpoint: fixture.committingCheckpoint,
            items: [fixture.readyItem, fixture.alternateReadyItem],
            prepared: fixture.preparedSaga,
            contentPromoted: fixture.promotedSaga,
            targetCommitted: fixture.targetCommittedSaga,
            retirePending: fixture.retirePendingSaga,
            retired: fixture.retiredSaga,
            commitReceiptID: fixture.commitReceipt.receiptID,
            terminalCheckpointUpdatedAt: C36FieldDraftTestSupportV1.fixedDate.addingTimeInterval(10),
            rowMutationIDs: fixture.rowMutationIDs
        )
    }
}

private enum C36AsyncReceiptFactory {
    static func receipt(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1,
        seed: Int
    ) throws -> MutationReceiptV1 {
        let digest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "c", count: 64)
        )
        let item = try AttachmentStagingItemV1(
            stageID: C36FieldDraftTestSupportV1.id(seed),
            draftID: C36FieldDraftTestSupportV1.id(seed + 1),
            workspaceID: workspaceID,
            attachmentKind: .photo,
            scratchLeaseID: C36FieldDraftTestSupportV1.id(seed + 2),
            expectedByteCount: 1,
            actualByteCount: 1,
            contentDigest: digest,
            retryClass: .none,
            state: .readyLocal,
            protectionState: .available,
            revision: 1,
            mutationID: mutationID
        )
        let mutation = try FieldDraftMutationV1(
            workspaceID: workspaceID,
            expectedRevision: 0,
            expectedBaseCanonicalRevision: 0,
            mutationID: mutationID,
            postImage: .appendStagingItem(item)
        )
        let identity = try WorkspaceEntityIdentityV1(
            kind: .attachmentStagingItem,
            id: item.stageID
        )
        let generationID = C36FieldDraftTestSupportV1.id(seed + 3)
        let writerInstanceID = C36FieldDraftTestSupportV1.id(seed + 4)
        let replicaID = ReplicaID(rawValue: C36FieldDraftTestSupportV1.id(seed + 5))
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: 0,
            entityRevisions: [.init(identity: identity, revision: 0)]
        )
        let envelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: mutationID,
                expectedRevision: expected,
                command: .applyFieldDraft(mutation)
            ),
            identity: try WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID,
                replicaID: replicaID
            )
        )
        let resulting = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: 1,
            entityRevisions: [.init(identity: identity, revision: 1)]
        )
        return try MutationReceiptV1(
            identity: .init(
                workspaceID: workspaceID,
                replicaID: replicaID,
                localSequence: 1
            ),
            envelope: envelope,
            resultingRevision: .init(resulting),
            postImages: [try mutation.postImage.mutationPostImage],
            committedAt: C36FieldDraftTestSupportV1.fixedDate
        )
    }
}

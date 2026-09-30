import Foundation
import XCTest
@testable import FieldEvidenceApp

final class S7_3LifecycleRestoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLifecycleAndRestorePresentationMatrixIsExact() {
        let expiry = now.addingTimeInterval(3_600)
        let active = fact(
            .active,
            expiration: expiry,
            trial: true,
            renews: false
        )
        let activePresentation = SubscriptionLifecyclePresentationV1.make(
            state: .active(until: expiry),
            latestVerifiedFact: active,
            dateText: { _ in "DATE" }
        )
        XCTAssertEqual(activePresentation.tone, .complete)
        XCTAssertEqual(activePresentation.badge, "Trial active")
        XCTAssertEqual(activePresentation.title, "Active until DATE")
        XCTAssertTrue(activePresentation.detail.contains("Auto-renew is off"))

        let rows: [(
            SubscriptionLifecycleStateV1,
            SubscriptionLifecycleToneV1,
            String,
            String
        )] = [
            (.loading, .information, "Subscription status", "Checking subscription…"),
            (.neverPaid, .information, "No active subscription", "No subscription found"),
            (.grace(until: expiry), .information, "Grace period", "Access through DATE"),
            (.inactive(reason: .billingRetry), .blocked, "Billing retry", "Subscription inactive"),
            (.inactive(reason: .expired), .blocked, "Subscription expired", "Subscription inactive"),
            (.inactive(reason: .refunded), .blocked, "Subscription refunded", "Subscription inactive"),
            (.inactive(reason: .revoked), .blocked, "Subscription revoked", "Subscription inactive"),
        ]
        for (state, tone, badge, title) in rows {
            let value = SubscriptionLifecyclePresentationV1.make(
                state: state,
                latestVerifiedFact: nil,
                dateText: { _ in "DATE" }
            )
            XCTAssertEqual(value.tone, tone)
            XCTAssertEqual(value.badge, badge)
            XCTAssertEqual(value.title, title)
            let retainsDataCopy = value.detail.contains("data")
                || value.detail.contains("sign details, photos, and reports")
            XCTAssertTrue(retainsDataCopy || state == .grace(until: expiry))
        }

        let restoreRows: [(StoreKitRestoreStateV1, String?)] = [
            (.idle, nil),
            (.restoring, "Restoring purchases…"),
            (.restored, "Purchases restored. Subscription access is updated."),
            (.noCurrentEntitlement, "No current subscription was found. Your existing data is still available."),
            (.unverified, "Purchase history couldn’t be verified. Your existing data is still available. Try again."),
            (.failed, "Purchases couldn’t be restored. Your existing data is still available. Try again."),
        ]
        for (state, copy) in restoreRows {
            XCTAssertEqual(
                StoreKitRestorePresentationV1.make(state: state)?.copy,
                copy
            )
        }
    }

    @MainActor
    func testExplicitRestoreSerializesAndPersistsBeforeSuccess() async throws {
        let root = try makeRoot("restore")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EntitlementStore(applicationSupportURL: root)
        let restoredFact = fact(
            .active,
            expiration: now.addingTimeInterval(3_600),
            trial: true,
            renews: false
        )
        let sequence = EventSequence([
            [],
            [.verified(.init(fact: restoredFact))],
        ])
        let processor = StoreKitTransactionProcessor(
            store: store,
            runtime: runtime(sequence),
            now: { [now] in now }
        )
        try await processor.start()
        await processor.waitForInitialRefresh()
        XCTAssertEqual(processor.state, .neverPaid)

        let gate = SynchronizeGate()
        let coordinator = StoreKitLifecycleCoordinator(
            processor: processor,
            runtime: .init(synchronize: { await gate.wait() })
        )
        let restore = Task { await coordinator.restorePurchases() }
        await eventually {
            let entered = await gate.hasEntered
            return coordinator.isRestoring && entered
        }
        let duplicateAccepted = await coordinator.restorePurchases()
        XCTAssertFalse(duplicateAccepted)
        await gate.release()
        let accepted = await restore.value
        XCTAssertTrue(accepted)

        XCTAssertEqual(coordinator.restoreState, .restored)
        XCTAssertFalse(coordinator.isRestoring)
        XCTAssertEqual(
            coordinator.lifecycleState,
            .active(until: try XCTUnwrap(restoredFact.expirationAt))
        )
        XCTAssertEqual(coordinator.latestVerifiedFact, restoredFact)
        let durable = try await store.load()
        XCTAssertEqual(durable?.state, .active)
        XCTAssertEqual(durable?.hasEverVerifiedPaid, true)
        let synchronizeCalls = await gate.callCount
        XCTAssertEqual(synchronizeCalls, 1)
        processor.stop()
    }

    @MainActor
    func testRestoreNoCurrentUnverifiedFailureAndMissingProcessorFailClosed()
        async throws {
        let empty = try await makeStartedProcessor(
            name: "empty",
            batches: [[], []]
        )
        defer {
            empty.processor.stop()
            try? FileManager.default.removeItem(at: empty.root)
        }
        let emptySync = SynchronizeCounter()
        let emptyCoordinator = StoreKitLifecycleCoordinator(
            processor: empty.processor,
            runtime: .init(synchronize: { await emptySync.record() })
        )
        let emptyAccepted = await emptyCoordinator.restorePurchases()
        XCTAssertTrue(emptyAccepted)
        XCTAssertEqual(emptyCoordinator.restoreState, .noCurrentEntitlement)
        let emptySyncCount = await emptySync.count
        XCTAssertEqual(emptySyncCount, 1)

        let unverified = try await makeStartedProcessor(
            name: "unverified",
            batches: [[], [.unverified]]
        )
        defer {
            unverified.processor.stop()
            try? FileManager.default.removeItem(at: unverified.root)
        }
        let unverifiedCoordinator = StoreKitLifecycleCoordinator(
            processor: unverified.processor,
            runtime: .init(synchronize: {})
        )
        let unverifiedAccepted = await unverifiedCoordinator.restorePurchases()
        XCTAssertTrue(unverifiedAccepted)
        XCTAssertEqual(unverifiedCoordinator.restoreState, .unverified)
        let unverifiedCache = try await unverified.store.load()
        XCTAssertNil(unverifiedCache)

        let failedCoordinator = StoreKitLifecycleCoordinator(
            processor: empty.processor,
            runtime: .init(synchronize: { throw ProbeError.injected })
        )
        let failedAccepted = await failedCoordinator.restorePurchases()
        XCTAssertTrue(failedAccepted)
        XCTAssertEqual(failedCoordinator.restoreState, .failed)
        XCTAssertEqual(emptyCoordinator.lifecycleState, .neverPaid)

        let missingProcessor = StoreKitLifecycleCoordinator(processor: nil)
        let missingAccepted = await missingProcessor.restorePurchases()
        XCTAssertTrue(missingAccepted)
        XCTAssertEqual(missingProcessor.restoreState, .failed)
    }

    @MainActor
    func testOfflineCacheExpiresWithoutInventingGraceOrRenewalFacts()
        async throws {
        let root = try makeRoot("offline")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EntitlementStore(applicationSupportURL: root)
        let expiry = now.addingTimeInterval(60)
        _ = try await store.persist(cache(.active, expiration: expiry))

        let offlineRuntime = StoreKitEntitlementRuntimeV1(
            initialEvents: { throw ProbeError.injected },
            transactionUpdates: { AsyncStream { $0.finish() } },
            statusUpdates: { AsyncStream { $0.finish() } }
        )
        let activeProcessor = StoreKitTransactionProcessor(
            store: store,
            runtime: offlineRuntime,
            now: { [now] in now }
        )
        try await activeProcessor.start()
        await activeProcessor.waitForInitialRefresh()
        let activeCoordinator = StoreKitLifecycleCoordinator(
            processor: activeProcessor
        )
        XCTAssertEqual(
            activeCoordinator.lifecycleState,
            .active(until: expiry)
        )
        XCTAssertNil(activeCoordinator.latestVerifiedFact)
        let presentation = SubscriptionLifecyclePresentationV1.make(
            state: activeCoordinator.lifecycleState,
            latestVerifiedFact: activeCoordinator.latestVerifiedFact,
            dateText: { _ in "DATE" }
        )
        XCTAssertEqual(presentation.title, "Active until DATE")
        XCTAssertFalse(presentation.detail.contains("Auto-renew"))
        activeProcessor.stop()

        let expiredProcessor = StoreKitTransactionProcessor(
            store: store,
            runtime: offlineRuntime,
            now: { expiry }
        )
        try await expiredProcessor.start()
        await expiredProcessor.waitForInitialRefresh()
        let expiredCoordinator = StoreKitLifecycleCoordinator(
            processor: expiredProcessor
        )
        XCTAssertEqual(
            expiredCoordinator.lifecycleState,
            .inactive(reason: .expired)
        )
        XCTAssertNil(expiredCoordinator.latestVerifiedFact)
        expiredProcessor.stop()
    }

    @MainActor
    func testUnverifiedRestorePreservesStillValidDurableAuthority()
        async throws {
        let root = try makeRoot("preserve")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EntitlementStore(applicationSupportURL: root)
        let expiry = now.addingTimeInterval(3_600)
        let prior = cache(.active, expiration: expiry)
        _ = try await store.persist(prior)

        let sequence = EventSequence([
            [.unverified],
            [.unverified],
        ])
        let processor = StoreKitTransactionProcessor(
            store: store,
            runtime: runtime(sequence),
            now: { [now] in now }
        )
        try await processor.start()
        await processor.waitForInitialRefresh()
        let coordinator = StoreKitLifecycleCoordinator(
            processor: processor,
            runtime: .init(synchronize: {})
        )
        let accepted = await coordinator.restorePurchases()
        XCTAssertTrue(accepted)
        XCTAssertEqual(coordinator.restoreState, .unverified)
        XCTAssertEqual(coordinator.lifecycleState, .active(until: expiry))
        XCTAssertNil(coordinator.latestVerifiedFact)
        let after = try await store.load()
        XCTAssertEqual(after, prior)
        processor.stop()
    }

    @MainActor
    func testPaidGraceAcceptsExactSixteenDaysAndRejectsLongerAuthority()
        async throws {
        let expiration = now.addingTimeInterval(-60)
        let exactGrace = fact(
            .grace,
            expiration: expiration,
            graceExpiration: expiration.addingTimeInterval(
                StoreKitPaidGraceAuthorityV1.maximumDuration
            )
        )
        XCTAssertTrue(StoreKitPaidGraceAuthorityV1.accepts(exactGrace))

        let accepted = try await makeStartedProcessor(
            name: "exact-grace",
            batches: [[.verified(.init(fact: exactGrace))]]
        )
        defer {
            accepted.processor.stop()
            try? FileManager.default.removeItem(at: accepted.root)
        }
        XCTAssertEqual(
            accepted.processor.state,
            .entitled(.grace, until: try XCTUnwrap(exactGrace.graceExpirationAt))
        )
        let acceptedCache = try await accepted.store.load()
        XCTAssertEqual(acceptedCache?.state, .grace)
        XCTAssertEqual(acceptedCache?.graceExpirationAt, exactGrace.graceExpirationAt)

        let overlongGrace = fact(
            .grace,
            expiration: expiration,
            graceExpiration: expiration.addingTimeInterval(
                StoreKitPaidGraceAuthorityV1.maximumDuration + 1
            )
        )
        XCTAssertFalse(StoreKitPaidGraceAuthorityV1.accepts(overlongGrace))
        let rejected = try await makeStartedProcessor(
            name: "overlong-grace",
            batches: [[], [.verified(.init(fact: overlongGrace))]]
        )
        defer {
            rejected.processor.stop()
            try? FileManager.default.removeItem(at: rejected.root)
        }
        let coordinator = StoreKitLifecycleCoordinator(
            processor: rejected.processor,
            runtime: .init(synchronize: {})
        )
        let restoreAccepted = await coordinator.restorePurchases()
        XCTAssertTrue(restoreAccepted)
        XCTAssertEqual(coordinator.restoreState, .failed)
        XCTAssertEqual(coordinator.lifecycleState, .neverPaid)
        XCTAssertNil(coordinator.latestVerifiedFact)
        let rejectedCache = try await rejected.store.load()
        XCTAssertNil(rejectedCache)

        let cachedRoot = try makeRoot("cached-overlong-grace")
        defer { try? FileManager.default.removeItem(at: cachedRoot) }
        let cachedStore = try EntitlementStore(applicationSupportURL: cachedRoot)
        let cachedOverlong = EntitlementCacheV1(
            productID: EntitlementReducerV1.productID,
            state: .grace,
            expirationAt: expiration,
            graceExpirationAt: expiration.addingTimeInterval(
                StoreKitPaidGraceAuthorityV1.maximumDuration + 1
            ),
            revocationAt: nil,
            verifiedAt: now,
            hasEverVerifiedPaid: true
        )
        _ = try await cachedStore.persist(cachedOverlong)
        let cachedProcessor = StoreKitTransactionProcessor(
            store: cachedStore,
            runtime: runtime(EventSequence([])),
            now: { [now] in now }
        )
        try await cachedProcessor.start()
        await cachedProcessor.waitForInitialRefresh()
        XCTAssertEqual(cachedProcessor.state, .loading)
        XCTAssertTrue(cachedProcessor.isStarted)
        XCTAssertNil(cachedProcessor.latestVerifiedFact)
        let cachedAfter = try await cachedStore.load()
        XCTAssertEqual(cachedAfter, cachedOverlong)
        cachedProcessor.stop()
    }
}

private extension S7_3LifecycleRestoreTests {
    enum ProbeError: Error { case injected }

    actor EventSequence {
        private var batches: [[EntitlementProcessorEventV1]]

        init(_ batches: [[EntitlementProcessorEventV1]]) {
            self.batches = batches
        }

        func next() -> [EntitlementProcessorEventV1] {
            guard !batches.isEmpty else { return [] }
            return batches.removeFirst()
        }
    }

    actor SynchronizeGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var hasEntered = false
        private(set) var callCount = 0

        func wait() async {
            callCount += 1
            hasEntered = true
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    actor SynchronizeCounter {
        private(set) var count = 0
        func record() { count += 1 }
    }

    struct StartedProcessor {
        let root: URL
        let store: EntitlementStore
        let processor: StoreKitTransactionProcessor
    }

    func fact(
        _ state: VerifiedSubscriptionStateV1,
        expiration: Date,
        graceExpiration: Date? = nil,
        trial: Bool = false,
        renews: Bool = true
    ) -> VerifiedEntitlementFactV1 {
        VerifiedEntitlementFactV1(
            productID: EntitlementReducerV1.productID,
            purchaseAt: now.addingTimeInterval(-7_200),
            expirationAt: expiration,
            graceExpirationAt: state == .grace ? graceExpiration : nil,
            revocationAt: state == .refunded || state == .revoked ? now : nil,
            verifiedAt: now,
            state: state,
            isIntroductoryOffer: trial,
            willAutoRenew: renews
        )
    }

    func cache(
        _ state: CachedEntitlementStateV1,
        expiration: Date
    ) -> EntitlementCacheV1 {
        EntitlementCacheV1(
            productID: EntitlementReducerV1.productID,
            state: state,
            expirationAt: expiration,
            graceExpirationAt: nil,
            revocationAt: nil,
            verifiedAt: now,
            hasEverVerifiedPaid: true
        )
    }

    func runtime(
        _ sequence: EventSequence
    ) -> StoreKitEntitlementRuntimeV1 {
        StoreKitEntitlementRuntimeV1(
            initialEvents: { await sequence.next() },
            transactionUpdates: { AsyncStream { $0.finish() } },
            statusUpdates: { AsyncStream { $0.finish() } }
        )
    }

    @MainActor
    func makeStartedProcessor(
        name: String,
        batches: [[EntitlementProcessorEventV1]]
    ) async throws -> StartedProcessor {
        let root = try makeRoot(name)
        let store = try EntitlementStore(applicationSupportURL: root)
        let processor = StoreKitTransactionProcessor(
            store: store,
            runtime: runtime(EventSequence(batches)),
            now: { [now] in now }
        )
        try await processor.start()
        await processor.waitForInitialRefresh()
        return StartedProcessor(root: root, store: store, processor: processor)
    }

    func makeRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "S7_3-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        return root
    }

    @MainActor
    func eventually(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not reached", file: file, line: line)
    }

}

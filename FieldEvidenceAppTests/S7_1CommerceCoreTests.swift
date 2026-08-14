import Foundation
import XCTest
@testable import FieldEvidenceApp

final class S7_1CommerceCoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReducerVerifiedTableSelectionAndOfflineBoundaries() throws {
        let expiry = now.addingTimeInterval(3_600)
        let grace = expiry.addingTimeInterval(16 * 86_400)
        let rows: [(String, VerifiedEntitlementFactV1, EntitlementAccessStateV1)] = [
            ("active", fact(.active, expiration: expiry), .entitled(.active, until: expiry)),
            ("trial", fact(.active, expiration: expiry, trial: true), .entitled(.active, until: expiry)),
            ("auto-renew-off", fact(.active, expiration: expiry, renews: false), .entitled(.active, until: expiry)),
            ("grace", fact(.grace, expiration: expiry, grace: grace), .entitled(.grace, until: grace)),
            ("billing", fact(.billingRetry, expiration: expiry), .formerPaidInactive(reason: .billingRetry)),
            ("expired", fact(.expired, expiration: expiry), .formerPaidInactive(reason: .expired)),
            ("refund", fact(.refunded, expiration: expiry, revocation: now), .formerPaidInactive(reason: .refunded)),
            ("revocation", fact(.revoked, expiration: expiry, revocation: now), .formerPaidInactive(reason: .revoked)),
        ]
        for (name, value, expected) in rows {
            let result = try EntitlementReducerV1.reduce(
                verifiedFacts: [value],
                priorCache: nil,
                now: now
            )
            XCTAssertEqual(result.state, expected, name)
            XCTAssertEqual(result.cache?.hasEverVerifiedPaid, true, name)
        }

        let older = fact(
            .active,
            purchase: now.addingTimeInterval(-7_200),
            expiration: expiry
        )
        let newer = fact(
            .expired,
            purchase: now.addingTimeInterval(-3_600),
            expiration: now.addingTimeInterval(1)
        )
        XCTAssertEqual(
            try EntitlementReducerV1.reduce(
                verifiedFacts: [older, newer],
                priorCache: nil,
                now: now
            ).state,
            .formerPaidInactive(reason: .expired)
        )
        let samePurchase = now.addingTimeInterval(-4_000)
        let shorter = fact(
            .expired,
            purchase: samePurchase,
            expiration: now.addingTimeInterval(100)
        )
        let longer = fact(
            .active,
            purchase: samePurchase,
            expiration: expiry
        )
        XCTAssertEqual(
            try EntitlementReducerV1.reduce(
                verifiedFacts: [shorter, longer],
                priorCache: nil,
                now: now
            ).state,
            .entitled(.active, until: expiry)
        )

        let tiedActive = fact(.active, expiration: expiry)
        let tiedBilling = fact(.billingRetry, expiration: expiry)
        assertThrows(.unresolvedTie) {
            _ = try EntitlementReducerV1.reduce(
                verifiedFacts: [tiedActive, tiedBilling],
                priorCache: nil,
                now: now
            )
        }
        var wrong = fact(.active, expiration: expiry)
        wrong = VerifiedEntitlementFactV1(
            productID: "wrong.product",
            purchaseAt: wrong.purchaseAt,
            expirationAt: wrong.expirationAt,
            verifiedAt: wrong.verifiedAt,
            state: wrong.state
        )
        assertThrows(.wrongProduct) {
            _ = try EntitlementReducerV1.reduce(
                verifiedFacts: [wrong],
                priorCache: nil,
                now: now
            )
        }

        let activeCache = cache(.active, expiration: expiry)
        XCTAssertEqual(
            try EntitlementReducerV1.offlineState(
                cache: activeCache,
                now: expiry.addingTimeInterval(-0.001)
            ),
            .entitled(.active, until: expiry)
        )
        for instant in [expiry, expiry.addingTimeInterval(0.001)] {
            XCTAssertEqual(
                try EntitlementReducerV1.offlineState(
                    cache: activeCache,
                    now: instant
                ),
                .formerPaidInactive(reason: .expired)
            )
        }
        let graceCache = cache(.grace, expiration: expiry, grace: grace)
        XCTAssertEqual(
            try EntitlementReducerV1.offlineState(
                cache: graceCache,
                now: grace.addingTimeInterval(-0.001)
            ),
            .entitled(.grace, until: grace)
        )
        XCTAssertEqual(
            try EntitlementReducerV1.offlineState(cache: graceCache, now: grace),
            .formerPaidInactive(reason: .expired)
        )
        XCTAssertEqual(
            try EntitlementReducerV1.offlineState(cache: nil, now: now),
            .neverPaid
        )
    }

    func testProductContractIsExactMonthlyTrialAndNotShared() throws {
        let valid = StoreKitProductContractV1(
            productID: EntitlementReducerV1.productID,
            kind: .autoRenewableSubscription,
            periodValue: 1,
            periodUnit: .month,
            isFamilyShareable: false,
            introductoryPeriodValue: 2,
            introductoryPeriodUnit: .week,
            introductoryPaymentMode: .freeTrial
        )
        XCTAssertNoThrow(try StoreKitProductLoader.validate(valid))

        let invalid: [StoreKitProductContractV1] = [
            .init(productID: "wrong", kind: valid.kind, periodValue: 1, periodUnit: .month, isFamilyShareable: false, introductoryPeriodValue: 2, introductoryPeriodUnit: .week, introductoryPaymentMode: .freeTrial),
            .init(productID: valid.productID, kind: .other, periodValue: 1, periodUnit: .month, isFamilyShareable: false, introductoryPeriodValue: 2, introductoryPeriodUnit: .week, introductoryPaymentMode: .freeTrial),
            .init(productID: valid.productID, kind: valid.kind, periodValue: 2, periodUnit: .week, isFamilyShareable: false, introductoryPeriodValue: 2, introductoryPeriodUnit: .week, introductoryPaymentMode: .freeTrial),
            .init(productID: valid.productID, kind: valid.kind, periodValue: 1, periodUnit: .month, isFamilyShareable: true, introductoryPeriodValue: 2, introductoryPeriodUnit: .week, introductoryPaymentMode: .freeTrial),
            .init(productID: valid.productID, kind: valid.kind, periodValue: 1, periodUnit: .month, isFamilyShareable: false, introductoryPeriodValue: 14, introductoryPeriodUnit: .day, introductoryPaymentMode: .freeTrial),
        ]
        for value in invalid {
            XCTAssertThrowsError(try StoreKitProductLoader.validate(value)) {
                XCTAssertEqual($0 as? StoreKitProductLoaderError, .invalidProduct)
            }
        }
    }

    @MainActor
    func testStoreCanonicalDurabilityMonotonicityAndFailClosedFamilies() async throws {
        let root = try makeRoot("store")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EntitlementStore(applicationSupportURL: root)
        let first = cache(.active, expiration: now.addingTimeInterval(3_600))
        let persisted = try await store.persist(first)
        let reopened = try await store.load()
        XCTAssertEqual(persisted, first)
        XCTAssertEqual(reopened, first)

        let bytes = try Data(contentsOf: commerce(root, "entitlement.json"))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), Set([
            "expirationAt", "graceExpirationAt", "hasEverVerifiedPaid",
            "productID", "revocationAt", "schemaVersion", "state", "verifiedAt",
        ]))
        XCTAssertEqual(try EntitlementCacheCodecV1.decode(bytes), first)

        let stale = cache(
            .expired,
            expiration: now.addingTimeInterval(1),
            verified: now.addingTimeInterval(-1)
        )
        await assertThrowsStore(.staleCache) { _ = try await store.persist(stale) }
        let forgetsPaid = EntitlementCacheV1(
            productID: EntitlementReducerV1.productID,
            state: .neverPaid,
            expirationAt: nil,
            graceExpirationAt: nil,
            revocationAt: nil,
            verifiedAt: now.addingTimeInterval(1),
            hasEverVerifiedPaid: false
        )
        await assertThrowsStore(.staleCache) {
            _ = try await store.persist(forgetsPaid)
        }
        let afterStale = try await store.load()
        XCTAssertEqual(afterStale, first)

        let malformedRoot = try makeRoot("malformed")
        defer { try? FileManager.default.removeItem(at: malformedRoot) }
        let malformedStore = try EntitlementStore(applicationSupportURL: malformedRoot)
        try Data(#"{"schemaVersion":1}"#.utf8).write(
            to: commerce(malformedRoot, "entitlement.json")
        )
        await assertThrowsStore(.invalidCache) { _ = try await malformedStore.load() }

        let collisionRoot = try makeRoot("collision")
        defer { try? FileManager.default.removeItem(at: collisionRoot) }
        let collisionStore = try EntitlementStore(applicationSupportURL: collisionRoot)
        try Data("collision".utf8).write(to: commerce(collisionRoot, "unexpected.bin"))
        await assertThrowsStore(.collidingAuthority) {
            _ = try await collisionStore.persist(first)
        }

        let failureRoot = try makeRoot("temporary")
        defer { try? FileManager.default.removeItem(at: failureRoot) }
        let failureStore = try EntitlementStore(
            applicationSupportURL: failureRoot,
            failureInjection: { point in
                if point == .afterTemporaryWrite { throw ProbeError.injected }
            }
        )
        await assertThrowsStore(.writeFailed) {
            _ = try await failureStore.persist(first)
        }
        let afterFailure = try await failureStore.load()
        XCTAssertNil(afterFailure)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: commerce(failureRoot).path
            ),
            []
        )
    }

    @MainActor
    func testProcessorObserversIgnoreNonverifiedPersistBeforeFinishAndReplayOnce() async throws {
        let root = try makeRoot("processor")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EntitlementStore(applicationSupportURL: root)
        let transaction = AsyncStream<EntitlementProcessorEventV1>.makeStream()
        let status = AsyncStream<EntitlementProcessorEventV1>.makeStream()
        let runtime = StoreKitEntitlementRuntimeV1(
            initialEvents: { [.pending, .userCancelled, .failed, .unverified] },
            transactionUpdates: { transaction.stream },
            statusUpdates: { status.stream }
        )
        let fixedNow = now
        let processor = StoreKitTransactionProcessor(
            store: store,
            runtime: runtime,
            now: { fixedNow }
        )
        try await processor.start()
        await processor.waitForInitialRefresh()
        XCTAssertEqual(processor.state, .neverPaid)
        let initialCache = try await store.load()
        XCTAssertNil(initialCache)

        let probe = FinishProbe()
        let active = fact(.active, expiration: now.addingTimeInterval(3_600))
        let event = EntitlementProcessorEventV1.verified(.init(
            fact: active,
            transactionID: 71,
            finish: {
                await probe.record(durable: (try? await store.load()) != nil)
            }
        ))
        transaction.continuation.yield(event)
        transaction.continuation.yield(event)
        await eventually { await probe.count == 1 }
        let finishWasDurable = await probe.allDurable
        XCTAssertTrue(finishWasDurable)
        XCTAssertEqual(
            processor.state,
            .entitled(.active, until: try XCTUnwrap(active.expirationAt))
        )

        let expired = fact(
            .expired,
            purchase: now.addingTimeInterval(-1_000),
            expiration: now.addingTimeInterval(1),
            verified: now.addingTimeInterval(10)
        )
        status.continuation.yield(.verified(.init(fact: expired)))
        await eventually {
            processor.state == .formerPaidInactive(reason: .expired)
        }
        let replayFinishCount = await probe.count
        XCTAssertEqual(replayFinishCount, 1)
        processor.stop()
        transaction.continuation.finish()
        status.continuation.finish()
    }

    @MainActor
    func testProcessorWriteFailureDoesNotFinish() async throws {
        let root = try makeRoot("processor-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EntitlementStore(
            applicationSupportURL: root,
            failureInjection: { point in
                if point == .afterTemporaryWrite { throw ProbeError.injected }
            }
        )
        let probe = FinishProbe()
        let value = VerifiedEntitlementProcessorEventV1(
            fact: fact(.active, expiration: now.addingTimeInterval(3_600)),
            transactionID: 72,
            finish: { await probe.record(durable: false) }
        )
        let runtime = StoreKitEntitlementRuntimeV1(
            initialEvents: { [.verified(value)] },
            transactionUpdates: { AsyncStream { $0.finish() } },
            statusUpdates: { AsyncStream { $0.finish() } }
        )
        let fixedNow = now
        let processor = StoreKitTransactionProcessor(
            store: store,
            runtime: runtime,
            now: { fixedNow }
        )
        try await processor.start()
        await processor.waitForInitialRefresh()
        let finishCount = await probe.count
        XCTAssertEqual(finishCount, 0)
        let failedCache = try await store.load()
        XCTAssertNil(failedCache)
        processor.stop()
    }
}

private extension S7_1CommerceCoreTests {
    enum ProbeError: Error { case injected }

    actor FinishProbe {
        private(set) var count = 0
        private(set) var allDurable = true

        func record(durable: Bool) {
            count += 1
            allDurable = allDurable && durable
        }
    }

    func fact(
        _ state: VerifiedSubscriptionStateV1,
        purchase: Date? = nil,
        expiration: Date,
        grace: Date? = nil,
        revocation: Date? = nil,
        verified: Date? = nil,
        trial: Bool = false,
        renews: Bool = true
    ) -> VerifiedEntitlementFactV1 {
        VerifiedEntitlementFactV1(
            productID: EntitlementReducerV1.productID,
            purchaseAt: purchase ?? now.addingTimeInterval(-7_200),
            expirationAt: expiration,
            graceExpirationAt: grace,
            revocationAt: revocation,
            verifiedAt: verified ?? now,
            state: state,
            isIntroductoryOffer: trial,
            willAutoRenew: renews
        )
    }

    func cache(
        _ state: CachedEntitlementStateV1,
        expiration: Date,
        grace: Date? = nil,
        verified: Date? = nil
    ) -> EntitlementCacheV1 {
        EntitlementCacheV1(
            productID: EntitlementReducerV1.productID,
            state: state,
            expirationAt: expiration,
            graceExpirationAt: grace,
            revocationAt: nil,
            verifiedAt: verified ?? now,
            hasEverVerifiedPaid: true
        )
    }

    func makeRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "S7_1-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        return root
    }

    func commerce(_ root: URL, _ leaf: String? = nil) -> URL {
        let directory = root.appendingPathComponent(
            "FieldEvidenceCommerce",
            isDirectory: true
        )
        return leaf.map { directory.appendingPathComponent($0) } ?? directory
    }

    func assertThrows(
        _ expected: EntitlementReductionErrorV1,
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? EntitlementReductionErrorV1, expected)
        }
    }

    func assertThrowsStore(
        _ expected: EntitlementStoreError,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? EntitlementStoreError, expected)
        }
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

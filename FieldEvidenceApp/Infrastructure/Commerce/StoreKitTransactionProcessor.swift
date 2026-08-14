import Foundation
import StoreKit
import Combine

struct VerifiedEntitlementProcessorEventV1: @unchecked Sendable {
    let fact: VerifiedEntitlementFactV1
    let transactionID: UInt64?
    let finish: (@Sendable () async -> Void)?

    init(
        fact: VerifiedEntitlementFactV1,
        transactionID: UInt64? = nil,
        finish: (@Sendable () async -> Void)? = nil
    ) {
        self.fact = fact
        self.transactionID = transactionID
        self.finish = finish
    }
}

enum EntitlementProcessorEventV1: @unchecked Sendable {
    case verified(VerifiedEntitlementProcessorEventV1)
    case pending
    case userCancelled
    case failed
    case unverified
}

struct StoreKitEntitlementRuntimeV1: @unchecked Sendable {
    let initialEvents: @Sendable () async throws
        -> [EntitlementProcessorEventV1]
    let transactionUpdates: @Sendable ()
        -> AsyncStream<EntitlementProcessorEventV1>
    let statusUpdates: @Sendable ()
        -> AsyncStream<EntitlementProcessorEventV1>

    static func live(
        productLoader: StoreKitProductLoader = StoreKitProductLoader()
    ) -> Self {
        Self(
            initialEvents: {
                try await StoreKitRuntimeAdapterV1.initialEvents(
                    productLoader: productLoader
                )
            },
            transactionUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        for await result in Transaction.updates {
                            let event = await StoreKitRuntimeAdapterV1.event(
                                from: result,
                                shouldFinish: true
                            )
                            continuation.yield(event)
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            statusUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        for await status in
                            Product.SubscriptionInfo.Status.updates {
                            continuation.yield(
                                StoreKitRuntimeAdapterV1.event(from: status)
                            )
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }
}

/// Owns exactly one current-fact refresh, one transaction observer, and one
/// subscription-status observer. Verified StoreKit values are reduced and
/// durably reopened before a transaction finisher is invoked.
@MainActor
final class StoreKitTransactionProcessor: ObservableObject {
    @Published private(set) var state: EntitlementAccessStateV1 = .loading

    private let store: EntitlementStore
    private let runtime: StoreKitEntitlementRuntimeV1
    private let now: @Sendable () -> Date

    private var transactionTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var initialRefreshTask: Task<Void, Never>?
    private var finishedTransactionIDs = Set<UInt64>()
    private var inFlightTransactionIDs = Set<UInt64>()
    private(set) var isStarted = false

    init(
        store: EntitlementStore,
        runtime: StoreKitEntitlementRuntimeV1 = .live(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.runtime = runtime
        self.now = now
    }

    deinit {
        transactionTask?.cancel()
        statusTask?.cancel()
        initialRefreshTask?.cancel()
    }

    func start() async throws {
        guard !isStarted else { return }
        let cache = try store.load()
        state = try EntitlementReducerV1.loadingState(
            cache: cache,
            now: now()
        )
        isStarted = true

        let runtime = self.runtime
        transactionTask = Task { [weak self, runtime] in
            for await event in runtime.transactionUpdates() {
                guard !Task.isCancelled else { return }
                await self?.process(event)
            }
        }
        statusTask = Task { [weak self, runtime] in
            for await event in runtime.statusUpdates() {
                guard !Task.isCancelled else { return }
                await self?.process(event)
            }
        }
        initialRefreshTask = Task { [weak self] in
            await self?.refreshInitialFacts()
        }
    }

    func stop() {
        transactionTask?.cancel()
        statusTask?.cancel()
        initialRefreshTask?.cancel()
        transactionTask = nil
        statusTask = nil
        initialRefreshTask = nil
        isStarted = false
    }

    func waitForInitialRefresh() async {
        await initialRefreshTask?.value
    }

    func process(_ event: EntitlementProcessorEventV1) async {
        guard isStarted else { return }
        switch event {
        case let .verified(value):
            await applyVerified([value])
        case .pending, .userCancelled, .failed, .unverified:
            break
        }
    }
}

private extension StoreKitTransactionProcessor {
    func refreshInitialFacts() async {
        do {
            let events = try await runtime.initialEvents()
            guard !Task.isCancelled, isStarted else { return }
            let verified = events.compactMap { event in
                if case let .verified(value) = event { return value }
                return nil
            }
            if verified.isEmpty {
                let cache = try store.load()
                state = try EntitlementReducerV1.offlineState(
                    cache: cache,
                    now: now()
                )
            } else {
                await applyVerified(verified)
            }
        } catch {
            guard !Task.isCancelled, isStarted else { return }
            do {
                let cache = try store.load()
                state = try EntitlementReducerV1.offlineState(
                    cache: cache,
                    now: now()
                )
            } catch {
                state = .loading
            }
        }
    }

    func applyVerified(_ events: [VerifiedEntitlementProcessorEventV1]) async {
        guard !events.isEmpty, isStarted else { return }
        let finishable = events.filter { value in
            guard let transactionID = value.transactionID,
                  value.finish != nil else {
                return false
            }
            return !finishedTransactionIDs.contains(transactionID)
                && !inFlightTransactionIDs.contains(transactionID)
        }
        finishable.compactMap(\.transactionID).forEach {
            inFlightTransactionIDs.insert($0)
        }
        defer {
            finishable.compactMap(\.transactionID).forEach {
                inFlightTransactionIDs.remove($0)
            }
        }

        do {
            let prior = try store.load()
            _ = try EntitlementReducerV1.reduce(
                verifiedFacts: events.map(\.fact),
                priorCache: nil,
                now: now()
            )
            let reduction = try EntitlementReducerV1.reduce(
                verifiedFacts: events.map(\.fact),
                priorCache: prior,
                now: now()
            )
            guard let replacement = reduction.cache else { return }
            let durable = try store.persist(replacement)
            guard durable == replacement else { return }
            state = reduction.state
            await finish(finishable)
        } catch {
            do {
                guard let standalone = try? EntitlementReducerV1.reduce(
                    verifiedFacts: events.map(\.fact),
                    priorCache: nil,
                    now: now()
                ),
                      let standaloneCache = standalone.cache else {
                    return
                }
                guard let durable = try store.load(),
                      durable.hasEverVerifiedPaid,
                      standaloneCache.verifiedAt <= durable.verifiedAt,
                      standaloneCache.verifiedAt < durable.verifiedAt
                        || standaloneCache == durable else {
                    return
                }
                state = try EntitlementReducerV1.offlineState(
                    cache: durable,
                    now: now()
                )
                await finish(finishable)
            } catch {
                return
            }
        }
    }

    func finish(_ events: [VerifiedEntitlementProcessorEventV1]) async {
        for event in events {
            guard let transactionID = event.transactionID,
                  let finish = event.finish,
                  !finishedTransactionIDs.contains(transactionID) else {
                continue
            }
            await finish()
            finishedTransactionIDs.insert(transactionID)
        }
    }
}

private enum StoreKitRuntimeAdapterV1 {
    static func initialEvents(
        productLoader: StoreKitProductLoader
    ) async throws -> [EntitlementProcessorEventV1] {
        let product = try await productLoader.loadMonthlyProduct()
        guard let subscription = product.subscription else {
            throw StoreKitProductLoaderError.invalidProduct
        }

        var values = [EntitlementProcessorEventV1]()
        let statuses = try await subscription.status
        values.append(contentsOf: statuses.map { event(from: $0) })

        for await result in Transaction.currentEntitlements {
            values.append(await event(from: result, shouldFinish: false))
        }
        for await result in Transaction.unfinished {
            values.append(await event(from: result, shouldFinish: true))
        }
        return values
    }

    static func event(
        from result: VerificationResult<Transaction>,
        shouldFinish: Bool
    ) async -> EntitlementProcessorEventV1 {
        guard case let .verified(transaction) = result,
              transaction.productID == EntitlementReducerV1.productID,
              transaction.productType == .autoRenewable,
              transaction.ownershipType == .purchased,
              let status = await transaction.subscriptionStatus,
              let fact = fact(from: status) else {
            return .unverified
        }
        return .verified(VerifiedEntitlementProcessorEventV1(
            fact: fact,
            transactionID: shouldFinish ? transaction.id : nil,
            finish: shouldFinish ? { await transaction.finish() } : nil
        ))
    }

    static func event(
        from status: Product.SubscriptionInfo.Status
    ) -> EntitlementProcessorEventV1 {
        guard let fact = fact(from: status) else { return .unverified }
        return .verified(VerifiedEntitlementProcessorEventV1(fact: fact))
    }

    static func fact(
        from status: Product.SubscriptionInfo.Status
    ) -> VerifiedEntitlementFactV1? {
        guard case let .verified(transaction) = status.transaction,
              case let .verified(renewal) = status.renewalInfo,
              status.state == renewal.state,
              transaction.productID == EntitlementReducerV1.productID,
              renewal.currentProductID == EntitlementReducerV1.productID,
              transaction.productType == .autoRenewable,
              transaction.ownershipType == .purchased else {
            return nil
        }

        let state: VerifiedSubscriptionStateV1
        let graceExpirationAt: Date?
        let revocationAt: Date?
        if status.state == .subscribed {
            state = .active
            graceExpirationAt = nil
            revocationAt = nil
        } else if status.state == .inGracePeriod {
            state = .grace
            graceExpirationAt = renewal.gracePeriodExpirationDate
            revocationAt = nil
        } else if status.state == .inBillingRetryPeriod {
            state = .billingRetry
            graceExpirationAt = nil
            revocationAt = nil
        } else if status.state == .expired {
            state = .expired
            graceExpirationAt = nil
            revocationAt = nil
        } else if status.state == .revoked,
                  let date = transaction.revocationDate {
            let type = transaction.revocationType
            state = type == .fullRefund || type == .proratedRefund
                ? .refunded
                : .revoked
            graceExpirationAt = nil
            revocationAt = date
        } else {
            return nil
        }

        return VerifiedEntitlementFactV1(
            productID: transaction.productID,
            purchaseAt: transaction.purchaseDate,
            expirationAt: transaction.expirationDate,
            graceExpirationAt: graceExpirationAt,
            revocationAt: revocationAt,
            verifiedAt: max(transaction.signedDate, renewal.signedDate),
            state: state,
            isIntroductoryOffer: transaction.offer?.type == .introductory,
            willAutoRenew: renewal.willAutoRenew
        )
    }
}

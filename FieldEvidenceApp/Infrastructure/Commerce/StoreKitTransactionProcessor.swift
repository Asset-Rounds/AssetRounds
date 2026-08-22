import Foundation
import StoreKit
import Combine

#if DEBUG
enum S10_4StoreKitPurchaseDiagnosticGate {
    static let launchArgument = "--s10-4-storekit-purchase-diagnostic"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

enum S10_4StoreKitPurchaseDiagnosticReasonV1: String, CaseIterable, Sendable {
    case missingPurchaseReservation
    case completionProductMismatch
    case purchaseVerificationUnverified
    case transactionProductIDMismatch
    case transactionProductTypeMismatch
    case transactionOwnershipMismatch
    case subscriptionStatusUnavailable
    case statusTransactionUnverified
    case statusRenewalInfoUnverified
    case statusTransactionProductIDMismatch
    case statusRenewalProductIDMismatch
    case statusTransactionProductTypeMismatch
    case statusTransactionOwnershipMismatch
    case statusRevokedWithoutRevocationDate
    case statusUnsupportedState
    case paidGraceAuthorityRejected
    case processorUnverifiedWithoutReason
}

enum S10_4StoreKitVerificationErrorV1: String, CaseIterable, Sendable {
    case invalidCertificateChain
    case invalidDeviceVerification
    case invalidEncoding
    case invalidSignature
    case missingRequiredProperties
    case revokedCertificate
    case unknown

    static func normalized<SignedType>(
        _ error: VerificationResult<SignedType>.VerificationError
    ) -> Self {
        switch error {
        case .invalidCertificateChain:
            return .invalidCertificateChain
        case .invalidDeviceVerification:
            return .invalidDeviceVerification
        case .invalidEncoding:
            return .invalidEncoding
        case .invalidSignature:
            return .invalidSignature
        case .missingRequiredProperties:
            return .missingRequiredProperties
        case .revokedCertificate:
            return .revokedCertificate
        @unknown default:
            return .unknown
        }
    }
}

struct S10_4StoreKitProcessorFailureV1: Equatable, Sendable {
    let reason: S10_4StoreKitPurchaseDiagnosticReasonV1
    let verificationError: S10_4StoreKitVerificationErrorV1?
}

fileprivate struct S10_4StoreKitVerifiedEventDiagnosticResolutionV1: Sendable {
    let event: VerifiedEntitlementProcessorEventV1?
    let failure: S10_4StoreKitProcessorFailureV1?
}

fileprivate struct S10_4StoreKitFactDiagnosticResolutionV1: Sendable {
    let fact: VerifiedEntitlementFactV1?
    let failure: S10_4StoreKitProcessorFailureV1?
}
#endif

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

enum StoreKitPaidGraceAuthorityV1 {
    static let maximumDuration: TimeInterval = 16 * 24 * 60 * 60

    static func accepts(_ fact: VerifiedEntitlementFactV1) -> Bool {
        guard fact.state == .grace else { return true }
        guard !fact.isIntroductoryOffer,
              let expirationAt = fact.expirationAt,
              let graceExpirationAt = fact.graceExpirationAt else {
            return false
        }
        let duration = graceExpirationAt.timeIntervalSince(expirationAt)
        return duration > 0 && duration <= maximumDuration
    }

    static func accepts(_ cache: EntitlementCacheV1?) -> Bool {
        guard let cache, cache.state == .grace else { return true }
        guard let expirationAt = cache.expirationAt,
              let graceExpirationAt = cache.graceExpirationAt else {
            return false
        }
        let duration = graceExpirationAt.timeIntervalSince(expirationAt)
        return duration > 0 && duration <= maximumDuration
    }
}

enum EntitlementProcessorEventV1: @unchecked Sendable {
    case verified(VerifiedEntitlementProcessorEventV1)
    case pending
    case userCancelled
    case failed
    case unverified
}

enum StoreKitVerifiedPurchaseProcessingResultV1: Equatable, Sendable {
    case verified
    case unverified
    case failed
}

enum StoreKitEntitlementRefreshResultV1: Equatable, Sendable {
    case verified
    case noVerifiedCurrentEntitlement
    case unverified
    case failed
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
    @Published private(set) var latestVerifiedFact: VerifiedEntitlementFactV1?
    @Published private(set) var draftAccessState: DraftAccessNormalizedStateV1 =
        .loading(.priorPaidWithoutValidCache)

    private let store: EntitlementStore
    private let runtime: StoreKitEntitlementRuntimeV1
    private let now: @Sendable () -> Date

    private var transactionTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var initialRefreshTask: Task<Void, Never>?
    private var finishedTransactionIDs = Set<UInt64>()
    private var inFlightTransactionIDs = Set<UInt64>()
    private(set) var isStarted = false
#if DEBUG
    private(set) var firstPurchaseDiagnosticFailure:
        S10_4StoreKitProcessorFailureV1?
#endif

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
        do {
            let cache = try store.load()
            if StoreKitPaidGraceAuthorityV1.accepts(cache) {
                state = try EntitlementReducerV1.loadingState(
                    cache: cache,
                    now: now()
                )
                if cache == nil {
                    draftAccessState = .loading(.neverPaidWithoutCache)
                } else if case .entitled = state {
                    draftAccessState = .loading(.validCachedEntitlement)
                } else {
                    publishDraftAccessState(from: state)
                }
            } else {
                state = .loading
                draftAccessState = .loading(.priorPaidWithoutValidCache)
            }
        } catch {
            state = .loading
            draftAccessState = .loading(.priorPaidWithoutValidCache)
        }
        latestVerifiedFact = nil
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
            _ = await self?.refreshCurrentFacts()
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
            _ = await applyVerified([value])
        case .pending, .userCancelled, .failed, .unverified:
            break
        }
    }

    func processPurchasedTransaction(
        _ transaction: Transaction
    ) async -> StoreKitVerifiedPurchaseProcessingResultV1 {
        guard isStarted else { return .failed }
#if DEBUG
        if S10_4StoreKitPurchaseDiagnosticGate.isEnabled {
            let resolution = await StoreKitRuntimeAdapterV1
                .purchaseDiagnosticVerifiedEvent(
                    from: transaction,
                    shouldFinish: true
                )
            if let failure = resolution.failure {
                recordPurchaseDiagnosticFailure(failure)
            }
            guard let event = resolution.event else {
                return .unverified
            }
            return await applyVerified([event]) ? .verified : .failed
        }
#endif
        guard let event = await StoreKitRuntimeAdapterV1.verifiedEvent(
            from: transaction,
            shouldFinish: true
        ) else {
            return .unverified
        }
        return await applyVerified([event]) ? .verified : .failed
    }

#if DEBUG
    func resetPurchaseDiagnosticFailure() {
        guard S10_4StoreKitPurchaseDiagnosticGate.isEnabled else { return }
        firstPurchaseDiagnosticFailure = nil
    }

    private func recordPurchaseDiagnosticFailure(
        _ failure: S10_4StoreKitProcessorFailureV1
    ) {
        guard S10_4StoreKitPurchaseDiagnosticGate.isEnabled,
              firstPurchaseDiagnosticFailure == nil else {
            return
        }
        firstPurchaseDiagnosticFailure = failure
    }
#endif

    /// Refreshes ordinary verified StoreKit authority without invoking
    /// `AppStore.sync()`. Explicit restore owns that user-initiated call and
    /// then invokes this same durable processing path.
    func refreshCurrentFacts() async -> StoreKitEntitlementRefreshResultV1 {
        guard isStarted else { return .failed }
        do {
            let events = try await runtime.initialEvents()
            guard !Task.isCancelled, isStarted else { return .failed }
            let verified = events.compactMap { event in
                if case let .verified(value) = event { return value }
                return nil
            }
            if verified.isEmpty {
                let sawUnverified = events.contains { event in
                    if case .unverified = event { return true }
                    return false
                }
                let cache = try store.load()
                guard StoreKitPaidGraceAuthorityV1.accepts(cache) else {
                    state = .loading
                    latestVerifiedFact = nil
                    draftAccessState = .loading(.priorPaidWithoutValidCache)
                    return .failed
                }
                state = try EntitlementReducerV1.offlineState(
                    cache: cache,
                    now: now()
                )
                publishDraftAccessState(from: state)
                latestVerifiedFact = nil
                return sawUnverified
                    ? .unverified
                    : .noVerifiedCurrentEntitlement
            }
            return await applyVerified(verified) ? .verified : .failed
        } catch {
            guard !Task.isCancelled, isStarted else { return .failed }
            do {
                let cache = try store.load()
                guard StoreKitPaidGraceAuthorityV1.accepts(cache) else {
                    throw EntitlementReductionErrorV1.invalidCache
                }
                state = try EntitlementReducerV1.offlineState(
                    cache: cache,
                    now: now()
                )
                publishDraftAccessState(from: state)
            } catch {
                state = .loading
                draftAccessState = .loading(.priorPaidWithoutValidCache)
            }
            latestVerifiedFact = nil
            return .failed
        }
    }
}

private extension StoreKitTransactionProcessor {
    func applyVerified(
        _ events: [VerifiedEntitlementProcessorEventV1]
    ) async -> Bool {
        guard !events.isEmpty,
              isStarted,
              events.allSatisfy({ StoreKitPaidGraceAuthorityV1.accepts($0.fact) }) else {
            return false
        }
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
            guard StoreKitPaidGraceAuthorityV1.accepts(prior) else {
                return false
            }
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
            guard let replacement = reduction.cache else { return false }
            let durable = try store.persist(replacement)
            guard durable == replacement else { return false }
            state = reduction.state
            publishDraftAccessState(from: state)
            latestVerifiedFact = selectedFact(
                in: events.map(\.fact),
                matching: replacement
            )
            await finish(finishable)
            return true
        } catch {
            do {
                guard let standalone = try? EntitlementReducerV1.reduce(
                    verifiedFacts: events.map(\.fact),
                    priorCache: nil,
                    now: now()
                ),
                      let standaloneCache = standalone.cache else {
                    return false
                }
                guard let durable = try store.load(),
                      StoreKitPaidGraceAuthorityV1.accepts(durable),
                      durable.hasEverVerifiedPaid,
                      standaloneCache.verifiedAt <= durable.verifiedAt,
                      standaloneCache.verifiedAt < durable.verifiedAt
                        || standaloneCache == durable else {
                    return false
                }
                state = try EntitlementReducerV1.offlineState(
                    cache: durable,
                    now: now()
                )
                publishDraftAccessState(from: state)
                latestVerifiedFact = standaloneCache == durable
                    ? selectedFact(
                        in: events.map(\.fact),
                        matching: standaloneCache
                    )
                    : nil
                await finish(finishable)
                return true
            } catch {
                return false
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

    func selectedFact(
        in facts: [VerifiedEntitlementFactV1],
        matching cache: EntitlementCacheV1
    ) -> VerifiedEntitlementFactV1? {
        facts.sorted {
            if $0.purchaseAt != $1.purchaseAt {
                return $0.purchaseAt > $1.purchaseAt
            }
            return ($0.expirationAt ?? .distantPast)
                > ($1.expirationAt ?? .distantPast)
        }.first { $0.verifiedAt == cache.verifiedAt }
    }

    func publishDraftAccessState(from state: EntitlementAccessStateV1) {
        switch state {
        case .loading:
            draftAccessState = .loading(.priorPaidWithoutValidCache)
        case .entitled:
            draftAccessState = .entitled
        case .neverPaid:
            draftAccessState = .neverPaid
        case .formerPaidInactive:
            draftAccessState = .formerPaidInactive
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
              let event = await verifiedEvent(
                from: transaction,
                shouldFinish: shouldFinish
              ) else {
            return .unverified
        }
        return .verified(event)
    }

    static func verifiedEvent(
        from transaction: Transaction,
        shouldFinish: Bool
    ) async -> VerifiedEntitlementProcessorEventV1? {
        guard transaction.productID == EntitlementReducerV1.productID,
              transaction.productType == .autoRenewable,
              transaction.ownershipType == .purchased,
              let status = await transaction.subscriptionStatus,
              let fact = fact(from: status) else {
            return nil
        }
        let finish: (@Sendable () async -> Void)?
        if shouldFinish {
            finish = { await transaction.finish() }
        } else {
            finish = nil
        }
        return VerifiedEntitlementProcessorEventV1(
            fact: fact,
            transactionID: shouldFinish ? transaction.id : nil,
            finish: finish
        )
    }

#if DEBUG
    fileprivate static func purchaseDiagnosticVerifiedEvent(
        from transaction: Transaction,
        shouldFinish: Bool
    ) async -> S10_4StoreKitVerifiedEventDiagnosticResolutionV1 {
        guard transaction.productID == EntitlementReducerV1.productID else {
            return .init(
                event: nil,
                failure: .init(
                    reason: .transactionProductIDMismatch,
                    verificationError: nil
                )
            )
        }
        guard transaction.productType == .autoRenewable else {
            return .init(
                event: nil,
                failure: .init(
                    reason: .transactionProductTypeMismatch,
                    verificationError: nil
                )
            )
        }
        guard transaction.ownershipType == .purchased else {
            return .init(
                event: nil,
                failure: .init(
                    reason: .transactionOwnershipMismatch,
                    verificationError: nil
                )
            )
        }
        guard let status = await transaction.subscriptionStatus else {
            return .init(
                event: nil,
                failure: .init(
                    reason: .subscriptionStatusUnavailable,
                    verificationError: nil
                )
            )
        }
        let factResolution = purchaseDiagnosticFact(from: status)
        guard let fact = factResolution.fact else {
            return .init(event: nil, failure: factResolution.failure)
        }
        let finish: (@Sendable () async -> Void)?
        if shouldFinish {
            finish = { await transaction.finish() }
        } else {
            finish = nil
        }
        return .init(
            event: VerifiedEntitlementProcessorEventV1(
                fact: fact,
                transactionID: shouldFinish ? transaction.id : nil,
                finish: finish
            ),
            failure: nil
        )
    }

    fileprivate static func purchaseDiagnosticFact(
        from status: Product.SubscriptionInfo.Status
    ) -> S10_4StoreKitFactDiagnosticResolutionV1 {
        let transaction: Transaction
        switch status.transaction {
        case let .verified(value):
            transaction = value
        case let .unverified(_, error):
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusTransactionUnverified,
                    verificationError: .normalized(error)
                )
            )
        @unknown default:
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusTransactionUnverified,
                    verificationError: .unknown
                )
            )
        }

        let renewal: Product.SubscriptionInfo.RenewalInfo
        switch status.renewalInfo {
        case let .verified(value):
            renewal = value
        case let .unverified(_, error):
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusRenewalInfoUnverified,
                    verificationError: .normalized(error)
                )
            )
        @unknown default:
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusRenewalInfoUnverified,
                    verificationError: .unknown
                )
            )
        }

        guard transaction.productID == EntitlementReducerV1.productID else {
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusTransactionProductIDMismatch,
                    verificationError: nil
                )
            )
        }
        guard renewal.currentProductID == EntitlementReducerV1.productID else {
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusRenewalProductIDMismatch,
                    verificationError: nil
                )
            )
        }
        guard transaction.productType == .autoRenewable else {
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusTransactionProductTypeMismatch,
                    verificationError: nil
                )
            )
        }
        guard transaction.ownershipType == .purchased else {
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusTransactionOwnershipMismatch,
                    verificationError: nil
                )
            )
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
        } else if status.state == .revoked {
            guard let date = transaction.revocationDate else {
                return .init(
                    fact: nil,
                    failure: .init(
                        reason: .statusRevokedWithoutRevocationDate,
                        verificationError: nil
                    )
                )
            }
            state = transaction.revocationReason == nil
                ? .revoked
                : .refunded
            graceExpirationAt = nil
            revocationAt = date
        } else {
            return .init(
                fact: nil,
                failure: .init(
                    reason: .statusUnsupportedState,
                    verificationError: nil
                )
            )
        }

        let fact = VerifiedEntitlementFactV1(
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
        guard StoreKitPaidGraceAuthorityV1.accepts(fact) else {
            return .init(
                fact: nil,
                failure: .init(
                    reason: .paidGraceAuthorityRejected,
                    verificationError: nil
                )
            )
        }
        return .init(fact: fact, failure: nil)
    }
#endif

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
            state = transaction.revocationReason == nil
                ? .revoked
                : .refunded
            graceExpirationAt = nil
            revocationAt = date
        } else {
            return nil
        }

        let fact = VerifiedEntitlementFactV1(
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
        return StoreKitPaidGraceAuthorityV1.accepts(fact) ? fact : nil
    }
}

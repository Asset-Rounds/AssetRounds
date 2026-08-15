import Combine
import Foundation
import StoreKit

enum SubscriptionLifecycleStateV1: Equatable, Sendable {
    case loading
    case neverPaid
    case active(until: Date)
    case grace(until: Date)
    case inactive(reason: EntitlementInactiveReasonV1)
}

enum StoreKitRestoreStateV1: Equatable, Sendable {
    case idle
    case restoring
    case restored
    case noCurrentEntitlement
    case unverified
    case failed
}

/// Injectable boundary around the one explicit App Store synchronization.
/// Constructing this value has no StoreKit side effects; `synchronize` is
/// invoked only after the user-selected route reaches `restorePurchases()`.
struct StoreKitRestoreRuntimeV1: @unchecked Sendable {
    let synchronize: @MainActor () async throws -> Void

    init(
        synchronize: @escaping @MainActor () async throws -> Void
    ) {
        self.synchronize = synchronize
    }

    static let live = StoreKitRestoreRuntimeV1 {
        try await AppStore.sync()
    }
}

/// Shared Welcome/Settings lifecycle authority. It presents normalized reducer
/// truth and serializes explicit restore requests without owning persistence.
@MainActor
final class StoreKitLifecycleCoordinator: ObservableObject {
    @Published private(set) var lifecycleState: SubscriptionLifecycleStateV1
    @Published private(set) var latestVerifiedFact: VerifiedEntitlementFactV1?
    @Published private(set) var restoreState: StoreKitRestoreStateV1 = .idle
    @Published private(set) var isRestoring = false

    private let processor: StoreKitTransactionProcessor?
    private let runtime: StoreKitRestoreRuntimeV1
    private var stateObservation: AnyCancellable?
    private var factObservation: AnyCancellable?

    init(
        processor: StoreKitTransactionProcessor?,
        runtime: StoreKitRestoreRuntimeV1 = .live
    ) {
        self.processor = processor
        self.runtime = runtime
        lifecycleState = Self.lifecycleState(
            from: processor?.state ?? .loading
        )
        latestVerifiedFact = processor?.latestVerifiedFact
        stateObservation = processor?.$state.sink { [weak self] state in
            self?.lifecycleState = Self.lifecycleState(from: state)
        }
        factObservation = processor?.$latestVerifiedFact.sink {
            [weak self] fact in
            self?.latestVerifiedFact = fact
        }
    }

    /// Returns false only when another explicit restore already owns the lock.
    /// Every accepted call releases the lock after publishing one honest result.
    @discardableResult
    func restorePurchases() async -> Bool {
        guard !isRestoring else { return false }
        isRestoring = true
        restoreState = .restoring
        defer { isRestoring = false }

        guard let processor else {
            restoreState = .failed
            return true
        }
        do {
            try await runtime.synchronize()
        } catch {
            restoreState = .failed
            return true
        }
        switch await processor.refreshCurrentFacts() {
        case .verified:
            restoreState = .restored
        case .noVerifiedCurrentEntitlement:
            restoreState = .noCurrentEntitlement
        case .unverified:
            restoreState = .unverified
        case .failed:
            restoreState = .failed
        }
        return true
    }

    func clearRestoreResult() {
        guard !isRestoring else { return }
        restoreState = .idle
    }

    private static func lifecycleState(
        from state: EntitlementAccessStateV1
    ) -> SubscriptionLifecycleStateV1 {
        switch state {
        case .loading:
            return .loading
        case .neverPaid:
            return .neverPaid
        case let .entitled(.active, until):
            return .active(until: until)
        case let .entitled(.grace, until):
            return .grace(until: until)
        case let .formerPaidInactive(reason):
            return .inactive(reason: reason)
        }
    }
}

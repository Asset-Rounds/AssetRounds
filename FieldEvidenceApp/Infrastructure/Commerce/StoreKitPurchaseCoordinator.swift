import Foundation
import StoreKit
import Combine

struct PaywallProductPresentationV1: Equatable, Sendable {
    let productID: String
    let displayName: String
    let displayPrice: String
    let subscriptionDuration: String
    let isEligibleForIntroOffer: Bool

    var isValid: Bool {
        productID == EntitlementReducerV1.productID
            && Self.validLocalizedText(displayName)
            && Self.validLocalizedText(displayPrice)
            && Self.validLocalizedText(subscriptionDuration)
    }

    private static func validLocalizedText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PaywallCatalogLinksV1: Equatable, Sendable {
    let terms: URL
    let privacy: URL
    let support: URL

    init?(terms: URL?, privacy: URL?, support: URL?) {
        guard let terms,
              let privacy,
              let support,
              Self.valid(terms, path: "/terms"),
              Self.valid(privacy, path: "/privacy"),
              Self.valid(support, path: "/support") else {
            return nil
        }
        self.terms = terms
        self.privacy = privacy
        self.support = support
    }

    static let uiTestFixture = PaywallCatalogLinksV1(
        terms: URL(string: "https://example.invalid/terms"),
        privacy: URL(string: "https://example.invalid/privacy"),
        support: URL(string: "https://example.invalid/support")
    )!

    private static func valid(_ url: URL, path: String) -> Bool {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return false
        }
        return components.scheme == "https"
            && components.host == "example.invalid"
            && components.path == path
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
    }
}

enum PaywallProductLoadStateV1: Equatable, Sendable {
    case loading
    case available
    case unavailable
}

enum PaywallPurchaseStateV1: Equatable, Sendable {
    case idle
    case purchasing
    case verified
    case cancelled
    case pending
    case unverified
    case failed

    var recoveryMessage: String? {
        switch self {
        case .cancelled:
            return "Purchase canceled. Nothing changed. You can try again when you’re ready."
        case .pending:
            return "Purchase pending. Your existing data is still available. Access will update when the App Store completes the purchase."
        case .unverified:
            return "Purchase couldn’t be verified. Your existing data is still available. Try again."
        case .failed:
            return "Purchase couldn’t be completed. Your existing data is still available. Try again."
        case .idle, .purchasing, .verified:
            return nil
        }
    }
}

@MainActor
enum PaywallPurchaseAttemptV1 {
    case verified(
        @MainActor () async -> StoreKitVerifiedPurchaseProcessingResultV1
    )
    case cancelled
    case pending
    case unverified
    case failed
}

@MainActor
final class StoreKitPurchaseCoordinator: ObservableObject {
    private struct PurchaseReservation: Equatable {
        let id: UUID
        let productID: String
    }

    private static let purchasePresentationDelayNanoseconds: UInt64 = 500_000_000

    typealias PresentationLoader = @MainActor () async throws
        -> PaywallProductPresentationV1
    typealias VerifiedTransactionProcessor = @MainActor (Transaction) async
        -> StoreKitVerifiedPurchaseProcessingResultV1

    @Published private(set) var loadState: PaywallProductLoadStateV1 = .loading
    @Published private(set) var productPresentation: PaywallProductPresentationV1?
    @Published private(set) var purchaseState: PaywallPurchaseStateV1 = .idle
    @Published private(set) var isPurchasing = false
#if DEBUG
    @Published private(set) var s10_4StoreKitPurchaseDiagnosticJSON: String?
#endif

    let catalogLinks: PaywallCatalogLinksV1?

    private let diagnosticsStore: DiagnosticsStore
    private let presentationLoader: PresentationLoader
    private let verifiedTransactionProcessor: VerifiedTransactionProcessor
    private let hasInstalledProcessor: Bool
#if DEBUG
    private let verifiedTransactionDiagnosticProvider:
        @MainActor () -> S10_4StoreKitProcessorFailureV1?
    private let verifiedTransactionDiagnosticReset: @MainActor () -> Void
#endif

    private var presentationTokens = Set<UUID>()
    private var isLoading = false
    private var purchaseReservation: PurchaseReservation?
    private var purchaseStatePublicationTask: Task<Void, Never>?

    init(
        processor: StoreKitTransactionProcessor?,
        diagnosticsStore: DiagnosticsStore,
        productLoader: StoreKitProductLoader = StoreKitProductLoader(),
        catalogLinks: PaywallCatalogLinksV1?
    ) {
        self.diagnosticsStore = diagnosticsStore
        self.catalogLinks = catalogLinks
        self.hasInstalledProcessor = processor != nil
        self.presentationLoader = {
            try await productLoader.loadMonthlyPresentation()
        }
        self.verifiedTransactionProcessor = { transaction in
            guard let processor else { return .failed }
            return await processor.processPurchasedTransaction(transaction)
        }
#if DEBUG
        self.verifiedTransactionDiagnosticProvider = {
            processor?.firstPurchaseDiagnosticFailure
        }
        self.verifiedTransactionDiagnosticReset = {
            processor?.resetPurchaseDiagnosticFailure()
        }
#endif
    }

    init(
        diagnosticsStore: DiagnosticsStore,
        catalogLinks: PaywallCatalogLinksV1?,
        presentationLoader: @escaping PresentationLoader,
        hasInstalledProcessor: Bool = true,
        verifiedTransactionProcessor: @escaping VerifiedTransactionProcessor = {
            _ in .failed
        }
    ) {
        self.diagnosticsStore = diagnosticsStore
        self.catalogLinks = catalogLinks
        self.presentationLoader = presentationLoader
        self.hasInstalledProcessor = hasInstalledProcessor
        self.verifiedTransactionProcessor = verifiedTransactionProcessor
#if DEBUG
        self.verifiedTransactionDiagnosticProvider = { nil }
        self.verifiedTransactionDiagnosticReset = {}
#endif
    }

    func present(token: UUID) async {
        guard presentationTokens.insert(token).inserted else { return }
        await diagnosticsStore.increment(.paywallPresented)
        purchaseState = .idle
        isPurchasing = false
        clearPurchaseReservation()
        await reloadProduct()
    }

    func retryProductLoad() async {
        clearPurchaseReservation()
        isPurchasing = false
        purchaseState = .idle
        await reloadProduct()
    }

    @discardableResult
    func purchaseStarted(productID: String) -> Bool {
        guard let reservation = reservePurchase(productID: productID) else {
            return false
        }
        publishPurchasing(for: reservation)
        return true
    }

    @discardableResult
    func storeKitPurchaseStarted(productID: String) -> Bool {
#if DEBUG
        if S10_4StoreKitPurchaseDiagnosticGate.isEnabled {
            s10_4StoreKitPurchaseDiagnosticJSON = nil
            verifiedTransactionDiagnosticReset()
        }
#endif
        guard let reservation = reservePurchase(productID: productID) else {
            return false
        }
        purchaseStatePublicationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: Self.purchasePresentationDelayNanoseconds
                )
            } catch {
                return
            }
            self?.publishPurchasing(for: reservation)
        }
        return true
    }

    private func reservePurchase(productID: String) -> PurchaseReservation? {
        guard productID == EntitlementReducerV1.productID,
              loadState == .available,
              productPresentation?.productID == productID,
              catalogLinks != nil,
              hasInstalledProcessor,
              purchaseReservation == nil,
              !isPurchasing else {
            return nil
        }
        let reservation = PurchaseReservation(id: UUID(), productID: productID)
        purchaseReservation = reservation
        return reservation
    }

    private func publishPurchasing(for reservation: PurchaseReservation) {
        guard purchaseReservation == reservation else { return }
        purchaseStatePublicationTask = nil
        purchaseState = .purchasing
        isPurchasing = true
    }

    func handleStoreKitCompletion(
        productID: String,
        result: Result<Product.PurchaseResult, any Error>
    ) async {
#if DEBUG
        if S10_4StoreKitPurchaseDiagnosticGate.isEnabled {
            if purchaseReservation == nil {
                publishS10_4StoreKitPurchaseDiagnostic(
                    terminalState: "unverified",
                    stage: "purchaseCompletion",
                    reason: .missingPurchaseReservation,
                    callbackProductID: productID
                )
            } else if purchaseReservation?.productID != productID {
                publishS10_4StoreKitPurchaseDiagnostic(
                    terminalState: "unverified",
                    stage: "purchaseCompletion",
                    reason: .completionProductMismatch,
                    callbackProductID: productID
                )
            }
        }
#endif
        guard let purchaseReservation,
              purchaseReservation.productID == productID else {
            await complete(.unverified)
            return
        }
        switch result {
        case .failure:
#if DEBUG
            publishS10_4StoreKitPurchaseDiagnostic(
                terminalState: "failed",
                stage: "purchaseCompletion",
                callbackProductID: productID
            )
#endif
            await complete(.failed)
        case let .success(purchaseResult):
            switch purchaseResult {
            case .userCancelled:
#if DEBUG
                publishS10_4StoreKitPurchaseDiagnostic(
                    terminalState: "cancelled",
                    stage: "purchaseCompletion",
                    callbackProductID: productID
                )
#endif
                await complete(.cancelled)
            case .pending:
#if DEBUG
                publishS10_4StoreKitPurchaseDiagnostic(
                    terminalState: "pending",
                    stage: "purchaseCompletion",
                    callbackProductID: productID
                )
#endif
                await complete(.pending)
            case let .success(verification):
                switch verification {
                case let .unverified(_, error):
#if DEBUG
                    publishS10_4StoreKitPurchaseDiagnostic(
                        terminalState: "unverified",
                        stage: "purchaseVerification",
                        reason: .purchaseVerificationUnverified,
                        verificationError: .normalized(error),
                        callbackProductID: productID
                    )
#endif
                    await complete(.unverified)
                case let .verified(transaction):
                    let processor = verifiedTransactionProcessor
                    await complete(.verified {
                        let processingResult = await processor(transaction)
#if DEBUG
                        switch processingResult {
                        case .verified:
                            self.publishS10_4StoreKitPurchaseDiagnostic(
                                terminalState: "verified",
                                stage: "transactionProcessor",
                                callbackProductID: productID
                            )
                        case .failed:
                            self.publishS10_4StoreKitPurchaseDiagnostic(
                                terminalState: "failed",
                                stage: "transactionProcessor",
                                callbackProductID: productID
                            )
                        case .unverified:
                            let failure = self
                                .verifiedTransactionDiagnosticProvider()
                                ?? S10_4StoreKitProcessorFailureV1(
                                    reason: .processorUnverifiedWithoutReason,
                                    verificationError: nil
                                )
                            self.publishS10_4StoreKitPurchaseDiagnostic(
                                terminalState: "unverified",
                                stage: "transactionProcessor",
                                reason: failure.reason,
                                verificationError: failure.verificationError,
                                callbackProductID: productID
                            )
                        }
#endif
                        return processingResult
                    })
                }
            @unknown default:
#if DEBUG
                publishS10_4StoreKitPurchaseDiagnostic(
                    terminalState: "failed",
                    stage: "purchaseCompletion",
                    callbackProductID: productID
                )
#endif
                await complete(.failed)
            }
        }
    }

    func complete(_ result: PaywallPurchaseAttemptV1) async {
        guard purchaseReservation != nil else { return }
        clearPurchaseReservation()

        if case .verified = result {
            purchaseState = .purchasing
            isPurchasing = true
        }

        let state: PaywallPurchaseStateV1
        let diagnostic: PurchaseResult
        switch result {
        case .cancelled:
            state = .cancelled
            diagnostic = .cancelled
        case .pending:
            state = .pending
            diagnostic = .pending
        case .unverified:
            state = .unverified
            diagnostic = .unverified
        case .failed:
            state = .failed
            diagnostic = .failed
        case let .verified(process):
            switch await process() {
            case .verified:
                state = .verified
                diagnostic = .verified
            case .unverified:
                state = .unverified
                diagnostic = .unverified
            case .failed:
                state = .failed
                diagnostic = .failed
            }
        }

        purchaseState = state
        isPurchasing = false
        await diagnosticsStore.incrementPurchaseResult(diagnostic)
    }

    private func clearPurchaseReservation() {
        purchaseStatePublicationTask?.cancel()
        purchaseStatePublicationTask = nil
        purchaseReservation = nil
    }

#if DEBUG
    private func publishS10_4StoreKitPurchaseDiagnostic(
        terminalState: String,
        stage: String,
        reason: S10_4StoreKitPurchaseDiagnosticReasonV1? = nil,
        verificationError: S10_4StoreKitVerificationErrorV1? = nil,
        callbackProductID: String
    ) {
        guard S10_4StoreKitPurchaseDiagnosticGate.isEnabled else { return }
        var object: [String: Any] = [
            "schemaVersion": 1,
            "terminalState": terminalState,
            "stage": stage,
            "callbackProductID": callbackProductID,
        ]
        if let reason {
            object["firstFailureReason"] = reason.rawValue
        }
        if let verificationError {
            object["verificationErrorCase"] = verificationError.rawValue
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ) else {
            return
        }
        s10_4StoreKitPurchaseDiagnosticJSON = String(
            decoding: data,
            as: UTF8.self
        )
    }
#endif

    private func reloadProduct() async {
        guard !isLoading else { return }
        guard catalogLinks != nil, hasInstalledProcessor else {
            productPresentation = nil
            loadState = .unavailable
            return
        }
        isLoading = true
        loadState = .loading
        productPresentation = nil
        defer { isLoading = false }

        do {
            let presentation = try await presentationLoader()
            guard presentation.isValid else {
                loadState = .unavailable
                return
            }
            productPresentation = presentation
            loadState = .available
        } catch {
            loadState = .unavailable
        }
    }
}

import Foundation
import StoreKit
import SwiftUI

struct PaywallView: View {
    static let settingsEntryAccessibilityIdentifier = "s7.2.settings.paywall"
    static let screenAccessibilityIdentifier = "s7.2.paywall.screen"
    static let closeAccessibilityIdentifier = "s7.2.paywall.close"
    static let loadingAccessibilityIdentifier = "s7.2.paywall.loading"
    static let unavailableAccessibilityIdentifier = "s7.2.paywall.unavailable"
    static let retryAccessibilityIdentifier = "s7.2.paywall.retry"
    static let storeAccessibilityIdentifier = "s7.2.paywall.store"
    static let productNameAccessibilityIdentifier = "s7.2.paywall.product-name"
    static let productDurationAccessibilityIdentifier = "s7.2.paywall.duration"
    static let productPriceAccessibilityIdentifier = "s7.2.paywall.price"
    static let trialAccessibilityIdentifier = "s7.2.paywall.trial"
    static let renewalAccessibilityIdentifier = "s7.2.paywall.renewal"
    static let noSyncAccessibilityIdentifier = "s7.2.paywall.no-sync"
    static let purchaseStateAccessibilityIdentifier = "s7.2.paywall.purchase-state"
    static let termsAccessibilityIdentifier = "s7.2.paywall.terms"
    static let privacyAccessibilityIdentifier = "s7.2.paywall.privacy"
    static let supportAccessibilityIdentifier = "s7.2.paywall.support"

    @ObservedObject var coordinator: StoreKitPurchaseCoordinator
    let presentationToken: UUID
    let close: @MainActor () -> Void

    @AccessibilityFocusState private var purchaseStatusFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.loadState {
                case .loading:
                    loading
                case .unavailable:
                    unavailable
                case .available:
                    if let presentation = coordinator.productPresentation,
                       let links = coordinator.catalogLinks {
                        available(presentation: presentation, links: links)
                    } else {
                        unavailable
                    }
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: close)
                        .frame(
                            minWidth: DesignTokens.Control.minimumHitSize,
                            minHeight: DesignTokens.Control.minimumHitSize
                        )
                        .disabled(coordinator.isPurchasing)
                        .accessibilityHint("Returns to your existing history")
                        .accessibilityIdentifier(Self.closeAccessibilityIdentifier)
                }
            }
        }
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .interactiveDismissDisabled(coordinator.isPurchasing)
        .task(id: presentationToken) {
            await coordinator.present(token: presentationToken)
        }
        .onChange(of: coordinator.purchaseState) { _, state in
            guard state.recoveryMessage != nil else { return }
            Task { @MainActor in
                await Task.yield()
                purchaseStatusFocused = true
            }
        }
    }

    private var loading: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            ProgressView()
            Text("Loading subscription options…")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.loadingAccessibilityIdentifier)
    }

    private var unavailable: some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(
                    kind: .blocked,
                    text: "Subscription unavailable"
                )

                Text("Subscription details are not available right now.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Your existing sign details, photos, and reports remain available. No price or trial information has been guessed.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Retry") {
                    Task { await coordinator.retryProductLoad() }
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityIdentifier(Self.retryAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.unavailableAccessibilityIdentifier)
    }

    private func available(
        presentation: PaywallProductPresentationV1,
        links: PaywallCatalogLinksV1
    ) -> some View {
        SubscriptionStoreView(productIDs: [EntitlementReducerV1.productID]) {
            marketingContent(presentation: presentation, links: links)
        }
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.hidden, for: .restorePurchases)
        .onInAppPurchaseStart { product in
            _ = await coordinator.purchaseStarted(productID: product.id)
        }
        .onInAppPurchaseCompletion { product, result in
            await coordinator.handleStoreKitCompletion(
                productID: product.id,
                result: result
            )
        }
        .disabled(coordinator.isPurchasing)
        .allowsHitTesting(!coordinator.isPurchasing)
        .accessibilityValue(coordinator.isPurchasing ? "Purchasing" : "Ready")
        .accessibilityIdentifier(Self.storeAccessibilityIdentifier)
    }

    private func marketingContent(
        presentation: PaywallProductPresentationV1,
        links: PaywallCatalogLinksV1
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            Text(presentation.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.productNameAccessibilityIdentifier)

            Text(presentation.subscriptionDuration)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityIdentifier(Self.productDurationAccessibilityIdentifier)

            Text(presentation.displayPrice)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityIdentifier(Self.productPriceAccessibilityIdentifier)

            if presentation.isEligibleForIntroOffer {
                Text("14 days free")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.completeText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.trialAccessibilityIdentifier)

                Text("Then \(presentation.displayPrice) every \(presentation.subscriptionDuration) until canceled.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.renewalAccessibilityIdentifier)
            } else {
                Text("Renews at \(presentation.displayPrice) every \(presentation.subscriptionDuration) until canceled.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.renewalAccessibilityIdentifier)
            }

            Text("Unlimited local signs, checks, rechecks, and report generation while subscribed.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Inspection data and photos stay on this device and do not sync with the subscription. Use a data backup to move them to another device.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.noSyncAccessibilityIdentifier)

            purchaseStatus

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Link("Terms", destination: links.terms)
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityIdentifier(Self.termsAccessibilityIdentifier)
                Link("Privacy", destination: links.privacy)
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityIdentifier(Self.privacyAccessibilityIdentifier)
                Link("Support", destination: links.support)
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityIdentifier(Self.supportAccessibilityIdentifier)
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: DesignTokens.Control.minimumHitSize)
        }
        .padding(DesignTokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var purchaseStatus: some View {
        switch coordinator.purchaseState {
        case .idle:
            EmptyView()
        case .purchasing:
            WorklightStatusBadge(kind: .information, text: "Purchasing…")
                .accessibilityIdentifier(Self.purchaseStateAccessibilityIdentifier)
        case .verified:
            WorklightStatusBadge(
                kind: .complete,
                text: "Purchase verified. Subscription access is ready."
            )
            .accessibilityIdentifier(Self.purchaseStateAccessibilityIdentifier)
        case .cancelled, .pending, .unverified, .failed:
            if let message = coordinator.purchaseState.recoveryMessage {
                Text(message)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($purchaseStatusFocused)
                    .accessibilityIdentifier(
                        Self.purchaseStateAccessibilityIdentifier
                    )
            }
        }
    }
}

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
        }
        .background(DesignTokens.SemanticColors.workBackground)
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
        VStack(spacing: DesignTokens.Spacing.space16) {
            ProgressView()
            Text("Loading subscription options…")
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)

            closeButton
        }
        .padding(DesignTokens.Spacing.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
        .accessibilityIdentifier(Self.loadingAccessibilityIdentifier)
    }

    private var unavailable: some View {
        ScrollView {
            AssetRoundsEvidenceCard {
                AssetRoundsStateLabel(kind: .unavailable, "Subscription unavailable")
                    .accessibilityLabel("Blocked: Subscription unavailable")
                    .accessibilityValue(Text(verbatim: String()))

                Text("Subscription details are not available right now.")
                    .font(DesignTokens.Typography.screenTitle)
                    .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Your existing sign details, photos, and reports remain available. No price or trial information has been guessed.")
                    .font(DesignTokens.Typography.primaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                AssetRoundsPrimaryAction("Retry") {
                    Task { await coordinator.retryProductLoad() }
                }
                .accessibilityIdentifier(Self.retryAccessibilityIdentifier)

                closeButton
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
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
            _ = await coordinator.storeKitPurchaseStarted(productID: product.id)
        }
        .onInAppPurchaseCompletion { product, result in
            await coordinator.handleStoreKitCompletion(
                productID: product.id,
                result: result
            )
        }
        .accessibilityValue(coordinator.isPurchasing ? "Purchasing" : "Ready")
        .accessibilityIdentifier(Self.storeAccessibilityIdentifier)
    }

    private func marketingContent(
        presentation: PaywallProductPresentationV1,
        links: PaywallCatalogLinksV1
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
            closeButton

            Text(presentation.displayName)
                .font(DesignTokens.Typography.screenTitle)
                .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.productNameAccessibilityIdentifier)

            Text(presentation.subscriptionDuration)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .accessibilityIdentifier(Self.productDurationAccessibilityIdentifier)

            Text(presentation.displayPrice)
                .font(DesignTokens.Typography.sectionHeading)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .accessibilityIdentifier(Self.productPriceAccessibilityIdentifier)

            if presentation.isEligibleForIntroOffer {
                Text("14 days free")
                    .font(DesignTokens.Typography.sectionHeading)
                    .foregroundStyle(DesignTokens.SemanticColors.completed)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.trialAccessibilityIdentifier)

                Text("Then \(presentation.displayPrice) every \(presentation.subscriptionDuration) until canceled.")
                    .font(DesignTokens.Typography.primaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.renewalAccessibilityIdentifier)
            } else {
                Text("Renews at \(presentation.displayPrice) every \(presentation.subscriptionDuration) until canceled.")
                    .font(DesignTokens.Typography.primaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.renewalAccessibilityIdentifier)
            }

            Text("Unlimited local signs, checks, rechecks, and report generation while subscribed.")
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Inspection data and photos stay on this device and do not sync with the subscription. Use a data backup to move them to another device.")
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.noSyncAccessibilityIdentifier)

            purchaseStatus

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
                Link("Terms", destination: links.terms)
                    .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                    .accessibilityIdentifier(Self.termsAccessibilityIdentifier)
                Link("Privacy", destination: links.privacy)
                    .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                    .accessibilityIdentifier(Self.privacyAccessibilityIdentifier)
                Link("Support", destination: links.support)
                    .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                    .accessibilityIdentifier(Self.supportAccessibilityIdentifier)
            }
            .font(DesignTokens.Typography.sectionHeading)
            .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
        }
        .padding(DesignTokens.Spacing.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeButton: some View {
        AssetRoundsSecondaryAction("Close", action: close)
            .disabled(coordinator.isPurchasing)
            .accessibilityHint("Returns to your existing history")
            .accessibilityIdentifier(Self.closeAccessibilityIdentifier)
    }

    @ViewBuilder
    private var purchaseStatus: some View {
        switch coordinator.purchaseState {
        case .idle:
            EmptyView()
        case .purchasing:
            AssetRoundsStateLabel(kind: .selected, "Purchasing…")
                .accessibilityLabel("Information: Purchasing…")
                .accessibilityValue(Text(verbatim: String()))
                .accessibilityIdentifier(Self.purchaseStateAccessibilityIdentifier)
        case .verified:
            AssetRoundsStateLabel(
                kind: .completed,
                "Purchase verified. Subscription access is ready."
            )
            .accessibilityLabel(
                "Complete: Purchase verified. Subscription access is ready."
            )
            .accessibilityValue(Text(verbatim: String()))
            .accessibilityIdentifier(Self.purchaseStateAccessibilityIdentifier)
        case .cancelled, .pending, .unverified, .failed:
            if let message = coordinator.purchaseState.recoveryMessage {
                Text(message)
                    .font(DesignTokens.Typography.primaryBody.weight(.semibold))
                    .foregroundStyle(DesignTokens.SemanticColors.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($purchaseStatusFocused)
                    .accessibilityIdentifier(
                        Self.purchaseStateAccessibilityIdentifier
                    )
            }
        }
    }
}

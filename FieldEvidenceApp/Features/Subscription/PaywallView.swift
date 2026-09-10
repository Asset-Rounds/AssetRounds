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
            .navigationTitle(BundledLocalizationCatalogV1.v30Text(.paywallNavigationTitle))
            .navigationBarTitleDisplayMode(.inline)
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
            Text(BundledLocalizationCatalogV1.v30Text(.paywallLoadingOptions))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            closeButton
        }
        .padding(DesignTokens.Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.loadingAccessibilityIdentifier)
    }

    private var unavailable: some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(
                    kind: .blocked,
                    text: BundledLocalizationCatalogV1.v30Text(.paywallUnavailableBadge)
                )

                Text(BundledLocalizationCatalogV1.v30Text(.paywallUnavailableMessage))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(BundledLocalizationCatalogV1.v30Text(.paywallUnavailableDataNotice))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(BundledLocalizationCatalogV1.v30Text(.paywallRetry)) {
                    Task { await coordinator.retryProductLoad() }
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityIdentifier(Self.retryAccessibilityIdentifier)

                closeButton
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
            _ = await coordinator.storeKitPurchaseStarted(productID: product.id)
        }
        .onInAppPurchaseCompletion { product, result in
            await coordinator.handleStoreKitCompletion(
                productID: product.id,
                result: result
            )
        }
        .accessibilityValue(coordinator.isPurchasing ? BundledLocalizationCatalogV1.v30Text(.paywallPurchasingAccessibilityValue) : BundledLocalizationCatalogV1.v30Text(.paywallReady))
        .accessibilityIdentifier(Self.storeAccessibilityIdentifier)
    }

    private func marketingContent(
        presentation: PaywallProductPresentationV1,
        links: PaywallCatalogLinksV1
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            closeButton

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
                Text(BundledLocalizationCatalogV1.v30Text(.paywallTrialDuration))
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.completeText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.trialAccessibilityIdentifier)

                Text(BundledLocalizationCatalogV1.v30PaywallTrialRenewal(price: presentation.displayPrice, duration: presentation.subscriptionDuration))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.renewalAccessibilityIdentifier)
            } else {
                Text(BundledLocalizationCatalogV1.v30PaywallRenewal(price: presentation.displayPrice, duration: presentation.subscriptionDuration))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.renewalAccessibilityIdentifier)
            }

            Text(BundledLocalizationCatalogV1.v30Text(.paywallSubscriptionBenefits))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(BundledLocalizationCatalogV1.v30Text(.paywallDataStorageNotice))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.noSyncAccessibilityIdentifier)

            purchaseStatus

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Link(BundledLocalizationCatalogV1.v30Text(.paywallTerms), destination: links.terms)
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityIdentifier(Self.termsAccessibilityIdentifier)
                Link(BundledLocalizationCatalogV1.v30Text(.paywallPrivacy), destination: links.privacy)
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityIdentifier(Self.privacyAccessibilityIdentifier)
                Link(BundledLocalizationCatalogV1.v30Text(.paywallSupport), destination: links.support)
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityIdentifier(Self.supportAccessibilityIdentifier)
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: DesignTokens.Control.minimumHitSize)
        }
        .padding(DesignTokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeButton: some View {
        Button(BundledLocalizationCatalogV1.v30Text(.paywallClose), action: close)
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(coordinator.isPurchasing)
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.paywallCloseHint))
            .accessibilityIdentifier(Self.closeAccessibilityIdentifier)
    }

    @ViewBuilder
    private var purchaseStatus: some View {
        switch coordinator.purchaseState {
        case .idle:
            EmptyView()
        case .purchasing:
            WorklightStatusBadge(kind: .information, text: BundledLocalizationCatalogV1.v30Text(.paywallPurchasing))
                .accessibilityIdentifier(Self.purchaseStateAccessibilityIdentifier)
        case .verified:
            WorklightStatusBadge(
                kind: .complete,
                text: BundledLocalizationCatalogV1.v30Text(.paywallPurchaseVerified)
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

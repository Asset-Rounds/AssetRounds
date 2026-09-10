import StoreKit
import SwiftUI

enum SubscriptionLifecycleToneV1: Equatable, Sendable {
    case information
    case complete
    case blocked
}

struct SubscriptionLifecyclePresentationV1: Equatable, Sendable {
    let tone: SubscriptionLifecycleToneV1
    let badge: String
    let title: String
    let detail: String

    static func make(
        state: SubscriptionLifecycleStateV1,
        latestVerifiedFact: VerifiedEntitlementFactV1?,
        dateText: (Date) -> String
    ) -> Self {
        switch state {
        case .loading:
            return Self(
                tone: .information,
                badge: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusBadge),
                title: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusChecking),
                detail: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusExistingDataAvailable)
            )
        case .neverPaid:
            return Self(
                tone: .information,
                badge: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusNoActiveBadge),
                title: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusNotFound),
                detail: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusNoActiveDetail)
            )
        case let .active(until):
            let badge = latestVerifiedFact?.isIntroductoryOffer == true
                ? BundledLocalizationCatalogV1.v30Text(.subscriptionStatusTrialActive)
                : BundledLocalizationCatalogV1.v30Text(.subscriptionStatusActive)
            let detail: String
            if latestVerifiedFact?.willAutoRenew == false {
                detail = BundledLocalizationCatalogV1.v30Text(.subscriptionStatusAutoRenewOff)
            } else if latestVerifiedFact?.isIntroductoryOffer == true {
                detail = BundledLocalizationCatalogV1.v30Text(.subscriptionStatusTrialDetail)
            } else {
                detail = BundledLocalizationCatalogV1.v30Text(.subscriptionStatusActiveDetail)
            }
            return Self(
                tone: .complete,
                badge: badge,
                title: BundledLocalizationCatalogV1.v30SubscriptionStatusActiveUntil(date: dateText(until)),
                detail: detail
            )
        case let .grace(until):
            return Self(
                tone: .information,
                badge: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusGracePeriod),
                title: BundledLocalizationCatalogV1.v30SubscriptionStatusAccessThrough(date: dateText(until)),
                detail: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusGracePeriodDetail)
            )
        case let .inactive(reason):
            switch reason {
            case .billingRetry:
                return Self(
                    tone: .blocked,
                    badge: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusBillingRetry),
                    title: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusInactive),
                    detail: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusBillingRetryDetail)
                )
            case .expired:
                return Self(
                    tone: .blocked,
                    badge: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusExpired),
                    title: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusInactive),
                    detail: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusExpiredDetail)
                )
            case .refunded:
                return Self(
                    tone: .blocked,
                    badge: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusRefunded),
                    title: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusInactive),
                    detail: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusRefundedDetail)
                )
            case .revoked:
                return Self(
                    tone: .blocked,
                    badge: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusRevoked),
                    title: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusInactive),
                    detail: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusRevokedDetail)
                )
            }
        }
    }
}

struct StoreKitRestorePresentationV1: Equatable, Sendable {
    let tone: SubscriptionLifecycleToneV1
    let copy: String

    static func make(state: StoreKitRestoreStateV1) -> Self? {
        switch state {
        case .idle:
            return nil
        case .restoring:
            return Self(
                tone: .information,
                copy: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusRestoringPurchasesStatus)
            )
        case .restored:
            return Self(
                tone: .complete,
                copy: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusPurchasesRestored)
            )
        case .noCurrentEntitlement:
            return Self(
                tone: .blocked,
                copy: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusNoCurrentSubscription)
            )
        case .unverified:
            return Self(
                tone: .blocked,
                copy: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusPurchaseHistoryUnverified)
            )
        case .failed:
            return Self(
                tone: .blocked,
                copy: BundledLocalizationCatalogV1.v30Text(.subscriptionStatusPurchasesRestoreFailed)
            )
        }
    }
}

struct SubscriptionStatusView: View {
    static let screenAccessibilityIdentifier = "s7.3.lifecycle.screen"
    static let statusAccessibilityIdentifier = "s7.3.lifecycle.status"
    static let statusTitleAccessibilityIdentifier =
        "s7.3.lifecycle.status-title"
    static let restoreAccessibilityIdentifier = "s7.3.lifecycle.restore"
    static let settingsRestoreAccessibilityIdentifier =
        "s7.3.settings.restore-purchases"
    static let manageAccessibilityIdentifier = "s7.3.lifecycle.manage"
    static let closeAccessibilityIdentifier = "s7.3.lifecycle.close"
    static let restoreResultAccessibilityIdentifier =
        "s7.3.lifecycle.restore-result"

    @ObservedObject var coordinator: StoreKitLifecycleCoordinator

    let startsRestoreOnAppear: Bool
    let close: @MainActor () -> Void

    @State private var showsManageSubscription = false
    @State private var didStartRequestedRestore = false
    @AccessibilityFocusState private var restoreResultFocused: Bool

    init(
        coordinator: StoreKitLifecycleCoordinator,
        startsRestoreOnAppear: Bool = false,
        close: @escaping @MainActor () -> Void
    ) {
        self.coordinator = coordinator
        self.startsRestoreOnAppear = startsRestoreOnAppear
        self.close = close
    }

    var body: some View {
        ScrollView {
            WorklightCard {
                lifecycleStatus
                restoreResult

                Button {
                    Task { await coordinator.restorePurchases() }
                } label: {
                    if coordinator.isRestoring {
                        HStack(spacing: DesignTokens.Spacing.small) {
                            ProgressView()
                            Text(BundledLocalizationCatalogV1.v30Text(.subscriptionStatusRestoringPurchases))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(BundledLocalizationCatalogV1.v30Text(.subscriptionStatusRestorePurchases))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(coordinator.isRestoring)
                .accessibilityIdentifier(Self.restoreAccessibilityIdentifier)

                Button(BundledLocalizationCatalogV1.v30Text(.subscriptionStatusManageSubscription)) {
                    showsManageSubscription = true
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(coordinator.isRestoring)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.subscriptionStatusManageHint))
                .accessibilityIdentifier(Self.manageAccessibilityIdentifier)

                Text(BundledLocalizationCatalogV1.v30Text(.subscriptionStatusDataStorageNotice))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(BundledLocalizationCatalogV1.v30Text(.subscriptionStatusClose)) {
                    coordinator.clearRestoreResult()
                    close()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(coordinator.isRestoring)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.subscriptionStatusCloseHint))
                .accessibilityIdentifier(Self.closeAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.subscriptionStatusNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .interactiveDismissDisabled(coordinator.isRestoring)
        .manageSubscriptionsSheet(isPresented: $showsManageSubscription)
        .task {
            guard startsRestoreOnAppear,
                  !didStartRequestedRestore else {
                return
            }
            didStartRequestedRestore = true
            _ = await coordinator.restorePurchases()
        }
        .onChange(of: coordinator.restoreState) { _, state in
            guard state != .idle, state != .restoring else { return }
            Task { @MainActor in
                await Task.yield()
                restoreResultFocused = true
            }
        }
    }

    private var lifecyclePresentation: SubscriptionLifecyclePresentationV1 {
        SubscriptionLifecyclePresentationV1.make(
            state: coordinator.lifecycleState,
            latestVerifiedFact: coordinator.latestVerifiedFact,
            dateText: {
                $0.formatted(date: .abbreviated, time: .omitted)
            }
        )
    }

    @ViewBuilder
    private var lifecycleStatus: some View {
        let presentation = lifecyclePresentation
        switch presentation.tone {
        case .information:
            WorklightStatusBadge(
                kind: .information,
                text: presentation.badge
            )
        case .complete:
            WorklightStatusBadge(kind: .complete, text: presentation.badge)
        case .blocked:
            WorklightStatusBadge(kind: .blocked, text: presentation.badge)
        }

        Text(presentation.title)
            .font(.title2.weight(.bold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(Self.statusTitleAccessibilityIdentifier)

        Text(presentation.detail)
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
    }

    @ViewBuilder
    private var restoreResult: some View {
        if let presentation = StoreKitRestorePresentationV1.make(
            state: coordinator.restoreState
        ) {
            switch presentation.tone {
            case .information:
                WorklightStatusBadge(
                    kind: .information,
                    text: presentation.copy
                )
                .accessibilityFocused($restoreResultFocused)
                .accessibilityIdentifier(
                    Self.restoreResultAccessibilityIdentifier
                )
            case .complete:
                WorklightStatusBadge(kind: .complete, text: presentation.copy)
                    .accessibilityFocused($restoreResultFocused)
                    .accessibilityIdentifier(
                        Self.restoreResultAccessibilityIdentifier
                    )
            case .blocked:
                Text(presentation.copy)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($restoreResultFocused)
                    .accessibilityIdentifier(
                        Self.restoreResultAccessibilityIdentifier
                    )
            }
        }
    }
}

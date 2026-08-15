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
                badge: "Subscription status",
                title: "Checking subscription…",
                detail: "Your existing sign details, photos, and reports remain available."
            )
        case .neverPaid:
            return Self(
                tone: .information,
                badge: "No active subscription",
                title: "No subscription found",
                detail: "Your existing data remains available. Restore Purchases checks Apple purchase history; it does not restore inspection data."
            )
        case let .active(until):
            let badge = latestVerifiedFact?.isIntroductoryOffer == true
                ? "Trial active"
                : "Subscription active"
            let detail: String
            if latestVerifiedFact?.willAutoRenew == false {
                detail = "Auto-renew is off. Access remains active through the signed date above."
            } else if latestVerifiedFact?.isIntroductoryOffer == true {
                detail = "The introductory trial is active through the signed date above. Renewal is managed by the App Store."
            } else {
                detail = "Access is active through the signed date above. Renewal is managed by the App Store."
            }
            return Self(
                tone: .complete,
                badge: badge,
                title: "Active until \(dateText(until))",
                detail: detail
            )
        case let .grace(until):
            return Self(
                tone: .information,
                badge: "Grace period",
                title: "Access through \(dateText(until))",
                detail: "Apple provided a signed grace period. Access does not continue beyond that signed date."
            )
        case let .inactive(reason):
            switch reason {
            case .billingRetry:
                return Self(
                    tone: .blocked,
                    badge: "Billing retry",
                    title: "Subscription inactive",
                    detail: "Apple reported billing retry without signed grace. Existing data remains available."
                )
            case .expired:
                return Self(
                    tone: .blocked,
                    badge: "Subscription expired",
                    title: "Subscription inactive",
                    detail: "The signed subscription period ended. Existing data remains available."
                )
            case .refunded:
                return Self(
                    tone: .blocked,
                    badge: "Subscription refunded",
                    title: "Subscription inactive",
                    detail: "Apple reported a refund. Existing data remains available."
                )
            case .revoked:
                return Self(
                    tone: .blocked,
                    badge: "Subscription revoked",
                    title: "Subscription inactive",
                    detail: "Apple reported a revoked subscription. Existing data remains available."
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
                copy: "Restoring purchases…"
            )
        case .restored:
            return Self(
                tone: .complete,
                copy: "Purchases restored. Subscription access is updated."
            )
        case .noCurrentEntitlement:
            return Self(
                tone: .blocked,
                copy: "No current subscription was found. Your existing data is still available."
            )
        case .unverified:
            return Self(
                tone: .blocked,
                copy: "Purchase history couldn’t be verified. Your existing data is still available. Try again."
            )
        case .failed:
            return Self(
                tone: .blocked,
                copy: "Purchases couldn’t be restored. Your existing data is still available. Try again."
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
                            Text("Restoring Purchases…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Restore Purchases")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(coordinator.isRestoring)
                .accessibilityIdentifier(Self.restoreAccessibilityIdentifier)

                Button("Manage Subscription") {
                    showsManageSubscription = true
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(coordinator.isRestoring)
                .accessibilityHint("Opens Apple subscription management")
                .accessibilityIdentifier(Self.manageAccessibilityIdentifier)

                Text("Inspection data and photos stay on this device and do not sync with the subscription. Use a data backup to move them.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Close") {
                    coordinator.clearRestoreResult()
                    close()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(coordinator.isRestoring)
                .accessibilityHint("Returns to your existing data")
                .accessibilityIdentifier(Self.closeAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Subscription")
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

import SwiftUI

/// Provisional C39 Settings presentation. Natural-stop integration owns any
/// native rating request; this surface only renders supplied local truth and
/// never infers that a system prompt, rating, review, or store effect occurred.
@MainActor
struct RatingSupportWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c39.rating-support.screen"
    static let supportAccessibilityIdentifier = "v23.p04.c39.rating-support.contact-support"
    static let recoveryAccessibilityIdentifier = "v23.p04.c39.rating-support.recovery"
    static let rateLinkAccessibilityIdentifier = "v23.p04.c39.rating-support.rate-link"
    static let automaticAccessibilityIdentifier = "v23.p04.c39.rating-support.automatic"
    static let statusAccessibilityIdentifier = "v23.p04.c39.rating-support.status"

    let eligibility: RatingEligibilityProjectionV1
    let rateAppLink: RateAppLinkV1
    let lastRequestStatus: RatingRequestOutcomeV1?
    let onContactSupport: @MainActor () -> Void
    let onRecovery: @MainActor () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    private enum FocusTarget: Hashable {
        case heading
        case status
    }

    init(
        eligibility: RatingEligibilityProjectionV1,
        rateAppLink: RateAppLinkV1,
        lastRequestStatus: RatingRequestOutcomeV1? = nil,
        onContactSupport: @escaping @MainActor () -> Void,
        onRecovery: @escaping @MainActor () -> Void
    ) {
        self.eligibility = eligibility
        self.rateAppLink = rateAppLink
        self.lastRequestStatus = lastRequestStatus
        self.onContactSupport = onContactSupport
        self.onRecovery = onRecovery
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                helpAndRecovery
                rateAssetRounds
                automaticRequestState
                if let lastRequestStatus {
                    requestStatus(lastRequestStatus)
                }
                boundaries
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Rating and support")
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            accessibilityFocus = .heading
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Rating and support")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)

            Text("Support and recovery are always available. Rating choices are separate and optional.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var helpAndRecovery: some View {
        WorklightCard {
            sectionHeading("Get help", identifier: "\(Self.screenAccessibilityIdentifier).help")
            Text("Contact Support or open Recovery at any time. Neither action depends on rating eligibility.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button("Contact Support", action: onContactSupport)
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityHint("Opens the existing support route. It does not request a rating.")
                .accessibilityIdentifier(Self.supportAccessibilityIdentifier)

            Button("Recovery", action: onRecovery)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint("Opens the existing recovery route. It does not request a rating.")
                .accessibilityIdentifier(Self.recoveryAccessibilityIdentifier)
        }
        .accessibilityElement(children: .contain)
    }

    private var rateAssetRounds: some View {
        WorklightCard {
            sectionHeading("Rate AssetRounds", identifier: "\(Self.screenAccessibilityIdentifier).rate")
            switch rateAppLink {
            case let .available(url):
                Text("Open the verified App Store rating link when you choose. This is separate from any automatic system request.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Rate AssetRounds") {
                    openURL(url)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint("Requests the verified App Store rating page. The app does not know whether a rating or review is made.")
                .accessibilityIdentifier(Self.rateLinkAccessibilityIdentifier)
            case .disabledUnverifiedAppStoreID:
                Label("Rate AssetRounds is unavailable because the App Store identity is not verified.", systemImage: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                Text("RATE_LINK_DISABLED_UNVERIFIED_APP_STORE_ID. Contact Support and Recovery remain available.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.rateLinkAccessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var automaticRequestState: some View {
        WorklightCard {
            sectionHeading("Automatic request", identifier: Self.automaticAccessibilityIdentifier)
            if eligibility.eligible {
                Label("Eligible at a quiet natural stopping point", systemImage: "checkmark.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .accessibilityElement(children: .combine)
                Text("Only the natural-stop integration may ask the system to consider a rating request. This Settings screen does not make that request.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Automatic request is not eligible now", systemImage: "minus.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .accessibilityElement(children: .combine)
                Text("Continue using the app normally. Support and Recovery remain available without waiting for rating eligibility.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !eligibility.reasons.isEmpty {
                    ForEach(eligibility.reasons, id: \.rawValue) { reason in
                        Text(reasonSummary(reason))
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("Local eligibility uses no rating, review, behavior, or marketing data.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func requestStatus(_ status: RatingRequestOutcomeV1) -> some View {
        WorklightCard {
            sectionHeading("Request status", identifier: Self.statusAccessibilityIdentifier)
            Text(requestStatusSummary(status))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($accessibilityFocus, equals: .status)
            Text("This status never confirms a prompt, star value, review text, submission, store response, reward, or effect.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading("Privacy and availability", identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text("This view has no rating form, satisfaction question, reward, customer list, marketing consent, telemetry, or network request.")
            Text("The system controls whether a native rating request appears. The App Store link and the existing support/recovery routes remain separate.")
            if reduceMotion {
                Text("Reduce Motion is on. This screen adds no state-change animation.")
            }
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private func sectionHeading(_ title: LocalizedStringKey, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func requestStatusSummary(_ status: RatingRequestOutcomeV1) -> String {
        switch status {
        case .ineligible:
            return "The supplied natural-stop state was not eligible, so no native rating request was made."
        case .duplicateConservativeAttempt:
            return "A prior local attempt is already recorded, so no additional native rating request was made."
        case .nativeRequestInvoked:
            return "AssetRounds asked the system to consider a rating request. The system may show nothing."
        case .nativeRequestInvokedStatusPersistencePending:
            return "AssetRounds conservatively recorded a request attempt while its final local status is pending. The system may show nothing."
        }
    }

    private func reasonSummary(_ reason: RatingEligibilityReasonV1) -> String {
        switch reason {
        case .insufficientDistinctSeries:
            return "More separate finalized activity series are needed before an automatic request can be considered."
        case .insufficientSevenDaySpan:
            return "The required time span between finalized activity series has not been reached."
        case .alreadyAttemptedForVersion:
            return "A request attempt is already recorded for this app version or natural stop."
        case .withinOneHundredTwentyDayCooldown:
            return "A recent request attempt keeps automatic requests paused."
        case .rollingYearAttemptLimit:
            return "The local yearly limit keeps automatic requests paused."
        case .erasedInstallationCooldown:
            return "This installation is in the post-erase cooldown for automatic requests."
        case .clockRollbackDetected:
            return "The device clock cannot safely establish automatic request timing."
        case .invalidMarketingVersion:
            return "The current app version cannot safely establish automatic request timing."
        case .noNaturalIdleStop:
            return "Automatic requests are considered only after a quiet natural stopping point."
        case .sceneUnavailable:
            return "No active scene is available for a possible automatic system request."
        case .activeContext:
            return "An active task or recovery context keeps automatic requests paused."
        case .ledgerCorrupt, .ledgerFutureVersion, .ledgerMigrationFailed, .ledgerUnavailable:
            return "Local request history cannot be safely read, so automatic requests are paused."
        case .automaticRequestDisabledUnverifiedPlatform:
            return "Automatic requests are disabled because the platform capability is not verified."
        }
    }
}

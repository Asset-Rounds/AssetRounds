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
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.ratingSupportNavigationTitle))
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
            Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)

            Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var helpAndRecovery: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.ratingSupportHelpHeading), identifier: "\(Self.screenAccessibilityIdentifier).help")
            Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportHelpDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(BundledLocalizationCatalogV1.v30Text(.ratingSupportContactSupport), action: onContactSupport)
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.ratingSupportContactHint))
                .accessibilityIdentifier(Self.supportAccessibilityIdentifier)

            Button(BundledLocalizationCatalogV1.v30Text(.ratingSupportRecovery), action: onRecovery)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.ratingSupportRecoveryHint))
                .accessibilityIdentifier(Self.recoveryAccessibilityIdentifier)
        }
        .accessibilityElement(children: .contain)
    }

    private var rateAssetRounds: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.ratingSupportRateHeading), identifier: "\(Self.screenAccessibilityIdentifier).rate")
            switch rateAppLink {
            case let .available(url):
                Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportRateDescription))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(BundledLocalizationCatalogV1.v30Text(.ratingSupportRateButton)) {
                    openURL(url)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.ratingSupportRateHint))
                .accessibilityIdentifier(Self.rateLinkAccessibilityIdentifier)
            case .disabledUnverifiedAppStoreID:
                Label(BundledLocalizationCatalogV1.v30Text(.ratingSupportRateUnavailable), systemImage: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportRateDisabledTokenDescription))
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
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.ratingSupportAutomaticHeading), identifier: Self.automaticAccessibilityIdentifier)
            if eligibility.eligible {
                Label(BundledLocalizationCatalogV1.v30Text(.ratingSupportEligible), systemImage: "checkmark.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .accessibilityElement(children: .combine)
                Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportEligibleDescription))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(BundledLocalizationCatalogV1.v30Text(.ratingSupportNotEligible), systemImage: "minus.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .accessibilityElement(children: .combine)
                Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportNotEligibleDescription))
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
            Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportEligibilityPrivacy))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func requestStatus(_ status: RatingRequestOutcomeV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.ratingSupportStatusHeading), identifier: Self.statusAccessibilityIdentifier)
            Text(requestStatusSummary(status))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($accessibilityFocus, equals: .status)
            Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportStatusDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.ratingSupportBoundariesHeading), identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportBoundariesDescription))
            Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportSystemBoundary))
            if reduceMotion {
                Text(BundledLocalizationCatalogV1.v30Text(.ratingSupportReduceMotionDescription))
            }
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private func sectionHeading(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func requestStatusSummary(_ status: RatingRequestOutcomeV1) -> String {
        switch status {
        case .ineligible:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportStatusIneligible)
        case .duplicateConservativeAttempt:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportStatusDuplicateAttempt)
        case .nativeRequestInvoked:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportStatusRequested)
        case .nativeRequestInvokedStatusPersistencePending:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportStatusPending)
        }
    }

    private func reasonSummary(_ reason: RatingEligibilityReasonV1) -> String {
        switch reason {
        case .insufficientDistinctSeries:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonInsufficientSeries)
        case .insufficientSevenDaySpan:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonInsufficientSpan)
        case .alreadyAttemptedForVersion:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonAlreadyAttempted)
        case .withinOneHundredTwentyDayCooldown:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonCooldown)
        case .rollingYearAttemptLimit:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonYearLimit)
        case .erasedInstallationCooldown:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonEraseCooldown)
        case .clockRollbackDetected:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonClockRollback)
        case .invalidMarketingVersion:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonInvalidVersion)
        case .noNaturalIdleStop:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonNoNaturalStop)
        case .sceneUnavailable:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonNoScene)
        case .activeContext:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonActiveContext)
        case .ledgerCorrupt, .ledgerFutureVersion, .ledgerMigrationFailed, .ledgerUnavailable:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonHistoryUnavailable)
        case .automaticRequestDisabledUnverifiedPlatform:
            return BundledLocalizationCatalogV1.v30Text(.ratingSupportReasonPlatformUnverified)
        }
    }
}

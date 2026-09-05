import Foundation
import SwiftUI

/// Standalone C04 presentation. It has no route, persistence, export, or
/// delivery authority; typed callers provide an already-derived snapshot.
@MainActor
struct ShopProfileOpenEvidenceHandoffView: View {
    static let screenAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.screen.rawValue
    static let profileAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.profile.rawValue
    static let presetAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.preset.rawValue
    static let audienceAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.audience.rawValue
    static let activationAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.activation.rawValue
    static let packagingAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.packaging.rawValue
    static let combinedPackageAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.combinedPackage.rawValue
    static let separatePackageAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.separatePackage.rawValue
    static let previewAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.preview.rawValue
    static let exactBytesAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.exactBytes.rawValue
    static let digestAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.digest.rawValue
    static let detectorAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.detector.rawValue
    static let detectorPassAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.detectorPass.rawValue
    static let detectorBlockedAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.detectorBlocked.rawValue
    static let semanticTextAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.semanticText.rawValue
    static let confirmationAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.confirmation.rawValue
    static let handoffAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.handoff.rawValue
    static let statusAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.status.rawValue
    static let recoveryAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.recovery.rawValue
    static let retryAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.retry.rawValue
    static let limitationsAccessibilityIdentifier = ShopReportProfileAccessibilityIDV1.limitations.rawValue

    let profile: ShopReportProfileV1?
    let coordinator: ShopReportProfileCoordinatorV1?
    let detection: PostMarkupAudiencePrivacyDetectionV1?
    let semanticText: String?
    let confirmation: FinalAudiencePrivacyConfirmationV1?
    let handoff: ShopOpenEvidenceHandoffReceiptV1?
    let onConfirmExactBytes: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        profile: ShopReportProfileV1? = nil,
        coordinator: ShopReportProfileCoordinatorV1? = nil,
        detection: PostMarkupAudiencePrivacyDetectionV1? = nil,
        semanticText: String? = nil,
        confirmation: FinalAudiencePrivacyConfirmationV1? = nil,
        handoff: ShopOpenEvidenceHandoffReceiptV1? = nil,
        onConfirmExactBytes: (() -> Void)? = nil
    ) {
        self.profile = profile
        self.coordinator = coordinator
        self.detection = detection
        self.semanticText = semanticText
        self.confirmation = confirmation
        self.handoff = handoff
        self.onConfirmExactBytes = onConfirmExactBytes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                profileSection
                previewSection
                privacySection
                handoffSection
                limitationsSection
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(localized(.heading))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? DesignTokens.Spacing.large : DesignTokens.Spacing.medium
    }

    private var profileSection: some View {
        WorklightCard {
            heading(.profileHeading, identifier: Self.profileAccessibilityIdentifier)
            guard let profile = trustedProfile else {
                bodyText(.defaultOff)
                return
            }
            fact(.presetHeading, localized(.profileHeading), identifier: Self.presetAccessibilityIdentifier)
            fact(.audienceHeading, audienceLabel(profile.evidenceDetailProfile.audience), identifier: Self.audienceAccessibilityIdentifier)
            fact(.activationHeading, activationLabel(profile.activation), identifier: Self.activationAccessibilityIdentifier)
            fact(.packagingHeading, packagingLabel(profile.packaging), identifier: Self.packagingAccessibilityIdentifier)
            Text(profile.activation == .off ? localized(.defaultOff) : localized(.noDeliveryClaim))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        WorklightCard {
            heading(.previewHeading, identifier: Self.previewAccessibilityIdentifier)
            if trustedDetection != nil {
                fact(.exactBytes, localized(.confirmationRequired), identifier: Self.exactBytesAccessibilityIdentifier)
                fact(.digest, localized(.confirmationRequired), identifier: Self.digestAccessibilityIdentifier)
            } else {
                status(.statusUnavailable, kind: .blocked, identifier: Self.statusAccessibilityIdentifier)
            }
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        WorklightCard {
            heading(.detectorHeading, identifier: Self.detectorAccessibilityIdentifier)
            if let detection = trustedDetection {
                switch detection.disposition {
                case .pass:
                    status(.detectorPass, kind: .complete, identifier: Self.detectorPassAccessibilityIdentifier)
                case .blocked:
                    status(.detectorBlocked, kind: .blocked, identifier: Self.detectorBlockedAccessibilityIdentifier)
                }
            } else {
                status(.statusUnavailable, kind: .blocked, identifier: Self.statusAccessibilityIdentifier)
            }

            heading(.semanticTextHeading, identifier: Self.semanticTextAccessibilityIdentifier)
            Text(trustedDetection == nil ? localized(.statusUnavailable) : localized(.confirmationRequired))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .accessibilityElement(children: .combine)

            heading(.confirmationHeading, identifier: Self.confirmationAccessibilityIdentifier)
            if trustedConfirmation != nil {
                status(.confirmationRecorded, kind: .information, identifier: Self.confirmationAccessibilityIdentifier)
            } else {
                bodyText(.confirmationRequired)
                if confirmationMayBeRequested {
                    Button(localized(.confirmationHeading)) { onConfirmExactBytes?() }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .disabled(onConfirmExactBytes == nil)
                        .accessibilityIdentifier(Self.confirmationAccessibilityIdentifier)
                        .accessibilityHint(localized(.confirmationRequired))
                }
            }
        }
    }

    private var handoffSection: some View {
        WorklightCard {
            heading(.handoffHeading, identifier: Self.handoffAccessibilityIdentifier)
            if let handoff = trustedHandoff {
                status(.handoffAvailable, kind: .information, identifier: Self.handoffAccessibilityIdentifier)
                let key: ShopReportProfileLocalizationKeyV1 = handoff.packaging == .combinedArchive ? .combinedPackage : .separatePackage
                let identifier = handoff.packaging == .combinedArchive
                    ? Self.combinedPackageAccessibilityIdentifier
                    : Self.separatePackageAccessibilityIdentifier
                fact(.packagingHeading, localized(key), identifier: identifier)
            } else {
                bodyText(.noDeliveryClaim)
            }
        }
    }

    private var limitationsSection: some View {
        WorklightCard {
            Text(localized(.limitations))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.limitationsAccessibilityIdentifier)
        }
    }

    private var trustedDetection: PostMarkupAudiencePrivacyDetectionV1? {
        guard let detection, let profile = trustedProfile else { return nil }
        do {
            try detection.validate()
            guard detection.audience == profile.evidenceDetailProfile.audience,
                  detection.policyID == profile.evidenceDetailProfile.audiencePrivacyPolicy.policyID,
                  detection.policyVersion == profile.evidenceDetailProfile.audiencePrivacyPolicy.policyVersion,
                  detection.policySHA256 == profile.evidenceDetailProfile.audiencePrivacyPolicy.policySHA256,
                  semanticText == detection.semanticText else { return nil }
            return detection
        } catch {
            return nil
        }
    }

    private var trustedProfile: ShopReportProfileV1? {
        guard let profile,
              let coordinator,
              let current = try? coordinator.current(profileID: profile.profileID),
              current == profile else { return nil }
        do {
            try profile.validateIntrinsic()
            return profile
        } catch {
            return nil
        }
    }

    private var trustedConfirmation: FinalAudiencePrivacyConfirmationV1? {
        guard let confirmation,
              let detection = trustedDetection else { return nil }
        do {
            try confirmation.validate()
            guard confirmation.detection == detection,
                  confirmation.composedOutputSHA256 == detection.composedOutputSHA256,
                  confirmation.semanticTextSHA256 == detection.semanticTextSHA256,
                  confirmation.userConfirmedExactComposedBytes else { return nil }
            return confirmation
        } catch {
            return nil
        }
    }

    private var confirmationMayBeRequested: Bool {
        trustedDetection?.disposition == .pass && trustedConfirmation == nil
    }

    private var trustedHandoff: ShopOpenEvidenceHandoffReceiptV1? {
        guard let handoff,
              let profile = trustedProfile,
              let confirmation = trustedConfirmation else { return nil }
        do {
            let profileFrontier = try profile.reference
            guard handoff.profileFrontier == profileFrontier,
                  handoff.confirmation == confirmation,
                  handoff.detailReceipt.confirmation == confirmation,
                  handoff.detailReceipt.composedOutputSHA256 == confirmation.composedOutputSHA256,
                  handoff.packaging == profile.packaging,
                  handoff.artifacts.contains({
                      $0.format == handoff.confirmedFormat
                          && $0.sha256 == confirmation.composedOutputSHA256
                  }),
                  !handoff.externalOpenClaimed,
                  !handoff.deliveryClaimed else { return nil }
            return handoff
        } catch {
            return nil
        }
    }

    private func heading(_ key: ShopReportProfileLocalizationKeyV1, identifier: String) -> some View {
        Text(localized(key))
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func bodyText(_ key: ShopReportProfileLocalizationKeyV1) -> some View {
        Text(localized(key))
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func status(_ key: ShopReportProfileLocalizationKeyV1, kind: WorklightStatusKind, identifier: String) -> some View {
        WorklightStatusBadge(kind: kind, text: localized(key))
            .accessibilityIdentifier(identifier)
    }

    private func fact(_ key: ShopReportProfileLocalizationKeyV1, _ value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localized(key))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func activationLabel(_ activation: ShopReportProfileActivationV1) -> String {
        localized(activation == .on ? .activationOn : .activationOff)
    }

    private func packagingLabel(_ packaging: ShopOpenEvidencePackagingV1) -> String {
        localized(packaging == .combinedArchive ? .combinedPackage : .separatePackage)
    }

    private func audienceLabel(_ audience: ReportAudienceV1) -> String {
        switch audience {
        case .internalUse: return "Internal use"
        case .customerSafe: return "Customer-safe"
        }
    }

    private func localized(_ key: ShopReportProfileLocalizationKeyV1) -> String {
        BundledLocalizationCatalogV1.shopReportProfileLocalized(key)
    }
}

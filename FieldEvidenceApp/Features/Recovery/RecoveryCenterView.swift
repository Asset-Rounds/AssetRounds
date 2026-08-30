import SwiftUI

/// A noncanonical, read-only presentation of the existing recovery
/// authorities.  All effects are supplied by the owning coordinators; this
/// view does not create a writer, store, route, or support-export engine.
struct RecoveryCenterView: View {
    static let screenAccessibilityIdentifier = RecoveryCenterAccessibilityIDV1.screen.rawValue
    static let statusAccessibilityIdentifier = RecoveryCenterAccessibilityIDV1.status.rawValue
    static let standardBackupAccessibilityIdentifier = RecoveryCenterAccessibilityIDV1.standardBackup.rawValue
    static let encryptedBackupAccessibilityIdentifier = RecoveryCenterAccessibilityIDV1.encryptedBackup.rawValue
    static let supportDraftAccessibilityIdentifier = RecoveryCenterAccessibilityIDV1.supportDraft.rawValue
    static let privacyBlockedAccessibilityIdentifier = RecoveryCenterAccessibilityIDV1.privacyBlocked.rawValue

    let projection: RecoveryCenterProjectionV1
    let feedbackDraft: SupportFeedbackDraftV1?
    let feedbackHandoffPreview: FeedbackHandoffPreviewV1?
    let onRefresh: (() -> Void)?
    let onStandardBackup: (() -> Void)?
    let onEncryptedBackup: (() -> Void)?
    let onSupportPreview: (() -> Void)?
    let onSupportExport: (() -> Void)?
    let onPrivacyPolicy: (() -> Void)?
    let onPrimaryAction: ((RecoveryFailurePresentationV1) -> Void)?
    let onFallbackAction: ((RecoveryFailurePresentationV1) -> Void)?
    let onHelp: ((OperationalHelpTopicV1) -> Void)?
    let onFeedbackHandoff: ((FeedbackHandoffPreviewV1) -> Void)?

    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiatesWithoutColor
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    init(
        projection: RecoveryCenterProjectionV1,
        feedbackDraft: SupportFeedbackDraftV1? = nil,
        feedbackHandoffPreview: FeedbackHandoffPreviewV1? = nil,
        onRefresh: (() -> Void)? = nil,
        onStandardBackup: (() -> Void)? = nil,
        onEncryptedBackup: (() -> Void)? = nil,
        onSupportPreview: (() -> Void)? = nil,
        onSupportExport: (() -> Void)? = nil,
        onPrivacyPolicy: (() -> Void)? = nil,
        onPrimaryAction: ((RecoveryFailurePresentationV1) -> Void)? = nil,
        onFallbackAction: ((RecoveryFailurePresentationV1) -> Void)? = nil,
        onHelp: ((OperationalHelpTopicV1) -> Void)? = nil,
        onFeedbackHandoff: ((FeedbackHandoffPreviewV1) -> Void)? = nil
    ) {
        self.projection = projection
        self.feedbackDraft = feedbackDraft
        self.feedbackHandoffPreview = feedbackHandoffPreview
        self.onRefresh = onRefresh
        self.onStandardBackup = onStandardBackup
        self.onEncryptedBackup = onEncryptedBackup
        self.onSupportPreview = onSupportPreview
        self.onSupportExport = onSupportExport
        self.onPrivacyPolicy = onPrivacyPolicy
        self.onPrimaryAction = onPrimaryAction
        self.onFallbackAction = onFallbackAction
        self.onHelp = onHelp
        self.onFeedbackHandoff = onFeedbackHandoff
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                Text(localized(.intro))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                statusCard
                reliabilityCard
                standardBackupCard
                encryptedBackupCard
                supportCard
                feedbackCard
                privacyCard
            }
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .padding(.vertical, DesignTokens.Spacing.medium)
        }
        .navigationTitle(localized(.heading))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var standardBackupSource: RecoveryAuthoritySnapshotV1? {
        projection.reliability.sources.first { $0.source == .backup }
    }

    private var feedbackPreviewMatchesDraft: Bool {
        guard let draft = feedbackDraft, let preview = feedbackHandoffPreview else {
            return false
        }
        return (try? preview.validate(against: draft)) != nil
    }

    @ViewBuilder
    private var statusCard: some View {
        WorklightCard {
            statusBadge

            Text(localized(stateKey(projection.state)))
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Text(localized(.refreshAction))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
    }

    private var statusBadge: some View {
        Label {
            Text(localized(stateKey(projection.state)))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: stateIcon(projection.state))
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(stateColor(projection.state))
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, DesignTokens.Spacing.small)
        .frame(minHeight: DesignTokens.Control.minimumHitSize)
        .background(stateBackground(projection.state))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                .stroke(
                    differentiatesWithoutColor ? stateColor(projection.state) : .clear,
                    lineWidth: differentiatesWithoutColor ? 1 : 0
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(localized(.statusHeading)): \(localized(stateKey(projection.state)))")
        )
    }

    @ViewBuilder
    private var reliabilityCard: some View {
        WorklightCard {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
                Text(localized(.reliabilityHeading))
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                Spacer(minLength: DesignTokens.Spacing.small)
                Text(localized(.freshnessHeading))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            ForEach(Array(projection.reliability.sources.enumerated()), id: \.offset) { _, source in
                HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(localized(sourceKey(source.source)))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                        Text(localized(stateKey(source.state)))
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }
                    Spacer(minLength: DesignTokens.Spacing.small)
                    Text(localized(freshnessKey(source.freshness)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .multilineTextAlignment(.trailing)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }

            if !projection.reliability.failures.isEmpty {
                failureActions
            }
        }
    }

    @ViewBuilder
    private var failureActions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            Text(localized(.failureHeading))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)

            ForEach(Array(projection.reliability.failures.enumerated()), id: \.offset) { _, failure in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    if let actionKey = actionKey(failure.primaryAction) {
                        actionRow(
                            labelKey: .failurePrimary,
                            actionKey: actionKey,
                            action: onPrimaryAction.map { handler in { handler(failure) } }
                        )
                    }
                    if let fallback = failure.fallbackAction,
                       let actionKey = actionKey(fallback) {
                        actionRow(
                            labelKey: .failureFallback,
                            actionKey: actionKey,
                            action: onFallbackAction.map { handler in { handler(failure) } }
                        )
                    }
                    if let helpTopic = failure.helpTopic,
                       let helpKey = helpKey(helpTopic) {
                        actionRow(
                            labelKey: .failureHelp,
                            actionKey: helpKey,
                            action: onHelp.map { handler in { handler(helpTopic) } }
                        )
                    }
                }
                .padding(.top, DesignTokens.Spacing.small)
            }
        }
    }

    @ViewBuilder
    private func actionRow(
        labelKey: RecoveryCenterLocalizationKeyV1,
        actionKey: RecoveryCenterLocalizationKeyV1,
        action: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(localized(labelKey))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            if let action {
                Button {
                    action()
                } label: {
                    Text(localized(actionKey))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
            } else {
                Text(localized(actionKey))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var standardBackupCard: some View {
        WorklightCard {
            Text(localized(.backupStandardHeading))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)

            Text(localized(.backupStandardDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let source = standardBackupSource {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
                    Text(localized(.statusHeading))
                        .font(.subheadline.weight(.semibold))
                    Text(localized(stateKey(source.state)))
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            } else {
                Text(localized(.backupStandardUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onStandardBackup {
                Button {
                    onStandardBackup()
                } label: {
                    Text(localized(.backupStandardAction))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityHint(Text(localized(.backupStandardDescription)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.standardBackupAccessibilityIdentifier)
    }

    @ViewBuilder
    private var encryptedBackupCard: some View {
        WorklightCard {
            Text(localized(.encryptedBackupHeading))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)

            switch projection.encryptedBackup.state {
            case .available:
                Text(localized(.encryptedBackupAvailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let onEncryptedBackup {
                    Button {
                        onEncryptedBackup()
                    } label: {
                        Text(localized(.encryptedBackupAction))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(Text(localized(.encryptedBackupAvailable)))
                }
            case .unavailable:
                Text(localized(.encryptedBackupUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.encryptedBackupAccessibilityIdentifier)
    }

    @ViewBuilder
    private var supportCard: some View {
        WorklightCard {
            Text(localized(.supportHeading))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)

            if let preview = projection.supportExportPreview {
                Text(localized(.supportPreviewHeading))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)

                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
                    Text(localized(.supportPreviewEntries))
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                    Spacer(minLength: DesignTokens.Spacing.small)
                    Text(verbatim: preview.entries.count.formatted())
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                }
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
                    Text(localized(.supportPreviewBytes))
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                    Spacer(minLength: DesignTokens.Spacing.small)
                    Text(verbatim: preview.totalCanonicalByteCount.formatted())
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                }
                .accessibilityElement(children: .combine)

                Text(localized(.supportPreviewPrivacy))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(localized(.supportExternalEffect))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let onSupportPreview {
                    Button {
                        onSupportPreview()
                    } label: {
                        Text(localized(.supportPreviewAction))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(Text(localized(.supportPreviewPrivacy)))
                }
                if let onSupportExport {
                    Button {
                        onSupportExport()
                    } label: {
                        Text(localized(.supportExportAction))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .accessibilityHint(Text(localized(.supportExternalEffect)))
                }
            } else {
                Text(localized(.supportPreviewUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let onSupportPreview {
                    Button {
                        onSupportPreview()
                    } label: {
                        Text(localized(.supportPrepareAction))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackCard: some View {
        if let feedbackDraft {
            WorklightCard {
                Text(localized(.feedbackHeading))
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                Text(localized(.feedbackDraftAvailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let feedbackHandoffPreview {
                    if feedbackPreviewMatchesDraft {
                        Text(localized(.feedbackHandoffReady))
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(localized(.feedbackExternalEffect))
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let onFeedbackHandoff {
                            Button {
                                onFeedbackHandoff(feedbackHandoffPreview)
                            } label: {
                                Text(localized(.feedbackHandoffAction))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(WorklightSecondaryButtonStyle())
                            .accessibilityHint(Text(localized(.feedbackExternalEffect)))
                        }
                    } else {
                        Text(localized(.feedbackInvalid))
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.blockedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(localized(.feedbackHandoffUnavailable))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.supportDraftAccessibilityIdentifier)
        }
    }

    @ViewBuilder
    private var privacyCard: some View {
        WorklightCard {
            Text(localized(.privacyHeading))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)

            switch projection.privacyData.policy.status {
            case .draftLocal:
                Text(localized(.privacyDraftLocal))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .liveMatched:
                Text(localized(.privacyLiveAvailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if projection.privacyData.policy.livePolicyURL != nil,
                   let onPrivacyPolicy {
                    Button {
                        onPrivacyPolicy()
                    } label: {
                        Text(localized(.privacyAction))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(Text(localized(.privacyLiveAvailable)))
                }
            case .blocked:
                Text(localized(.privacyBlocked))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.privacyBlockedAccessibilityIdentifier)
            }
        }
    }

    private func localized(_ key: RecoveryCenterLocalizationKeyV1) -> String {
        BundledLocalizationCatalogV1.recoveryCenterLocalized(key)
    }

    private func stateKey(
        _ state: RecoveryCenterStateV1
    ) -> RecoveryCenterLocalizationKeyV1 {
        switch state {
        case .healthy: return .stateHealthy
        case .checking: return .stateChecking
        case .actionable: return .stateActionable
        case .inProgress: return .stateInProgress
        case .interrupted: return .stateInterrupted
        case .fileRequired: return .stateFileRequired
        case .validationFailed: return .stateValidationFailed
        case .partialSafe: return .statePartialSafe
        case .complete: return .stateComplete
        case .restartRequired: return .stateRestartRequired
        case .externalActionRequired: return .stateExternalActionRequired
        }
    }

    private func sourceKey(
        _ source: RecoveryAuthoritySourceV1
    ) -> RecoveryCenterLocalizationKeyV1 {
        switch source {
        case .backup: return .sourceBackup
        case .restore: return .sourceRestore
        case .generation: return .sourceGeneration
        case .finalization: return .sourceFinalization
        case .reporting: return .sourceReporting
        case .storage: return .sourceStorage
        case .protectedData: return .sourceProtectedData
        case .jobs: return .sourceJobs
        case .packageReadiness: return .sourcePackageReadiness
        case .commerce: return .sourceCommerce
        case .diagnostics: return .sourceDiagnostics
        }
    }

    private func freshnessKey(
        _ freshness: RecoverySourceFreshnessV1
    ) -> RecoveryCenterLocalizationKeyV1 {
        switch freshness {
        case .current: return .freshnessCurrent
        case .historic: return .freshnessHistoric
        case .unavailable: return .freshnessUnavailable
        }
    }

    private func actionKey(
        _ action: OperationalActionV1
    ) -> RecoveryCenterLocalizationKeyV1? {
        switch action {
        case .cancel: return .actionCancel
        case .chooseFile: return .actionChooseFile
        case .closeOtherOperation: return .actionCloseOtherOperation
        case .contactSupport: return .actionContactSupport
        case .freeStorage: return .actionFreeStorage
        case .none: return nil
        case .openSettings: return .actionOpenSettings
        case .retry: return .actionRetry
        case .restart: return .actionRestart
        case .resume: return .actionResume
        case .unlockDevice: return .actionUnlockDevice
        }
    }

    private func helpKey(
        _ topic: OperationalHelpTopicV1
    ) -> RecoveryCenterLocalizationKeyV1? {
        switch topic {
        case .backup: return .helpBackup
        case .commerce: return .helpCommerce
        case .diagnosticsReset: return .helpDiagnosticsReset
        case .permissions: return .helpPermissions
        case .reports: return .helpReports
        case .storage: return .helpStorage
        case .supportExport: return .helpSupportExport
        }
    }

    private func stateIcon(_ state: RecoveryCenterStateV1) -> String {
        switch state {
        case .healthy, .complete: return "checkmark.circle.fill"
        case .checking, .inProgress: return "arrow.triangle.2.circlepath"
        case .actionable, .interrupted, .partialSafe: return "exclamationmark.triangle.fill"
        case .fileRequired, .validationFailed, .restartRequired, .externalActionRequired:
            return "xmark.octagon.fill"
        }
    }

    private func stateColor(_ state: RecoveryCenterStateV1) -> Color {
        switch state {
        case .healthy, .complete: return DesignTokens.Colors.completeText
        case .checking, .inProgress: return DesignTokens.Colors.informationText
        case .actionable, .interrupted, .partialSafe: return DesignTokens.Colors.attentionText
        case .fileRequired, .validationFailed, .restartRequired, .externalActionRequired:
            return DesignTokens.Colors.blockedText
        }
    }

    private func stateBackground(_ state: RecoveryCenterStateV1) -> Color {
        switch state {
        case .healthy, .complete: return DesignTokens.Colors.completeContainer
        case .checking, .inProgress: return DesignTokens.Colors.informationContainer
        case .actionable, .interrupted, .partialSafe: return DesignTokens.Colors.attentionContainer
        case .fileRequired, .validationFailed, .restartRequired, .externalActionRequired:
            return DesignTokens.Colors.blockedContainer
        }
    }
}

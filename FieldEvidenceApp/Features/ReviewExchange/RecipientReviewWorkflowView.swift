import SwiftUI

/// An isolated C35 review surface. Commands are supplied by the caller from
/// the canonical C48/C54 contracts; the view adds no store, writer, crypto,
/// document route, or retained passphrase state.
@MainActor
struct RecipientReviewWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c35.recipient-review.screen"
    static let trustAccessibilityIdentifier = "v23.p04.c35.recipient-review.trust"
    static let encryptionAccessibilityIdentifier = "v23.p04.c35.recipient-review.encryption"
    static let previewAccessibilityIdentifier = "v23.p04.c35.recipient-review.preview"
    static let statusAccessibilityIdentifier = "v23.p04.c35.recipient-review.status"

    let coordinator: RecipientReviewWorkflowCoordinatorV1
    let context: RecipientReviewWorkflowContextV1
    let commands: [RecipientReviewWorkflowCommandV1]
    let onOutcome: (@MainActor (RecipientReviewWorkflowCommandOutcomeV1) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var projection: RecipientReviewWorkflowProjectionV1?
    @State private var isPerforming = false
    @State private var operationMessage: String?
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    private enum FocusTarget: Hashable {
        case heading
        case errorSummary
        case operationStatus
    }

    init(
        coordinator: RecipientReviewWorkflowCoordinatorV1,
        context: RecipientReviewWorkflowContextV1,
        commands: [RecipientReviewWorkflowCommandV1] = [],
        onOutcome: (@MainActor (RecipientReviewWorkflowCommandOutcomeV1) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.context = context
        self.commands = commands
        self.onOutcome = onOutcome
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                trustDisclosure
                if let projection {
                    recipientReadiness(projection)
                    exchangeProtection(projection)
                    recipientResponse(projection)
                    responseReceivedElsewhere
                    previewAndAcceptance(projection)
                    recovery
                    operatingBoundaries
                } else {
                    loadingOrUnavailable
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.recipientReviewNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .task { await reloadProjection() }
        .onChange(of: operationMessage) { _, _ in
            accessibilityFocus = .operationStatus
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? DesignTokens.Spacing.large : DesignTokens.Spacing.medium
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trustDisclosure: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.recipientReviewTrustHeading), identifier: Self.trustAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewTrustDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var loadingOrUnavailable: some View {
        WorklightCard {
            if operationMessage == nil {
                Label(BundledLocalizationCatalogV1.v30Text(.recipientReviewLoading), systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                Label(BundledLocalizationCatalogV1.v30Text(.recipientReviewUnavailable), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .accessibilityFocused($accessibilityFocus, equals: .errorSummary)
            }
            if let operationMessage {
                Text(operationMessage)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func recipientReadiness(_ projection: RecipientReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.recipientReviewIsolatedHeading), identifier: "\(Self.screenAccessibilityIdentifier).readiness")
            stateRow(BundledLocalizationCatalogV1.v30Text(.recipientReviewRequest), value: projection.requestPublicID.rawValue)
            stateRow(BundledLocalizationCatalogV1.v30Text(.recipientReviewSession), value: lifecycleText(projection.lifecycleState))
            stateRow(BundledLocalizationCatalogV1.v30Text(.recipientReviewManifest), value: projection.hasReplayableManifest ? BundledLocalizationCatalogV1.v30Text(.recipientReviewReplayable) : BundledLocalizationCatalogV1.v30Text(.recipientReviewUnavailable))
            stateRow(BundledLocalizationCatalogV1.v30Text(.recipientReviewRequestPackage), value: projection.hasReplayablePackage ? BundledLocalizationCatalogV1.v30Text(.recipientReviewReplayable) : BundledLocalizationCatalogV1.v30Text(.recipientReviewUnavailable))
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewIsolatedDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .accessibilityElement(children: .contain)
    }

    private func exchangeProtection(_ projection: RecipientReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.recipientReviewExchangeProtectionHeading), identifier: Self.encryptionAccessibilityIdentifier)
            switch projection.encryptionAvailability {
            case .manualPassphraseAvailable:
                Label(BundledLocalizationCatalogV1.v30Text(.recipientReviewEncryptedAvailable), systemImage: "lock")
                    .foregroundStyle(DesignTokens.Colors.informationText)
                Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewEncryptedAvailableDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            case .disabled:
                Label(BundledLocalizationCatalogV1.v30Text(.recipientReviewEncryptedDisabled), systemImage: "lock.slash")
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            case .unavailable:
                Label(BundledLocalizationCatalogV1.v30Text(.recipientReviewEncryptedUnavailable), systemImage: "exclamationmark.lock")
                    .foregroundStyle(DesignTokens.Colors.blockedText)
            }
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewEncryptionDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewClearWarningDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.recipientReviewReplayClearRequest), command: command(named: .replayClearRequest))
        }
        .accessibilityElement(children: .contain)
    }

    private func recipientResponse(_ projection: RecipientReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.recipientReviewResponseHeading), identifier: "\(Self.screenAccessibilityIdentifier).response")
            Text(projection.canCreateResponse
                 ? BundledLocalizationCatalogV1.v30Text(.recipientReviewResponseAvailable)
                 : BundledLocalizationCatalogV1.v30Text(.recipientReviewResponseUnavailable))
                .font(.body)
                .foregroundStyle(projection.canCreateResponse ? DesignTokens.Colors.primaryText : DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewResponseDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.recipientReviewCreateResponse), command: command(named: .createResponse), disabled: !projection.canCreateResponse)
        }
        .accessibilityElement(children: .contain)
    }

    private var responseReceivedElsewhere: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.recipientReviewResponseElsewhereHeading), identifier: "\(Self.screenAccessibilityIdentifier).elsewhere")
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewResponseElsewhereDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.recipientReviewRecordExternalResponse), command: command(named: .recordResponseReceivedElsewhere))
        }
        .accessibilityElement(children: .contain)
    }

    private func previewAndAcceptance(_ projection: RecipientReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.recipientReviewPreviewHeading), identifier: Self.previewAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewPreviewDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewDecisionDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.recipientReviewPreviewImport), command: command(named: .previewImport))
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.recipientReviewAcceptAndApply), command: command(named: .acceptAndApply))
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.recipientReviewFinalizeSessionDecision), command: command(named: .finalizeSessionOnly))
            operationStatus
            if projection.previewWrites {
                Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewPreviewUnavailable))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var recovery: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.recipientReviewRecoveryHeading), identifier: "\(Self.screenAccessibilityIdentifier).recovery")
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewRecoveryDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.recipientReviewRecoverAcceptance), command: command(named: .recoverAcceptAndApply))
        }
        .accessibilityElement(children: .contain)
    }

    private var operatingBoundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.recipientReviewBoundariesHeading), identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewOfflineBoundary))
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewCustomerSafeBoundary))
            Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewResponseBoundary))
            if reduceMotion {
                Text(BundledLocalizationCatalogV1.v30Text(.recipientReviewReduceMotionDescription))
            }
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var operationStatus: some View {
        if let operationMessage {
            Label(operationMessage, systemImage: "info.circle")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.informationText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($accessibilityFocus, equals: .operationStatus)
                .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
        }
    }

    @ViewBuilder
    private func commandButton(
        title: String,
        command: RecipientReviewWorkflowCommandV1?,
        disabled: Bool = false
    ) -> some View {
        if let command {
            Button(title) { perform(command) }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(disabled || isPerforming)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.recipientReviewCommandHint))
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text(BundledLocalizationCatalogV1.v30RecipientReviewUnavailableCommand(title: title))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
    }

    private func sectionHeading(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func stateRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.body.weight(.semibold))
            Spacer(minLength: DesignTokens.Spacing.small)
            Text(value)
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func lifecycleText(_ state: PortableExchangeSessionStateV2?) -> String {
        guard let state else { return BundledLocalizationCatalogV1.v30Text(.recipientReviewNoLocalSession) }
        return state.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private func command(named name: CommandName) -> RecipientReviewWorkflowCommandV1? {
        commands.first { command in
            switch (name, command) {
            case (.replayClearRequest, .replayClearRequest), (.createResponse, .createResponse),
                 (.previewImport, .previewImport), (.acceptAndApply, .acceptAndApply),
                 (.finalizeSessionOnly, .finalizeSessionOnly),
                 (.recordResponseReceivedElsewhere, .recordResponseReceivedElsewhere),
                 (.recoverAcceptAndApply, .recoverAcceptAndApply):
                return true
            default:
                return false
            }
        }
    }

    private enum CommandName {
        case replayClearRequest, createResponse, previewImport, acceptAndApply
        case finalizeSessionOnly, recordResponseReceivedElsewhere, recoverAcceptAndApply
    }

    private func commandIdentifier(_ command: RecipientReviewWorkflowCommandV1) -> String {
        switch command {
        case .replayClearRequest: return "replay-clear"
        case .createResponse: return "create-response"
        case .previewImport: return "preview"
        case .acceptAndApply: return "accept-and-apply"
        case .finalizeSessionOnly: return "session-only"
        case .recordResponseReceivedElsewhere: return "received-elsewhere"
        case .recoverAcceptAndApply: return "recover"
        }
    }

    private func reloadProjection() async {
        do {
            projection = try await coordinator.projection(context: context)
            accessibilityFocus = projection?.hasReplayablePackage == false ? .errorSummary : .heading
        } catch {
            projection = nil
            operationMessage = BundledLocalizationCatalogV1.v30Text(.recipientReviewRecordUnavailable)
        }
    }

    private func perform(_ command: RecipientReviewWorkflowCommandV1) {
        guard !isPerforming else { return }
        isPerforming = true
        operationMessage = BundledLocalizationCatalogV1.v30Text(.recipientReviewSubmittingCommand)
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let outcome = try await coordinator.execute(command, context: context)
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.recipientReviewCancelled)
                    return
                }
                operationMessage = outcomeText(outcome)
                onOutcome?(outcome)
                await reloadProjection()
            } catch is CancellationError {
                operationMessage = BundledLocalizationCatalogV1.v30Text(.recipientReviewCancelled)
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.recipientReviewCancelled)
                    return
                }
                operationMessage = BundledLocalizationCatalogV1.v30Text(.recipientReviewCommandNotCompleted)
            }
        }
    }

    private func outcomeText(_ outcome: RecipientReviewWorkflowCommandOutcomeV1) -> String {
        switch outcome {
        case .requestReplay:
            return BundledLocalizationCatalogV1.v30Text(.recipientReviewClearRequestReplayed)
        case .responseCreated:
            return BundledLocalizationCatalogV1.v30Text(.recipientReviewResponseCreated)
        case .importPreview:
            return BundledLocalizationCatalogV1.v30Text(.recipientReviewImportPreviewComplete)
        case .canonicalApplied:
            return BundledLocalizationCatalogV1.v30Text(.recipientReviewApplicationComplete)
        case .sessionFinalized:
            return BundledLocalizationCatalogV1.v30Text(.recipientReviewSessionDecisionComplete)
        case .unverifiedHistoryRecorded:
            return BundledLocalizationCatalogV1.v30Text(.recipientReviewExternalResponseRecorded)
        case .recovered:
            return BundledLocalizationCatalogV1.v30Text(.recipientReviewRecoveryComplete)
        }
    }
}

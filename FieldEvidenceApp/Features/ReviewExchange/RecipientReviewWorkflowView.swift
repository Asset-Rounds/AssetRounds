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
        .navigationTitle("Recipient review")
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
            Text("Recipient review")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("Review a portable request offline, without entitlement and outside normal workspaces.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trustDisclosure: some View {
        WorklightCard {
            sectionHeading("Trust disclosure", identifier: Self.trustAccessibilityIdentifier)
            Text("A matching response proof shows possession of the request capability and detects a changed response for that request. It does not establish identity, authority, personal review, delivery, read status, legal effect, or approval.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var loadingOrUnavailable: some View {
        WorklightCard {
            if operationMessage == nil {
                Label("Loading recipient review", systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                Label("Recipient review unavailable", systemImage: "exclamationmark.triangle.fill")
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
            sectionHeading("Isolated review", identifier: "\(Self.screenAccessibilityIdentifier).readiness")
            stateRow("Request", value: projection.requestPublicID.rawValue)
            stateRow("Session", value: lifecycleText(projection.lifecycleState))
            stateRow("Manifest", value: projection.hasReplayableManifest ? "Replayable" : "Unavailable")
            stateRow("Request package", value: projection.hasReplayablePackage ? "Replayable" : "Unavailable")
            Text("This mode does not open or create a normal workspace.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .accessibilityElement(children: .contain)
    }

    private func exchangeProtection(_ projection: RecipientReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Exchange protection", identifier: Self.encryptionAccessibilityIdentifier)
            switch projection.encryptionAvailability {
            case .manualPassphraseAvailable:
                Label("Passphrase-encrypted review exchange is available.", systemImage: "lock")
                    .foregroundStyle(DesignTokens.Colors.informationText)
                Text("Enter a passphrase again only in the native protected operation. This view does not retain a passphrase, key, or capability.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            case .disabled:
                Label("Encrypted exchange is disabled. Use only the explicit clear/manual path when appropriate.", systemImage: "lock.slash")
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            case .unavailable:
                Label("Encrypted exchange is unavailable. A typed manual fallback remains explicit.", systemImage: "exclamationmark.lock")
                    .foregroundStyle(DesignTokens.Colors.blockedText)
            }
            Text("Wrong passphrase and damaged encrypted-envelope failures are intentionally presented as one neutral error. Encryption does not establish identity, authority, delivery, approval, or legal effect.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Legacy clear files require an explicit visible warning acknowledgement before they can be replayed or read.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: "Replay clear request after warning", command: command(named: .replayClearRequest))
        }
        .accessibilityElement(children: .contain)
    }

    private func recipientResponse(_ projection: RecipientReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Recipient response", identifier: "\(Self.screenAccessibilityIdentifier).response")
            Text(projection.canCreateResponse
                 ? "A canonical response can be created from the supplied request manifest and capability."
                 : "A response cannot be created until the supplied manifest and request package are available.")
                .font(.body)
                .foregroundStyle(projection.canCreateResponse ? DesignTokens.Colors.primaryText : DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Response author text is self-entered assertion, not verified identity. Review disposition remains a recorded response, not an approval claim by this screen.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: "Create supplied response", command: command(named: .createResponse), disabled: !projection.canCreateResponse)
        }
        .accessibilityElement(children: .contain)
    }

    private var responseReceivedElsewhere: some View {
        WorklightCard {
            sectionHeading("Response received elsewhere", identifier: "\(Self.screenAccessibilityIdentifier).elsewhere")
            Text("Record a response received elsewhere only through the supplied canonical command. It remains unverified by AssetRounds and is not applied to the canonical workspace.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: "Record unverified external response", command: command(named: .recordResponseReceivedElsewhere))
        }
        .accessibilityElement(children: .contain)
    }

    private func previewAndAcceptance(_ projection: RecipientReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Preview and explicit acceptance", identifier: Self.previewAccessibilityIdentifier)
            Text("Preview checks the supplied response and current review basis without a write. Import never applies automatically.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose one supplied decision after preview: ACCEPT_AND_APPLY, record as history only, discard unimported, or keep quarantined. Quarantine and discard do not create a workspace receipt.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: "Preview supplied import", command: command(named: .previewImport))
            commandButton(title: "Explicitly accept and apply", command: command(named: .acceptAndApply))
            commandButton(title: "Finalize supplied session-only decision", command: command(named: .finalizeSessionOnly))
            operationStatus
            if projection.previewWrites {
                Text("Preview write status is unavailable; do not accept or apply until a fresh zero-write preview is supplied.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var recovery: some View {
        WorklightCard {
            sectionHeading("Recovery", identifier: "\(Self.screenAccessibilityIdentifier).recovery")
            Text("Retry reuses the supplied mutation identity and returns its existing effect or receipt, or no effect. Reload the canonical record after interruption.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: "Recover supplied acceptance", command: command(named: .recoverAcceptAndApply))
        }
        .accessibilityElement(children: .contain)
    }

    private var operatingBoundaries: some View {
        WorklightCard {
            sectionHeading("Operating boundaries", identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text("Offline: this surface makes no network, sent, delivered, or read claim.")
            Text("Customer-safe exchange excludes stable workspace IDs, raw originals, internal notes, contact records, and local paths.")
            Text("No response is rendered as secure, verified, approved, accepted, signed, or legally effective by this surface.")
            if reduceMotion {
                Text("Reduce Motion is on. State changes are presented without added animation.")
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
                .accessibilityHint("Uses the supplied canonical recipient-review command.")
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text("\(title) is unavailable until its canonical command is supplied.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
    }

    private func sectionHeading(_ title: LocalizedStringKey, identifier: String) -> some View {
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
        guard let state else { return "No local review session" }
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
            operationMessage = "The current recipient-review record could not be loaded. No command was accepted."
        }
    }

    private func perform(_ command: RecipientReviewWorkflowCommandV1) {
        guard !isPerforming else { return }
        isPerforming = true
        operationMessage = "Submitting the supplied recipient-review command…"
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let outcome = try await coordinator.execute(command, context: context)
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
                    return
                }
                operationMessage = outcomeText(outcome)
                onOutcome?(outcome)
                await reloadProjection()
            } catch is CancellationError {
                operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
                    return
                }
                operationMessage = "The supplied command was not completed. The current record remains the source of truth."
            }
        }
    }

    private func outcomeText(_ outcome: RecipientReviewWorkflowCommandOutcomeV1) -> String {
        switch outcome {
        case .requestReplay:
            return "The clear request was replayed after its explicit warning acknowledgement."
        case .responseCreated:
            return "The supplied recipient response was created from the canonical request inputs."
        case .importPreview:
            return "The import preview is complete and made no canonical write. Choose an explicit decision."
        case .canonicalApplied:
            return "The explicit canonical application completed. Refresh from the current workspace record."
        case .sessionFinalized:
            return "The supplied session-only decision was recorded without canonical workspace application."
        case .unverifiedHistoryRecorded:
            return "The response received elsewhere was recorded as unverified history only."
        case .recovered:
            return "Recovery completed. Refresh from the canonical record before continuing."
        }
    }
}

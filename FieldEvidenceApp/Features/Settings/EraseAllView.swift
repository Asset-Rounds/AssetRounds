import SwiftUI

struct EraseAllView: View {
    static let settingsEntryAccessibilityIdentifier = "s6.6.settings.erase-all"
    static let maintenanceEntryAccessibilityIdentifier = "s6.6.maintenance.erase-all"
    static let screenAccessibilityIdentifier = "s6.6.erase.screen"
    static let confirmationAccessibilityIdentifier = "s6.6.erase.confirmation"
    static let cancelAccessibilityIdentifier = "s6.6.erase.cancel"
    static let eraseAccessibilityIdentifier = "s6.6.erase.confirm"
    static let errorAccessibilityIdentifier = "s6.6.erase.error"

    static let title = "Erase All"
    static let warning = "Erase all local sign details, notes, photos, reports, and the anonymous free-report count from this app. This cannot be undone."
    static let subscriptionCopy = "This does not cancel your Apple subscription. Backups saved outside this app are not deleted."

    @Environment(\.dismiss) private var dismiss
    @FocusState private var confirmationFocused: Bool

    @ObservedObject var coordinator: StoreSessionCoordinator
    let diagnosticsStore: DiagnosticsStore
    let applicationSupportURL: URL
    let onBegin: @MainActor () -> Void
    let onActivate: @MainActor (StoreGenerationSession) async -> Void
    let onDeferred: @MainActor (StoreGenerationSession) async -> Void
    let onFinished: @MainActor (StoreGenerationSession) async -> Void
    let onFailure: @MainActor () -> Void

    @State private var confirmation = ""
    @State private var isErasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                AssetRoundsEvidenceCard {
                    Text(Self.title)
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(Self.warning)
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(Self.subscriptionCopy)
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Type ERASE to continue.")
                        .font(DesignTokens.Typography.sectionHeading)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("ERASE", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($confirmationFocused)
                        .frame(
                            minHeight: DesignTokens.Target.minimumInteractiveHeight
                        )
                        .padding(.horizontal, DesignTokens.Spacing.space8)
                        .background(DesignTokens.SemanticColors.workBackground)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: DesignTokens.Radius.standard
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: DesignTokens.Radius.standard
                            )
                            .stroke(
                                DesignTokens.SemanticColors.separator,
                                lineWidth: DesignTokens.Stroke.standard
                            )
                        }
                        .accessibilityLabel("Type ERASE")
                        .accessibilityIdentifier(
                            Self.confirmationAccessibilityIdentifier
                        )

                    if let errorMessage {
                        AssetRoundsStateLabel(
                            kind: .error,
                            text: Text(errorMessage)
                        )
                            .accessibilityLabel(Text(errorMessage))
                            .accessibilityValue(Text(verbatim: String()))
                            .accessibilityIdentifier(
                                Self.errorAccessibilityIdentifier
                            )
                    }

                    AssetRoundsSecondaryAction("Cancel") {
                        dismiss()
                    }
                    .disabled(isErasing)
                    .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)

                    AssetRoundsDestructiveAction(action: {
                        beginErase()
                    }) {
                        if isErasing {
                            HStack(spacing: DesignTokens.Spacing.space8) {
                                ProgressView()
                                Text("Erasing local data")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(Self.title)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(
                        isErasing
                            || confirmation
                                != EraseAllService.requiredConfirmation
                    )
                    .accessibilityIdentifier(Self.eraseAccessibilityIdentifier)
                }
                .padding(DesignTokens.Spacing.space16)
            }
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.SemanticColors.workBackground)
            .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        }
        .interactiveDismissDisabled(isErasing)
    }

    private func beginErase() {
        guard confirmation == EraseAllService.requiredConfirmation,
              !isErasing else {
            confirmationFocused = true
            return
        }
        confirmationFocused = false
        isErasing = true
        errorMessage = nil
        let coordinator = coordinator
        let diagnosticsStore = diagnosticsStore
        let applicationSupportURL = applicationSupportURL
        let onActivate = onActivate
        let onDeferred = onDeferred
        let onFinished = onFinished
        let onFailure = onFailure
        onBegin()
        dismiss()
        Task { @MainActor [
            coordinator,
            diagnosticsStore,
            applicationSupportURL,
            onActivate,
            onDeferred,
            onFinished,
            onFailure
        ] in
            await Task.yield()
            do {
                let outcome = try await EraseAllService(
                    applicationSupportURL: applicationSupportURL
                ).erase(
                    confirmation: confirmation,
                    coordinator: coordinator,
                    diagnosticsStore: diagnosticsStore,
                    activate: onActivate
                )
                if outcome.cleanupDeferred {
                    await onDeferred(outcome.session)
                } else {
                    await onFinished(outcome.session)
                }
            } catch {
                onFailure()
            }
        }
    }
}

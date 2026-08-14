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
    let onActivate: @MainActor (StoreGenerationSession) async -> Void
    let onFinished: @MainActor (StoreGenerationSession) async -> Void
    let onFailure: @MainActor () -> Void

    @State private var confirmation = ""
    @State private var isErasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                WorklightCard {
                    Text(Self.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.blockedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(Self.warning)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(Self.subscriptionCopy)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Type ERASE to continue.")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("ERASE", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($confirmationFocused)
                        .frame(
                            minHeight: DesignTokens.Control.minimumHitSize
                        )
                        .padding(.horizontal, DesignTokens.Spacing.small)
                        .background(DesignTokens.Colors.canvas)
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
                                DesignTokens.Colors.essentialControlStroke,
                                lineWidth: 1
                            )
                        }
                        .accessibilityLabel("Type ERASE")
                        .accessibilityIdentifier(
                            Self.confirmationAccessibilityIdentifier
                        )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.blockedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(
                                Self.errorAccessibilityIdentifier
                            )
                    }

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .disabled(isErasing)
                    .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)

                    Button {
                        beginErase()
                    } label: {
                        if isErasing {
                            HStack(spacing: DesignTokens.Spacing.small) {
                                ProgressView()
                                Text("Erasing local data")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(Self.title)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(EraseDestructiveButtonStyle())
                    .disabled(
                        isErasing
                            || confirmation
                                != EraseAllService.requiredConfirmation
                    )
                    .accessibilityIdentifier(Self.eraseAccessibilityIdentifier)
                }
                .padding(DesignTokens.Spacing.medium)
            }
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Colors.canvas)
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
        Task { @MainActor in
            do {
                let session = try await EraseAllService(
                    applicationSupportURL: applicationSupportURL
                ).erase(
                    confirmation: confirmation,
                    coordinator: coordinator,
                    diagnosticsStore: diagnosticsStore,
                    activate: onActivate
                )
                await onFinished(session)
            } catch {
                isErasing = false
                errorMessage = "Erase could not finish safely. Local data changes are blocked while recovery checks run."
                onFailure()
            }
        }
    }
}

private struct EraseDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(
                isEnabled
                    ? DesignTokens.Colors.blockedText
                    : DesignTokens.Colors.secondaryText
            )
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .frame(
                maxWidth: .infinity,
                minHeight: DesignTokens.Control.minimumHitSize
            )
            .background(
                isEnabled
                    ? DesignTokens.Colors.blockedContainer
                    : DesignTokens.Colors.raisedSurface
            )
            .clipShape(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                    .stroke(
                        DesignTokens.Colors.essentialControlStroke,
                        lineWidth: 1
                    )
            }
            .brightness(configuration.isPressed && isEnabled ? -0.08 : 0)
            .contentShape(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
            )
    }
}

import SwiftUI

struct StartupMaintenanceView: View {
    static let titleText = "Local data needs attention"
    static let messageText = "The app stopped to avoid changing or losing local records."
    static let recoveryStepsText = "If Retry cannot recover this device, delete and reinstall the app. This removes all local app data and does not cancel your Apple subscription. A backup stored outside this app can be restored from Welcome after reinstalling."
    static let retryButtonText = "Retry checks"
    static let recoveryButtonText = "Recovery steps"

    static let screenAccessibilityIdentifier = "s2.maintenance.screen"
    static let retryAccessibilityIdentifier = "s2.maintenance.retry"
    static let recoveryButtonAccessibilityIdentifier = "s2.maintenance.recovery.button"
    static let recoveryTextAccessibilityIdentifier = "s2.maintenance.recovery.text"
    static let restoreAccessibilityIdentifier = "s6.4.maintenance.restore-data-backup"

    let reason: StartupMaintenanceReason
    let retryChecks: () -> Void
    let restoreDataBackup: (() -> Void)?

    @State private var showsRecoverySteps = false

    init(
        reason: StartupMaintenanceReason,
        retryChecks: @escaping () -> Void,
        restoreDataBackup: (() -> Void)? = nil
    ) {
        self.reason = reason
        self.retryChecks = retryChecks
        self.restoreDataBackup = restoreDataBackup
    }

    var body: some View {
        ScrollView {
            WorklightCard {
                Text(Self.titleText)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(Self.messageText)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: retryChecks) {
                    Label(Self.retryButtonText, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityIdentifier(Self.retryAccessibilityIdentifier)

                if let restoreDataBackup {
                    Button("Restore data backup", action: restoreDataBackup)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier(Self.restoreAccessibilityIdentifier)
                }

                Button {
                    showsRecoverySteps.toggle()
                } label: {
                    Label(
                        Self.recoveryButtonText,
                        systemImage: showsRecoverySteps ? "chevron.up" : "chevron.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityValue(showsRecoverySteps ? "Expanded" : "Collapsed")
                .accessibilityIdentifier(Self.recoveryButtonAccessibilityIdentifier)

                if showsRecoverySteps {
                    Text(Self.recoveryStepsText)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.recoveryTextAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            DesignTokens.Colors.canvas
                .ignoresSafeArea()
        }
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }
}

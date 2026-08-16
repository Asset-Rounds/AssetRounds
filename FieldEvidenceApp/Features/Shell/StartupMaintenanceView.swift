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
    static let eraseAccessibilityIdentifier = "s6.6.maintenance.erase-all"

    let reason: StartupMaintenanceReason
    let retryChecks: () -> Void
    let restoreDataBackup: (() -> Void)?
    let eraseAll: (() -> Void)?

    @State private var showsRecoverySteps = false

    init(
        reason: StartupMaintenanceReason,
        retryChecks: @escaping () -> Void,
        restoreDataBackup: (() -> Void)? = nil,
        eraseAll: (() -> Void)? = nil
    ) {
        self.reason = reason
        self.retryChecks = retryChecks
        self.restoreDataBackup = restoreDataBackup
        self.eraseAll = eraseAll
    }

    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                AssetRoundsEvidenceCard {
                    Text(Self.titleText)
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(Self.messageText)
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    AssetRoundsPrimaryAction(action: retryChecks) {
                        Label(Self.retryButtonText, systemImage: "arrow.clockwise")
                    }
                    .accessibilityLabel(Self.retryButtonText)
                    .accessibilityIdentifier(Self.retryAccessibilityIdentifier)

                    if let restoreDataBackup {
                        AssetRoundsSecondaryAction(
                            "Restore data backup",
                            action: restoreDataBackup
                        )
                        .accessibilityLabel("Restore data backup")
                        .accessibilityIdentifier(Self.restoreAccessibilityIdentifier)
                    }

                    if let eraseAll {
                        AssetRoundsSecondaryAction("Erase All", action: eraseAll)
                            .accessibilityLabel("Erase All")
                            .accessibilityIdentifier(Self.eraseAccessibilityIdentifier)
                    }

                    AssetRoundsSecondaryAction(action: {
                        showsRecoverySteps.toggle()
                    }) {
                        Label(
                            Self.recoveryButtonText,
                            systemImage: showsRecoverySteps ? "chevron.up" : "chevron.down"
                        )
                    }
                    .accessibilityLabel(Self.recoveryButtonText)
                    .accessibilityValue(showsRecoverySteps ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier(Self.recoveryButtonAccessibilityIdentifier)

                    if showsRecoverySteps {
                        Text(Self.recoveryStepsText)
                            .font(DesignTokens.Typography.primaryBody)
                            .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(Self.recoveryTextAccessibilityIdentifier)
                    }
                }
            }
        }
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }
}

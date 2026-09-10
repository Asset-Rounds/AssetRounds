import SwiftUI

struct StartupMaintenanceView: View {
    static let titleText = BundledLocalizationCatalogV1.v30Text(.startupMaintenanceTitle)
    static let messageText = BundledLocalizationCatalogV1.v30Text(.startupMaintenanceMessage)
    static let recoveryStepsText = BundledLocalizationCatalogV1.v30Text(.startupMaintenanceRecoverySteps)
    static let retryButtonText = BundledLocalizationCatalogV1.v30Text(.startupMaintenanceRetryChecks)
    static let recoveryButtonText = BundledLocalizationCatalogV1.v30Text(.startupMaintenanceRecoveryStepsButton)

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
                    Button(BundledLocalizationCatalogV1.v30Text(.startupMaintenanceRestoreDataBackup), action: restoreDataBackup)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier(Self.restoreAccessibilityIdentifier)
                }

                if let eraseAll {
                    Button(BundledLocalizationCatalogV1.v30Text(.startupMaintenanceEraseAll), action: eraseAll)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier(Self.eraseAccessibilityIdentifier)
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
                .accessibilityValue(showsRecoverySteps ? BundledLocalizationCatalogV1.v30Text(.startupMaintenanceExpanded) : BundledLocalizationCatalogV1.v30Text(.startupMaintenanceCollapsed))
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

import SwiftUI

/// Successful publication still requires a genuinely separate process to
/// validate the store. This is not the destructive maintenance fallback.
struct StartupMigrationValidationView: View {
    let retryChecks: () -> Void
    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                AssetRoundsEvidenceCard {
                    Text("Restart to finish updating local data")
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your local data has been preserved. Close AssetRounds completely, then reopen it to finish validation. Retry checks cannot replace a restart.")
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    AssetRoundsPrimaryAction(action: retryChecks) {
                        Label("Retry checks", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("v23.migration.awaiting-validation.retry")
                }
            }
        }
        .accessibilityIdentifier("v23.migration.awaiting-validation.screen")
    }
}

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
    /// Support path (blueprint: post-activation failures enter
    /// maintenance/export/support). Reuses the Settings diagnostics label.
    static let viewDiagnosticsButtonText = "View diagnostics"
    static let viewDiagnosticsAccessibilityIdentifier = "s2.maintenance.view-diagnostics"
    /// Plain-files salvage when no backup can be produced. Not a backup.
    static let savePhotosAndReportsButtonText = "Save photos and reports"
    static let savePhotosAndReportsHintText = "Saves copies of your photos and report PDFs as ordinary files. This is not a backup and cannot be restored."
    static let savePhotosAndReportsAccessibilityIdentifier = "s2.maintenance.save-photos-and-reports"
    static let salvageNothingFoundText = "No photos or reports were found to save."
    static let salvageFailedText = "Photos and reports could not be saved. Try again."
    static let salvageStatusAccessibilityIdentifier = "s2.maintenance.save-photos-and-reports.status"
    static let salvageInProgressText = "Preparing photos and reports…"

    /// The save action never ends silently: an empty inventory and a failed
    /// copy each map to a brief status.
    static func salvageStatusText(for error: Error) -> String {
        (error as? MaintenanceSalvageExportV1.Failure) == .nothingToSave
            ? salvageNothingFoundText : salvageFailedText
    }

    let reason: StartupMaintenanceReason
    let retryChecks: () -> Void
    let restoreDataBackup: (() -> Void)?
    let eraseAll: (() -> Void)?
    let viewDiagnostics: (() -> Void)?
    let savePhotosAndReports: (() -> Void)?
    let salvageStatus: String?
    let salvageInProgress: Bool

    @State private var showsRecoverySteps = false

    init(
        reason: StartupMaintenanceReason,
        retryChecks: @escaping () -> Void,
        restoreDataBackup: (() -> Void)? = nil,
        eraseAll: (() -> Void)? = nil,
        viewDiagnostics: (() -> Void)? = nil,
        savePhotosAndReports: (() -> Void)? = nil,
        salvageStatus: String? = nil,
        salvageInProgress: Bool = false
    ) {
        self.reason = reason
        self.retryChecks = retryChecks
        self.restoreDataBackup = restoreDataBackup
        self.eraseAll = eraseAll
        self.viewDiagnostics = viewDiagnostics
        self.savePhotosAndReports = savePhotosAndReports
        self.salvageStatus = salvageStatus
        self.salvageInProgress = salvageInProgress
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

                    if let savePhotosAndReports {
                        AssetRoundsSecondaryAction(action: savePhotosAndReports) {
                            if salvageInProgress {
                                HStack(spacing: DesignTokens.Spacing.space8) {
                                    ProgressView()
                                    Text("Preparing photos and reports…")
                                }
                            } else {
                                Text("Save photos and reports")
                            }
                        }
                            .disabled(salvageInProgress)
                            .accessibilityLabel(Self.savePhotosAndReportsButtonText)
                            .accessibilityValue(salvageInProgress ? Self.salvageInProgressText : "")
                            .accessibilityHint(Self.savePhotosAndReportsHintText)
                            .accessibilityIdentifier(Self.savePhotosAndReportsAccessibilityIdentifier)
                        Text(Self.savePhotosAndReportsHintText)
                            .font(DesignTokens.Typography.secondaryBody)
                            .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let salvageStatus {
                            Text(salvageStatus)
                                .font(DesignTokens.Typography.secondaryBody)
                                .foregroundStyle(DesignTokens.SemanticColors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier(Self.salvageStatusAccessibilityIdentifier)
                        }
                    }

                    if let viewDiagnostics {
                        AssetRoundsSecondaryAction("View diagnostics", action: viewDiagnostics)
                            .accessibilityLabel(Self.viewDiagnosticsButtonText)
                            .accessibilityHint(
                                "Previews privacy-safe local counters and bounded system diagnostics before saving"
                            )
                            .accessibilityIdentifier(Self.viewDiagnosticsAccessibilityIdentifier)
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

import SwiftUI

@MainActor
struct AppLockSettingsSectionV1: View {
    let isEnabled: Bool
    let isBusy: Bool
    let isAvailable: Bool
    let onSetEnabled: @MainActor (Bool) -> Void
    let onLockNow: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space12) {
            Text("App Lock")
                .font(DesignTokens.Typography.sectionHeading)
                .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                .accessibilityAddTraits(.isHeader)

            Toggle(isOn: enabledBinding) {
                Text(AppLockCopyV1.setting)
                    .font(DesignTokens.Typography.primaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(DesignTokens.SemanticColors.primaryAction)
            .disabled(!isAvailable || isBusy)
            .accessibilityIdentifier("v23.appLock.toggle")

            Text(AppLockCopyV1.disclosure)
                .font(DesignTokens.Typography.secondaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            AssetRoundsSecondaryAction("Lock Now", action: onLockNow)
                .disabled(!isEnabled || isBusy)
                .accessibilityIdentifier("v23.appLock.lockNow")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("v23.appLock.settings")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { onSetEnabled($0) }
        )
    }
}

import SwiftUI

struct AppLockCoverViewV1: View {
    static let coverAccessibilityIdentifier = "v23.appLock.cover"
    static let unlockAccessibilityIdentifier = "v23.appLock.unlock"
    static let authenticatingAccessibilityIdentifier =
        "v23.appLock.authenticating"

    let isAuthenticating: Bool
    let onUnlock: @MainActor () -> Void

    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                AssetRoundsEvidenceCard {
                    Text("App Lock")
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(AppLockCopyV1.locked)
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    AssetRoundsPrimaryAction("Unlock", action: onUnlock)
                        .disabled(isAuthenticating)
                        .accessibilityLabel("Unlock")
                        .accessibilityIdentifier(Self.unlockAccessibilityIdentifier)

                    if isAuthenticating {
                        ProgressView()
                            .accessibilityLabel("Authenticating")
                            .accessibilityIdentifier(
                                Self.authenticatingAccessibilityIdentifier
                            )
                    }
                }
            }
        }
        .accessibilityIdentifier(Self.coverAccessibilityIdentifier)
    }
}

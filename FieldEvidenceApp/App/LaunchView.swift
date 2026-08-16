import SwiftUI

struct LaunchView: View {
    static let titleText = "AssetRounds"
    static let subtitleText = "Sign Inspection"
    static let screenAccessibilityIdentifier = "s0.launch.screen"
    static let titleAccessibilityIdentifier = "s0.launch.title"

    var body: some View {
        AssetRoundsScreenFoundation {
            VStack(spacing: DesignTokens.Spacing.space12) {
                Image(AssetRoundsBrandImageAsset.originalSymbol.rawValue)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(
                        width: DesignTokens.Spacing.space32,
                        height: DesignTokens.Spacing.space32
                    )
                    .accessibilityHidden(true)

                Text(Self.titleText)
                    .font(DesignTokens.Typography.screenTitle)
                    .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(1)
                    .accessibilityIdentifier(Self.titleAccessibilityIdentifier)

                Text(Self.subtitleText)
                    .font(DesignTokens.Typography.sectionHeading)
                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }
}

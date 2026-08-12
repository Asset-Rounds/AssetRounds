import SwiftUI

struct LaunchView: View {
    static let titleText = "AssetRounds"
    static let subtitleText = "Sign Inspection"
    static let screenAccessibilityIdentifier = "s0.launch.screen"
    static let titleAccessibilityIdentifier = "s0.launch.title"

    var body: some View {
        VStack(spacing: 12) {
            Text(Self.titleText)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(1)
                .accessibilityIdentifier(Self.titleAccessibilityIdentifier)

            Text(Self.subtitleText)
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }
}

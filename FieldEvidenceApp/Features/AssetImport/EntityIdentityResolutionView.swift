import SwiftUI

/// C13 contained identity-resolution review; it exposes no automatic mutation.
struct EntityIdentityResolutionView: View {
    enum State { case accepted, ambiguity, staleConflict, confirmation, interrupted, historicAlias }
    let state: State; let reason: String; let onConfirm: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
        Text(copy(.heading)).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
        Label(copy(stateKey), systemImage: state == .accepted ? "checkmark.circle" : "exclamationmark.triangle").accessibilityIdentifier(C13AccessibilityIDV1.state.rawValue)
        Text(reason).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(C13AccessibilityIDV1.reason.rawValue)
        Text(copy(.automaticMutationFalse)).font(.footnote)
        if state == .confirmation { Button(copy(.confirmConsolidation)) { onConfirm?() }.accessibilityIdentifier(C13AccessibilityIDV1.confirm.rawValue) }
        if state == .historicAlias { Text(copy(.historicAlias)).font(.body) }
        if reduceMotion { Text(copy(.reducedMotion)).font(.footnote) }
    }.padding(DesignTokens.Spacing.medium) }.accessibilityIdentifier(C13AccessibilityIDV1.screen.rawValue) }
    private var stateKey: C13LocalizationKeyV1 { switch state { case .accepted: return .accepted; case .ambiguity: return .ambiguity; case .staleConflict: return .staleConflict; case .confirmation: return .confirmation; case .interrupted: return .interrupted; case .historicAlias: return .historicAlias } }
    private func copy(_ key: C13LocalizationKeyV1) -> String { BundledLocalizationCatalogV1.c13Localized(key) }
}

import SwiftUI

/// C12 contained, unadopted reinspection presentation. Selection and evidence
/// truth are supplied by the owning coordinator; this view never infers either.
struct ReinspectionPlanView: View {
    enum State { case ready, empty, protectedData, storage, offline, interrupted, error }
    struct Item: Identifiable { let id: String; let reason: String; let evidenceState: EvidenceState }
    enum EvidenceState { case freshEvidence, unchangedAttestation }
    let state: State; let items: [Item]; let onReview: ((Item) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
        Text(text(.reinspectionHeading)).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
        Text(text(.reinspectionDisclosure)).fixedSize(horizontal: false, vertical: true)
        if state == .ready { ForEach(items) { item in Button { onReview?(item) } label: { VStack(alignment: .leading) { Text(item.reason).font(.headline); Text(text(item.evidenceState == .freshEvidence ? .freshEvidence : .unchangedAttestation)).font(.subheadline) } }.accessibilityIdentifier(C12AccessibilityIDV1.reinspectionItem.rawValue + "." + item.id) } } else { Label(text(stateKey), systemImage: "exclamationmark.triangle").accessibilityIdentifier(C12AccessibilityIDV1.reinspectionState.rawValue) }
        if reduceMotion { Text(text(.reducedMotion)).font(.footnote) }
    }.padding(DesignTokens.Spacing.medium) }.accessibilityIdentifier(C12AccessibilityIDV1.reinspectionScreen.rawValue) }
    private var stateKey: C12LocalizationKeyV1 { switch state { case .empty: return .empty; case .protectedData: return .protected; case .storage: return .storage; case .offline: return .offline; case .interrupted: return .interrupted; case .error: return .error; case .ready: return .reinspectionHeading } }
    private func text(_ key: C12LocalizationKeyV1) -> String { BundledLocalizationCatalogV1.c12Localized(key) }
}

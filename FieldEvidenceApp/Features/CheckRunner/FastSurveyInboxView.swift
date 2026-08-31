import SwiftUI

/// C11 presentation-only local inbox. It is intentionally unadopted: callers
/// supply all local state and own every capture, promotion, snippet, and erase effect.
struct FastSurveyInboxView: View {
    enum State: String, CaseIterable, Identifiable { case inbox, unassigned, collision, recovery, storagePressure, protectedData; var id: String { rawValue } }
    struct Item: Identifiable { let id: String; let title: String; let detail: String; let promoted: Bool }
    let state: State
    let items: [Item]
    let onCapture: (() -> Void)?
    let onReview: ((Item) -> Void)?
    let onSnippet: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                Text(copy(.heading)).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(copy(.localOnly)).font(.body).fixedSize(horizontal: false, vertical: true)
                status
                if state == .inbox || state == .unassigned { inbox }
                controls
                if reduceMotion { Text(copy(.reducedMotion)).font(.footnote) }
            }.padding(DesignTokens.Spacing.medium)
        }
        .accessibilityIdentifier(FastSurveyInboxAccessibilityIDV1.screen.rawValue)
        .environment(\.layoutDirection, layoutDirection)
    }

    private var status: some View {
        Label(copy(state == .unassigned ? .unassigned : state == .collision ? .collision : state == .storagePressure ? .storage : state == .protectedData ? .protected : state == .recovery ? .recovery : .inbox), systemImage: state == .inbox ? "tray" : "exclamationmark.triangle")
            .foregroundStyle(state == .inbox ? DesignTokens.Colors.secondaryText : .primary)
            .accessibilityIdentifier(FastSurveyInboxAccessibilityIDV1.status.rawValue)
    }
    private var inbox: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(copy(.review)).font(.headline)
            ForEach(items) { item in
                Button { onReview?(item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.title).font(.body.weight(.medium))
                        Text(item.detail).font(.footnote)
                        Text(item.promoted ? copy(.promoted) : copy(.notPromoted)).font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier(FastSurveyInboxAccessibilityIDV1.item.rawValue + "." + item.id)
            }
        }.accessibilityIdentifier(FastSurveyInboxAccessibilityIDV1.inbox.rawValue)
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Button(copy(.capture)) { onCapture?() }.accessibilityIdentifier(FastSurveyInboxAccessibilityIDV1.capture.rawValue)
            Button(copy(.snippet)) { onSnippet?() }.accessibilityIdentifier(FastSurveyInboxAccessibilityIDV1.snippet.rawValue)
            Text(copy(.previewOnly)).font(.footnote).accessibilityIdentifier(FastSurveyInboxAccessibilityIDV1.preview.rawValue)
            Text(copy(.noAcceptance)).font(.footnote).accessibilityIdentifier(FastSurveyInboxAccessibilityIDV1.noAcceptance.rawValue)
        }
    }
    private func copy(_ key: FastSurveyInboxLocalizationKeyV1) -> String { BundledLocalizationCatalogV1.fastSurveyInboxLocalized(key) }
}

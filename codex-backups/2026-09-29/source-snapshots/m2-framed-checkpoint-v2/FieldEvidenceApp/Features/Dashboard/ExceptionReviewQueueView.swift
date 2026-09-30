import SwiftUI

/// C12 contained local exception-queue presentation; acknowledgement never
/// resolves a source record or marks prior evidence as new.
struct ExceptionReviewQueueView: View {
    enum State { case ready, empty, protectedData, storage, offline, interrupted, error }
    struct Entry: Identifiable { let id: String; let title: String; let severity: String; let duplicateCount: Int; let acknowledged: Bool }
    let state: State; let entries: [Entry]; let onPreview: ((Entry) -> Void)?; let onAcknowledge: ((Entry) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
        Text(copy(.queueHeading)).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
        Text(copy(.queueDisclosure)).fixedSize(horizontal: false, vertical: true)
        if state == .ready { ForEach(entries) { entry in WorklightCard { VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) { Text(entry.title).font(.headline); Text("\(copy(.severity)): \(entry.severity)").font(.subheadline); Text("\(copy(.deduplicated)): \(entry.duplicateCount)").font(.caption); Text(entry.acknowledged ? copy(.acknowledged) : copy(.notAcknowledged)).font(.caption); Button(copy(.preview)) { onPreview?(entry) }; Button(copy(.acknowledge)) { onAcknowledge?(entry) } }.accessibilityIdentifier(C12AccessibilityIDV1.queueItem.rawValue + "." + entry.id) } } } else { Label(copy(.queueUnavailable), systemImage: "exclamationmark.triangle").accessibilityIdentifier(C12AccessibilityIDV1.queueState.rawValue) }
        if reduceMotion { Text(copy(.reducedMotion)).font(.footnote) }
    }.padding(DesignTokens.Spacing.medium) }.accessibilityIdentifier(C12AccessibilityIDV1.queueScreen.rawValue) }
    private func copy(_ key: C12LocalizationKeyV1) -> String { BundledLocalizationCatalogV1.c12Localized(key) }
}

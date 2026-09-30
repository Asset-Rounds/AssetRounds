import SwiftUI

/// Value-only C08 preview input. The zero-write preview makes no changes to
/// canonical state. It owns no parser, planner, writer, receipt,
/// export file, or navigation route.
struct ImportBulkPreviewStateV1: Sendable {
    enum Disposition: String, CaseIterable, Sendable { case create = "CREATE", updateExactMatch = "UPDATE_EXACT_MATCH", unchanged = "UNCHANGED", duplicateSource = "DUPLICATE_SOURCE", ambiguousTarget = "AMBIGUOUS_TARGET", conflict = "CONFLICT", invalid = "INVALID", unsupported = "UNSUPPORTED", skippedByUser = "SKIPPED_BY_USER" }
    enum ExecutionTruth: Sendable { case previewOnly, allOrNothingPreview, chunkedPreview, partialCommitted, interrupted, stale }
    let sourceIdentity: String; let schemaIdentity: String; let mappingIdentity: String; let planIdentity: String
    let rows: [(disposition: Disposition, reason: String)]
    let executionTruth: ExecutionTruth; let detail: String
}

struct ImportBulkPreviewView: View {
    let state: ImportBulkPreviewStateV1
    let onIdentityResolutionHandoff: (() -> Void)?
    init(state: ImportBulkPreviewStateV1, onIdentityResolutionHandoff: (() -> Void)? = nil) { self.state = state; self.onIdentityResolutionHandoff = onIdentityResolutionHandoff }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Label(executionText, systemImage: "eye")
                .font(.headline)
                .accessibilityLabel(executionText)
                .accessibilityIdentifier(ImportBulkPreviewAccessibilityIDV1.summary.rawValue)
            Text(text(.identityDisclosure))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(text(.identityDisclosure))
            Text(executionText)
                .font(.body.weight(.medium))
                .accessibilityLabel(executionText)
                .accessibilityIdentifier(ImportBulkPreviewAccessibilityIDV1.commitMode.rawValue)
            statusDisclosure
            ForEach(Array(state.rows.enumerated()), id: \.offset) { index, row in
                Label(dispositionText(row.disposition), systemImage: symbol(row.disposition))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(dispositionText(row.disposition))
                    .accessibilityIdentifier("\(ImportBulkPreviewAccessibilityIDV1.disposition.rawValue).\(index)")
            }
            Text(text(.noReceiptClaim))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(text(.noReceiptClaim))
                .accessibilityIdentifier(ImportBulkPreviewAccessibilityIDV1.export.rawValue)
            if let onIdentityResolutionHandoff { Button(BundledLocalizationCatalogV1.c13Localized(.handoff)) { onIdentityResolutionHandoff() }.accessibilityIdentifier(C13AccessibilityIDV1.handoff.rawValue) }
        }.padding().frame(maxWidth: .infinity, alignment: .leading) }
        .navigationTitle(text(.heading)).navigationBarTitleDisplayMode(.inline).accessibilityIdentifier(ImportBulkPreviewAccessibilityIDV1.screen.rawValue)
    }
    private var executionText: String { switch state.executionTruth { case .previewOnly: return text(.previewOnly); case .allOrNothingPreview: return text(.allOrNothing); case .chunkedPreview: return text(.chunked); case .partialCommitted: return text(.partial); case .interrupted: return text(.interrupted); case .stale: return text(.stale) } }
    @ViewBuilder private var statusDisclosure: some View {
        switch state.executionTruth {
        case .previewOnly, .allOrNothingPreview, .chunkedPreview:
            Text(text(.noReceiptClaim)).accessibilityIdentifier(ImportBulkPreviewAccessibilityIDV1.progress.rawValue)
        case .partialCommitted:
            Text(text(.partial)).accessibilityIdentifier(ImportBulkPreviewAccessibilityIDV1.correction.rawValue)
        case .interrupted:
            Text(text(.interrupted)).accessibilityIdentifier(ImportBulkPreviewAccessibilityIDV1.recovery.rawValue)
        case .stale:
            Text(text(.stale)).accessibilityIdentifier(ImportBulkPreviewAccessibilityIDV1.error.rawValue)
        }
    }
    private func dispositionText(_ value: ImportBulkPreviewStateV1.Disposition) -> String { switch value { case .create: return text(.create); case .updateExactMatch: return text(.update); case .unchanged: return text(.unchanged); case .duplicateSource: return text(.duplicate); case .ambiguousTarget: return text(.ambiguous); case .conflict: return text(.conflict); case .invalid: return text(.invalid); case .unsupported: return text(.unsupported); case .skippedByUser: return text(.skipped) } }
    private func symbol(_ value: ImportBulkPreviewStateV1.Disposition) -> String { switch value { case .create: return "plus.circle"; case .updateExactMatch: return "arrow.triangle.2.circlepath"; case .unchanged: return "equal.circle"; case .duplicateSource, .ambiguousTarget, .conflict, .invalid, .unsupported: return "exclamationmark.triangle"; case .skippedByUser: return "minus.circle" } }
    private func text(_ key: ImportBulkPreviewLocalizationKeyV1) -> String { BundledLocalizationCatalogV1.importBulkPreviewLocalized(key) }
}

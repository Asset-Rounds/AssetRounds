import Foundation
import SwiftUI

struct BackupValidationSummaryView: View {
    static let screenAccessibilityIdentifier = "s6.3.backup-validation.screen"
    static let headingAccessibilityIdentifier = "s6.3.backup-validation.heading"
    static let signCountAccessibilityIdentifier = "s6.3.backup-validation.sign-count"
    static let reportCountAccessibilityIdentifier = "s6.3.backup-validation.report-count"
    static let photoCountAccessibilityIdentifier = "s6.3.backup-validation.photo-count"
    static let dateAccessibilityIdentifier = "s6.3.backup-validation.date"
    static let sizeAccessibilityIdentifier = "s6.3.backup-validation.size"
    static let packsAccessibilityIdentifier = "s6.3.backup-validation.packs"
    static let rootsAccessibilityIdentifier = "s6.3.backup-validation.roots"
    static let slotsAccessibilityIdentifier = "s6.3.backup-validation.slots"

    let summary: BackupValidationSummaryV1

    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ScrollView {
            WorklightCard {
                Text(BundledLocalizationCatalogV1.v30Text(.backupValidationHeading))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)
                    .accessibilityFocused($headingFocused)

                Text(BundledLocalizationCatalogV1.v30BackupValidationSignCount(count: summary.incomingSignCount))
                    .summaryValue(identifier: Self.signCountAccessibilityIdentifier)
                Text(BundledLocalizationCatalogV1.v30BackupValidationReportCount(count: summary.incomingReportCount))
                    .summaryValue(identifier: Self.reportCountAccessibilityIdentifier)
                Text(BundledLocalizationCatalogV1.v30BackupValidationPhotoCount(count: summary.incomingPhotoCount))
                    .summaryValue(identifier: Self.photoCountAccessibilityIdentifier)

                summaryRow(
                    label: BundledLocalizationCatalogV1.v30Text(.backupValidationDateLabel),
                    value: Self.timestampFormatter.string(from: summary.exportedAt),
                    identifier: Self.dateAccessibilityIdentifier
                )
                summaryRow(
                    label: BundledLocalizationCatalogV1.v30Text(.backupValidationSizeLabel),
                    value: BundledLocalizationCatalogV1.v30BackupValidationPayloadBytes(byteCount: summary.declaredPayloadByteCount),
                    identifier: Self.sizeAccessibilityIdentifier
                )
                summaryRow(
                    label: BundledLocalizationCatalogV1.v30Text(.backupValidationPackLabel),
                    value: summary.packs.isEmpty
                        ? "0"
                        : summary.packs.map {
                            "\($0.packID) \($0.schemaVersion).\($0.contentVersion)"
                        }.joined(separator: ", "),
                    identifier: Self.packsAccessibilityIdentifier
                )
                summaryRow(
                    label: BundledLocalizationCatalogV1.v30Text(.backupValidationCountedRootsLabel),
                    value: String(summary.consumedRootCount),
                    identifier: Self.rootsAccessibilityIdentifier
                )
                summaryRow(
                    label: BundledLocalizationCatalogV1.v30Text(.backupValidationSlotsLabel),
                    value: BundledLocalizationCatalogV1.v30BackupValidationSlotCounts(liveCount: summary.liveSlotCount, deletedCount: summary.tombstonedSlotCount),
                    identifier: Self.slotsAccessibilityIdentifier
                )
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .task {
            await Task.yield()
            headingFocused = true
        }
    }

    @ViewBuilder
    private func summaryRow(
        label: String,
        value: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }


    private static let timestampFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        value.timeZone = TimeZone(secondsFromGMT: 0)
        return value
    }()
}

private extension View {
    func summaryValue(identifier: String) -> some View {
        self
            .font(.headline)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

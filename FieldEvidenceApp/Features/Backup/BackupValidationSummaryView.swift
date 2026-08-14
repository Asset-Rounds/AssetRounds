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
                Text("Backup")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)
                    .accessibilityFocused($headingFocused)

                Text(countLabel(summary.incomingSignCount, singular: "sign", plural: "signs"))
                    .summaryValue(identifier: Self.signCountAccessibilityIdentifier)
                Text(countLabel(summary.incomingReportCount, singular: "report", plural: "reports"))
                    .summaryValue(identifier: Self.reportCountAccessibilityIdentifier)
                Text(countLabel(summary.incomingPhotoCount, singular: "photo", plural: "photos"))
                    .summaryValue(identifier: Self.photoCountAccessibilityIdentifier)

                summaryRow(
                    label: "Date",
                    value: Self.timestampFormatter.string(from: summary.exportedAt),
                    identifier: Self.dateAccessibilityIdentifier
                )
                summaryRow(
                    label: "Size",
                    value: "\(summary.declaredPayloadByteCount) bytes",
                    identifier: Self.sizeAccessibilityIdentifier
                )
                summaryRow(
                    label: "Pack",
                    value: summary.packs.isEmpty
                        ? "0"
                        : summary.packs.map {
                            "\($0.packID) \($0.schemaVersion).\($0.contentVersion)"
                        }.joined(separator: ", "),
                    identifier: Self.packsAccessibilityIdentifier
                )
                summaryRow(
                    label: "Counted roots",
                    value: String(summary.consumedRootCount),
                    identifier: Self.rootsAccessibilityIdentifier
                )
                summaryRow(
                    label: "Slots",
                    value: "\(summary.liveSlotCount) live, \(summary.tombstonedSlotCount) deleted",
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

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
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

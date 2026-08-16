import SwiftUI
import UIKit

struct IssueDetailView: View {
    static let screenAccessibilityIdentifier = "s5.1.issue.screen"
    static let headerAccessibilityIdentifier = "s5.1.issue.header"
    static let statusAccessibilityIdentifier = "s5.1.issue.status"
    static let recordWorkAccessibilityIdentifier = "s5.1.issue.record-work"
    static let workRecordAccessibilityIdentifier = "s5.1.issue.work-record"
    static let workDateAccessibilityIdentifier = "s5.1.issue.work-date"
    static let workDescriptionAccessibilityIdentifier = "s5.1.issue.work-description"
    static let workNoteAccessibilityIdentifier = "s5.1.issue.work-note"
    static let workPhotoAccessibilityIdentifier = "s5.1.issue.work-photo"
    static let startRecheckAccessibilityIdentifier = "s5.2.issue.start-recheck"

    let issue: WorkIssuePresentationValue
    let recordWork: () -> Void
    let startRecheck: () -> Void

    @AccessibilityFocusState private var focusesHeader: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                AssetRoundsEvidenceCard {
                    statusLabel
                    .accessibilityIdentifier(Self.statusAccessibilityIdentifier)

                    Text(issue.label)
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
                        .accessibilityFocused($focusesHeader)

                    if issue.canRecordWork {
                        Button("Record work", action: recordWork)
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.SemanticColors.primaryAction)
                            .controlSize(.large)
                            .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                            .accessibilityIdentifier(Self.recordWorkAccessibilityIdentifier)
                    } else if issue.status == .recheckDue {
                        Button("Start recheck", action: startRecheck)
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.SemanticColors.primaryAction)
                            .controlSize(.large)
                            .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                            .accessibilityIdentifier(Self.startRecheckAccessibilityIdentifier)
                    }
                }

                ForEach(issue.records) { record in
                    AssetRoundsEvidenceCard {
                        detailRow(
                            title: "Date",
                            value: record.performedLocalDate,
                            identifier: Self.workDateAccessibilityIdentifier
                        )
                        detailRow(
                            title: "Short description",
                            value: record.description,
                            identifier: Self.workDescriptionAccessibilityIdentifier
                        )
                        if let note = record.note {
                            detailRow(
                                title: "Note",
                                value: note,
                                identifier: Self.workNoteAccessibilityIdentifier
                            )
                        }
                        if let data = record.photoThumbnailJPEG,
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: image.size.width)
                                .accessibilityLabel(
                                    "Add one optional photo showing the work performed."
                                )
                                .accessibilityIdentifier(Self.workPhotoAccessibilityIdentifier)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(Self.workRecordAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .navigationTitle(statusDisplay)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .onAppear {
            focusesHeader = false
            Task { @MainActor in
                await Task.yield()
                focusesHeader = true
            }
        }
    }

    private var statusDisplay: String {
        switch issue.status {
        case .open: "Record work"
        case .recheckDue: "Recheck due"
        case .resolved: "Resolved"
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch issue.status {
        case .open:
            Label(statusDisplay, systemImage: "info.circle.fill")
                .font(DesignTokens.Typography.secondaryBody.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Information: \(statusDisplay)"))
        case .recheckDue:
            AssetRoundsStateLabel(
                kind: .warning,
                text: Text(statusDisplay)
            )
            .accessibilityLabel(Text("Attention: \(statusDisplay)"))
            .accessibilityValue(Text(verbatim: String()))
        case .resolved:
            AssetRoundsStateLabel(
                kind: .completed,
                text: Text(statusDisplay)
            )
            .accessibilityLabel(Text("Complete: \(statusDisplay)"))
            .accessibilityValue(Text(verbatim: String()))
        }
    }

    private func detailRow(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(title)
                .font(DesignTokens.Typography.supportingCaption.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
            Text(value)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

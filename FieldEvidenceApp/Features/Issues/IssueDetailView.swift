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

    let issue: WorkIssuePresentationValue
    let recordWork: () -> Void

    @AccessibilityFocusState private var focusesHeader: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    WorklightStatusBadge(
                        kind: issue.status == .recheckDue ? .attention : .information,
                        text: issue.status == .recheckDue ? "Recheck due" : "Record work"
                    )
                    .accessibilityIdentifier(Self.statusAccessibilityIdentifier)

                    Text(issue.label)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
                        .accessibilityFocused($focusesHeader)

                    if issue.canRecordWork {
                        Button("Record work", action: recordWork)
                            .buttonStyle(WorklightPrimaryButtonStyle())
                            .accessibilityIdentifier(Self.recordWorkAccessibilityIdentifier)
                    }
                }

                ForEach(issue.records) { record in
                    WorklightCard {
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
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(issue.status == .recheckDue ? "Recheck due" : "Record work")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .onAppear {
            focusesHeader = false
            Task { @MainActor in
                await Task.yield()
                focusesHeader = true
            }
        }
    }

    private func detailRow(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

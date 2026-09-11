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
    static let signoffWorkRootAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.work-root"
    static let signoffImmutableDetailAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.immutable-work-detail"
    static let signoffMoreAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.more"
    static let signoffRecordResponseAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.record-approval-response"

    let issue: WorkIssuePresentationValue
    let recordWork: () -> Void
    let startRecheck: () -> Void
    let recordApprovalResponse: (() -> Void)?

    init(
        issue: WorkIssuePresentationValue,
        recordWork: @escaping () -> Void,
        startRecheck: @escaping () -> Void,
        recordApprovalResponse: (() -> Void)? = nil
    ) {
        self.issue = issue
        self.recordWork = recordWork
        self.startRecheck = startRecheck
        self.recordApprovalResponse = recordApprovalResponse
    }

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

                    if issue.status == .resolved,
                       let recordApprovalResponse {
                        Menu {
                            Button("Record response", action: recordApprovalResponse)
                                .accessibilityHint(
                                    "Opens the response editor for this completed work."
                                )
                                .accessibilityIdentifier(
                                    Self.signoffRecordResponseAccessibilityIdentifier
                                )
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: DesignTokens.Control.minimumHitSize
                                )
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityLabel("More")
                        .accessibilityHint(
                            "More actions for this completed work, including Record response."
                        )
                        .accessibilityIdentifier(Self.signoffMoreAccessibilityIdentifier)
                    }

                    if issue.canRecordWork {
                        AssetRoundsPrimaryAction("Record work", action: recordWork)
                            .accessibilityIdentifier(Self.recordWorkAccessibilityIdentifier)
                    } else if issue.status == .recheckDue {
                        AssetRoundsPrimaryAction("Start recheck", action: startRecheck)
                            .accessibilityIdentifier(Self.startRecheckAccessibilityIdentifier)
                    }
                }
                .accessibilityIdentifier(Self.signoffImmutableDetailAccessibilityIdentifier)

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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.signoffWorkRootAccessibilityIdentifier)
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
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            Text(value)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

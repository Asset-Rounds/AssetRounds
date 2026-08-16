import SwiftUI

struct SignDetailView: View {
    static let screenAccessibilityIdentifier = "s2.sign-detail.screen"
    static let siteLabelAccessibilityIdentifier = "s2.sign-detail.site-label"
    static let signLabelAccessibilityIdentifier = "s2.sign-detail.sign-label"
    static let addressAccessibilityIdentifier = "s2.sign-detail.address"
    static let timeZoneAccessibilityIdentifier = "s2.sign-detail.time-zone"
    static let startCheckAccessibilityIdentifier = "s2.sign-detail.start-check"
    static let noCheckStartedAccessibilityIdentifier = "s3.sign-detail.no-check-started"
    static let viewReportAccessibilityIdentifier = "s4.3.sign-detail.view-report"
    static let reportHistoryAccessibilityIdentifier =
        "s4.4.sign-detail.report-history"
    static let recordWorkAccessibilityIdentifier = "s5.1.sign-detail.record-work"
    static let recheckDueAccessibilityIdentifier = "s5.1.sign-detail.recheck-due"
    static let resolvedIssueAccessibilityIdentifier = "s5.2.sign-detail.resolved"
    static let deleteActionAccessibilityIdentifier = "s6.1.delete.action"
    static let deleteScreenAccessibilityIdentifier = "s6.1.delete.screen"
    static let deleteMessageAccessibilityIdentifier = "s6.1.delete.message"
    static let deleteCancelAccessibilityIdentifier = "s6.1.delete.cancel"
    static let deleteConfirmAccessibilityIdentifier = "s6.1.delete.confirm"
    static let allSignsAccessibilityIdentifier = "s7.4.sign-detail.all-signs"
    static let addSignAccessibilityIdentifier = "s7.4.sign-detail.add-sign"
    private static let startCheckTitle: LocalizedStringKey = "Start Check"

    let snapshot: FirstSignSnapshot
    let checkNotice: String?
    let openReport: (() -> Void)?
    let openReportHistory: () -> Void
    let refreshReport: () -> Void
    let activeIssue: WorkIssuePresentationValue?
    let openIssue: () -> Void
    let recordWork: () -> Void
    let refreshIssue: () -> Void
    let startCheck: () -> Void
    let showAllSigns: () -> Void
    let addSign: () -> Void
    let deleteSign: () async throws -> Void

    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @AccessibilityFocusState private var deletionMessageFocused: Bool

    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                AssetRoundsEvidenceCard {
                    AssetRoundsStateLabel(kind: .completed, "Sign saved")
                        .accessibilityLabel("Complete: Sign saved")
                        .accessibilityValue(Text(verbatim: String()))

                    Text(snapshot.signLabel)
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.signLabelAccessibilityIdentifier)
                        .accessibilityAddTraits(.isHeader)

                    detailRow(
                        title: "Customer / site",
                        value: snapshot.siteLabel,
                        identifier: Self.siteLabelAccessibilityIdentifier
                    )

                    if let address = snapshot.address {
                        detailRow(
                            title: "Address",
                            value: address,
                            identifier: Self.addressAccessibilityIdentifier
                        )
                    }

                    if let timeZoneID = snapshot.timeZoneID {
                        detailRow(
                            title: "Time zone",
                            value: timeZoneID,
                            identifier: Self.timeZoneAccessibilityIdentifier
                        )
                    }
                }

                AssetRoundsEvidenceCard {
                    AssetRoundsSecondaryAction("All signs", action: showAllSigns)
                        .accessibilityLabel("All signs")
                        .accessibilityIdentifier(Self.allSignsAccessibilityIdentifier)

                    AssetRoundsSecondaryAction("Add sign", action: addSign)
                        .accessibilityLabel("Add sign")
                        .accessibilityIdentifier(Self.addSignAccessibilityIdentifier)

                    if let activeIssue {
                        if activeIssue.canRecordWork {
                            AssetRoundsPrimaryAction("Record work", action: recordWork)
                                .accessibilityLabel("Record work")
                                .accessibilityIdentifier(
                                    Self.recordWorkAccessibilityIdentifier
                                )
                        } else if activeIssue.status == .recheckDue {
                            AssetRoundsSecondaryAction("Recheck due", action: openIssue)
                                .accessibilityLabel("Recheck due")
                                .accessibilityIdentifier(
                                    Self.recheckDueAccessibilityIdentifier
                                )
                        } else {
                            AssetRoundsSecondaryAction("Resolved", action: openIssue)
                                .accessibilityLabel("Resolved")
                                .accessibilityIdentifier(
                                    Self.resolvedIssueAccessibilityIdentifier
                                )
                        }
                    }

                    if let openReport {
                        AssetRoundsSecondaryAction("View report", action: openReport)
                            .accessibilityLabel("View report")
                            .accessibilityHint("Opens the saved report for this sign")
                            .accessibilityIdentifier(Self.viewReportAccessibilityIdentifier)
                    }

                    AssetRoundsSecondaryAction("Report history", action: openReportHistory)
                        .accessibilityLabel("Report history")
                        .accessibilityHint("Opens report history for this sign")
                        .accessibilityIdentifier(Self.reportHistoryAccessibilityIdentifier)

                    Group {
                        if activeIssue?.canRecordWork == true {
                            AssetRoundsSecondaryAction(action: startCheck) {
                                Text(Self.startCheckTitle)
                            }
                        } else {
                            AssetRoundsPrimaryAction(action: startCheck) {
                                Text(Self.startCheckTitle)
                            }
                        }
                    }
                    .accessibilityLabel("Start Check")
                    .accessibilityIdentifier(Self.startCheckAccessibilityIdentifier)

                    if let checkNotice {
                        Label(checkNotice, systemImage: "info.circle.fill")
                            .font(DesignTokens.Typography.secondaryBody)
                            .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(checkNotice)
                            .accessibilityIdentifier(Self.noCheckStartedAccessibilityIdentifier)
                    }
                }

                    if isConfirmingDeletion {
                        AssetRoundsEvidenceCard {
                        AssetRoundsStateLabel(kind: .warning, "Delete sign")
                            .accessibilityLabel("Delete sign")
                            .accessibilityValue(Text(verbatim: String()))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(Self.deleteScreenAccessibilityIdentifier)

                        Text("Delete this sign, its photos, and its reports from this app? This cannot be undone. Your free-report count will not reset. Erase All removes the remaining anonymous count.")
                            .font(DesignTokens.Typography.primaryBody)
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($deletionMessageFocused)
                            .accessibilityIdentifier(Self.deleteMessageAccessibilityIdentifier)

                        AssetRoundsSecondaryAction("Cancel") {
                            isConfirmingDeletion = false
                        }
                        .accessibilityLabel("Cancel")
                        .disabled(isDeleting)
                        .accessibilityIdentifier(Self.deleteCancelAccessibilityIdentifier)

                        AssetRoundsDestructiveAction("Delete sign") {
                            performDeletion()
                        }
                        .accessibilityLabel("Delete sign")
                        .disabled(isDeleting)
                        .accessibilityIdentifier(Self.deleteConfirmAccessibilityIdentifier)
                        }
                    } else {
                        AssetRoundsDestructiveAction("Delete sign") {
                            isConfirmingDeletion = true
                            Task { @MainActor in
                                await Task.yield()
                                deletionMessageFocused = true
                            }
                        }
                        .accessibilityLabel("Delete sign")
                        .accessibilityIdentifier(Self.deleteActionAccessibilityIdentifier)
                    }
                }
            }
        }
        .navigationTitle("Sign detail")
        .navigationBarBackButtonHidden(true)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .onAppear {
            refreshReport()
            refreshIssue()
        }
    }

    private func performDeletion() {
        guard !isDeleting else { return }
        isDeleting = true
        Task { @MainActor in
            do {
                try await deleteSign()
            } catch {
                isDeleting = false
                await Task.yield()
                deletionMessageFocused = true
            }
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

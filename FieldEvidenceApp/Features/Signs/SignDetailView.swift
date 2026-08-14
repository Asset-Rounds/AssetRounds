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
    let deleteSign: () async throws -> Void

    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @AccessibilityFocusState private var deletionMessageFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    WorklightStatusBadge(kind: .complete, text: "Sign saved")

                    Text(snapshot.signLabel)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
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

                WorklightCard {
                    if let activeIssue {
                        if activeIssue.canRecordWork {
                            Button("Record work", action: recordWork)
                                .buttonStyle(WorklightPrimaryButtonStyle())
                                .accessibilityIdentifier(
                                    Self.recordWorkAccessibilityIdentifier
                                )
                        } else if activeIssue.status == .recheckDue {
                            Button("Recheck due", action: openIssue)
                                .buttonStyle(WorklightSecondaryButtonStyle())
                                .accessibilityIdentifier(
                                    Self.recheckDueAccessibilityIdentifier
                                )
                        } else {
                            Button("Resolved", action: openIssue)
                                .buttonStyle(WorklightSecondaryButtonStyle())
                                .accessibilityIdentifier(
                                    Self.resolvedIssueAccessibilityIdentifier
                                )
                        }
                    }

                    if let openReport {
                        Button("View report", action: openReport)
                            .buttonStyle(WorklightSecondaryButtonStyle())
                            .accessibilityHint("Opens the saved report for this sign")
                            .accessibilityIdentifier(Self.viewReportAccessibilityIdentifier)
                    }

                    Button("Report history", action: openReportHistory)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityHint("Opens report history for this sign")
                        .accessibilityIdentifier(Self.reportHistoryAccessibilityIdentifier)

                    Button("Start Check", action: startCheck)
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .accessibilityIdentifier(Self.startCheckAccessibilityIdentifier)

                    if let checkNotice {
                        Label(checkNotice, systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.Colors.informationText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(checkNotice)
                            .accessibilityIdentifier(Self.noCheckStartedAccessibilityIdentifier)
                    }
                }

                if isConfirmingDeletion {
                    WorklightCard {
                        Text("Delete sign")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .accessibilityAddTraits(.isHeader)

                        Text("Delete this sign, its photos, and its reports from this app? This cannot be undone. Your free-report count will not reset. Erase All removes the remaining anonymous count.")
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($deletionMessageFocused)
                            .accessibilityIdentifier(Self.deleteMessageAccessibilityIdentifier)

                        Button("Cancel") {
                            isConfirmingDeletion = false
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(isDeleting)
                        .accessibilityIdentifier(Self.deleteCancelAccessibilityIdentifier)

                        Button("Delete sign", role: .destructive) {
                            performDeletion()
                        }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .disabled(isDeleting)
                        .accessibilityIdentifier(Self.deleteConfirmAccessibilityIdentifier)
                    }
                    .accessibilityIdentifier(Self.deleteScreenAccessibilityIdentifier)
                } else {
                    Button("Delete sign", role: .destructive) {
                        isConfirmingDeletion = true
                        Task { @MainActor in
                            await Task.yield()
                            deletionMessageFocused = true
                        }
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(Self.deleteActionAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Sign detail")
        .navigationBarBackButtonHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
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

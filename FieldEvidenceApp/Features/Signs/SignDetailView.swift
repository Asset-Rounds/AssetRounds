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
                        } else {
                            Button("Recheck due", action: openIssue)
                                .buttonStyle(WorklightSecondaryButtonStyle())
                                .accessibilityIdentifier(
                                    Self.recheckDueAccessibilityIdentifier
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

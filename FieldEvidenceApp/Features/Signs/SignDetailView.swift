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
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    WorklightStatusBadge(kind: .complete, text: BundledLocalizationCatalogV1.v30Text(.signDetailSignSaved))

                    Text(snapshot.signLabel)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.signLabelAccessibilityIdentifier)
                        .accessibilityAddTraits(.isHeader)

                    detailRow(
                        title: BundledLocalizationCatalogV1.v30Text(.signDetailCustomerOrSite),
                        value: snapshot.siteLabel,
                        identifier: Self.siteLabelAccessibilityIdentifier
                    )

                    if let address = snapshot.address {
                        detailRow(
                            title: BundledLocalizationCatalogV1.v30Text(.signDetailAddress),
                            value: address,
                            identifier: Self.addressAccessibilityIdentifier
                        )
                    }

                    if let timeZoneID = snapshot.timeZoneID {
                        detailRow(
                            title: BundledLocalizationCatalogV1.v30Text(.signDetailTimeZone),
                            value: timeZoneID,
                            identifier: Self.timeZoneAccessibilityIdentifier
                        )
                    }
                }

                WorklightCard {
                    Button(BundledLocalizationCatalogV1.v30Text(.signDetailAllSigns), action: showAllSigns)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier(Self.allSignsAccessibilityIdentifier)

                    Button(BundledLocalizationCatalogV1.v30Text(.signDetailAddSign), action: addSign)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier(Self.addSignAccessibilityIdentifier)

                    if let activeIssue {
                        if activeIssue.canRecordWork {
                            Button(BundledLocalizationCatalogV1.v30Text(.signDetailRecordWork), action: recordWork)
                                .buttonStyle(WorklightPrimaryButtonStyle())
                                .accessibilityIdentifier(
                                    Self.recordWorkAccessibilityIdentifier
                                )
                        } else if activeIssue.status == .recheckDue {
                            Button(BundledLocalizationCatalogV1.v30Text(.signDetailRecheckDue), action: openIssue)
                                .buttonStyle(WorklightSecondaryButtonStyle())
                                .accessibilityIdentifier(
                                    Self.recheckDueAccessibilityIdentifier
                                )
                        } else {
                            Button(BundledLocalizationCatalogV1.v30Text(.signDetailResolved), action: openIssue)
                                .buttonStyle(WorklightSecondaryButtonStyle())
                                .accessibilityIdentifier(
                                    Self.resolvedIssueAccessibilityIdentifier
                                )
                        }
                    }

                    if let openReport {
                        Button(BundledLocalizationCatalogV1.v30Text(.signDetailViewReport), action: openReport)
                            .buttonStyle(WorklightSecondaryButtonStyle())
                            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.signDetailViewReportHint))
                            .accessibilityIdentifier(Self.viewReportAccessibilityIdentifier)
                    }

                    Button(BundledLocalizationCatalogV1.v30Text(.signDetailReportHistory), action: openReportHistory)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.signDetailReportHistoryHint))
                        .accessibilityIdentifier(Self.reportHistoryAccessibilityIdentifier)

                    Button(BundledLocalizationCatalogV1.v30Text(.signDetailStartCheck), action: startCheck)
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
                        Text(BundledLocalizationCatalogV1.v30Text(.signDetailDeleteSignHeading))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(Self.deleteScreenAccessibilityIdentifier)

                        Text(BundledLocalizationCatalogV1.v30Text(.signDetailDeleteConfirmationMessage))
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($deletionMessageFocused)
                            .accessibilityIdentifier(Self.deleteMessageAccessibilityIdentifier)

                        Button(BundledLocalizationCatalogV1.v30Text(.signDetailCancel)) {
                            isConfirmingDeletion = false
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(isDeleting)
                        .accessibilityIdentifier(Self.deleteCancelAccessibilityIdentifier)

                        Button(BundledLocalizationCatalogV1.v30Text(.signDetailDeleteSignAction), role: .destructive) {
                            performDeletion()
                        }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .disabled(isDeleting)
                        .accessibilityIdentifier(Self.deleteConfirmAccessibilityIdentifier)
                    }
                } else {
                    Button(BundledLocalizationCatalogV1.v30Text(.signDetailDeleteSignAction), role: .destructive) {
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
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.signDetailNavigationTitle))
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

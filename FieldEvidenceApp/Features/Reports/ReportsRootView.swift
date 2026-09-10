import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ReportsRootView: View {
    static let screenAccessibilityIdentifier = "s4.4.reports.screen"
    static let headerAccessibilityIdentifier = "s4.4.reports.header"
    static let siteFilterAccessibilityIdentifier = "s4.4.reports.site-filter"
    static let signFilterAccessibilityIdentifier = "s4.4.reports.sign-filter"
    static let visitAccessibilityIdentifier = "s4.4.reports.visit"
    static let viewReportAccessibilityIdentifier = "s4.4.reports.view-report"
    static let compareAccessibilityIdentifier = "s4.4.reports.compare"

    private let deliveryCoordinator: ReportDeliveryCoordinator?
    private let historyCoordinator: ReportHistoryCoordinator?

    @State private var indexValue: ReportHistoryIndexValue?
    @State private var siteOptions: [ReportHistoryFilterOption] = []
    @State private var signOptions: [ReportHistoryFilterOption] = []
    @State private var selectedSiteID: UUID?
    @State private var selectedSignID: UUID?
    @State private var comparableRootIDs: Set<UUID> = []
    @State private var loadErrorMessage: String?
    @AccessibilityFocusState private var focusedElement: ReportsFocus?

    private enum ReportsFocus: Hashable {
        case header
        case siteFilter
        case signFilter
    }

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        diagnosticsStore: DiagnosticsStore,
        signPack: SignPack
    ) {
        let delivery = try? ReportDeliveryCoordinator(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            diagnosticsStore: diagnosticsStore,
            signPack: signPack
        )
        deliveryCoordinator = delivery
        historyCoordinator = delivery.map {
            ReportHistoryCoordinator(
                modelContext: modelContext,
                deliveryCoordinator: $0
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                filters

                if let loadErrorMessage {
                    ReportHistoryUnavailableView(message: loadErrorMessage)
                } else if let indexValue {
                    if indexValue.visits.isEmpty {
                        emptyState
                    } else {
                        ReportVisitList(
                            visits: indexValue.visits,
                            comparableRootIDs: comparableRootIDs
                        )
                    }
                } else {
                    ProgressView(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility))
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility))
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.reportsReportNavigation))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .onAppear(perform: refreshCurrentIndex)
        .navigationDestination(for: ReportHistoryRoute.self) { route in
            destination(for: route)
        }
    }

    private var filters: some View {
        WorklightCard {
            Text(BundledLocalizationCatalogV1.v30Text(.reportsReportLabel))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
                .accessibilityFocused($focusedElement, equals: .header)

            siteFilter
            signFilter
        }
    }

    private var siteFilter: some View {
        Menu {
            Button(BundledLocalizationCatalogV1.v30Text(.reportsReportAction)) {
                selectedSiteID = nil
                selectedSignID = nil
                loadIndex(
                    filter: .all,
                    updatesSignOptions: true,
                    restoringFocusTo: .siteFilter
                )
            }

            ForEach(siteOptions) { option in
                Button(option.label) {
                    selectedSiteID = option.id
                    selectedSignID = nil
                    loadIndex(
                        filter: .site(option.id),
                        updatesSignOptions: true,
                        restoringFocusTo: .siteFilter
                    )
                }
            }
        } label: {
            Label(siteFilterLabel, systemImage: "building.2")
        }
        .buttonStyle(WorklightSecondaryButtonStyle())
        .accessibilityLabel(siteFilterLabel)
        .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility2))
        .accessibilityIdentifier(Self.siteFilterAccessibilityIdentifier)
        .accessibilityFocused($focusedElement, equals: .siteFilter)
    }

    private var signFilter: some View {
        Menu {
            Button(BundledLocalizationCatalogV1.v30Text(.reportsReportAction2)) {
                selectedSignID = nil
                if let selectedSiteID {
                    loadIndex(
                        filter: .site(selectedSiteID),
                        updatesSignOptions: true,
                        restoringFocusTo: .signFilter
                    )
                } else {
                    loadIndex(
                        filter: .all,
                        updatesSignOptions: true,
                        restoringFocusTo: .signFilter
                    )
                }
            }

            ForEach(signOptions) { option in
                Button(option.label) {
                    selectedSignID = option.id
                    loadIndex(
                        filter: .asset(option.id),
                        updatesSignOptions: false,
                        restoringFocusTo: .signFilter
                    )
                }
            }
        } label: {
            Label(signFilterLabel, systemImage: "signpost.right")
        }
        .buttonStyle(WorklightSecondaryButtonStyle())
        .accessibilityLabel(signFilterLabel)
        .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility3))
        .accessibilityIdentifier(Self.signFilterAccessibilityIdentifier)
        .accessibilityFocused($focusedElement, equals: .signFilter)
    }

    private var siteFilterLabel: String {
        guard let selectedSiteID else { return BundledLocalizationCatalogV1.v30Text(.reportsReportAction) }
        return siteOptions.first { $0.id == selectedSiteID }?.label ?? BundledLocalizationCatalogV1.v30Text(.reportsReportAction)
    }

    private var signFilterLabel: String {
        guard let selectedSignID else { return BundledLocalizationCatalogV1.v30Text(.reportsReportAction2) }
        return signOptions.first { $0.id == selectedSignID }?.label ?? BundledLocalizationCatalogV1.v30Text(.reportsReportAction2)
    }

    private var emptyState: some View {
        WorklightCard {
            WorklightStatusBadge(kind: .information, text: BundledLocalizationCatalogV1.v30Text(.reportsReportNavigation))

            Text(BundledLocalizationCatalogV1.v30Text(.reportsReportLabel2))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier(AppShellView.reportsPlaceholderAccessibilityIdentifier)
    }

    @ViewBuilder
    private func destination(for route: ReportHistoryRoute) -> some View {
        switch route {
        case let .report(reportID):
            if let deliveryCoordinator {
                ReportHistoryDetailDestination(
                    reportID: reportID,
                    deliveryCoordinator: deliveryCoordinator
                )
            } else {
                ReportHistoryUnavailableView(
                    message: BundledLocalizationCatalogV1.v30Text(.reportsReportFailure)
                )
            }
        case let .comparison(stableRootID):
            if let historyCoordinator {
                ReportComparisonView(
                    stableRootID: stableRootID,
                    historyCoordinator: historyCoordinator
                )
            } else {
                ReportHistoryUnavailableView(
                    message: BundledLocalizationCatalogV1.v30Text(.reportsReportFailure2)
                )
            }
        }
    }

    private func loadInitialIndex() {
        guard let historyCoordinator else {
            loadErrorMessage = BundledLocalizationCatalogV1.v30Text(.reportsReportFailure3)
            return
        }
        do {
            let value = try historyCoordinator.index()
            indexValue = value
            siteOptions = value.siteOptions
            signOptions = filteredSignOptions(in: value)
            comparableRootIDs = comparableRoots(
                visits: value.visits,
                coordinator: historyCoordinator
            )
            loadErrorMessage = nil
            moveAccessibilityFocus(to: .header)
        } catch {
            indexValue = nil
            loadErrorMessage = BundledLocalizationCatalogV1.v30Text(.reportsReportFailure3)
            moveAccessibilityFocus(to: .header)
        }
    }

    private func refreshCurrentIndex() {
        if let selectedSignID {
            loadIndex(
                filter: .asset(selectedSignID),
                updatesSignOptions: false,
                restoringFocusTo: .header
            )
        } else if let selectedSiteID {
            loadIndex(
                filter: .site(selectedSiteID),
                updatesSignOptions: true,
                restoringFocusTo: .header
            )
        } else {
            loadInitialIndex()
        }
    }

    private func loadIndex(
        filter: ReportHistoryFilter,
        updatesSignOptions: Bool,
        restoringFocusTo focus: ReportsFocus
    ) {
        guard let historyCoordinator else {
            indexValue = nil
            loadErrorMessage = BundledLocalizationCatalogV1.v30Text(.reportsReportFailure3)
            return
        }
        do {
            let value = try historyCoordinator.index(filter: filter)
            indexValue = value
            if updatesSignOptions {
                signOptions = filteredSignOptions(in: value)
            }
            comparableRootIDs = comparableRoots(
                visits: value.visits,
                coordinator: historyCoordinator
            )
            loadErrorMessage = nil
            moveAccessibilityFocus(to: focus)
        } catch {
            indexValue = nil
            comparableRootIDs = []
            loadErrorMessage = BundledLocalizationCatalogV1.v30Text(.reportsReportFailure3)
            moveAccessibilityFocus(to: .header)
        }
    }

    private func filteredSignOptions(
        in value: ReportHistoryIndexValue
    ) -> [ReportHistoryFilterOption] {
        let representedAssetIDs = Set(value.visits.map(\.assetID))
        return value.assetOptions.filter { representedAssetIDs.contains($0.id) }
    }

    private func moveAccessibilityFocus(to target: ReportsFocus) {
        focusedElement = nil
        Task { @MainActor in
            await Task.yield()
            focusedElement = target
        }
    }
}

struct SignReportHistoryView: View {
    static let screenAccessibilityIdentifier = "s4.4.history.screen"
    static let headerAccessibilityIdentifier = "s4.4.history.header"

    let assetID: UUID
    let historyCoordinator: ReportHistoryCoordinator
    let deliveryCoordinator: ReportDeliveryCoordinator

    @State private var history: ReportSignHistoryValue?
    @State private var comparableRootIDs: Set<UUID> = []
    @State private var loadErrorMessage: String?
    @State private var didLoad = false
    @AccessibilityFocusState private var focusedElement: SignHistoryFocus?

    private enum SignHistoryFocus: Hashable {
        case header
        case unavailable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if let loadErrorMessage {
                    ReportHistoryUnavailableView(message: loadErrorMessage)
                        .accessibilityFocused(
                            $focusedElement,
                            equals: .unavailable
                        )
                } else if let history {
                    WorklightCard {
                        Text(history.assetLabel)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
                            .accessibilityFocused($focusedElement, equals: .header)

                        Text(history.siteLabel)
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(BundledLocalizationCatalogV1.v30Text(.reportsReportLabel3))
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }

                    if history.visits.isEmpty {
                        WorklightCard {
                            Text(BundledLocalizationCatalogV1.v30Text(.reportsReportLabel4))
                                .font(.body)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        ReportVisitList(
                            visits: history.visits,
                            comparableRootIDs: comparableRootIDs
                        )
                    }
                } else {
                    ProgressView(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility4))
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility4))
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.reportsReportNavigation2))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .task {
            guard !didLoad else { return }
            didLoad = true
            loadHistory()
        }
        .navigationDestination(for: ReportHistoryRoute.self) { route in
            destination(for: route)
        }
    }

    @ViewBuilder
    private func destination(for route: ReportHistoryRoute) -> some View {
        switch route {
        case let .report(reportID):
            ReportHistoryDetailDestination(
                reportID: reportID,
                deliveryCoordinator: deliveryCoordinator
            )
        case let .comparison(stableRootID):
            ReportComparisonView(
                stableRootID: stableRootID,
                historyCoordinator: historyCoordinator
            )
        }
    }

    private func loadHistory() {
        do {
            guard let value = try historyCoordinator.signHistory(assetID: assetID) else {
                history = nil
                loadErrorMessage = BundledLocalizationCatalogV1.v30Text(.reportsReportFailure4)
                moveAccessibilityFocus(to: .unavailable)
                return
            }
            history = value
            comparableRootIDs = comparableRoots(
                visits: value.visits,
                coordinator: historyCoordinator
            )
            loadErrorMessage = nil
            moveAccessibilityFocus(to: .header)
        } catch {
            history = nil
            comparableRootIDs = []
            loadErrorMessage = BundledLocalizationCatalogV1.v30Text(.reportsReportFailure4)
            moveAccessibilityFocus(to: .unavailable)
        }
    }

    private func moveAccessibilityFocus(to target: SignHistoryFocus) {
        focusedElement = nil
        Task { @MainActor in
            await Task.yield()
            focusedElement = target
        }
    }
}

private enum ReportHistoryRoute: Hashable {
    case report(UUID)
    case comparison(UUID)
}

private struct ReportVisitList: View {
    let visits: [ReportHistoryVisitValue]
    let comparableRootIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            ForEach(visits) { visit in
                WorklightCard {
                    WorklightStatusBadge(kind: .complete, text: BundledLocalizationCatalogV1.v30Text(.reportsReportStatus))

                    Text(visit.assetLabel)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(visit.siteLabel)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ReportVisitFact(label: BundledLocalizationCatalogV1.v30Text(.reportsReportLabel5), value: visitDate(visit))
                    ReportVisitFact(label: BundledLocalizationCatalogV1.v30Text(.reportsRootStage), value: visit.stage)
                    ReportVisitFact(label: BundledLocalizationCatalogV1.v30Text(.reportsRootOutcome), value: visit.outcome)

                    NavigationLink(
                        BundledLocalizationCatalogV1.v30Text(.reportsReportLabel6),
                        value: ReportHistoryRoute.report(visit.reportID)
                    )
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility5))
                    .accessibilityIdentifier(
                        ReportsRootView.viewReportAccessibilityIdentifier
                    )

                    if comparableRootIDs.contains(visit.stableRootID) {
                        NavigationLink(
                            BundledLocalizationCatalogV1.v30Text(.reportsReportLabel7),
                            value: ReportHistoryRoute.comparison(visit.stableRootID)
                        )
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityHint(
                            BundledLocalizationCatalogV1.v30Text(.reportsReportLabel8)
                        )
                        .accessibilityIdentifier(
                            ReportsRootView.compareAccessibilityIdentifier
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(ReportsRootView.visitAccessibilityIdentifier)
            }
        }
    }

    private func visitDate(_ visit: ReportHistoryVisitValue) -> String {
        BundledLocalizationCatalogV1.v30ReportsRootVisitDateTime(date: visit.localDate, time: visit.localTime)
    }
}

private struct ReportVisitFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReportHistoryDetailDestination: View {
    let reportID: UUID
    let deliveryCoordinator: ReportDeliveryCoordinator

    @State private var delivery: ReportDeliveryValue?
    @State private var failed = false
    @State private var didLoad = false
    @AccessibilityFocusState private var focusedElement: DetailFocus?

    private enum DetailFocus: Hashable {
        case detail
        case unavailable
    }

    var body: some View {
        Group {
            if let delivery {
                ReportDetailView(
                    delivery: delivery,
                    coordinator: deliveryCoordinator
                )
                .accessibilityFocused($focusedElement, equals: .detail)
            } else if failed {
                ReportHistoryUnavailableView(
                    message: BundledLocalizationCatalogV1.v30Text(.reportsReportFailure)
                )
                .accessibilityFocused($focusedElement, equals: .unavailable)
            } else {
                ProgressView(BundledLocalizationCatalogV1.v30Text(.reportsReportProgress))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DesignTokens.Colors.canvas)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            do {
                delivery = try deliveryCoordinator.loadReadyReport(id: reportID)
                moveAccessibilityFocus(to: .detail)
            } catch {
                failed = true
                moveAccessibilityFocus(to: .unavailable)
            }
        }
    }

    private func moveAccessibilityFocus(to target: DetailFocus) {
        focusedElement = nil
        Task { @MainActor in
            await Task.yield()
            focusedElement = target
        }
    }
}

private struct ReportComparisonView: View {
    static let screenAccessibilityIdentifier = "s4.4.comparison.screen"
    static let unavailableAccessibilityIdentifier = "s4.4.comparison.unavailable"
    static let thenHeadingAccessibilityIdentifier =
        "s4.4.comparison.then.heading"
    static let nowHeadingAccessibilityIdentifier =
        "s4.4.comparison.now.heading"

    let stableRootID: UUID
    let historyCoordinator: ReportHistoryCoordinator

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var comparison: ReportHistoryComparisonValue?
    @State private var failed = false
    @State private var didLoad = false
    @AccessibilityFocusState private var focusedElement: ComparisonFocus?

    private enum ComparisonFocus: Hashable {
        case thenHeading
        case unavailable
    }

    var body: some View {
        ScrollView {
            Group {
                if let comparison {
                    comparisonContent(comparison)
                } else if failed {
                    unavailable
                } else {
                    ProgressView(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility6))
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.reportsReportAccessibility6))
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.reportsReportNavigation3))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .task {
            guard !didLoad else { return }
            didLoad = true
            do {
                guard let value = try historyCoordinator.comparison(
                    stableRootID: stableRootID
                ) else {
                    failed = true
                    moveAccessibilityFocus(to: .unavailable)
                    return
                }
                comparison = value
                moveAccessibilityFocus(to: .thenHeading)
            } catch {
                failed = true
                moveAccessibilityFocus(to: .unavailable)
            }
        }
    }

    @ViewBuilder
    private func comparisonContent(_ value: ReportHistoryComparisonValue) -> some View {
        if let thenWide = evidence("wide_context", in: value.then),
           let thenClose = evidence("close_detail", in: value.then),
           let nowWide = evidence("wide_context", in: value.now),
           let nowClose = evidence("close_detail", in: value.now),
           let thenWideImage = UIImage(data: thenWide.originalData),
           let thenCloseImage = UIImage(data: thenClose.originalData),
           let nowWideImage = UIImage(data: nowWide.originalData),
           let nowCloseImage = UIImage(data: nowClose.originalData) {
            if dynamicTypeSize.isAccessibilitySize {
                verticalComparison(
                    value: value,
                    thenWide: thenWide,
                    thenWideImage: thenWideImage,
                    thenClose: thenClose,
                    thenCloseImage: thenCloseImage,
                    nowWide: nowWide,
                    nowWideImage: nowWideImage,
                    nowClose: nowClose,
                    nowCloseImage: nowCloseImage
                )
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.medium) {
                        comparisonSide(
                            heading: "Then",
                            visit: value.then,
                            wideEvidence: thenWide,
                            wideImage: thenWideImage,
                            closeEvidence: thenClose,
                            closeImage: thenCloseImage,
                            identifierPrefix: "s4.4.comparison.then"
                        )
                        .frame(maxWidth: .infinity, alignment: .top)

                        comparisonSide(
                            heading: "Now",
                            visit: value.now,
                            wideEvidence: nowWide,
                            wideImage: nowWideImage,
                            closeEvidence: nowClose,
                            closeImage: nowCloseImage,
                            identifierPrefix: "s4.4.comparison.now"
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    }

                    verticalComparison(
                        value: value,
                        thenWide: thenWide,
                        thenWideImage: thenWideImage,
                        thenClose: thenClose,
                        thenCloseImage: thenCloseImage,
                        nowWide: nowWide,
                        nowWideImage: nowWideImage,
                        nowClose: nowClose,
                        nowCloseImage: nowCloseImage
                    )
                }
            }
        } else {
            unavailable
        }
    }

    private func verticalComparison(
        value: ReportHistoryComparisonValue,
        thenWide: ReportHistoryEvidenceValue,
        thenWideImage: UIImage,
        thenClose: ReportHistoryEvidenceValue,
        thenCloseImage: UIImage,
        nowWide: ReportHistoryEvidenceValue,
        nowWideImage: UIImage,
        nowClose: ReportHistoryEvidenceValue,
        nowCloseImage: UIImage
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            comparisonSide(
                heading: "Then",
                visit: value.then,
                wideEvidence: thenWide,
                wideImage: thenWideImage,
                closeEvidence: thenClose,
                closeImage: thenCloseImage,
                identifierPrefix: "s4.4.comparison.then"
            )

            comparisonSide(
                heading: "Now",
                visit: value.now,
                wideEvidence: nowWide,
                wideImage: nowWideImage,
                closeEvidence: nowClose,
                closeImage: nowCloseImage,
                identifierPrefix: "s4.4.comparison.now"
            )
        }
    }

    private func comparisonSide(
        heading: String,
        visit: ReportHistoryVisitValue,
        wideEvidence: ReportHistoryEvidenceValue,
        wideImage: UIImage,
        closeEvidence: ReportHistoryEvidenceValue,
        closeImage: UIImage,
        identifierPrefix: String
    ) -> some View {
        WorklightCard {
            comparisonHeading(heading == "Then" ? BundledLocalizationCatalogV1.v30Text(.reportsRootThen) : BundledLocalizationCatalogV1.v30Text(.reportsRootNow), isThen: heading == "Then")

            Text(BundledLocalizationCatalogV1.v30ReportsRootVisitDateTime(date: visit.localDate, time: visit.localTime))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(BundledLocalizationCatalogV1.v30ReportsRootVisitStageOutcome(stage: visit.stage, outcome: visit.outcome))
                .font(.subheadline)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            comparisonImage(
                image: wideImage,
                caption: wideEvidence.purposeDisplay,
                accessibilityLabel: BundledLocalizationCatalogV1.v30ReportsRootEvidenceAccessibilityLabel(heading: heading == "Then" ? BundledLocalizationCatalogV1.v30Text(.reportsRootThen) : BundledLocalizationCatalogV1.v30Text(.reportsRootNow), purpose: wideEvidence.purposeDisplay),
                identifier: "\(identifierPrefix).wide"
            )

            comparisonImage(
                image: closeImage,
                caption: closeEvidence.purposeDisplay,
                accessibilityLabel: BundledLocalizationCatalogV1.v30ReportsRootEvidenceAccessibilityLabel(heading: heading == "Then" ? BundledLocalizationCatalogV1.v30Text(.reportsRootThen) : BundledLocalizationCatalogV1.v30Text(.reportsRootNow), purpose: closeEvidence.purposeDisplay),
                identifier: "\(identifierPrefix).close"
            )
        }
    }

    @ViewBuilder
    private func comparisonHeading(_ heading: String, isThen: Bool) -> some View {
        if isThen {
            headingText(heading, isThen: isThen)
                .accessibilityFocused($focusedElement, equals: .thenHeading)
        } else {
            headingText(heading, isThen: isThen)
        }
    }

    private func headingText(_ heading: String, isThen: Bool) -> some View {
        Text(heading)
            .font(.title2.weight(.bold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(
                isThen
                    ? Self.thenHeadingAccessibilityIdentifier
                    : Self.nowHeadingAccessibilityIdentifier
            )
    }

    private func comparisonImage(
        image: UIImage,
        caption: String,
        accessibilityLabel: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(caption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)

            Image(uiImage: image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: image.size.width, alignment: .leading)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier)
        }
    }

    private var unavailable: some View {
        ReportHistoryUnavailableView(message: BundledLocalizationCatalogV1.v30Text(.reportsReportFailure2))
            .accessibilityIdentifier(Self.unavailableAccessibilityIdentifier)
            .accessibilityFocused($focusedElement, equals: .unavailable)
    }

    private func evidence(
        _ purposeKey: String,
        in visit: ReportHistoryVisitValue
    ) -> ReportHistoryEvidenceValue? {
        let values = visit.evidence.filter { $0.purposeKey == purposeKey }
        guard values.count == 1 else { return nil }
        return values[0]
    }

    private func moveAccessibilityFocus(to target: ComparisonFocus) {
        focusedElement = nil
        Task { @MainActor in
            await Task.yield()
            focusedElement = target
        }
    }
}

private struct ReportHistoryUnavailableView: View {
    let message: String

    var body: some View {
        WorklightCard {
            WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.reportsReportFailure5))
            Text(message)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private func comparableRoots(
    visits: [ReportHistoryVisitValue],
    coordinator: ReportHistoryCoordinator
) -> Set<UUID> {
    Set(
        visits.compactMap { visit in
            guard (try? coordinator.comparison(stableRootID: visit.stableRootID)) != nil else {
                return nil
            }
            return visit.stableRootID
        }
    )
}

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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
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
                    ProgressView("Opening reports")
                        .frame(
                            maxWidth: .infinity,
                            minHeight: DesignTokens.Target.minimumInteractiveHeight
                        )
                        .accessibilityLabel("Opening reports")
                }
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .navigationTitle("Reports")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .onAppear(perform: refreshCurrentIndex)
        .navigationDestination(for: ReportHistoryRoute.self) { route in
            destination(for: route)
        }
    }

    private var filters: some View {
        AssetRoundsEvidenceCard {
            Text("Filter reports")
                .font(DesignTokens.Typography.sectionHeading)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
                .accessibilityFocused($focusedElement, equals: .header)

            siteFilter
            signFilter
        }
    }

    private var siteFilter: some View {
        Menu {
            Button("All sites") {
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
        .buttonStyle(.bordered)
        .tint(DesignTokens.SemanticColors.primaryAction)
        .controlSize(.large)
        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
        .accessibilityLabel(siteFilterLabel)
        .accessibilityHint("Filters saved reports by site")
        .accessibilityIdentifier(Self.siteFilterAccessibilityIdentifier)
        .accessibilityFocused($focusedElement, equals: .siteFilter)
    }

    private var signFilter: some View {
        Menu {
            Button("All signs") {
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
        .buttonStyle(.bordered)
        .tint(DesignTokens.SemanticColors.primaryAction)
        .controlSize(.large)
        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
        .accessibilityLabel(signFilterLabel)
        .accessibilityHint("Filters saved reports by sign")
        .accessibilityIdentifier(Self.signFilterAccessibilityIdentifier)
        .accessibilityFocused($focusedElement, equals: .signFilter)
    }

    private var siteFilterLabel: String {
        guard let selectedSiteID else { return "All sites" }
        return siteOptions.first { $0.id == selectedSiteID }?.label ?? "All sites"
    }

    private var signFilterLabel: String {
        guard let selectedSignID else { return "All signs" }
        return signOptions.first { $0.id == selectedSignID }?.label ?? "All signs"
    }

    private var emptyState: some View {
        AssetRoundsEmptyState(
            title: Text("Reports"),
            message: Text("Saved reports will appear here.")
        )
        .accessibilityRepresentation {
            VStack(alignment: .leading) {
                Label("Reports", systemImage: "info.circle.fill")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Information: Reports")

                Text("Saved reports will appear here.")
            }
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
                    message: "The saved report could not be opened."
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
                    message: "This comparison is unavailable."
                )
            }
        }
    }

    private func loadInitialIndex() {
        guard let historyCoordinator else {
            loadErrorMessage = "Saved reports could not be opened."
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
            loadErrorMessage = "Saved reports could not be opened."
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
            loadErrorMessage = "Saved reports could not be opened."
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
            loadErrorMessage = "Saved reports could not be opened."
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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                if let loadErrorMessage {
                    ReportHistoryUnavailableView(message: loadErrorMessage)
                        .accessibilityFocused(
                            $focusedElement,
                            equals: .unavailable
                        )
                } else if let history {
                    AssetRoundsEvidenceCard {
                        Text(history.assetLabel)
                            .font(DesignTokens.Typography.screenTitle)
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
                            .accessibilityFocused($focusedElement, equals: .header)

                        Text(history.siteLabel)
                            .font(DesignTokens.Typography.primaryBody)
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Chronological report history")
                            .font(DesignTokens.Typography.secondaryBody)
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    }

                    if history.visits.isEmpty {
                        AssetRoundsEvidenceCard {
                            Text("No saved reports for this sign.")
                                .font(DesignTokens.Typography.primaryBody)
                                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        ReportVisitList(
                            visits: history.visits,
                            comparableRootIDs: comparableRootIDs
                        )
                    }
                } else {
                    ProgressView("Opening report history")
                        .frame(
                            maxWidth: .infinity,
                            minHeight: DesignTokens.Target.minimumInteractiveHeight
                        )
                        .accessibilityLabel("Opening report history")
                }
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .navigationTitle("Report history")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
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
                loadErrorMessage = "Report history could not be opened."
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
            loadErrorMessage = "Report history could not be opened."
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
            ForEach(visits) { visit in
                AssetRoundsEvidenceCard {
                    AssetRoundsStateLabel(
                        kind: .completed,
                        text: Text("Current revision")
                    )
                    .accessibilityLabel("Complete: Current revision")
                    .accessibilityValue(Text(verbatim: String()))

                    Text(visit.assetLabel)
                        .font(DesignTokens.Typography.sectionHeading)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(visit.siteLabel)
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ReportVisitFact(label: "Visit", value: visitDate(visit))
                    ReportVisitFact(label: "Stage", value: visit.stage)
                    ReportVisitFact(label: "Outcome", value: visit.outcome)

                    NavigationLink(
                        "View report",
                        value: ReportHistoryRoute.report(visit.reportID)
                    )
                    .buttonStyle(.bordered)
                    .tint(DesignTokens.SemanticColors.primaryAction)
                    .controlSize(.large)
                    .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                    .accessibilityHint("Opens this saved report")
                    .accessibilityIdentifier(
                        ReportsRootView.viewReportAccessibilityIdentifier
                    )

                    if comparableRootIDs.contains(visit.stableRootID) {
                        NavigationLink(
                            "Compare with previous",
                            value: ReportHistoryRoute.comparison(visit.stableRootID)
                        )
                        .buttonStyle(.bordered)
                        .tint(DesignTokens.SemanticColors.primaryAction)
                        .controlSize(.large)
                        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                        .accessibilityHint(
                            "Compares this visit with the immediately previous visit"
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
        "\(visit.localDate) at \(visit.localTime)"
    }
}

private struct ReportVisitFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space4) {
            Text(label)
                .font(DesignTokens.Typography.supportingCaption.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            Text(value)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
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
                    message: "The saved report could not be opened."
                )
                .accessibilityFocused($focusedElement, equals: .unavailable)
            } else {
                ProgressView("Opening report")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DesignTokens.SemanticColors.workBackground)
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
                    ProgressView("Opening comparison")
                        .frame(
                            maxWidth: .infinity,
                            minHeight: DesignTokens.Target.minimumInteractiveHeight
                        )
                        .accessibilityLabel("Opening comparison")
                }
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .navigationTitle("Then and Now")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
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
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.space16) {
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
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
        AssetRoundsPhotoCapture {
            comparisonHeading(heading)

            Text("\(visit.localDate) at \(visit.localTime)")
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(visit.stage) · \(visit.outcome)")
                .font(DesignTokens.Typography.secondaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            comparisonImage(
                image: wideImage,
                caption: wideEvidence.purposeDisplay,
                accessibilityLabel: "\(heading) \(wideEvidence.purposeDisplay)",
                identifier: "\(identifierPrefix).wide"
            )

            comparisonImage(
                image: closeImage,
                caption: closeEvidence.purposeDisplay,
                accessibilityLabel: "\(heading) \(closeEvidence.purposeDisplay)",
                identifier: "\(identifierPrefix).close"
            )
        }
    }

    @ViewBuilder
    private func comparisonHeading(_ heading: String) -> some View {
        if heading == "Then" {
            headingText(heading)
                .accessibilityFocused($focusedElement, equals: .thenHeading)
        } else {
            headingText(heading)
        }
    }

    private func headingText(_ heading: String) -> some View {
        Text(heading)
            .font(DesignTokens.Typography.screenTitle)
            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(
                heading == "Then"
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(caption)
                .font(DesignTokens.Typography.fieldLabel)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)

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
        ReportHistoryUnavailableView(message: "This comparison is unavailable.")
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
        AssetRoundsEvidenceCard {
            AssetRoundsStateLabel(
                kind: .unavailable,
                text: Text("Unavailable")
            )
            .accessibilityLabel("Blocked: Unavailable")
            .accessibilityValue(Text(verbatim: String()))
            Text(message)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
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

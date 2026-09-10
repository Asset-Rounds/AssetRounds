import Foundation
import SwiftData
import SwiftUI

struct SignsRootView: View {
    static let welcomeScreenAccessibilityIdentifier = "s2.welcome.screen"
    static let welcomeTitleAccessibilityIdentifier = "s2.welcome.title"
    static let addFirstSignAccessibilityIdentifier = "s2.welcome.add-first-sign"
    static let viewSampleAccessibilityIdentifier = "s2.welcome.view-sample"
    static let restoreDataAccessibilityIdentifier = "s2.welcome.restore-data-backup"
    static let restorePurchasesAccessibilityIdentifier = "s2.welcome.restore-purchases"
    static let sampleScreenAccessibilityIdentifier = "s2.sample.screen"
    static let sampleBackAccessibilityIdentifier = "s2.sample.back"
    static let signSelectionAccessibilityIdentifier = "s7.4.signs.selection"
    static let signRowAccessibilityIdentifier = "s7.4.signs.row"
    static let addSignAccessibilityIdentifier = "s7.4.signs.add-sign"
    static let accessNoticeAccessibilityIdentifier = "s7.4.signs.access-notice"

    private struct LifecyclePresentation: Identifiable {
        let id = UUID()
    }

    private struct PaywallPresentation: Identifiable {
        let id = UUID()
    }

    private enum Route: Hashable {
        case sample
        case newSign
        case settings
        case check
        case report(UUID)
        case reportHistory(UUID)
        case issue(UUID)
        case work(WorkDraftValue)
    }

    let pack: SignPack
    let generationRootURL: URL
    let modelContext: ModelContext
    let diagnosticsStore: DiagnosticsStore
    let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    let feedbackConfiguration: FeedbackConfigurationV1
    let mailComposerAdapter: MailComposerAdapter
    let usesImportedCaptureFixturesForUITest: Bool
    let cameraAdapter: CameraAdapter
    let restoreDataBackup: @MainActor () -> Void
    let replaceDataBackup: @MainActor () -> Void

    @ObservedObject var purchaseCoordinator: StoreKitPurchaseCoordinator
    @ObservedObject var lifecycleCoordinator: StoreKitLifecycleCoordinator

    @StateObject private var coordinator: FirstSignCoordinator
    private let checkRunnerCoordinator: CheckRunnerCoordinator
    private let reportDeliveryCoordinator: ReportDeliveryCoordinator?
    private let reportHistoryCoordinator: ReportHistoryCoordinator?
    private let workCoordinator: WorkCoordinator?
    private let deletionService: WholeSignDeletionService
    @State private var snapshot: FirstSignSnapshot?
    @State private var snapshots = [FirstSignSnapshot]()
    @State private var showsSignSelection = false
    @State private var readyReport: ReportDeliveryValue?
    @State private var path = NavigationPath()
    @State private var didLoad = false
    @State private var loadErrorMessage: String?
    @State private var checkNotice: String?
    @State private var activeIssue: WorkIssuePresentationValue?
    @State private var lifecyclePresentation: LifecyclePresentation?
    @State private var paywallPresentation: PaywallPresentation?
    @AccessibilityFocusState private var welcomeTitleFocused: Bool

    init(
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter,
        feedbackConfiguration: FeedbackConfigurationV1,
        mailComposerAdapter: MailComposerAdapter,
        pack: SignPack,
        generationRootURL: URL,
        usesImportedCaptureFixturesForUITest: Bool = false,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        cameraAdapter: CameraAdapter = .live,
        purchaseCoordinator: StoreKitPurchaseCoordinator,
        lifecycleCoordinator: StoreKitLifecycleCoordinator,
        restoreDataBackup: @escaping @MainActor () -> Void = {},
        replaceDataBackup: @escaping @MainActor () -> Void = {}
    ) {
        self.pack = pack
        self.generationRootURL = generationRootURL
        self.modelContext = modelContext
        self.diagnosticsStore = diagnosticsStore
        self.metricKitDiagnosticsAdapter = metricKitDiagnosticsAdapter
        self.feedbackConfiguration = feedbackConfiguration
        self.mailComposerAdapter = mailComposerAdapter
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        self.cameraAdapter = cameraAdapter
        self.purchaseCoordinator = purchaseCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
        self.restoreDataBackup = restoreDataBackup
        self.replaceDataBackup = replaceDataBackup
        _coordinator = StateObject(
            wrappedValue: FirstSignCoordinator(
                modelContext: modelContext,
                diagnosticsStore: diagnosticsStore,
                signPack: pack,
                accessState: { lifecycleCoordinator.draftAccessState }
            )
        )
        let runnerCoordinator = CheckRunnerCoordinator(
            modelContext: modelContext,
            signPack: pack,
            diagnosticsStore: diagnosticsStore,
            injectsLowStorageFailureOnceForUITest:
                injectsLowStorageFailureOnceForUITest,
            draftAccessState: { lifecycleCoordinator.draftAccessState }
        )
        runnerCoordinator.configureCapture(generationRootURL: generationRootURL)
        checkRunnerCoordinator = runnerCoordinator
        let deliveryCoordinator = try? ReportDeliveryCoordinator(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            diagnosticsStore: diagnosticsStore,
            signPack: pack
        )
        reportDeliveryCoordinator = deliveryCoordinator
        reportHistoryCoordinator = deliveryCoordinator.map {
            ReportHistoryCoordinator(
                modelContext: modelContext,
                deliveryCoordinator: $0
            )
        }
        workCoordinator = try? WorkCoordinator(
            modelContext: modelContext,
            signPack: pack,
            generationRootURL: generationRootURL,
            checkRunnerCoordinator: runnerCoordinator
        )
        deletionService = WholeSignDeletionService(
            modelContext: modelContext,
            generationRootURL: generationRootURL
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if showsSignSelection, !snapshots.isEmpty {
                    signSelection
                } else if let snapshot {
                    SignDetailView(
                        snapshot: snapshot,
                        checkNotice: checkNotice,
                        openReport: readyReport.map { report in
                            { openReport(id: report.reportID) }
                        },
                        openReportHistory: {
                            path.append(Route.reportHistory(snapshot.assetID))
                        },
                        refreshReport: refreshReadyReport,
                        activeIssue: activeIssue,
                        openIssue: openActiveIssue,
                        recordWork: beginRecordWork,
                        refreshIssue: { refreshActiveIssue() },
                        startCheck: {
                            beginCheck()
                        },
                        showAllSigns: showAllSigns,
                        addSign: beginAddSign,
                        deleteSign: {
                            try await deleteCurrentSign(assetID: snapshot.assetID)
                        }
                    )
                } else if let loadErrorMessage {
                    loadFailure(message: loadErrorMessage)
                } else {
                    welcome
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        path.append(Route.settings)
                    } label: {
                        Label(BundledLocalizationCatalogV1.v30Text(.signsRootSettings), systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(AppShellView.settingsButtonAccessibilityIdentifier)
                }
                .padding(.horizontal, DesignTokens.Spacing.medium)
                .padding(.vertical, DesignTokens.Spacing.small)
                .background(DesignTokens.Colors.canvas)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .sample:
                    sample
                case .newSign:
                    NewSignView(
                        coordinator: coordinator,
                        siteOptions: (try? coordinator.siteOptions()) ?? [],
                        accessBlocked: handleAccessDecision
                    ) { savedSnapshot in
                        do {
                            snapshots = try coordinator.loadAll()
                            select(savedSnapshot)
                            path = NavigationPath()
                        } catch {
                            loadErrorMessage = BundledLocalizationCatalogV1.v30Text(.signsRootSavedDataUnavailable)
                        }
                    }
                case .settings:
                    SettingsPlaceholderView(
                        modelContext: modelContext,
                        generationRootURL: generationRootURL,
                        diagnosticsStore: diagnosticsStore,
                        metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                        feedbackConfiguration: feedbackConfiguration,
                        mailComposerAdapter: mailComposerAdapter,
                        purchaseCoordinator: purchaseCoordinator,
                        lifecycleCoordinator: lifecycleCoordinator,
                        restoreDataBackup: replaceDataBackup
                    )
                case .check:
                    if let snapshot {
                        PreflightView(
                            snapshot: snapshot,
                            pack: pack,
                            coordinator: checkRunnerCoordinator,
                            generationRootURL: generationRootURL,
                            usesImportedCaptureFixturesForUITest:
                                usesImportedCaptureFixturesForUITest,
                            cameraAdapter: cameraAdapter,
                            cannotComplete: {
                                checkRunnerCoordinator.clearPendingRecheckRequest()
                                path.removeLast()
                            }
                        ) {
                            checkRunnerCoordinator.clearPendingRecheckRequest()
                            checkNotice = BundledLocalizationCatalogV1.v30Text(.signsRootNoCheckStarted)
                            path.removeLast()
                        }
                    }
                case .report(let reportID):
                    if let reportDeliveryCoordinator,
                       let delivery = try? reportDeliveryCoordinator.loadReadyReport(
                           id: reportID
                       ) {
                        ReportDetailView(
                            delivery: delivery,
                            coordinator: reportDeliveryCoordinator
                        )
                    } else {
                        reportUnavailable
                    }
                case .reportHistory(let assetID):
                    if let reportHistoryCoordinator,
                       let reportDeliveryCoordinator {
                        SignReportHistoryView(
                            assetID: assetID,
                            historyCoordinator: reportHistoryCoordinator,
                            deliveryCoordinator: reportDeliveryCoordinator
                        )
                    } else {
                        reportHistoryUnavailable
                    }
                case .issue(let issueID):
                    if let activeIssue,
                       activeIssue.id == issueID {
                        IssueDetailView(
                            issue: activeIssue,
                            recordWork: beginRecordWork,
                            startRecheck: beginRecheck
                        )
                        .onDisappear {
                            guard activeIssue.status == .resolved else { return }
                            self.activeIssue = nil
                            refreshActiveIssue(
                                preferRetained: false,
                                openLoadedIssue: true
                            )
                        }
                    } else {
                        issueUnavailable
                    }
                case .work(let draft):
                    if let workCoordinator {
                        RecordWorkView(
                            draft: draft,
                            coordinator: workCoordinator,
                            usesImportedFixtureForUITest:
                                usesImportedCaptureFixturesForUITest
                        ) { issue in
                            activeIssue = issue
                            if !path.isEmpty {
                                path.removeLast()
                            }
                            path.append(Route.issue(issue.id))
                        }
                    } else {
                        issueUnavailable
                    }
                }
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true

            do {
                snapshots = try coordinator.loadAll()
                if snapshots.count == 1, let loadedSnapshot = snapshots.first {
                    select(loadedSnapshot)
                    _ = try resumeExistingDraftIfPresent(
                        assetID: loadedSnapshot.assetID
                    )
                } else if snapshots.count > 1 {
                    snapshot = nil
                    showsSignSelection = true
                }
            } catch {
                loadErrorMessage = BundledLocalizationCatalogV1.v30Text(.signsRootSavedDataUnavailable)
            }
        }
        .sheet(item: $lifecyclePresentation) { _ in
            NavigationStack {
                SubscriptionStatusView(
                    coordinator: lifecycleCoordinator,
                    startsRestoreOnAppear: true,
                    close: { lifecyclePresentation = nil }
                )
            }
        }
        .sheet(item: $paywallPresentation) { presentation in
            PaywallView(
                coordinator: purchaseCoordinator,
                presentationToken: presentation.id,
                close: { paywallPresentation = nil }
            )
        }
    }

    private func refreshReadyReport() {
        guard let assetID = snapshot?.assetID,
              let reportDeliveryCoordinator else {
            readyReport = nil
            return
        }
        readyReport = try? reportDeliveryCoordinator.onlyReadyReport(assetID: assetID)
    }

    private func select(_ value: FirstSignSnapshot) {
        snapshot = value
        showsSignSelection = false
        readyReport = nil
        activeIssue = nil
        checkNotice = nil
        refreshReadyReport()
        refreshActiveIssue(preferRetained: false)
    }

    private func showAllSigns() {
        path = NavigationPath()
        showsSignSelection = true
        checkNotice = nil
    }

    private func selectAndResume(_ value: FirstSignSnapshot) {
        select(value)
        do {
            _ = try resumeExistingDraftIfPresent(assetID: value.assetID)
        } catch {
            checkNotice = BundledLocalizationCatalogV1.v30Text(.signsRootDraftResumeUnavailable)
        }
    }

    private func beginAddSign() {
        do {
            handleEntryDecision(
                try coordinator.accessDecisionForCreateSign(),
                allowed: { path.append(Route.newSign) }
            )
        } catch {
            checkNotice = BundledLocalizationCatalogV1.v30Text(.signsRootNewSignUnavailable)
        }
    }

    private func beginCheck() {
        guard let snapshot else { return }
        do {
            if try resumeExistingDraftIfPresent(assetID: snapshot.assetID) {
                return
            }
            let decision = try checkRunnerCoordinator.accessDecision(
                assetID: snapshot.assetID,
                requestedStage: .check,
                issueID: nil
            )
            handleEntryDecision(decision) {
                checkRunnerCoordinator.clearPendingRecheckRequest()
                checkNotice = nil
                path.append(Route.check)
            }
        } catch {
            checkNotice = BundledLocalizationCatalogV1.v30Text(.signsRootNewCheckUnavailable)
        }
    }

    private func handleEntryDecision(
        _ decision: DraftAccessDecisionV1,
        allowed: () -> Void
    ) {
        switch decision {
        case .allow, .continueExisting:
            allowed()
        case .blockPaid, .blockEvaluation:
            paywallPresentation = PaywallPresentation()
        case .waitForStore:
            checkNotice = BundledLocalizationCatalogV1.v30Text(.signsRootSubscriptionChecking)
        case .blockInvalidRequest:
            checkNotice = BundledLocalizationCatalogV1.v30Text(.signsRootActionUnavailable)
        }
    }

    private func handleAccessDecision(_ decision: DraftAccessDecisionV1) {
        handleEntryDecision(decision, allowed: {})
    }

    @discardableResult
    private func resumeExistingDraftIfPresent(assetID: UUID) throws -> Bool {
        guard let draft = try checkRunnerCoordinator.existingDraft(
            assetID: assetID
        ),
              let stage = WorkflowStage(rawValue: draft.stage) else {
            return false
        }
        let decision = try checkRunnerCoordinator.accessDecision(
            assetID: assetID,
            requestedStage: stage,
            issueID: draft.issueID
        )
        guard decision == .continueExisting else {
            handleAccessDecision(decision)
            return true
        }
        switch stage {
        case .check, .recheck:
            path.append(Route.check)
        case .work:
            guard let issueID = draft.issueID else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            path.append(Route.work(WorkDraftValue(
                recordID: draft.id,
                issueID: issueID,
                assetID: draft.assetID,
                startedAt: draft.startedAt
            )))
        }
        return true
    }

    private func refreshActiveIssue(
        preferRetained: Bool = true,
        openLoadedIssue: Bool = false
    ) {
        guard let assetID = snapshot?.assetID,
              let workCoordinator else {
            activeIssue = nil
            return
        }
        Task {
            if preferRetained,
               let retained = activeIssue,
               let status = try? checkRunnerCoordinator.issueStatus(
                assetID: assetID,
                issueID: retained.id
               ),
               status == .resolved {
                guard snapshot?.assetID == assetID else { return }
                activeIssue = WorkIssuePresentationValue(
                    id: retained.id,
                    assetID: retained.assetID,
                    label: retained.label,
                    status: status,
                    records: retained.records
                )
            } else if let loaded = try? await workCoordinator.activeIssue(assetID: assetID) {
                guard snapshot?.assetID == assetID else { return }
                activeIssue = loaded
                if openLoadedIssue {
                    path.append(Route.issue(loaded.id))
                }
            } else if let retained = activeIssue,
                      let status = try? checkRunnerCoordinator.issueStatus(
                        assetID: assetID,
                        issueID: retained.id
                      ) {
                guard snapshot?.assetID == assetID else { return }
                activeIssue = WorkIssuePresentationValue(
                    id: retained.id,
                    assetID: retained.assetID,
                    label: retained.label,
                    status: status,
                    records: retained.records
                )
            } else {
                guard snapshot?.assetID == assetID else { return }
                activeIssue = nil
            }
        }
    }

    private func openActiveIssue() {
        guard let activeIssue else { return }
        path.append(Route.issue(activeIssue.id))
    }

    private func beginRecordWork() {
        guard let snapshot,
              let activeIssue,
              activeIssue.canRecordWork,
              let workCoordinator else {
            return
        }
        do {
            if try resumeExistingDraftIfPresent(assetID: snapshot.assetID) {
                return
            }
            let draft = try workCoordinator.beginWork(issueID: activeIssue.id)
            path.append(Route.work(draft))
        } catch let error as WorkCoordinatorError {
            if case let .accessDenied(decision) = error {
                handleAccessDecision(decision)
                return
            }
            refreshActiveIssue()
        } catch {
            refreshActiveIssue()
        }
    }

    private func beginRecheck() {
        guard let snapshot,
              let activeIssue,
              activeIssue.status == .recheckDue else {
            return
        }
        do {
            if try resumeExistingDraftIfPresent(assetID: snapshot.assetID) {
                return
            }
            try checkRunnerCoordinator.requestRecheck(
                assetID: activeIssue.assetID,
                issueID: activeIssue.id
            )
            path.append(Route.check)
        } catch let error as CheckRunnerCoordinatorError {
            if case let .accessDenied(decision) = error {
                handleAccessDecision(decision)
                return
            }
            refreshActiveIssue()
        } catch {
            refreshActiveIssue()
        }
    }

    private func openReport(id reportID: UUID) {
        guard let assetID = snapshot?.assetID,
              let reportDeliveryCoordinator,
              let delivery = try? reportDeliveryCoordinator.onlyReadyReport(assetID: assetID),
              delivery.reportID == reportID else {
            readyReport = nil
            return
        }
        path.append(Route.report(reportID))
    }

    private func deleteCurrentSign(assetID: UUID) async throws {
        do {
            _ = try await deletionService.delete(assetID: assetID)
        } catch {
            let recovery = try? await deletionService.reconcile()
            guard recovery?.completedCommittedCount ?? 0 > 0 else {
                throw error
            }
        }
        path = NavigationPath()
        readyReport = nil
        activeIssue = nil
        checkNotice = nil
        loadErrorMessage = nil
        snapshots = try coordinator.loadAll()
        if snapshots.count == 1, let remaining = snapshots.first {
            select(remaining)
        } else if snapshots.isEmpty {
            snapshot = nil
            showsSignSelection = false
        } else {
            snapshot = nil
            showsSignSelection = true
        }
        await Task.yield()
        welcomeTitleFocused = snapshots.isEmpty
    }

    private var reportUnavailable: some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.signsRootReportUnavailable))
                Text(BundledLocalizationCatalogV1.v30Text(.signsRootSavedReportUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
    }

    private var reportHistoryUnavailable: some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.signsRootHistoryUnavailable))
                Text(BundledLocalizationCatalogV1.v30Text(.signsRootReportHistoryUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
    }

    private var issueUnavailable: some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.signsRootRecordWork))
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    WorklightStatusBadge(kind: .information, text: BundledLocalizationCatalogV1.v30Text(.signsRootBrandBadge))

                    Text(BundledLocalizationCatalogV1.v30Text(.signsRootWelcomeMessage))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.welcomeTitleAccessibilityIdentifier)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($welcomeTitleFocused)

                    Text(BundledLocalizationCatalogV1.v30Text(.signsRootWelcomeInstructions))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(BundledLocalizationCatalogV1.v30Text(.signsRootAddFirstSign)) {
                    beginAddSign()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityIdentifier(Self.addFirstSignAccessibilityIdentifier)

                Button(BundledLocalizationCatalogV1.v30Text(.signsRootViewSample)) {
                    path.append(Route.sample)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier(Self.viewSampleAccessibilityIdentifier)

                WorklightCard {
                    Button(BundledLocalizationCatalogV1.v30Text(.signsRootRestoreDataBackup), action: restoreDataBackup)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier(Self.restoreDataAccessibilityIdentifier)

                    Button(BundledLocalizationCatalogV1.v30Text(.signsRootRestorePurchases)) {
                        lifecyclePresentation = LifecyclePresentation()
                    }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityHint(
                            BundledLocalizationCatalogV1.v30Text(.signsRootRestorePurchasesHint)
                        )
                        .accessibilityIdentifier(Self.restorePurchasesAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.signsRootNavigationTitle))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.welcomeScreenAccessibilityIdentifier)
    }

    private var signSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    Text(BundledLocalizationCatalogV1.v30Text(.signsRootHeading))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text(BundledLocalizationCatalogV1.v30Text(.signsRootInstructions))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(snapshots) { value in
                    Button {
                        selectAndResume(value)
                    } label: {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            Text(value.signLabel)
                                .font(.headline)
                            Text(value.siteLabel)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityLabel(BundledLocalizationCatalogV1.v30SignsRootSignRowAccessibility(signLabel: value.signLabel, siteLabel: value.siteLabel))
                    .accessibilityIdentifier(
                        "\(Self.signRowAccessibilityIdentifier).\(value.assetID.uuidString.lowercased())"
                    )
                }

                Button(BundledLocalizationCatalogV1.v30Text(.signsRootAddSign), action: beginAddSign)
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .accessibilityIdentifier(Self.addSignAccessibilityIdentifier)

                if let checkNotice {
                    WorklightStatusBadge(kind: .information, text: checkNotice)
                        .accessibilityIdentifier(Self.accessNoticeAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
            .navigationTitle(BundledLocalizationCatalogV1.v30Text(.signsRootNavigationTitle))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.signSelectionAccessibilityIdentifier)
    }

    private var sample: some View {
        PackSampleView(pack: pack)
            .navigationTitle(BundledLocalizationCatalogV1.v30Text(.signsRootSampleNavigationTitle))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        path.removeLast()
                    } label: {
                        Label(BundledLocalizationCatalogV1.v30Text(.signsRootBack), systemImage: "chevron.left")
                    }
                    .frame(
                        minWidth: DesignTokens.Control.minimumHitSize,
                        minHeight: DesignTokens.Control.minimumHitSize
                    )
                    .accessibilityIdentifier(Self.sampleBackAccessibilityIdentifier)
                }
            }
            .accessibilityIdentifier(Self.sampleScreenAccessibilityIdentifier)
    }

    private func loadFailure(message: String) -> some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.signsRootSavedDataUnavailableBadge))

                Text(message)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
    }
}

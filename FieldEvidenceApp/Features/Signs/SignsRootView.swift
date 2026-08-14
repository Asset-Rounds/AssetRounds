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

    private enum Route: Hashable {
        case sample
        case newSign
        case check
        case report(UUID)
        case reportHistory(UUID)
        case issue(UUID)
        case work(WorkDraftValue)
    }

    let pack: SignPack
    let generationRootURL: URL
    let modelContext: ModelContext
    let usesImportedCaptureFixturesForUITest: Bool
    let cameraAdapter: CameraAdapter
    let restoreDataBackup: @MainActor () -> Void
    let replaceDataBackup: @MainActor () -> Void

    @StateObject private var coordinator: FirstSignCoordinator
    private let checkRunnerCoordinator: CheckRunnerCoordinator
    private let reportDeliveryCoordinator: ReportDeliveryCoordinator?
    private let reportHistoryCoordinator: ReportHistoryCoordinator?
    private let workCoordinator: WorkCoordinator?
    private let deletionService: WholeSignDeletionService
    @State private var snapshot: FirstSignSnapshot?
    @State private var readyReport: ReportDeliveryValue?
    @State private var path = NavigationPath()
    @State private var didLoad = false
    @State private var loadErrorMessage: String?
    @State private var checkNotice: String?
    @State private var activeIssue: WorkIssuePresentationValue?
    @AccessibilityFocusState private var welcomeTitleFocused: Bool

    init(
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        pack: SignPack,
        generationRootURL: URL,
        usesImportedCaptureFixturesForUITest: Bool = false,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        cameraAdapter: CameraAdapter = .live,
        restoreDataBackup: @escaping @MainActor () -> Void = {},
        replaceDataBackup: @escaping @MainActor () -> Void = {}
    ) {
        self.pack = pack
        self.generationRootURL = generationRootURL
        self.modelContext = modelContext
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        self.cameraAdapter = cameraAdapter
        self.restoreDataBackup = restoreDataBackup
        self.replaceDataBackup = replaceDataBackup
        _coordinator = StateObject(
            wrappedValue: FirstSignCoordinator(
                modelContext: modelContext,
                diagnosticsStore: diagnosticsStore,
                signPack: pack
            )
        )
        let runnerCoordinator = CheckRunnerCoordinator(
            modelContext: modelContext,
            signPack: pack,
            diagnosticsStore: diagnosticsStore,
            injectsLowStorageFailureOnceForUITest:
                injectsLowStorageFailureOnceForUITest
        )
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
                if let snapshot {
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
                            checkRunnerCoordinator.clearPendingRecheckRequest()
                            checkNotice = nil
                            path.append(Route.check)
                        },
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
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .sample:
                    sample
                case .newSign:
                    NewSignView(coordinator: coordinator) { savedSnapshot in
                        snapshot = savedSnapshot
                        path = NavigationPath()
                    }
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
                            checkNotice = "No check was started."
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsPlaceholderView(
                            modelContext: modelContext,
                            generationRootURL: generationRootURL,
                            restoreDataBackup: replaceDataBackup
                        )
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .frame(
                        minWidth: DesignTokens.Control.minimumHitSize,
                        minHeight: DesignTokens.Control.minimumHitSize
                    )
                    .contentShape(Rectangle())
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier(AppShellView.settingsButtonAccessibilityIdentifier)
                }
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true

            do {
                let loadedSnapshot = try coordinator.load()
                snapshot = loadedSnapshot
                refreshReadyReport()
                refreshActiveIssue()

                if let loadedSnapshot,
                   try checkRunnerCoordinator.existingDraft(assetID: loadedSnapshot.assetID) != nil {
                    path.append(Route.check)
                }
            } catch {
                loadErrorMessage = "Saved sign data could not be opened."
            }
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
                activeIssue = WorkIssuePresentationValue(
                    id: retained.id,
                    assetID: retained.assetID,
                    label: retained.label,
                    status: status,
                    records: retained.records
                )
            } else if let loaded = try? await workCoordinator.activeIssue(assetID: assetID) {
                activeIssue = loaded
                if openLoadedIssue {
                    path.append(Route.issue(loaded.id))
                }
            } else if let retained = activeIssue,
                      let status = try? checkRunnerCoordinator.issueStatus(
                        assetID: assetID,
                        issueID: retained.id
                      ) {
                activeIssue = WorkIssuePresentationValue(
                    id: retained.id,
                    assetID: retained.assetID,
                    label: retained.label,
                    status: status,
                    records: retained.records
                )
            } else {
                activeIssue = nil
            }
        }
    }

    private func openActiveIssue() {
        guard let activeIssue else { return }
        path.append(Route.issue(activeIssue.id))
    }

    private func beginRecordWork() {
        guard let activeIssue,
              activeIssue.canRecordWork,
              let workCoordinator else {
            return
        }
        do {
            let draft = try workCoordinator.beginWork(issueID: activeIssue.id)
            path.append(Route.work(draft))
        } catch {
            refreshActiveIssue()
        }
    }

    private func beginRecheck() {
        guard let activeIssue,
              activeIssue.status == .recheckDue else {
            return
        }
        do {
            try checkRunnerCoordinator.requestRecheck(
                assetID: activeIssue.assetID,
                issueID: activeIssue.id
            )
            path.append(Route.check)
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
        snapshot = try coordinator.load()
        await Task.yield()
        welcomeTitleFocused = true
    }

    private var reportUnavailable: some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(kind: .blocked, text: "Report unavailable")
                Text("The saved report could not be opened.")
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
                WorklightStatusBadge(kind: .blocked, text: "History unavailable")
                Text("Report history could not be opened.")
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
                WorklightStatusBadge(kind: .blocked, text: "Record work")
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
                    WorklightStatusBadge(kind: .information, text: "Field Evidence")

                    Text("Turn tonight's sign check into a clear report.")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.welcomeTitleAccessibilityIdentifier)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($welcomeTitleFocused)

                    Text("Add the first sign you inspect, or look through the bundled sample before you begin.")
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Add first sign") {
                    path.append(Route.newSign)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityIdentifier(Self.addFirstSignAccessibilityIdentifier)

                Button("View sample") {
                    path.append(Route.sample)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier(Self.viewSampleAccessibilityIdentifier)

                WorklightCard {
                    Button("Restore data backup", action: restoreDataBackup)
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier(Self.restoreDataAccessibilityIdentifier)

                    Button("Restore Purchases") {}
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(true)
                        .accessibilityHint("Unavailable in this version")
                        .accessibilityIdentifier(Self.restorePurchasesAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Signs")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.welcomeScreenAccessibilityIdentifier)
    }

    private var sample: some View {
        PackSampleView(pack: pack)
            .navigationTitle("Sample")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        path.removeLast()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
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
                WorklightStatusBadge(kind: .blocked, text: "Saved data unavailable")

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

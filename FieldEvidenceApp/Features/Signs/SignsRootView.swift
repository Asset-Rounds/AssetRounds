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
    }

    let pack: SignPack
    let generationRootURL: URL
    let usesImportedCaptureFixturesForUITest: Bool
    let cameraAdapter: CameraAdapter

    @StateObject private var coordinator: FirstSignCoordinator
    private let checkRunnerCoordinator: CheckRunnerCoordinator
    private let reportDeliveryCoordinator: ReportDeliveryCoordinator?
    private let reportHistoryCoordinator: ReportHistoryCoordinator?
    @State private var snapshot: FirstSignSnapshot?
    @State private var readyReport: ReportDeliveryValue?
    @State private var path = NavigationPath()
    @State private var didLoad = false
    @State private var loadErrorMessage: String?
    @State private var checkNotice: String?

    init(
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        pack: SignPack,
        generationRootURL: URL,
        usesImportedCaptureFixturesForUITest: Bool = false,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        cameraAdapter: CameraAdapter = .live
    ) {
        self.pack = pack
        self.generationRootURL = generationRootURL
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        self.cameraAdapter = cameraAdapter
        _coordinator = StateObject(
            wrappedValue: FirstSignCoordinator(
                modelContext: modelContext,
                diagnosticsStore: diagnosticsStore,
                signPack: pack
            )
        )
        checkRunnerCoordinator = CheckRunnerCoordinator(
            modelContext: modelContext,
            signPack: pack,
            diagnosticsStore: diagnosticsStore,
            injectsLowStorageFailureOnceForUITest:
                injectsLowStorageFailureOnceForUITest
        )
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
                        refreshReport: refreshReadyReport
                    ) {
                        checkNotice = nil
                        path.append(Route.check)
                    }
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
                                path.removeLast()
                            }
                        ) {
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
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsPlaceholderView()
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
                    Button("Restore data backup") {}
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(true)
                        .accessibilityHint("Unavailable in this version")
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

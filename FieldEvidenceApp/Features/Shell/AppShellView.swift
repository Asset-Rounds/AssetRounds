import Foundation
import SwiftData
import SwiftUI

private struct EraseAllAction {
    let call: @MainActor () -> Void
}

private struct EraseAllActionKey: EnvironmentKey {
    static let defaultValue = EraseAllAction(call: {})
}

private extension EnvironmentValues {
    var eraseAllAction: EraseAllAction {
        get { self[EraseAllActionKey.self] }
        set { self[EraseAllActionKey.self] = newValue }
    }
}

struct AppShellView: View {
    static let screenAccessibilityIdentifier = "s1.shell.screen"
    static let signsTabAccessibilityIdentifier = "s1.tab.signs"
    static let reportsTabAccessibilityIdentifier = "s1.tab.reports"
    static let settingsButtonAccessibilityIdentifier = "s1.settings.button"
    static let settingsScreenAccessibilityIdentifier = "s1.settings.screen"
    static let reportsPlaceholderAccessibilityIdentifier = "s1.reports.placeholder"
    static let unavailableAccessibilityIdentifier = "s1.pack.unavailable"

    @Environment(\.colorScheme) private var colorScheme

    private enum Tab: Hashable {
        case signs
        case reports
    }

    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool
    let modelContext: ModelContext
    let diagnosticsStore: DiagnosticsStore
    let generationRootURL: URL
    let usesImportedCaptureFixturesForUITest: Bool
    let injectsLowStorageFailureOnceForUITest: Bool
    let cameraAdapter: CameraAdapter
    let restoreDataBackup: @MainActor () -> Void
    let replaceDataBackup: @MainActor () -> Void
    let eraseAll: @MainActor () -> Void

    @StateObject private var purchaseCoordinator: StoreKitPurchaseCoordinator

    @State private var selectedTab: Tab = .signs

    init(
        packLoadResult: SignPackLoadResult,
        exposesColorSchemeForUITest: Bool = false,
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        generationRootURL: URL,
        usesImportedCaptureFixturesForUITest: Bool = false,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        cameraAdapter: CameraAdapter = .live,
        entitlementProcessor: StoreKitTransactionProcessor? = nil,
        paywallCatalogLinks: PaywallCatalogLinksV1? = nil,
        restoreDataBackup: @escaping @MainActor () -> Void = {},
        replaceDataBackup: @escaping @MainActor () -> Void = {},
        eraseAll: @escaping @MainActor () -> Void = {}
    ) {
        self.packLoadResult = packLoadResult
        self.exposesColorSchemeForUITest = exposesColorSchemeForUITest
        self.modelContext = modelContext
        self.diagnosticsStore = diagnosticsStore
        self.generationRootURL = generationRootURL
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        self.injectsLowStorageFailureOnceForUITest =
            injectsLowStorageFailureOnceForUITest
        self.cameraAdapter = cameraAdapter
        _purchaseCoordinator = StateObject(
            wrappedValue: StoreKitPurchaseCoordinator(
                processor: entitlementProcessor,
                diagnosticsStore: diagnosticsStore,
                catalogLinks: paywallCatalogLinks
            )
        )
        self.restoreDataBackup = restoreDataBackup
        self.replaceDataBackup = replaceDataBackup
        self.eraseAll = eraseAll
    }

    var body: some View {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--s6-3-ui-test-validation-summary")
            || arguments.contains("--s6-4-ui-test-export-source") {
            S6_3BackupValidationUITestHost(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                keepsPackageForRestoreUITest: arguments.contains(
                    "--s6-4-ui-test-export-source"
                )
            )
        } else {
            switch packLoadResult {
            case let .available(pack):
                availableShell(pack: pack)
            case .unavailable:
                PackUnavailableView()
                    .accessibilityIdentifier(Self.unavailableAccessibilityIdentifier)
            }
        }
    }

    private func availableShell(pack: SignPack) -> some View {
        TabView(selection: $selectedTab) {
            SignsRootView(
                modelContext: modelContext,
                diagnosticsStore: diagnosticsStore,
                pack: pack,
                generationRootURL: generationRootURL,
                usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                injectsLowStorageFailureOnceForUITest:
                    injectsLowStorageFailureOnceForUITest,
                cameraAdapter: cameraAdapter,
                purchaseCoordinator: purchaseCoordinator,
                restoreDataBackup: restoreDataBackup,
                replaceDataBackup: replaceDataBackup
            )
            .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
            .accessibilityValue(
                exposesColorSchemeForUITest
                    ? (colorScheme == .dark ? "Dark" : "Light")
                    : ""
            )
            .tag(Tab.signs)
            .tabItem {
                Label("Signs", systemImage: "signpost.right.fill")
                    .accessibilityIdentifier(Self.signsTabAccessibilityIdentifier)
            }

            NavigationStack {
                ReportsRootView(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    diagnosticsStore: diagnosticsStore,
                    signPack: pack
                )
                    .toolbar {
                        settingsToolbar
                    }
            }
            .tag(Tab.reports)
            .tabItem {
                Label("Reports", systemImage: "doc.text.fill")
                    .accessibilityIdentifier(Self.reportsTabAccessibilityIdentifier)
            }
        }
        .tint(DesignTokens.Colors.interactionAccent)
        .background(DesignTokens.Colors.canvas)
        .environment(\.eraseAllAction, EraseAllAction(call: eraseAll))
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsPlaceholderView(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    purchaseCoordinator: purchaseCoordinator,
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
            .accessibilityIdentifier(Self.settingsButtonAccessibilityIdentifier)
        }
    }
}

private struct S6_3BackupValidationUITestHost: View {
    let modelContext: ModelContext
    let generationRootURL: URL
    let keepsPackageForRestoreUITest: Bool

    @State private var summary: BackupValidationSummaryV1?
    @State private var didStart = false

    var body: some View {
        Group {
            if let summary {
                BackupValidationSummaryView(summary: summary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .task {
            guard !didStart else { return }
            didStart = true
            loadValidatedSummary()
        }
    }

    @MainActor
    private func loadValidatedSummary() {
        do {
            let fileManager = FileManager.default
            let destination: URL
            if keepsPackageForRestoreUITest {
                destination = try BackupRestoreService.applicationSupportURL(
                    containing: generationRootURL
                ).appendingPathComponent(
                    "S6_4UITestSource",
                    isDirectory: true
                )
            } else {
                destination = fileManager.temporaryDirectory.appendingPathComponent(
                    "S6_3BackupValidationUITest",
                    isDirectory: true
                )
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )
            try materializeMixedFixture(fileManager: fileManager)
            let exporter = BackupExportService(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                now: { Date(timeIntervalSince1970: 1_786_708_800) }
            )
            let preview = try exporter.prepare()
            let packageURL = try exporter.export(
                previewID: preview.id,
                to: destination
            )
            let importer = try BackupImportService(
                generationRootURL: generationRootURL,
                scopedAccess: .alreadyAuthorized
            )
            let validatedPackage = try importer.stageAndValidate(
                selectedPackageURL: packageURL
            )
            try importer.discard(validatedPackage)
            summary = validatedPackage.summary
        } catch {
            summary = nil
        }
    }

    @MainActor
    private func materializeMixedFixture(fileManager: FileManager) throws {
        let issues = try modelContext.fetch(FetchDescriptor<Issue>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        guard issues.count == 1,
              let issue = issues.first,
              issue.status == IssueStatus.resolved.rawValue,
              let resolvedBy = issue.resolvedByRecordID,
              let opening = records.first(where: { $0.id == issue.openedByRecordID }),
              let recheck = records.first(where: {
                  $0.id == resolvedBy
                      && $0.stage == WorkflowStage.recheck.rawValue
                      && $0.revisionKind == WorkflowRevisionKind.original.rawValue
              }),
              let correction = records.first(where: {
                  $0.revisesRecordID == recheck.id
                      && $0.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue
              }),
              correction.evidenceSourceRecordID == recheck.id,
              let separate = records.first(where: {
                  $0.stage == WorkflowStage.check.rawValue
                      && $0.outcomeKey == "no_visible_issue"
                      && $0.issueID == nil
              }),
              let openingReport = reports.first(where: { $0.sourceRecordID == opening.id }),
              let recheckReport = reports.first(where: { $0.sourceRecordID == recheck.id }),
              let correctionReport = reports.first(where: { $0.sourceRecordID == correction.id }),
              let separateReport = reports.first(where: { $0.sourceRecordID == separate.id }),
              reports.count == 4,
              recheckReport.pdfState == ReportPDFState.ready.rawValue,
              correctionReport.pdfState == ReportPDFState.ready.rawValue,
              correctionReport.replacesReportID == recheckReport.id else {
            throw BackupImportServiceError.invalidSource
        }

        try removeReadyPDF(openingReport, fileManager: fileManager)
        openingReport.pdfState = ReportPDFState.failed.rawValue
        openingReport.pdfRelativePath = nil
        openingReport.pdfSHA256 = nil
        try removeReadyPDF(separateReport, fileManager: fileManager)
        separateReport.pdfState = ReportPDFState.pending.rawValue
        separateReport.pdfRelativePath = nil
        separateReport.pdfSHA256 = nil

        modelContext.insert(Packet(
            id: UUID(uuidString: "63000000-0000-0000-0000-000000000089")!,
            stableRootID: UUID(uuidString: "63000000-0000-0000-0000-000000000090")!,
            currentRecordID: nil,
            evaluationCounted: true,
            contentDeletedAt: Date(timeIntervalSince1970: 1_735_689_590),
            createdAt: Date(timeIntervalSince1970: 1_735_689_500)
        ))
        try modelContext.save()
    }

    private func removeReadyPDF(
        _ report: Report,
        fileManager: FileManager
    ) throws {
        let expectedPath = "pdfs/\(report.id.uuidString.lowercased()).pdf"
        guard report.pdfState == ReportPDFState.ready.rawValue,
              report.pdfRelativePath == expectedPath,
              report.pdfSHA256 != nil else {
            throw BackupImportServiceError.invalidSource
        }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
        let url = generationRootURL.appendingPathComponent(expectedPath)
        _ = try ReportPDFAnchoredFile.readRegularFile(
            at: url,
            within: generationRootURL,
            rootIdentity: rootIdentity
        )
        try fileManager.removeItem(at: url)
    }
}

struct SettingsPlaceholderView: View {
    private struct PaywallPresentation: Identifiable {
        let id = UUID()
    }

    @Environment(\.eraseAllAction) private var eraseAllAction

    @ObservedObject var purchaseCoordinator: StoreKitPurchaseCoordinator

    let modelContext: ModelContext
    let generationRootURL: URL
    let restoreDataBackup: @MainActor () -> Void

    @State private var paywallPresentation: PaywallPresentation?

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        purchaseCoordinator: StoreKitPurchaseCoordinator,
        restoreDataBackup: @escaping @MainActor () -> Void = {}
    ) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL
        self.purchaseCoordinator = purchaseCoordinator
        self.restoreDataBackup = restoreDataBackup
    }

    var body: some View {
        ScrollView {
            WorklightCard {
                Text("Settings")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                NavigationLink("Back up current data") {
                    BackupExportView(
                        modelContext: modelContext,
                        generationRootURL: generationRootURL
                    )
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityIdentifier(
                    BackupExportView.settingsEntryAccessibilityIdentifier
                )

                Button("Restore data backup", action: restoreDataBackup)
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(
                        BackupRestoreProgressView.settingsEntryAccessibilityIdentifier
                    )

                Button("View subscription") {
                    paywallPresentation = PaywallPresentation()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(
                    "Shows the monthly subscription without changing existing data"
                )
                .accessibilityIdentifier(
                    PaywallView.settingsEntryAccessibilityIdentifier
                )

                Text("Inspection data and photos are device-local and do not sync with the subscription.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Erase All", action: eraseAllAction.call)
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(
                        EraseAllView.settingsEntryAccessibilityIdentifier
                    )
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(AppShellView.settingsScreenAccessibilityIdentifier)
        .sheet(item: $paywallPresentation) { presentation in
            PaywallView(
                coordinator: purchaseCoordinator,
                presentationToken: presentation.id,
                close: { paywallPresentation = nil }
            )
        }
    }
}

private struct PackUnavailableView: View {
    var body: some View {
        ScrollView {
            WorklightCard {
                Text("Content unavailable")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("The bundled sign content could not be loaded.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No partial or guessed content is shown.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
    }
}

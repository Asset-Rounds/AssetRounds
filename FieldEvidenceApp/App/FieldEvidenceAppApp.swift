import Foundation
import SwiftData
import SwiftUI
import UIKit

@main
@MainActor
struct FieldEvidenceAppApp: App {
    private static let invalidPackLaunchArgument = "--s1-invalid-pack"
    private static let lightModeLaunchArgument = "--s1-ui-test-light-mode"
    private static let darkModeLaunchArgument = "--s1-ui-test-dark-mode"
    private static let importedCaptureFixturesLaunchArgument =
        "--s3-2-ui-test-imported-fixtures"
    private static let lowStorageOnceLaunchArgument =
        "--s3-5-ui-test-low-storage-once"
    private static let cameraDeniedOnceLaunchArgument =
        "--s3-6-ui-test-camera-denied-once"
    private static let reportRenderFailureOnceLaunchArgument =
        "--s4-2-ui-test-render-failure-once"
    private static let emptyRestoreUITestLaunchArgument =
        "--s6-4-ui-test-empty-restore"
    private static let replacementRestoreUITestLaunchArgument =
        "--s6-5-ui-test-replacement-restore"
    private static let paywallUITestLaunchArgument =
        "--s7-2-ui-test-paywall"
    private static let feedbackMailAvailableUITestLaunchArgument =
        "--s8-4-ui-test-mail-available"
    private static let feedbackMailUnavailableUITestLaunchArgument =
        "--s8-4-ui-test-mail-unavailable"

    @StateObject private var startupRouter: StartupRouter
    @StateObject private var appAccessPresentation: AppAccessPresentationV1

    private let applicationSupportURL: URL
    private let packLoadResult: SignPackLoadResult
    private let preferredColorScheme: ColorScheme?
    private let exposesColorSchemeForUITest: Bool
    private let usesImportedCaptureFixturesForUITest: Bool
    private let injectsLowStorageFailureOnceForUITest: Bool
    private let cameraAdapter: CameraAdapter
    private let selectedRestorePackageForUITest: URL?
    private let paywallCatalogLinks: PaywallCatalogLinksV1?
    private let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    private let feedbackConfiguration: FeedbackConfigurationV1
    private let mailComposerAdapter: MailComposerAdapter

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let metricKitDiagnosticsAdapter = MetricKitDiagnosticsAdapter()
        metricKitDiagnosticsAdapter.start()
        self.metricKitDiagnosticsAdapter = metricKitDiagnosticsAdapter
        paywallCatalogLinks = arguments.contains(Self.paywallUITestLaunchArgument)
            ? .uiTestFixture
            : nil
        let usesAvailableFeedbackFixture = arguments.contains(
            Self.feedbackMailAvailableUITestLaunchArgument
        )
        let usesUnavailableFeedbackFixture = arguments.contains(
            Self.feedbackMailUnavailableUITestLaunchArgument
        )
        feedbackConfiguration = usesAvailableFeedbackFixture
            || usesUnavailableFeedbackFixture
            ? .uiTestFixture
            : .production
        if usesAvailableFeedbackFixture && !usesUnavailableFeedbackFixture {
            mailComposerAdapter = .uiTest
        } else if usesUnavailableFeedbackFixture {
            mailComposerAdapter = .unavailable
        } else {
            mailComposerAdapter = .live
        }
        let fileManager = FileManager.default
        var applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        var startupPreparationFailure: StartupMaintenanceReason?
        do {
            try fileManager.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
            var isDirectory: ObjCBool = false
            guard
                fileManager.fileExists(
                    atPath: applicationSupportURL.path,
                    isDirectory: &isDirectory
                ) && isDirectory.boolValue
            else {
                throw StartupMaintenanceReason.dataPointerInvalid
            }
        } catch {
            startupPreparationFailure = .dataPointerInvalid
        }
#if DEBUG
        if arguments.contains("--v23-ui-test-legacy-migration") {
            if let rawID = ProcessInfo.processInfo.environment["V23_MIGRATION_TEST_ID"],
               let id = UUID(uuidString: rawID), id.uuidString.lowercased() == rawID,
               !arguments.contains(Self.emptyRestoreUITestLaunchArgument),
               !arguments.contains(Self.replacementRestoreUITestLaunchArgument) {
                applicationSupportURL = applicationSupportURL.appendingPathComponent("V23MigrationUITests").appendingPathComponent(rawID)
                do { try StoreGenerationFactory(applicationSupportURL: applicationSupportURL).seedIsolatedLegacyStartupUITestIfEmpty() }
                catch { startupPreparationFailure = .dataPointerInvalid }
            } else {
                startupPreparationFailure = .dataPointerInvalid
            }
        }
#endif
        self.applicationSupportURL = applicationSupportURL
        let usesEmptyRestoreFixture = arguments.contains(
            Self.emptyRestoreUITestLaunchArgument
        ) && startupPreparationFailure == nil
        let usesReplacementRestoreFixture = arguments.contains(
            Self.replacementRestoreUITestLaunchArgument
        ) && startupPreparationFailure == nil
        if usesEmptyRestoreFixture {
            for name in [
                "FieldEvidenceData",
                "FieldEvidenceRestore",
                "FieldEvidenceOperations",
            ] {
                let url = applicationSupportURL.appendingPathComponent(
                    name,
                    isDirectory: true
                )
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        if usesEmptyRestoreFixture || usesReplacementRestoreFixture {
            let sourceDirectory = applicationSupportURL.appendingPathComponent(
                "S6_4UITestSource",
                isDirectory: true
            )
            let packages = (try? FileManager.default.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "fieldrecordbackup" } ?? []
            selectedRestorePackageForUITest = packages.count == 1
                ? packages[0]
                : nil
        } else {
            selectedRestorePackageForUITest = nil
        }
        let router = StartupRouter(
            applicationSupportURL: applicationSupportURL,
            injectsReportRenderFailureOnce: arguments.contains(
                Self.reportRenderFailureOnceLaunchArgument
            ),
            startupPreparationFailure: startupPreparationFailure
        )
        _startupRouter = StateObject(wrappedValue: router)
        _appAccessPresentation = StateObject(
            wrappedValue: AppAccessPresentationV1(
                startupRouter: router,
                applicationSupportURL: applicationSupportURL
            )
        )

        usesImportedCaptureFixturesForUITest = arguments.contains(
            Self.importedCaptureFixturesLaunchArgument
        )
        injectsLowStorageFailureOnceForUITest = arguments.contains(
            Self.lowStorageOnceLaunchArgument
        )
        if arguments.contains(Self.cameraDeniedOnceLaunchArgument) {
            var status = CameraAuthorizationStatus.notDetermined
            var authorizesOnNextStatusQuery = false
            cameraAdapter = CameraAdapter(
                authorizationStatus: {
                    if authorizesOnNextStatusQuery {
                        authorizesOnNextStatusQuery = false
                        status = .authorized
                    }
                    return status
                },
                requestAuthorization: {
                    status = .denied
                    authorizesOnNextStatusQuery = true
                    return status
                },
                isCameraAvailable: { true }
            )
        } else {
            cameraAdapter = .live
        }

        if arguments.contains(Self.invalidPackLaunchArgument) {
            let malformedPayload = Data(#"{"schemaVersion":1,"unexpected":"content"}"#.utf8)
            packLoadResult = SignPackLoader.load(data: malformedPayload)
        } else {
            packLoadResult = SignPackLoader.loadBundled()
        }

        if arguments.contains(Self.darkModeLaunchArgument) {
            preferredColorScheme = .dark
            exposesColorSchemeForUITest = true
        } else if arguments.contains(Self.lightModeLaunchArgument) {
            preferredColorScheme = .light
            exposesColorSchemeForUITest = true
        } else {
            preferredColorScheme = nil
            exposesColorSchemeForUITest = false
        }
    }

    var body: some Scene {
        WindowGroup {
            StartupRootView(
                router: startupRouter,
                access: appAccessPresentation,
                packLoadResult: packLoadResult,
                exposesColorSchemeForUITest: exposesColorSchemeForUITest,
                usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                injectsLowStorageFailureOnceForUITest:
                    injectsLowStorageFailureOnceForUITest,
                cameraAdapter: cameraAdapter,
                applicationSupportURL: applicationSupportURL,
                selectedRestorePackageForUITest: selectedRestorePackageForUITest,
                paywallCatalogLinks: paywallCatalogLinks,
                metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                feedbackConfiguration: feedbackConfiguration,
                mailComposerAdapter: mailComposerAdapter
            )
            .preferredColorScheme(preferredColorScheme)
        }
    }
}

private struct StartupRootView: View {
    @ObservedObject var router: StartupRouter
    @ObservedObject var access: AppAccessPresentationV1

    @Environment(\.scenePhase) private var scenePhase

    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool
    let usesImportedCaptureFixturesForUITest: Bool
    let injectsLowStorageFailureOnceForUITest: Bool
    let cameraAdapter: CameraAdapter
    let applicationSupportURL: URL
    let selectedRestorePackageForUITest: URL?
    let paywallCatalogLinks: PaywallCatalogLinksV1?
    let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    let feedbackConfiguration: FeedbackConfigurationV1
    let mailComposerAdapter: MailComposerAdapter

    var body: some View {
        Group {
            if access.permitsContentPresentation {
                switch router.route {
            case .checking:
                AssetRoundsScreenFoundation {
                    ProgressView("Checking local data")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityIdentifier("s2.startup.checking")

            case let .maintenance(reason):
                MaintenanceRestoreHost(
                    router: router,
                    access: access,
                    reason: reason,
                    restoreSession: router.maintenanceRestoreSession,
                    eraseSession: router.maintenanceEraseSession,
                    applicationSupportURL: applicationSupportURL
                )

            case .awaitingIndependentValidation:
                StartupMigrationValidationView {
                    Task { await access.retryStartup() }
                }

            case let .ready(coordinator, diagnosticsStore, reportRecoveryService):
                ReadyAppView(
                    coordinator: coordinator,
                    diagnosticsStore: diagnosticsStore,
                    reportRecoveryService: reportRecoveryService,
                    onUnsafePDFRecovery: {
                        router.failClosedPDFRecovery()
                    },
                    packLoadResult: packLoadResult,
                    exposesColorSchemeForUITest: exposesColorSchemeForUITest,
                    usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                    injectsLowStorageFailureOnceForUITest:
                        injectsLowStorageFailureOnceForUITest,
                    cameraAdapter: cameraAdapter,
                    applicationSupportURL: applicationSupportURL,
                    router: router,
                    access: access,
                    selectedRestorePackageForUITest:
                        selectedRestorePackageForUITest,
                    paywallCatalogLinks: paywallCatalogLinks,
                    metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                    feedbackConfiguration: feedbackConfiguration,
                    mailComposerAdapter: mailComposerAdapter
                )

            case .eraseCleanupPending:
                EraseCleanupPendingView()
                }
            } else {
                AppLockCoverViewV1(
                    isAuthenticating: access.isBusy,
                    onUnlock: unlockOrRetry
                )
                .overlay(alignment: .bottom) {
                    if access.failure != nil {
                        AssetRoundsStateLabel(kind: .error, "Unavailable")
                            .padding(DesignTokens.Spacing.space16)
                    }
                }
            }
        }
        .task {
            access.receive(.coldLaunch)
            access.receive(sceneEvent(for: scenePhase))
            await access.bootstrapIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            access.receive(sceneEvent(for: phase))
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.protectedDataDidBecomeAvailableNotification
            )
        ) { _ in
            access.receive(sceneEvent(for: scenePhase))
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.protectedDataWillBecomeUnavailableNotification
            )
        ) { _ in
            access.receive(.protectedDataUnavailable)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            access.receive(.termination)
        }
    }

    private func sceneEvent(for phase: ScenePhase) -> AppLockLifecycleEventV1 {
        switch phase {
        case .active: .sceneActive
        case .inactive: .sceneInactive
        case .background: .sceneBackground
        @unknown default: .sceneInactive
        }
    }

    private func unlockOrRetry() {
        Task {
            if access.failure == .startup {
                await access.retryStartup()
            } else {
                await access.unlock()
            }
        }
    }
}

private struct ReadyAppView: View {
    private struct RestorePresentation: Identifiable {
        let id = UUID()
        let mode: BackupRestoreMode
    }

    @ObservedObject var coordinator: StoreSessionCoordinator

    let diagnosticsStore: DiagnosticsStore
    @ObservedObject var reportRecoveryService: ReportRecoveryService
    let onUnsafePDFRecovery: @MainActor () -> Void
    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool
    let usesImportedCaptureFixturesForUITest: Bool
    let injectsLowStorageFailureOnceForUITest: Bool
    let cameraAdapter: CameraAdapter
    let applicationSupportURL: URL
    @ObservedObject var router: StartupRouter
    @ObservedObject var access: AppAccessPresentationV1
    let selectedRestorePackageForUITest: URL?
    let paywallCatalogLinks: PaywallCatalogLinksV1?
    let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    let feedbackConfiguration: FeedbackConfigurationV1
    let mailComposerAdapter: MailComposerAdapter

    @State private var restorePresentation: RestorePresentation?
    @State private var showsEraseAll = false

    var body: some View {
        Group {
            if reportRecoveryService.failedReportIDs.isEmpty {
            if let contentAccess = access.renderAccess,
               let sceneNavigationAccess = access.sceneNavigationAccess,
               let myDayAccess = access.myDayAccess {
            AppShellView(
                packLoadResult: packLoadResult,
                exposesColorSchemeForUITest: exposesColorSchemeForUITest,
                storeSession: coordinator,
                contentAccess: contentAccess,
                sceneNavigationAccess: sceneNavigationAccess,
                myDayAccess: myDayAccess,
                roundAccess: access.roundAccess,
                diagnosticsStore: diagnosticsStore,
                metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                feedbackConfiguration: feedbackConfiguration,
                mailComposerAdapter: mailComposerAdapter,
                usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                injectsLowStorageFailureOnceForUITest:
                    injectsLowStorageFailureOnceForUITest,
                cameraAdapter: cameraAdapter,
                entitlementProcessor: router.entitlementProcessor,
                paywallCatalogLinks: paywallCatalogLinks,
                restoreDataBackup: {
                    restorePresentation = RestorePresentation(mode: .emptyInstall)
                },
                replaceDataBackup: {
                    restorePresentation = RestorePresentation(mode: .replaceExisting)
                },
                eraseAll: {
                    showsEraseAll = true
                },
                appLockSettingsSection: AppLockSettingsSectionV1(
                    isEnabled: access.settingIsEnabled ?? false,
                    isBusy: access.isBusy,
                    isAvailable: access.settingIsEnabled != nil,
                    onSetEnabled: { enabled in
                        Task { await access.setEnabled(enabled) }
                    },
                    onLockNow: {
                        access.lockNow()
                    }
                )
            )
            }
            } else {
                ReportFailureView(
                    recovery: reportRecoveryService,
                    onUnsafeRecovery: onUnsafePDFRecovery
                )
            }
        }
        .id(coordinator.uiGenerationToken)
        .modelContext(coordinator.modelContext)
        .sheet(item: $restorePresentation) { presentation in
            if let previewAccess = access.backupPreviewAccess {
            BackupRestoreProgressView(
                applicationSupportURL: applicationSupportURL,
                currentModelContext: coordinator.modelContext,
                currentGenerationID: coordinator.generationID,
                currentGenerationRootURL: coordinator.generationRootURL,
                mode: presentation.mode,
                selectedPackageForUITest: selectedRestorePackageForUITest,
                previewAccess: previewAccess
            ) { package in
                try await access.performRestore(applicationSupportURL: applicationSupportURL,
                    package: package, sourceModelContext: coordinator.modelContext,
                    sourceGenerationID: coordinator.generationID,
                    sourceGenerationRootURL: coordinator.generationRootURL,
                    mode: presentation.mode, coordinator: coordinator)
            }
            }
        }
        .sheet(isPresented: $showsEraseAll) {
            EraseAllView(
                coordinator: coordinator,
                diagnosticsStore: diagnosticsStore,
                applicationSupportURL: applicationSupportURL,
                performErase: { [access, coordinator] confirmation in
                    try await access.performErase(applicationSupportURL: applicationSupportURL,
                        confirmation: confirmation, coordinator: coordinator,
                        diagnosticsStore: diagnosticsStore)
                }
            )
        }
    }
}

private struct MaintenanceRestoreHost: View {
    @ObservedObject var router: StartupRouter
    @ObservedObject var access: AppAccessPresentationV1

    let reason: StartupMaintenanceReason
    let restoreSession: StoreGenerationSession?
    let eraseSession: StoreGenerationSession?
    let applicationSupportURL: URL

    @State private var showsRestore = false
    @State private var showsErase = false
    @State private var eraseCoordinator: StoreSessionCoordinator?

    var body: some View {
        StartupMaintenanceView(
            reason: reason,
            retryChecks: {
                Task { await access.retryStartup() }
            },
            restoreDataBackup: restoreAction,
            eraseAll: eraseAction
        )
        .sheet(isPresented: $showsRestore) {
            if let restoreSession, let previewAccess = access.backupPreviewAccess {
                BackupRestoreProgressView(
                    applicationSupportURL: applicationSupportURL,
                    currentModelContext: restoreSession.modelContext,
                    currentGenerationID: restoreSession.generationID,
                    currentGenerationRootURL: restoreSession.generationRootURL,
                    previewAccess: previewAccess
                ) { package in
                    try await access.performRestore(applicationSupportURL: applicationSupportURL,
                        package: package, sourceModelContext: restoreSession.modelContext,
                        sourceGenerationID: restoreSession.generationID,
                        sourceGenerationRootURL: restoreSession.generationRootURL,
                        mode: .emptyInstall, coordinator: nil)
                }
            }
        }
        .sheet(isPresented: $showsErase) {
            if let eraseCoordinator {
                EraseAllView(
                    coordinator: eraseCoordinator,
                    diagnosticsStore: router.maintenanceDiagnosticsStore,
                    applicationSupportURL: applicationSupportURL,
                    performErase: { [access, eraseCoordinator] confirmation in
                        try await access.performErase(applicationSupportURL: applicationSupportURL,
                            confirmation: confirmation, coordinator: eraseCoordinator,
                            diagnosticsStore: router.maintenanceDiagnosticsStore)
                    }
                )
            }
        }
    }

    private var restoreAction: (() -> Void)? {
        guard restoreSession != nil else { return nil }
        return { showsRestore = true }
    }

    private var eraseAction: (() -> Void)? {
        guard let eraseSession else { return nil }
        return {
            eraseCoordinator = StoreSessionCoordinator(session: eraseSession)
            showsErase = true
        }
    }
}

private struct EraseCleanupPendingView: View {
    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                AssetRoundsEvidenceCard {
                    AssetRoundsStateLabel(kind: .warning, "Field Evidence")
                        .accessibilityLabel("Information: Field Evidence")
                        .accessibilityValue(Text(verbatim: String()))
                    Text("Erase incomplete")
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Secure cleanup is still pending.")
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView("Secure cleanup pending")
                        .tint(DesignTokens.SemanticColors.primaryAction)
                }
            }
        }
        .accessibilityIdentifier(
            SignsRootView.welcomeScreenAccessibilityIdentifier
        )
    }
}

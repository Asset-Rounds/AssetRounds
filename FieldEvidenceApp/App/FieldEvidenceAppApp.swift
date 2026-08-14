import Foundation
import SwiftData
import SwiftUI

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

    @StateObject private var startupRouter: StartupRouter

    private let applicationSupportURL: URL
    private let packLoadResult: SignPackLoadResult
    private let preferredColorScheme: ColorScheme?
    private let exposesColorSchemeForUITest: Bool
    private let usesImportedCaptureFixturesForUITest: Bool
    private let injectsLowStorageFailureOnceForUITest: Bool
    private let cameraAdapter: CameraAdapter
    private let selectedRestorePackageForUITest: URL?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.applicationSupportURL = applicationSupportURL
        let usesEmptyRestoreFixture = arguments.contains(
            Self.emptyRestoreUITestLaunchArgument
        )
        let usesReplacementRestoreFixture = arguments.contains(
            Self.replacementRestoreUITestLaunchArgument
        )
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
        _startupRouter = StateObject(
            wrappedValue: StartupRouter(
                applicationSupportURL: applicationSupportURL,
                injectsReportRenderFailureOnce: arguments.contains(
                    Self.reportRenderFailureOnceLaunchArgument
                )
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
                packLoadResult: packLoadResult,
                exposesColorSchemeForUITest: exposesColorSchemeForUITest,
                usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                injectsLowStorageFailureOnceForUITest:
                    injectsLowStorageFailureOnceForUITest,
                cameraAdapter: cameraAdapter,
                applicationSupportURL: applicationSupportURL,
                selectedRestorePackageForUITest: selectedRestorePackageForUITest
            )
            .preferredColorScheme(preferredColorScheme)
        }
    }
}

private struct StartupRootView: View {
    @ObservedObject var router: StartupRouter

    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool
    let usesImportedCaptureFixturesForUITest: Bool
    let injectsLowStorageFailureOnceForUITest: Bool
    let cameraAdapter: CameraAdapter
    let applicationSupportURL: URL
    let selectedRestorePackageForUITest: URL?

    var body: some View {
        Group {
            switch router.route {
            case .checking:
                ProgressView("Checking local data")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        DesignTokens.Colors.canvas
                            .ignoresSafeArea()
                    }
                    .accessibilityIdentifier("s2.startup.checking")

            case let .maintenance(reason):
                MaintenanceRestoreHost(
                    router: router,
                    reason: reason,
                    session: router.maintenanceRestoreSession,
                    applicationSupportURL: applicationSupportURL
                )

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
                    selectedRestorePackageForUITest:
                        selectedRestorePackageForUITest
                )
            }
        }
        .task {
            await router.startIfNeeded()
        }
    }
}

private struct ReadyAppView: View {
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
    let selectedRestorePackageForUITest: URL?

    @State private var showsRestore = false
    @State private var restoreMode: BackupRestoreMode = .emptyInstall

    var body: some View {
        Group {
            if reportRecoveryService.failedReportIDs.isEmpty {
            AppShellView(
                packLoadResult: packLoadResult,
                exposesColorSchemeForUITest: exposesColorSchemeForUITest,
                modelContext: coordinator.modelContext,
                diagnosticsStore: diagnosticsStore,
                generationRootURL: coordinator.generationRootURL,
                usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                injectsLowStorageFailureOnceForUITest:
                    injectsLowStorageFailureOnceForUITest,
                cameraAdapter: cameraAdapter,
                restoreDataBackup: {
                    restoreMode = .emptyInstall
                    showsRestore = true
                },
                replaceDataBackup: {
                    restoreMode = .replaceExisting
                    showsRestore = true
                }
            )
            } else {
                ReportFailureView(
                    recovery: reportRecoveryService,
                    onUnsafeRecovery: onUnsafePDFRecovery
                )
            }
        }
        .id(coordinator.uiGenerationToken)
        .modelContext(coordinator.modelContext)
        .sheet(isPresented: $showsRestore) {
            BackupRestoreProgressView(
                applicationSupportURL: applicationSupportURL,
                currentModelContext: coordinator.modelContext,
                currentGenerationID: coordinator.generationID,
                currentGenerationRootURL: coordinator.generationRootURL,
                mode: restoreMode,
                selectedPackageForUITest: selectedRestorePackageForUITest
            ) { session in
                await router.activateRestoredSession(
                    session,
                    coordinator: coordinator
                )
            }
        }
    }
}

private struct MaintenanceRestoreHost: View {
    @ObservedObject var router: StartupRouter

    let reason: StartupMaintenanceReason
    let session: StoreGenerationSession?
    let applicationSupportURL: URL

    @State private var showsRestore = false

    var body: some View {
        StartupMaintenanceView(
            reason: reason,
            retryChecks: {
                Task { await router.retryChecks() }
            },
            restoreDataBackup: restoreAction
        )
        .sheet(isPresented: $showsRestore) {
            if let session {
                BackupRestoreProgressView(
                    applicationSupportURL: applicationSupportURL,
                    currentModelContext: session.modelContext,
                    currentGenerationID: session.generationID,
                    currentGenerationRootURL: session.generationRootURL
                ) { restored in
                    await router.activateRestoredSession(
                        restored,
                        coordinator: nil
                    )
                }
            }
        }
    }

    private var restoreAction: (() -> Void)? {
        guard session != nil else { return nil }
        return { showsRestore = true }
    }
}

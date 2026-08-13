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

    @StateObject private var startupRouter: StartupRouter

    private let packLoadResult: SignPackLoadResult
    private let preferredColorScheme: ColorScheme?
    private let exposesColorSchemeForUITest: Bool
    private let usesImportedCaptureFixturesForUITest: Bool
    private let injectsLowStorageFailureOnceForUITest: Bool
    private let cameraAdapter: CameraAdapter

    init() {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        _startupRouter = StateObject(
            wrappedValue: StartupRouter(
                applicationSupportURL: applicationSupportURL
            )
        )

        let arguments = ProcessInfo.processInfo.arguments
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
                cameraAdapter: cameraAdapter
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
                StartupMaintenanceView(reason: reason) {
                    Task { await router.retryChecks() }
                }

            case let .ready(coordinator, diagnosticsStore):
                ReadyAppView(
                    coordinator: coordinator,
                    diagnosticsStore: diagnosticsStore,
                    packLoadResult: packLoadResult,
                    exposesColorSchemeForUITest: exposesColorSchemeForUITest,
                    usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                    injectsLowStorageFailureOnceForUITest:
                        injectsLowStorageFailureOnceForUITest,
                    cameraAdapter: cameraAdapter
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
    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool
    let usesImportedCaptureFixturesForUITest: Bool
    let injectsLowStorageFailureOnceForUITest: Bool
    let cameraAdapter: CameraAdapter

    var body: some View {
        AppShellView(
            packLoadResult: packLoadResult,
            exposesColorSchemeForUITest: exposesColorSchemeForUITest,
            modelContext: coordinator.modelContext,
            diagnosticsStore: diagnosticsStore,
            generationRootURL: coordinator.generationRootURL,
            usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
            injectsLowStorageFailureOnceForUITest:
                injectsLowStorageFailureOnceForUITest,
            cameraAdapter: cameraAdapter
        )
        .id(coordinator.uiGenerationToken)
        .modelContext(coordinator.modelContext)
    }
}

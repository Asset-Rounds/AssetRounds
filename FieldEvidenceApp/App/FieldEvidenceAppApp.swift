import Foundation
import SwiftData
import SwiftUI

@main
@MainActor
struct FieldEvidenceAppApp: App {
    private static let invalidPackLaunchArgument = "--s1-invalid-pack"
    private static let lightModeLaunchArgument = "--s1-ui-test-light-mode"
    private static let darkModeLaunchArgument = "--s1-ui-test-dark-mode"

    @StateObject private var startupRouter: StartupRouter

    private let packLoadResult: SignPackLoadResult
    private let preferredColorScheme: ColorScheme?
    private let exposesColorSchemeForUITest: Bool

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
                exposesColorSchemeForUITest: exposesColorSchemeForUITest
            )
            .preferredColorScheme(preferredColorScheme)
        }
    }
}

private struct StartupRootView: View {
    @ObservedObject var router: StartupRouter

    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool

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

            case let .ready(coordinator):
                ReadyAppView(
                    coordinator: coordinator,
                    packLoadResult: packLoadResult,
                    exposesColorSchemeForUITest: exposesColorSchemeForUITest
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

    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool

    var body: some View {
        AppShellView(
            packLoadResult: packLoadResult,
            exposesColorSchemeForUITest: exposesColorSchemeForUITest
        )
        .id(coordinator.uiGenerationToken)
        .modelContext(coordinator.modelContext)
    }
}

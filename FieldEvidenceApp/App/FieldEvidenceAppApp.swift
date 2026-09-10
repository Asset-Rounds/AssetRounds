import Foundation
import SwiftData
import SwiftUI

#if DEBUG && targetEnvironment(simulator)
/// Test-only launch configuration for the C06 screenshot harness. The parser
/// deliberately requires both gates so a stray pseudo option can never alter a
/// normal debug launch.
struct V30PseudoLocalizationLaunchConfigurationV1: Equatable, Sendable {
    enum Profile: String, CaseIterable, Sendable {
        case enXA = "en-XA"
        case arXB = "ar-XB"
        case enXL = "en-XL"

        var isRightToLeft: Bool { self == .arXB }
    }

    enum DynamicType: String, CaseIterable, Sendable {
        case large
        case accessibility5
    }

    enum Appearance: String, CaseIterable, Sendable {
        case light
        case dark
    }

    enum Contrast: String, CaseIterable, Sendable {
        case normal
        case increased
    }

    enum ParseError: Error, Equatable, Sendable {
        case partialActivation
        case unknownOption
        case duplicateOption
        case missingValue
        case invalidValue
    }

    static let harnessArgument = "--v30-p02-c06-harness"
    static let uiTestingArgument = "--v30-ui-testing"
    static let profileArgument = "--v30-p02-c06-profile"
    static let dynamicTypeArgument = "--v30-p02-c06-dynamic-type"
    static let appearanceArgument = "--v30-p02-c06-appearance"
    static let contrastArgument = "--v30-p02-c06-contrast"

    let profile: Profile
    let dynamicType: DynamicType
    let appearance: Appearance
    let contrast: Contrast

    static func parse(arguments: [String]) throws -> Self? {
        let hasHarness = arguments.contains(harnessArgument)
        let hasUITesting = arguments.contains(uiTestingArgument)
        let containsC06Option = arguments.contains { $0.hasPrefix("--v30-p02-c06-") }
        guard hasHarness || hasUITesting || containsC06Option else { return nil }
        guard hasHarness && hasUITesting else { throw ParseError.partialActivation }
        guard arguments.filter({ $0 == harnessArgument }).count == 1,
              arguments.filter({ $0 == uiTestingArgument }).count == 1 else {
            throw ParseError.duplicateOption
        }

        var values: [String: String] = [:]
        let valueArguments = Set([
            profileArgument,
            dynamicTypeArgument,
            appearanceArgument,
            contrastArgument,
        ])
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == harnessArgument || argument == uiTestingArgument {
                index += 1
                continue
            }
            guard !argument.hasPrefix("--v30-p02-c06-") else {
                guard valueArguments.contains(argument) else {
                    throw ParseError.unknownOption
                }
                guard index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw ParseError.missingValue
                }
                guard values[argument] == nil else { throw ParseError.duplicateOption }
                values[argument] = arguments[index + 1]
                index += 2
                continue
            }
            index += 1
        }

        guard let profileValue = values[profileArgument],
              let dynamicTypeValue = values[dynamicTypeArgument],
              let appearanceValue = values[appearanceArgument],
              let contrastValue = values[contrastArgument],
              let profile = Profile(rawValue: profileValue),
              let dynamicType = DynamicType(rawValue: dynamicTypeValue),
              let appearance = Appearance(rawValue: appearanceValue),
              let contrast = Contrast(rawValue: contrastValue) else {
            throw ParseError.invalidValue
        }
        return Self(
            profile: profile,
            dynamicType: dynamicType,
            appearance: appearance,
            contrast: contrast
        )
    }
}
#endif

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
#if DEBUG && targetEnvironment(simulator)
    private let pseudoLocaleHarness: V30PseudoLocalizationLaunchConfigurationV1?
#endif

    init() {
        let arguments = ProcessInfo.processInfo.arguments
#if DEBUG && targetEnvironment(simulator)
        let pseudoLocaleHarness = try? V30PseudoLocalizationLaunchConfigurationV1.parse(arguments: arguments)
        self.pseudoLocaleHarness = pseudoLocaleHarness
#endif
#if DEBUG && targetEnvironment(simulator)
        let metricKitDiagnosticsAdapter = MetricKitDiagnosticsAdapter()
        if pseudoLocaleHarness == nil {
            metricKitDiagnosticsAdapter.start()
        }
        self.metricKitDiagnosticsAdapter = metricKitDiagnosticsAdapter
#else
        let metricKitDiagnosticsAdapter = MetricKitDiagnosticsAdapter()
        metricKitDiagnosticsAdapter.start()
        self.metricKitDiagnosticsAdapter = metricKitDiagnosticsAdapter
#endif
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
#if DEBUG && targetEnvironment(simulator)
            if let pseudoLocaleHarness {
                PseudoLocalizationScreenshotHarnessView(configuration: pseudoLocaleHarness)
            } else {
            StartupRootView(
                router: startupRouter,
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
#else
            StartupRootView(
                router: startupRouter,
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
#endif
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
    let paywallCatalogLinks: PaywallCatalogLinksV1?
    let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    let feedbackConfiguration: FeedbackConfigurationV1
    let mailComposerAdapter: MailComposerAdapter

    var body: some View {
        Group {
            switch router.route {
            case .checking:
                ProgressView(BundledLocalizationCatalogV1.v30Text(.appStartupCheckingLocalData))
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
                    restoreSession: router.maintenanceRestoreSession,
                    eraseSession: router.maintenanceEraseSession,
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
                        selectedRestorePackageForUITest,
                    paywallCatalogLinks: paywallCatalogLinks,
                    metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                    feedbackConfiguration: feedbackConfiguration,
                    mailComposerAdapter: mailComposerAdapter
                )

            case .eraseCleanupPending:
                EraseCleanupPendingView()
            }
        }
        .task {
            await router.startIfNeeded()
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
            AppShellView(
                packLoadResult: packLoadResult,
                exposesColorSchemeForUITest: exposesColorSchemeForUITest,
                modelContext: coordinator.modelContext,
                diagnosticsStore: diagnosticsStore,
                metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                feedbackConfiguration: feedbackConfiguration,
                mailComposerAdapter: mailComposerAdapter,
                generationRootURL: coordinator.generationRootURL,
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
        .sheet(item: $restorePresentation) { presentation in
            BackupRestoreProgressView(
                applicationSupportURL: applicationSupportURL,
                currentModelContext: coordinator.modelContext,
                currentGenerationID: coordinator.generationID,
                currentGenerationRootURL: coordinator.generationRootURL,
                mode: presentation.mode,
                selectedPackageForUITest: selectedRestorePackageForUITest
            ) { session in
                await router.activateRestoredSession(
                    session,
                    coordinator: coordinator
                )
            }
        }
        .sheet(isPresented: $showsEraseAll) {
            EraseAllView(
                coordinator: coordinator,
                diagnosticsStore: diagnosticsStore,
                applicationSupportURL: applicationSupportURL,
                onBegin: { [router, coordinator] in
                    router.beginEraseBlocking(coordinator: coordinator)
                },
                onActivate: { [router, coordinator] session in
                    await router.beginErasedSessionActivation(
                        session,
                        coordinator: coordinator
                    )
                },
                onDeferred: { [router, coordinator] session in
                    router.deferErasedSessionCleanup(
                        session,
                        coordinator: coordinator
                    )
                },
                onFinished: { [router, coordinator] session in
                    await router.finishErasedSessionActivation(
                        session,
                        coordinator: coordinator
                    )
                },
                onFailure: { [router] in
                    router.failClosedErase()
                }
            )
        }
    }
}

private struct MaintenanceRestoreHost: View {
    @ObservedObject var router: StartupRouter

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
                Task { await router.retryChecks() }
            },
            restoreDataBackup: restoreAction,
            eraseAll: eraseAction
        )
        .sheet(isPresented: $showsRestore) {
            if let restoreSession {
                BackupRestoreProgressView(
                    applicationSupportURL: applicationSupportURL,
                    currentModelContext: restoreSession.modelContext,
                    currentGenerationID: restoreSession.generationID,
                    currentGenerationRootURL: restoreSession.generationRootURL
                ) { restored in
                    await router.activateRestoredSession(
                        restored,
                        coordinator: nil
                    )
                }
            }
        }
        .sheet(isPresented: $showsErase) {
            if let eraseCoordinator {
                EraseAllView(
                    coordinator: eraseCoordinator,
                    diagnosticsStore: router.maintenanceDiagnosticsStore,
                    applicationSupportURL: applicationSupportURL,
                    onBegin: { [router, eraseCoordinator] in
                        router.beginEraseBlocking(
                            coordinator: eraseCoordinator
                        )
                    },
                    onActivate: { [router, eraseCoordinator] session in
                        await router.beginErasedSessionActivation(
                            session,
                            coordinator: eraseCoordinator
                        )
                    },
                    onDeferred: { [router, eraseCoordinator] session in
                        router.deferErasedSessionCleanup(
                            session,
                            coordinator: eraseCoordinator
                        )
                    },
                    onFinished: { [router, eraseCoordinator] session in
                        await router.finishErasedSessionActivation(
                            session,
                            coordinator: eraseCoordinator
                        )
                    },
                    onFailure: { [router] in
                        router.failClosedErase()
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
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(kind: .information, text: BundledLocalizationCatalogV1.v30Text(.appErasePendingFieldEvidence))
                Text(BundledLocalizationCatalogV1.v30Text(.appErasePendingLocalDataErased))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(BundledLocalizationCatalogV1.v30Text(.appErasePendingCleanupInstruction))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(BundledLocalizationCatalogV1.v30Text(.appErasePendingFinishingErase))
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(
            SignsRootView.welcomeScreenAccessibilityIdentifier
        )
    }
}

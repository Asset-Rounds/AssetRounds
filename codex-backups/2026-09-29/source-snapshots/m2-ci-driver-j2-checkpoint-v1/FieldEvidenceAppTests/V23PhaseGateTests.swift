import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

#if DEBUG
/// One hosted view in its own key window, restored on unmount.
@MainActor
private final class V23PhaseGateMountedHostV1 {
    let window: UIWindow
    let host: UIViewController
    private let previousKeyWindow: UIWindow?
    private var isMounted = true

    init(content: AnyView, windowScene: UIWindowScene) {
        previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let controller = UIHostingController(rootView: content)
        let mountedWindow = UIWindow(windowScene: windowScene)
        mountedWindow.rootViewController = controller
        mountedWindow.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        window = mountedWindow
        host = controller
    }

    func unmount() {
        guard isMounted else { return }
        isMounted = false
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKeyAndVisible()
    }
}
#endif

/// Phase 1 reachability gate. The shipping gate hides every later-phase V23
/// entry point; `.allFeatures` (DEBUG only) keeps them reachable for tests.
final class V23PhaseGateTests: V23ProductionFourRootShellTestSupport {
    /// DEBUG witnesses on the gated reminder section and each of its rows.
    private static let reminderWitnessIdentifiers = [
        ReminderSettingsSectionV1.sectionAccessibilityIdentifier,
        ReminderSettingsSectionV1.enabledAccessibilityIdentifier,
        ReminderSettingsSectionV1.detailsAccessibilityIdentifier,
    ]
    private static let acceptedS10CameraPurpose =
        "Use the camera to add sign photos to reports stored on this iPhone."

    // MARK: - Gate values

    @MainActor
    func testShippingGateEnablesNoGatedFeature() {
        XCTAssertEqual(V23PhaseGateV1.shipping, V23PhaseGateV1(through: .phase1))
        XCTAssertTrue(V23PhaseGateV1.shipping.enabled.isEmpty)
        for feature in V23GatedFeatureV1.allCases {
            XCTAssertFalse(V23PhaseGateV1.shipping.allows(feature), feature.rawValue)
        }
        XCTAssertEqual(EnvironmentValues().v23PhaseGate, V23PhaseGateV1.shipping,
            "Views without an injected gate use the shipping gate")
    }

    @MainActor
    func testAllFeaturesGateEnablesEveryGatedFeature() throws {
        #if DEBUG
        XCTAssertEqual(V23PhaseGateV1.allFeatures.enabled, Set(V23GatedFeatureV1.allCases))
        for feature in V23GatedFeatureV1.allCases {
            XCTAssertTrue(V23PhaseGateV1.allFeatures.allows(feature), feature.rawValue)
        }
        XCTAssertNotEqual(V23PhaseGateV1.allFeatures, V23PhaseGateV1.shipping)
        #else
        throw XCTSkip("The all-features gate exists only in DEBUG builds")
        #endif
    }

    @MainActor
    func testEveryGatedFeatureBelongsToAPhaseLaterThanPhaseOne() {
        XCTAssertEqual(Set(V23GatedFeatureV1.allCases.map(\.rawValue)), [
            "myDay", "workSources", "reminders", "systemDiscovery", "envelopeDocumentOpen",
        ])
        XCTAssertEqual(V23PhaseV1.allCases, [.phase1, .phase2, .phase3])
        XCTAssertLessThan(V23PhaseV1.phase1, V23PhaseV1.phase2)
        XCTAssertLessThan(V23PhaseV1.phase2, V23PhaseV1.phase3)
        for feature in V23GatedFeatureV1.allCases {
            XCTAssertGreaterThan(feature.phase, V23PhaseV1.phase1, feature.rawValue)
            XCTAssertTrue(V23PhaseGateV1(through: feature.phase).allows(feature), feature.rawValue)
        }
        XCTAssertEqual(V23PhaseGateV1(through: .phase3).enabled, Set(V23GatedFeatureV1.allCases))
    }

    // MARK: - Built product

    @MainActor
    func testBuiltInfoPlistClaimsNoEnvelopeDocumentTypeWhileEnvelopeOpenIsGated() throws {
        XCTAssertFalse(V23PhaseGateV1.shipping.allows(.envelopeDocumentOpen))
        // The exported type stays declared, which also proves this is the
        // app host's built plist rather than an empty test bundle plist.
        let exported = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        XCTAssertTrue(exported.contains { declaration in
            declaration["UTTypeIdentifier"] as? String
                == EncryptedPortableEnvelopeProtocolReleaseV1.uniformTypeIdentifier
        })
        let documentTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes")
            as? [[String: Any]] ?? []
        let envelopeClaims = documentTypes.filter { documentType in
            let extensions = documentType["CFBundleTypeExtensions"] as? [String] ?? []
            let contentTypes = documentType["LSItemContentTypes"] as? [String] ?? []
            let mediaTypes = documentType["CFBundleTypeMIMETypes"] as? [String] ?? []
            return extensions.contains(EncryptedPortableEnvelopeProtocolReleaseV1.fileExtension)
                || contentTypes.contains(EncryptedPortableEnvelopeProtocolReleaseV1.uniformTypeIdentifier)
                || mediaTypes.contains(EncryptedPortableEnvelopeProtocolReleaseV1.mediaType)
        }
        XCTAssertTrue(envelopeClaims.isEmpty, "Open in AssetRounds must not be offered for .arenvelope")
    }

    @MainActor
    func testBuiltCameraPurposeUsesTheAcceptedS10Wording() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
            Self.acceptedS10CameraPurpose)
    }

    @MainActor
    func testSystemDiscoveryIntentsAreUndiscoverableWhileGated() {
        XCTAssertFalse(V23PhaseGateV1.shipping.allows(.systemDiscovery))
        XCTAssertFalse(OpenTodayPrivateSystemDiscoveryIntentV1.isDiscoverable)
        XCTAssertFalse(OpenAssetsPrivateSystemDiscoveryIntentV1.isDiscoverable)
        XCTAssertFalse(OpenReportsPrivateSystemDiscoveryIntentV1.isDiscoverable)
    }

    // MARK: - Hosted shell

    /// Production default: no gate is injected, exactly as the app composes it.
    @MainActor
    func testShippingShellShowsPhaseOneTodayAndCompletedWorkWithoutLaterPhaseSurfaces() async throws {
        #if DEBUG
        let fixture = try await makeFixture("phase-gate-shipping")
        defer { fixture.cleanUp() }
        try selectPhaseGateRoot(.today, in: fixture)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        var shellScene: AppShellSceneStateV1?
        let shell = try mountPhaseGateShell(fixture, gate: nil) { scene in
            if shellScene == nil { shellScene = scene }
        }
        defer { shell.unmount() }

        let phaseOneMounted = await waitForMountedScreen(
            ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier, from: shell.host)
        XCTAssertTrue(phaseOneMounted, "Today shows the Phase 1 empty state")
        // The My Day witness sits on the gated branch view that owns the
        // available-work list, the Plan toolbar entry and the editor sheet;
        // the all-features test below observes the same witness.
        XCTAssertFalse(nativeScreenObservation(
            ProductionMyDayRootViewV1.myDayObservationIdentifier, from: shell.host).found,
            "The My Day list, Plan entry and editor are not composed")

        let scene = try XCTUnwrap(shellScene)
        try scene.select(.work)
        let workMounted = await waitForMountedScreen(
            ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: shell.host)
        XCTAssertTrue(workMounted, "The Work root loads")
        let completedMounted = await waitForMountedScreen(
            SignoffEnrollmentView.workRootAccessibilityIdentifier, from: shell.host)
        XCTAssertTrue(completedMounted, "Completed work stays reachable on the Work root")
        // The witness is attached to the currentWork rows themselves, which
        // precede Completed work in the list; any rendered row would carry it.
        XCTAssertFalse(nativeScreenObservation(
            ProductionWorkRootViewV1.currentWorkObservationIdentifier, from: shell.host).found,
            "The current-work list is not composed")
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        shell.unmount()

        // Settings is reached only through a toolbar link, so it is hosted
        // directly with the same reminder section the app composes. SwiftUI
        // rows inside its ScrollView have no UIKit or accessibility backing in
        // the unit-test host, so presence and absence are observed through the
        // DEBUG witnesses attached to the screen and to the rows themselves.
        let settings = try mountPhaseGateSettings(fixture, gate: nil)
        defer { settings.unmount() }
        let settingsMounted = await waitForMountedScreen(
            AppShellView.settingsScreenAccessibilityIdentifier, from: settings.host)
        XCTAssertTrue(settingsMounted, "The Settings screen loads")
        let restoreMounted = await waitForMountedScreen(
            BackupRestoreProgressView.settingsEntryAccessibilityIdentifier, from: settings.host)
        XCTAssertTrue(restoreMounted, "Settings renders its S10 rows")
        // The reminder section precedes the restore row in the same card, so
        // a rendered restore row means a composed reminder section would be
        // rendered too; the all-features test observes these same witnesses.
        for identifier in Self.reminderWitnessIdentifiers {
            XCTAssertFalse(nativeScreenObservation(identifier, from: settings.host).found,
                "Settings has no Reminders row: \(identifier)")
        }
        #else
        throw XCTSkip("Native hosted gate observation is DEBUG-only")
        #endif
    }

    /// Control for the negative checks above: the same witnesses appear when
    /// tests inject `.allFeatures`.
    @MainActor
    func testAllFeaturesShellStillReachesEveryGatedSurfaceForTests() async throws {
        #if DEBUG
        let fixture = try await makeFixture("phase-gate-all-features")
        defer { fixture.cleanUp() }
        try selectPhaseGateRoot(.today, in: fixture)
        var shellScene: AppShellSceneStateV1?
        let shell = try mountPhaseGateShell(fixture, gate: .allFeatures) { scene in
            if shellScene == nil { shellScene = scene }
        }
        defer { shell.unmount() }

        let myDayMounted = await waitForMountedScreen(
            ProductionMyDayRootViewV1.myDayObservationIdentifier, from: shell.host)
        XCTAssertTrue(myDayMounted, "Injected tests still reach My Day")
        XCTAssertFalse(nativeScreenObservation(
            ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier, from: shell.host).found)

        let scene = try XCTUnwrap(shellScene)
        try scene.select(.work)
        let currentWorkMounted = await waitForMountedScreen(
            ProductionWorkRootViewV1.currentWorkObservationIdentifier, from: shell.host)
        XCTAssertTrue(currentWorkMounted, "Injected tests still reach the current-work list")
        let completedMounted = await waitForMountedScreen(
            SignoffEnrollmentView.workRootAccessibilityIdentifier, from: shell.host)
        XCTAssertTrue(completedMounted)
        shell.unmount()

        let settings = try mountPhaseGateSettings(fixture, gate: .allFeatures)
        defer { settings.unmount() }
        let restoreMounted = await waitForMountedScreen(
            BackupRestoreProgressView.settingsEntryAccessibilityIdentifier, from: settings.host)
        XCTAssertTrue(restoreMounted, "Settings renders its S10 rows")
        for identifier in Self.reminderWitnessIdentifiers {
            let reminderMounted = await waitForMountedScreen(identifier, from: settings.host)
            XCTAssertTrue(reminderMounted, "Injected tests still reach the Reminders row: \(identifier)")
        }
        #else
        throw XCTSkip("Native hosted gate observation is DEBUG-only")
        #endif
    }
}

#if DEBUG
private extension V23PhaseGateTests {
    /// Persists the selected root before the shell restores.
    @MainActor
    func selectPhaseGateRoot(_ root: AppRootV1,
                             in fixture: V23ProductionMyDayPresentationHarness) throws {
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        try scene.restore()
        try scene.select(root)
    }

    /// Hosts the real production shell. A nil gate injects nothing, so the
    /// shell reads the environment default exactly as the app does.
    @MainActor
    func mountPhaseGateShell(
        _ fixture: V23ProductionMyDayPresentationHarness,
        gate: V23PhaseGateV1?,
        onScene: @escaping @MainActor (AppShellSceneStateV1) -> Void
    ) throws -> V23PhaseGateMountedHostV1 {
        var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: fixture.coordinator,
            contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
            sceneNavigationAccess: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        shell.onProductionSceneBoundForTesting = onScene
        let context = fixture.coordinator.modelContext
        let content: AnyView
        if let gate {
            content = AnyView(shell.environment(\.v23PhaseGate, gate).modelContext(context))
        } else {
            content = AnyView(shell.modelContext(context))
        }
        return V23PhaseGateMountedHostV1(content: content, windowScene: try phaseGateWindowScene())
    }

    /// Hosts the production Settings screen with the reminder section the
    /// app composes from the published reminder settings access.
    @MainActor
    func mountPhaseGateSettings(
        _ fixture: V23ProductionMyDayPresentationHarness,
        gate: V23PhaseGateV1?
    ) throws -> V23PhaseGateMountedHostV1 {
        let access = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        let processor = fixture.router.entitlementProcessor
        let purchase = StoreKitPurchaseCoordinator(processor: processor,
            diagnosticsStore: fixture.diagnostics, catalogLinks: nil)
        let lifecycle = StoreKitLifecycleCoordinator(processor: processor)
        let settings = SettingsPlaceholderView(
            modelContext: fixture.coordinator.modelContext,
            generationRootURL: fixture.coordinator.generationRootURL,
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production,
            mailComposerAdapter: .unavailable,
            purchaseCoordinator: purchase,
            lifecycleCoordinator: lifecycle)
        let section = ReminderSettingsSectionV1(access: access)
        let stack = NavigationStack {
            settings.reminderSettingsSectionForTesting(section)
        }
        let content: AnyView
        if let gate {
            content = AnyView(stack.environment(\.v23PhaseGate, gate))
        } else {
            content = AnyView(stack)
        }
        return V23PhaseGateMountedHostV1(content: content, windowScene: try phaseGateWindowScene())
    }

    @MainActor
    func phaseGateWindowScene() throws -> UIWindowScene {
        try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
    }
}
#endif

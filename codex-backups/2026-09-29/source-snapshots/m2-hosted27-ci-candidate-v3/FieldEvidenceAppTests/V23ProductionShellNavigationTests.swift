import Combine
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionShellNavigationTests: XCTestCase {
    @MainActor
    func testActualShellStatePersistsFourRootsAndReconcilesPathsWithoutCanonicalEffects() async throws {
        let harness = try await makeHarness()
        defer { harness.cleanUp() }
        let access = try XCTUnwrap(harness.presentation.sceneNavigationAccess)
        let render = try XCTUnwrap(harness.presentation.renderAccess)
        let workflow = try render.withRead {
            let profiles = try WorkspacePackageLifecycleCompatibilityV1
                .legacyV3Registry(package: .illuminatedSignV1)
            let root = try ProductionCompositionRoot(storeSession: harness.store,
                diagnosticsStore: harness.diagnostics, profileRegistry: profiles)
            return try root.makeSignWorkflow(signPack: .illuminatedSignV1, accessState: { .entitled })
        }
        let asset = try await workflow.firstSign.create(.init(siteLabel: "Shell site",
            signLabel: "Shell asset", timeZoneID: "America/New_York", isTimeZoneConfirmed: true))
        let assetTarget = try NavigationTargetV1(workspaceID: harness.store.workspaceID,
            destination: .assets, stableEntityID: asset.assetID)
        let siteTarget = try NavigationTargetV1(workspaceID: harness.store.workspaceID,
            destination: .work, stableLocationID: asset.siteID)
        let registry = try RouteRegistryV1()
        let state = AppShellSceneStateV1(workspaceID: harness.store.workspaceID,
            access: access, registry: registry)
        let before = try harness.store.workspaceWriter.currentRevision()
        try state.restore()
        XCTAssertEqual(state.snapshot?.selectedRoot, .today)
        XCTAssertEqual(state.snapshot?.paths.map(\.root), AppRootV1.frozenOrder)
        XCTAssertTrue(try XCTUnwrap(state.snapshot).paths.allSatisfy { $0.targets.isEmpty })
        try state.setPath([assetTarget], for: .assets)
        try state.setPath([siteTarget], for: .work)

        for root in AppRootV1.frozenOrder {
            try state.select(root)
            XCTAssertEqual(state.snapshot?.selectedRoot, root)
            XCTAssertEqual(state.snapshot?.paths.first { $0.root == .assets }?.targets, [assetTarget])
            XCTAssertEqual(state.snapshot?.paths.first { $0.root == .work }?.targets, [siteTarget])
            let reopened = AppShellSceneStateV1(workspaceID: harness.store.workspaceID,
                access: access, registry: registry)
            try reopened.restore()
            XCTAssertEqual(reopened.snapshot?.selectedRoot, root)
            XCTAssertEqual(reopened.snapshot?.paths, state.snapshot?.paths)
        }

        let missing = try NavigationTargetV1(workspaceID: harness.store.workspaceID,
            destination: .assets, stableEntityID: UUID())
        try state.setPath([assetTarget, missing], for: .assets)
        XCTAssertEqual(state.snapshot?.paths.first { $0.root == .assets }?.targets, [assetTarget])
        XCTAssertEqual(state.lastRestoration?.receipt.result.reason, .deletedOrTombstoned)
        XCTAssertEqual(state.lastRestoration?.receipt.result.target, assetTarget)

        let settings = try NavigationTargetV1(workspaceID: harness.store.workspaceID, destination: .settings)
        try state.open(settings)
        XCTAssertEqual(state.snapshot?.selectedRoot, settings.root)
        XCTAssertEqual(state.snapshot?.paths.first { $0.root == settings.root }?.targets, [settings])
        XCTAssertEqual(state.snapshot?.paths.first { $0.root == .work }?.targets, [siteTarget])
        try state.setPath([], for: settings.root)
        XCTAssertTrue(try XCTUnwrap(state.snapshot?.paths.first { $0.root == settings.root }).targets.isEmpty)
        XCTAssertEqual(state.snapshot?.paths.first { $0.root == .work }?.targets, [siteTarget])
        XCTAssertEqual(try harness.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try harness.store.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try harness.store.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertFalse(harness.store.modelContext.hasChanges)
        XCTAssertEqual(state.lastRestoration?.receipt.canonicalMutationCount, 0)
        XCTAssertEqual(state.lastRestoration?.receipt.startsAutomaticWork, false)
    }

    @MainActor
    func testInvalidAndRevokedShellOperationsClearPresentationWithoutReplacingSavedState() async throws {
        let harness = try await makeHarness()
        defer { harness.cleanUp() }
        let access = try XCTUnwrap(harness.presentation.sceneNavigationAccess)
        let state = AppShellSceneStateV1(workspaceID: harness.store.workspaceID,
            access: access, registry: try RouteRegistryV1())
        try state.restore()
        try state.select(.reports)
        let saved = try access.load()
        let before = try harness.store.workspaceWriter.currentRevision()
        let foreign = try NavigationTargetV1(workspaceID: WorkspaceID(), destination: .assets)
        XCTAssertThrowsError(try state.setPath([foreign], for: .assets))
        XCTAssertNil(state.snapshot)
        XCTAssertNil(state.lastRestoration)
        XCTAssertEqual(try access.load(), saved)
        try state.restore()
        XCTAssertEqual(state.snapshot?.selectedRoot, .reports)

        let overlong = try (0...SceneNavigationSnapshotV1.maximumPathDepth).map { _ in
            try NavigationTargetV1(workspaceID: harness.store.workspaceID,
                destination: .assets, stableEntityID: UUID())
        }
        let beforeInvalidDepth = try access.load()
        XCTAssertThrowsError(try state.setPath(overlong, for: .assets))
        XCTAssertNil(state.snapshot)
        XCTAssertEqual(try access.load(), beforeInvalidDepth)
        try state.restore()
        harness.presentation.receive(.sceneInactive)
        XCTAssertThrowsError(try state.select(.today)) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertNil(state.snapshot)
        XCTAssertNil(state.lastRestoration)
        XCTAssertThrowsError(try state.restore()) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertEqual(try harness.store.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(harness.store.modelContext.hasChanges)
    }

    @MainActor
    private func makeHarness() async throws -> ShellNavigationHarness {
        let suiteName = "V23.ShellNavigation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ShellNavigation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        do {
            let router = StartupRouter(applicationSupportURL: support)
            let session = try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: support, startupRouter: router, defaults: defaults,
                authenticationClient: ShellNavigationAuthentication(),
                notificationSystem: ShellNavigationNotificationSystem())
            let presentation = AppAccessPresentationV1(startupRouter: router, sessionFactory: { session })
            let published = expectation(description: "Actual production shell capability")
            let subscription = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
                .sink { _ in published.fulfill() }
            defer { subscription.cancel() }
            await presentation.bootstrapIfNeeded()
            await fulfillment(of: [published], timeout: 30)
            guard case .ready(let store, let diagnostics, _) = router.route else {
                throw AppAccessContractFailureV1.accessDenied
            }
            return ShellNavigationHarness(presentation: presentation, store: store,
                diagnostics: diagnostics, defaults: defaults, suiteName: suiteName, support: support)
        } catch {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: support)
            throw error
        }
    }
}

@MainActor private struct ShellNavigationHarness {
    let presentation: AppAccessPresentationV1
    let store: StoreSessionCoordinator
    let diagnostics: DiagnosticsStore
    let defaults: UserDefaults
    let suiteName: String
    let support: URL

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: support)
    }
}

private actor ShellNavigationAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}

@MainActor private final class ShellNavigationNotificationSystem: NotificationSystemPortV1 {
    private var requests: [NotificationSystemRequestV1] = []
    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }
    func observations() async throws -> [NotificationSystemObservationV1] {
        requests.map { .init(requestID: $0.notification.requestID, request: $0, delivered: false) }
    }
    func add(_ request: NotificationSystemRequestV1) async throws { requests.append(request) }
    func remove(_ requestIDs: [String]) async throws {
        requests.removeAll { requestIDs.contains($0.notification.requestID) }
    }
}

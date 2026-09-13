import Combine
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionSceneNavigationTests: XCTestCase {
    @MainActor
    func testCanonicalPacketLookupUsesPacketIDAndSafelyRejectsAmbiguousVersionHistory() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ScenePacket-\(UUID().uuidString)")
        let generation = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let store = try StoreSessionCoordinator(validatingSession: generation)
        defer { try? FileManager.default.removeItem(at: support) }
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 178_000)
        let source = try fixture.manifest.rebound(to: store.workspaceID)
        let actor = source.creator
        _ = try store.workspaceWriter.execute(.applyPartyAccountability(.appendActorSnapshot(actor)),
            mutationID: MutationIDV1(rawValue: UUID()))
        func packet(version: UInt64) throws -> WorkPacketManifestV1 {
            try .init(manifestID: UUID(), packetID: source.packetID, packetVersion: version,
                workspaceID: store.workspaceID,
                items: [.init(itemID: "source-item", kind: .inspection,
                    expectedRevision: 1, itemSHA256: String(repeating: "a", count: 64))],
                packageReleases: [],
                creationBasis: .explicitLocalSelection, creator: actor, createdAt: source.createdAt,
                mutationID: MutationIDV1(rawValue: UUID()))
        }
        func append(_ value: WorkPacketManifestV1) throws {
            let mutation = try WorkPacketMutationV1(workspaceID: store.workspaceID,
                expectedRevision: 0, mutationID: value.mutationID, postImage: .appendManifest(value))
            _ = try store.workspaceWriter.execute(.applyWorkPacket(mutation), mutationID: value.mutationID)
        }
        let first = try packet(version: 1)
        try append(first)
        let route = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .work, stableEntityID: first.packetID, expectedRevision: first.revision)
        let wrongKey = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .work, stableEntityID: first.manifestID)
        let registry = try RouteRegistryV1()
        let beforeFirstRead = try store.workspaceWriter.currentRevision()
        let context = try ProductionSceneNavigationSourceV1.context(
            for: [route, wrongKey], in: store, registry: registry)
        XCTAssertEqual(try registry.resolve(route, context: context).target, route)
        XCTAssertEqual(try registry.resolve(route, context: context).disposition, .resolved)
        XCTAssertEqual(try registry.resolve(wrongKey, context: context).reason, .deletedOrTombstoned)
        XCTAssertEqual(try store.workspaceWriter.currentRevision(), beforeFirstRead)

        let second = try packet(version: 2)
        try append(second)
        let beforeHistoryRead = try store.workspaceWriter.currentRevision()
        // Both immutable versions are valid. The bare packet ID cannot choose
        // one version; it must fall back without treating the store as corrupt.
        let ambiguous = try ProductionSceneNavigationSourceV1.context(for: [route], in: store, registry: registry)
        let result = try registry.resolve(route, context: ambiguous)
        XCTAssertEqual(result.reason, .invalidTarget)
        XCTAssertEqual(result.disposition, .safeFallback)
        XCTAssertEqual(result.canonicalMutationCount, 0)
        XCTAssertEqual(try store.workspaceWriter.currentRevision(), beforeHistoryRead)
        XCTAssertEqual(try store.modelContext.fetchCount(FetchDescriptor<WorkPacketManifestRow>()), 2)
        XCTAssertFalse(store.modelContext.hasChanges)
    }

    @MainActor
    func testProductionRestorationUsesCanonicalOwnersAndRejectsForgedOrForeignAuthority() async throws {
        let suiteName = "V23.ProductionScene.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionScene-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: support)
        }
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: SceneNavigationAuthentication(),
            notificationSystem: SceneNavigationNotificationSystem())
        let presentation = AppAccessPresentationV1(startupRouter: router, sessionFactory: { session })
        let published = expectation(description: "Real startup publishes scene capability")
        let subscription = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        let scene = try XCTUnwrap(presentation.sceneNavigationAccess)
        let render = try XCTUnwrap(presentation.renderAccess)
        guard case .ready(let store, let diagnostics, _) = router.route else {
            return XCTFail("Expected the actual recovered production store")
        }
        let workflow = try render.withRead {
            let profiles = try WorkspacePackageLifecycleCompatibilityV1
                .legacyV3Registry(package: .illuminatedSignV1)
            let root = try ProductionCompositionRoot(storeSession: store,
                diagnosticsStore: diagnostics, profileRegistry: profiles)
            return try root.makeSignWorkflow(signPack: .illuminatedSignV1, accessState: { .entitled })
        }
        let first = try await workflow.firstSign.create(.init(
            siteLabel: "Navigation site", signLabel: "First asset",
            timeZoneID: "America/New_York", isTimeZoneConfirmed: true))
        _ = try await workflow.firstSign.create(.init(existingSiteID: first.siteID,
            siteLabel: "Navigation site", signLabel: "Second asset",
            timeZoneID: "America/New_York", isTimeZoneConfirmed: true))
        let before = try store.workspaceWriter.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: first.assetID)
        let assetRevision = try XCTUnwrap(before.entityRevisions.first { $0.identity == identity }).revision
        XCTAssertGreaterThan(before.revision, assetRevision)
        let live = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .assets, stableEntityID: first.assetID, expectedRevision: assetRevision)
        let missing = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .assets, stableEntityID: UUID())
        let wrongKind = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .reports, stableEntityID: first.assetID)
        let stale = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .assets, stableEntityID: first.assetID, expectedRevision: assetRevision + 1)
        let foreign = try NavigationTargetV1(workspaceID: WorkspaceID(),
            destination: .assets, stableEntityID: first.assetID)
        let unsupportedRoot = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .today, requestedMode: .resume, expectedRevision: before.revision)
        let location = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .work, stableLocationID: first.siteID)
        let unsupportedLocationAnchor = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .work, stableLocationID: first.siteID, requestedMode: .resume,
            draftResumeAnchor: DraftResumeAnchorV1(sectionID: "inspection", fieldID: "condition"))
        let routes = RouteCoordinatorV1(registry: try RouteRegistryV1())
        func request(_ target: NavigationTargetV1) -> RouteRestorationRequestV1 {
            .init(context: .init(currentWorkspaceID: store.workspaceID,
                    currentRevision: before.revision, sourceAvailability: [target: .available]),
                startupMaintenanceTarget: nil, incompleteMutationRecoveryTarget: nil,
                explicitIngressTarget: target, sceneSnapshot: nil, discardedSnapshotReason: nil,
                evidenceKind: .hostile, receiptID: UUID())
        }
        let liveResult = try scene.restore(request(live), using: routes)
        XCTAssertEqual(liveResult.receipt.result.target, live)
        XCTAssertEqual(liveResult.receipt.result.disposition, .resolved)
        XCTAssertEqual(try scene.restore(request(location), using: routes).receipt.result.target, location)
        for (target, reason) in [(missing, RouteFallbackReasonV1.deletedOrTombstoned),
                                 (wrongKind, .invalidTarget),
                                 (stale, .staleRevision), (foreign, .wrongWorkspace),
                                 (unsupportedRoot, .invalidTarget),
                                 (unsupportedLocationAnchor, .invalidTarget)] {
            let result = try scene.restore(request(target), using: routes)
            XCTAssertEqual(result.receipt.result.reason, reason)
            XCTAssertEqual(result.receipt.canonicalMutationCount, 0)
            XCTAssertFalse(result.receipt.startsAutomaticWork)
        }
        let saved = try SceneNavigationSnapshotV1(workspaceID: store.workspaceID,
            selectedRoot: .assets, paths: AppRootV1.frozenOrder.map {
                .init(root: $0, targets: $0 == .assets ? [live, missing] : [])
            }, snapshotID: UUID())
        try scene.save(saved)
        let restored = try scene.restore(loaded: scene.load(), using: routes, evidenceKind: .recovery)
        XCTAssertEqual(restored.paths.first { $0.root == .assets }?.targets, [live])
        XCTAssertEqual(restored.receipt.result.reason, .deletedOrTombstoned)
        XCTAssertEqual(restored.receipt.result.target, live)

        // A valid saved scene may contain all four paths at their full depth.
        // Missing rows should trim those paths, not exceed a query's ID limit.
        let fullPaths = try AppRootV1.frozenOrder.map { root in
            SceneRootPathV1(root: root, targets: try (0..<SceneNavigationSnapshotV1.maximumPathDepth).map { index in
                if root == .assets && index == 0 { return live }
                return try NavigationTargetV1(workspaceID: store.workspaceID,
                    destination: RouteRegistryV1.rootDestination(for: root), stableEntityID: UUID())
            })
        }
        let fullScene = try SceneNavigationSnapshotV1(workspaceID: store.workspaceID,
            selectedRoot: .assets, paths: fullPaths, snapshotID: UUID())
        let fullResult = try scene.restore(loaded: .restored(fullScene),
            using: routes, evidenceKind: .recovery)
        XCTAssertEqual(fullResult.paths.first { $0.root == .assets }?.targets, [live])
        XCTAssertTrue(fullResult.paths.filter { $0.root != .assets }.allSatisfy { $0.targets.isEmpty })
        XCTAssertEqual(fullResult.receipt.result.reason, .deletedOrTombstoned)
        XCTAssertEqual(fullResult.receipt.canonicalMutationCount, 0)

        let foreignGate = AppAccessGateV1(setting: .absentDisabled,
            authentication: SceneNavigationAuthentication(),
            clock: SystemApplicationClock(), identifiers: SystemApplicationIDSource())
        let foreignToken = try await foreignGate.beginContentRead(for: .sceneRestoration)
        XCTAssertThrowsError(try router.restoreSceneNavigationState(request(live), using: routes,
            workspaceID: store.workspaceID, generationID: store.generationID,
            authorization: foreignToken)) { error in
                XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
            }
        XCTAssertEqual(try store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try store.modelContext.fetchCount(FetchDescriptor<Asset>()), 2)
        XCTAssertEqual(try store.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertFalse(store.modelContext.hasChanges)
        presentation.receive(.sceneInactive)
        XCTAssertThrowsError(try scene.restore(loaded: .restored(saved),
            using: routes, evidenceKind: .interruption)) { error in
                XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
            }
    }

    func testLiveSourceContextIsExhaustiveAndUsesTheTargetOwnersRevision() throws {
        let workspace = WorkspaceID()
        let target = try NavigationTargetV1(
            workspaceID: workspace, destination: .assets,
            stableEntityID: UUID(), expectedRevision: 7
        )
        let registry = try RouteRegistryV1()
        let incomplete = RouteResolutionContextV1(
            currentWorkspaceID: workspace, currentRevision: 31,
            sourceAvailability: [:]
        )
        XCTAssertEqual(try registry.resolve(target, context: incomplete).reason, .invalidTarget)

        let validated = RouteResolutionContextV1(
            currentWorkspaceID: workspace, currentRevision: 31,
            sourceAvailability: [target: .available]
        )
        let result = try registry.resolve(target, context: validated)
        XCTAssertEqual(result.disposition, .resolved)
        XCTAssertEqual(result.target, target)
        XCTAssertEqual(result.canonicalMutationCount, 0)
        XCTAssertFalse(result.startsAutomaticWork)

        let legacy = RouteResolutionContextV1(currentWorkspaceID: workspace, currentRevision: 31)
        XCTAssertEqual(try registry.resolve(target, context: legacy).reason, .staleRevision)
    }

    func testLiveSourceAvailabilityDistinguishesRolesSharingTheSameUUID() throws {
        let workspace = WorkspaceID()
        let identity = UUID()
        let asset = try NavigationTargetV1(
            workspaceID: workspace, destination: .assets, stableEntityID: identity
        )
        let report = try NavigationTargetV1(
            workspaceID: workspace, destination: .reports, stableEntityID: identity
        )
        let context = RouteResolutionContextV1(
            currentWorkspaceID: workspace, currentRevision: 0,
            sourceAvailability: [asset: .available, report: .fallback(.deletedOrTombstoned)]
        )
        let registry = try RouteRegistryV1()
        XCTAssertEqual(try registry.resolve(asset, context: context).disposition, .resolved)
        XCTAssertEqual(try registry.resolve(report, context: context).reason, .deletedOrTombstoned)
    }

    func testReportsReadTargetKeepsTheCanonicalDetailIdentityAndFallbacksHaveNoEffects() throws {
        let workspace = WorkspaceID()
        let reportID = UUID()
        let target = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .reports,
            stableEntityID: reportID,
            requestedMode: .read,
            expectedRevision: 7,
            fallback: try NavigationFallbackV1(
                root: .reports,
                destination: .reports
            )
        )
        let registry = try RouteRegistryV1()
        let live = RouteResolutionContextV1(
            currentWorkspaceID: workspace,
            currentRevision: 31,
            sourceAvailability: [target: .available]
        )
        let resolved = try registry.resolve(target, context: live)
        XCTAssertEqual(resolved.disposition, .resolved)
        XCTAssertEqual(resolved.target, target)
        XCTAssertEqual(resolved.target.stableEntityID, reportID)
        XCTAssertEqual(resolved.target.requestedMode, .read)
        XCTAssertEqual(resolved.target.fallback.root, .reports)
        XCTAssertEqual(resolved.canonicalMutationCount, 0)
        XCTAssertFalse(resolved.startsAutomaticWork)

        let failures: [RouteResolutionContextV1] = [
            .init(currentWorkspaceID: workspace, currentRevision: 31,
                  sourceAvailability: [target: .fallback(.deletedOrTombstoned)]),
            .init(currentWorkspaceID: workspace, currentRevision: 31,
                  sourceAvailability: [target: .fallback(.staleRevision)]),
            .init(currentWorkspaceID: WorkspaceID(), currentRevision: 31,
                  sourceAvailability: [target: .available]),
            .init(currentWorkspaceID: workspace, currentRevision: 31,
                  availabilityRevoked: true, sourceAvailability: [target: .available]),
        ]
        for context in failures {
            let result = try registry.resolve(target, context: context)
            XCTAssertEqual(result.disposition, .safeFallback)
            XCTAssertEqual(result.canonicalMutationCount, 0)
            XCTAssertFalse(result.startsAutomaticWork)
        }
    }

    func testSourceAvailabilityCannotOverrideWorkspaceOrAccessRevocation() throws {
        let workspace = WorkspaceID()
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .assets)
        let registry = try RouteRegistryV1()
        let foreign = RouteResolutionContextV1(
            currentWorkspaceID: WorkspaceID(), currentRevision: 0,
            sourceAvailability: [target: .available]
        )
        XCTAssertEqual(try registry.resolve(target, context: foreign).reason, .wrongWorkspace)
        let protected = RouteResolutionContextV1(
            currentWorkspaceID: workspace, currentRevision: 0,
            protectedDataAvailable: false, sourceAvailability: [target: .available]
        )
        XCTAssertEqual(try registry.resolve(target, context: protected).reason, .protectedDataUnavailable)
        let revoked = RouteResolutionContextV1(
            currentWorkspaceID: workspace, currentRevision: 0,
            availabilityRevoked: true, sourceAvailability: [target: .available]
        )
        XCTAssertEqual(try registry.resolve(target, context: revoked).reason, .revokedAvailability)
        let package = try NavigationTargetV1(workspaceID: workspace, destination: .packageSurface,
            root: .work, packageSurfaceID: "uninstalled.package.surface")
        let fabricatedPackage = RouteResolutionContextV1(currentWorkspaceID: workspace,
            currentRevision: 0, sourceAvailability: [package: .available])
        XCTAssertEqual(try registry.resolve(package, context: fabricatedPackage).reason, .retiredOrMissingPackage)
    }
}

private actor SceneNavigationAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}

@MainActor private final class SceneNavigationNotificationSystem: NotificationSystemPortV1 {
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

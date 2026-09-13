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
        let workAsset = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .work, stableEntityID: first.assetID, requestedMode: .read,
            expectedRevision: assetRevision,
            fallback: try NavigationFallbackV1(root: .work, destination: .work))
        let currentWorkAsset = try NavigationTargetV1(workspaceID: store.workspaceID,
            destination: .work, stableEntityID: first.assetID, requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .work, destination: .work))
        let liveSource = try ProductionSceneNavigationSourceV1.context(
            for: [workAsset, currentWorkAsset], in: store, registry: try RouteRegistryV1())
        XCTAssertEqual(try RouteRegistryV1().resolve(workAsset, context: liveSource).target, workAsset)
        XCTAssertEqual(try RouteRegistryV1().resolve(currentWorkAsset, context: liveSource).target,
            currentWorkAsset)
        XCTAssertNil(currentWorkAsset.expectedRevision)
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

    func testWorkAssetReadTargetPreservesNilRevisionAndFailsClosedForOtherWorkFamilies() throws {
        let workspace = WorkspaceID()
        let assetID = UUID()
        let revisionBound = try NavigationTargetV1(
            workspaceID: workspace, destination: .work, stableEntityID: assetID,
            requestedMode: .read, expectedRevision: 7,
            fallback: try NavigationFallbackV1(root: .work, destination: .work)
        )
        let currentAvailability = try NavigationTargetV1(
            workspaceID: workspace, destination: .work, stableEntityID: assetID,
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .work, destination: .work)
        )
        let registry = try RouteRegistryV1()
        for target in [revisionBound, currentAvailability] {
            let resolved = try registry.resolve(target, context: .init(
                currentWorkspaceID: workspace, currentRevision: 31,
                sourceAvailability: [target: .available]
            ))
            XCTAssertEqual(resolved.disposition, .resolved)
            XCTAssertEqual(resolved.target, target)
            XCTAssertEqual(resolved.canonicalMutationCount, 0)
            XCTAssertFalse(resolved.startsAutomaticWork)
        }
        XCTAssertNil(currentAvailability.expectedRevision)
        XCTAssertEqual(try registry.resolve(revisionBound, context: .init(
            currentWorkspaceID: workspace, currentRevision: 31,
            sourceAvailability: [revisionBound: .fallback(.staleRevision)]
        )).reason, .staleRevision)
        let session = try NavigationTargetV1(
            workspaceID: workspace, destination: .work, stableSessionID: UUID(),
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .work, destination: .work)
        )
        let location = try NavigationTargetV1(
            workspaceID: workspace, destination: .work, stableLocationID: UUID(),
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .work, destination: .work)
        )
        for target in [session, location] {
            let fallback = try registry.resolve(target, context: .init(
                currentWorkspaceID: workspace, currentRevision: 31,
                sourceAvailability: [target: .fallback(.invalidTarget)]
            ))
            XCTAssertEqual(fallback.disposition, .safeFallback)
            XCTAssertEqual(fallback.target.destination, .work)
            XCTAssertEqual(fallback.canonicalMutationCount, 0)
            XCTAssertFalse(fallback.startsAutomaticWork)
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

extension V23ProductionSceneNavigationTests {
    @MainActor
    func testWorkAssetRouteFallsBackForFirstWriterProducedRetirementAtRevisionTwo() async throws {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(
            testCase: self, name: "work-retirement-first"
        )
        defer { fixture.cleanUp() }
        let route = try await V23WorkRouteHarness.make(in: fixture, label: "retirement-first")
        let initialRevision = try route.assetRevision()
        XCTAssertEqual(initialRevision, 1)

        let mutationID = MutationIDV1(rawValue: UUID())
        let record = try AssetLifecycleEventRecordV1.canonical(
            for: .retiredRecorded, eventID: UUID(), workspaceID: route.store.workspaceID,
            assetID: route.sign.assetID, predecessorEventID: nil, revision: initialRevision + 1,
            mutationID: mutationID, recordedAt: Date()
        )
        let mutation = try AssetSemanticsMutationV1(
            workspaceID: route.store.workspaceID, assetID: route.sign.assetID,
            expectedAssetRevision: initialRevision, mutationID: mutationID,
            operation: .appendLifecycle,
            lifecycleEvent: .retiredRecorded(record)
        )
        _ = try route.store.workspaceWriter.execute(
            .applyAssetSemantics(mutation), mutationID: mutationID
        )
        XCTAssertEqual(try route.assetRevision(), 2)

        let target = try route.target(expectedRevision: nil)
        let beforeRead = try route.store.workspaceWriter.currentRevision()
        let registry = try RouteRegistryV1()
        let source = try ProductionSceneNavigationSourceV1.context(
            for: [target], in: route.store, registry: registry
        )
        let resolution = try registry.resolve(target, context: source)
        XCTAssertEqual(resolution.disposition, .safeFallback)
        XCTAssertEqual(resolution.reason, .deletedOrTombstoned)
        XCTAssertEqual(resolution.canonicalMutationCount, 0)
        XCTAssertFalse(resolution.startsAutomaticWork)
        XCTAssertEqual(try route.store.workspaceWriter.currentRevision(), beforeRead)
        XCTAssertFalse(route.store.modelContext.hasChanges)
    }

    @MainActor
    func testWorkAssetRouteAcceptsWriterProducedLifecycleGapAndStillFallsBackWhenRetired() async throws {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(
            testCase: self, name: "work-retirement-gap"
        )
        defer { fixture.cleanUp() }
        let route = try await V23WorkRouteHarness.make(in: fixture, label: "retirement-gap")
        XCTAssertEqual(try route.assetRevision(), 1)

        let activeID = MutationIDV1(rawValue: UUID())
        let activeRecord = try AssetLifecycleEventRecordV1.canonical(
            for: .activeRecorded, eventID: UUID(), workspaceID: route.store.workspaceID,
            assetID: route.sign.assetID, predecessorEventID: nil, revision: 2,
            mutationID: activeID, recordedAt: Date()
        )
        let active = try AssetSemanticsMutationV1(
            workspaceID: route.store.workspaceID, assetID: route.sign.assetID,
            expectedAssetRevision: 1, mutationID: activeID, operation: .appendLifecycle,
            lifecycleEvent: .activeRecorded(activeRecord)
        )
        _ = try route.store.workspaceWriter.execute(.applyAssetSemantics(active), mutationID: activeID)
        XCTAssertEqual(try route.assetRevision(), 2)

        let productID = MutationIDV1(rawValue: UUID())
        let identifier = AssetProductIdentifierV1(
            kind: .serial, value: "WORK-RETIRE-GAP", normalizedComparisonValue: "work-retire-gap",
            issuer: "test", provenance: .humanRecorded, reviewState: .reviewedAsRecorded,
            effectiveFrom: Date(), effectiveUntil: nil
        )
        let product = try AssetProductIdentityV1(
            identityID: UUID(), workspaceID: route.store.workspaceID, assetID: route.sign.assetID,
            identifiers: [identifier], predecessorIdentityID: nil, revision: 3,
            mutationID: productID, recordedAt: Date()
        )
        let productMutation = try AssetSemanticsMutationV1(
            workspaceID: route.store.workspaceID, assetID: route.sign.assetID,
            expectedAssetRevision: 2, mutationID: productID, operation: .appendProductIdentity,
            productIdentity: product
        )
        _ = try route.store.workspaceWriter.execute(
            .applyAssetSemantics(productMutation), mutationID: productID
        )
        XCTAssertEqual(try route.assetRevision(), 3)

        let retirementID = MutationIDV1(rawValue: UUID())
        let retirementRecord = try AssetLifecycleEventRecordV1.canonical(
            for: .retiredRecorded, eventID: UUID(), workspaceID: route.store.workspaceID,
            assetID: route.sign.assetID, predecessorEventID: activeRecord.eventID, revision: 4,
            mutationID: retirementID, recordedAt: Date().addingTimeInterval(1)
        )
        let retirement = try AssetSemanticsMutationV1(
            workspaceID: route.store.workspaceID, assetID: route.sign.assetID,
            expectedAssetRevision: 3, mutationID: retirementID, operation: .appendLifecycle,
            lifecycleEvent: .retiredRecorded(retirementRecord)
        )
        _ = try route.store.workspaceWriter.execute(
            .applyAssetSemantics(retirement), mutationID: retirementID
        )
        XCTAssertEqual(try route.assetRevision(), 4)

        let target = try route.target(expectedRevision: nil)
        let beforeRead = try route.store.workspaceWriter.currentRevision()
        let registry = try RouteRegistryV1()
        let source = try ProductionSceneNavigationSourceV1.context(
            for: [target], in: route.store, registry: registry
        )
        let resolution = try registry.resolve(target, context: source)
        XCTAssertEqual(resolution.reason, .deletedOrTombstoned)
        XCTAssertEqual(resolution.canonicalMutationCount, 0)
        XCTAssertEqual(try route.store.workspaceWriter.currentRevision(), beforeRead)
        XCTAssertFalse(route.store.modelContext.hasChanges)
    }

    @MainActor
    func testWorkAssetRouteRejectsDeliberatelyInsertedDuplicateLifecycleRevisionAsCorruptSource() async throws {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(
            testCase: self, name: "work-retirement-malformed"
        )
        defer { fixture.cleanUp() }
        let route = try await V23WorkRouteHarness.make(in: fixture, label: "retirement-malformed")
        let activeID = MutationIDV1(rawValue: UUID())
        let active = try AssetLifecycleEventV1.activeRecorded(
            AssetLifecycleEventRecordV1.canonical(
                for: .activeRecorded, eventID: UUID(), workspaceID: route.store.workspaceID,
                assetID: route.sign.assetID, predecessorEventID: nil, revision: 2,
                mutationID: activeID, recordedAt: Date()
            )
        )
        let duplicateID = MutationIDV1(rawValue: UUID())
        let duplicate = try AssetLifecycleEventV1.retiredRecorded(
            AssetLifecycleEventRecordV1.canonical(
                for: .retiredRecorded, eventID: UUID(), workspaceID: route.store.workspaceID,
                assetID: route.sign.assetID, predecessorEventID: active.record.eventID, revision: 2,
                mutationID: duplicateID, recordedAt: Date().addingTimeInterval(1)
            )
        )
        // These rows intentionally bypass the writer to model hostile durable input.  Each
        // row is individually canonical; only their duplicated aggregate revision is invalid.
        route.store.modelContext.insert(try AssetLifecycleEventRow(active))
        route.store.modelContext.insert(try AssetLifecycleEventRow(duplicate))
        try route.store.modelContext.save()

        let target = try route.target(expectedRevision: nil)
        XCTAssertThrowsError(try ProductionSceneNavigationSourceV1.context(
            for: [target], in: route.store, registry: try RouteRegistryV1()
        )) { error in
            XCTAssertEqual(error as? ProductionSceneNavigationSourceFailureV1, .corruptSource)
        }
        XCTAssertFalse(route.store.modelContext.hasChanges)
    }
}

extension V23ProductionSceneNavigationTests {
    @MainActor
    func testActualRoundMissingAndDamagedHistoryDeniesReadsWithoutNewReceipts() async throws {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(
            testCase: self, name: "round-missing-corrupt")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "corrupt")
        let missing = try NavigationTargetV1(workspaceID: context.work.store.workspaceID,
            destination: .work, stableSessionID: UUID(), requestedMode: .read,
            fallback: NavigationFallbackV1(root: .work, destination: .work))
        let before = try context.work.store.workspaceWriter.currentRevision()
        try context.work.scene.open(missing)
        XCTAssertEqual(context.work.scene.lastRestoration?.receipt.result.disposition, .safeFallback)
        XCTAssertEqual(context.work.scene.lastRestoration?.receipt.result.reason, .deletedOrTombstoned)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        let beforeReceipts = try context.work.store.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>())
        let row = try XCTUnwrap(context.work.store.modelContext.fetch(
            FetchDescriptor<RoundSessionRevisionRowV1>()).first)
        // Deliberate durable corruption is confined to this negative fixture.
        // Every positive Round above was created through commitRoundSession.
        row.canonicalData = Data("invalid round bytes".utf8)
        try context.work.store.modelContext.save()
        do {
            _ = try await context.access.readSession(sessionID: context.round.sessionID,
                expectedRevision: context.round.revision)
            XCTFail("A canonical read cannot publish damaged Round history")
        } catch {}
        let target = try context.target(for: context.round)
        XCTAssertThrowsError(try ProductionSceneNavigationSourceV1.context(
            for: [target], in: context.work.store, registry: RouteRegistryV1()))
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(
            FetchDescriptor<MutationReceiptRow>()), beforeReceipts)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(
            FetchDescriptor<RoundSessionRevisionRowV1>()), 1)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualRoundStaleLeaveCannotReplaceAnotherSessionOrSelectedRoot() async throws {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(
            testCase: self, name: "round-stale-leave")
        defer { fixture.cleanUp() }
        let first = try await V23RoundRouteHarness.make(in: fixture, label: "first")
        let second = try await V23RoundRouteHarness.make(in: fixture, label: "second")
        let firstTarget = try first.target(for: first.round)
        let secondTarget = try second.target(for: second.round)
        let scene = first.work.scene
        try scene.open(firstTarget)
        let firstState = ProductionRoundSessionPresentationV1(target: firstTarget,
            scene: scene, access: first.access)
        await firstState.refresh()
        XCTAssertEqual(firstState.session, first.round)
        try scene.open(secondTarget)
        let before = try first.work.store.workspaceWriter.currentRevision()
        firstState.leave()
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [secondTarget])
        let secondState = ProductionRoundSessionPresentationV1(target: secondTarget,
            scene: scene, access: second.access)
        await secondState.refresh()
        XCTAssertEqual(secondState.session, second.round)
        try scene.select(.reports)
        secondState.leave()
        XCTAssertEqual(scene.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [secondTarget])
        try scene.select(.work)
        secondState.leave()
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [])
        XCTAssertEqual(try first.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try first.work.store.modelContext.fetchCount(
            FetchDescriptor<RoundSessionRevisionRowV1>()), 2)
        XCTAssertFalse(first.work.store.modelContext.hasChanges)
    }
}

import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

class V23ProductionFourRootShellTestSupport: XCTestCase {
    @MainActor
    func makeRoundContentReference(workspaceID: WorkspaceID, label: String, bytes: Data,
                                           contentID: String? = nil) throws -> ContentReferenceV1 {
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: KernelCanonicalHashV1.sha256(bytes))
        return try ContentReferenceV1(workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: contentID ?? "round-content-\(label)", byteLength: Int64(bytes.count),
            mediaType: "application/pdf", digests: .init([digest]), byteRole: .immutableOriginal,
            createdAt: "2026-09-13T00:00:00Z")
    }

    @MainActor
    func persistRoundContent(in context: V23WorkRouteHarness, label: String,
                                     bytes: Data) async throws -> ContentReferenceV1 {
        let reference = try makeRoundContentReference(workspaceID: context.store.workspaceID,
            label: label, bytes: bytes)
        let digest = try XCTUnwrap(reference.digests.digest(for: .sha256))
        let request = try DraftImmutableContentWriteRequestV1(workspaceID: context.store.workspaceID,
            contentID: reference.contentID, digest: digest, byteLength: reference.byteLength,
            mediaType: reference.mediaType, mutationID: MutationIDV1(rawValue: UUID()),
            createdAt: reference.createdAt)
        let receipt = try await EvidenceBundleStore(generationRootURL: context.store.generationRootURL)
            .persistImmutableOriginal(bytes: bytes, request: request)
        try receipt.validate(request: request, bytes: bytes)
        return reference
    }

    @MainActor
    func makeFixture(_ name: String) async throws -> V23ProductionMyDayPresentationHarness {
        try await V23ProductionMyDayPresentationHarness.start(testCase: self, name: name)
    }

    @MainActor
    func makeReadyReport(
        in fixture: V23ProductionMyDayPresentationHarness,
        label: String = "ready"
    ) async throws -> (reportID: UUID, assetID: UUID) {
        let access = try XCTUnwrap(fixture.presentation.renderAccess)
        let workflow = try access.withRead {
            let profiles = try WorkspacePackageLifecycleCompatibilityV1
                .legacyV3Registry(package: .illuminatedSignV1)
            let root = try ProductionCompositionRoot(
                storeSession: fixture.coordinator,
                diagnosticsStore: fixture.diagnostics,
                profileRegistry: profiles
            )
            return try root.makeSignWorkflow(
                signPack: .illuminatedSignV1,
                accessState: { .entitled }
            )
        }
        let sign = try await workflow.firstSign.create(.init(
            siteLabel: "Reports route site \(label)",
            signLabel: "Reports route sign \(label)",
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true
        ))
        _ = try workflow.checkRunner.beginCheck(
            assetID: sign.assetID,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: Date(timeIntervalSince1970: 1_800_500_000)
        )
        let result = try await workflow.checkRunner.finalize(
            assetID: sign.assetID,
            selection: .couldNotVerify(
                reasonKey: "required_view_obstructed",
                note: nil
            ),
            completedAt: Date(timeIntervalSince1970: 1_800_500_010),
            snapshotCreatedAt: Date(timeIntervalSince1970: 1_800_500_011),
            sourceApp: SourceAppSnapshotV1(
                build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            )
        )
        guard case .ready = try workflow.checkRunner.prepareReportDelivery(result: result)
        else { throw AppAccessContractFailureV1.configurationUnknown }
        return (result.reportID, sign.assetID)
    }

    @MainActor
    func makeWorkAsset(
        in fixture: V23ProductionMyDayPresentationHarness,
        label: String
    ) async throws -> FirstSignSnapshot {
        let access = try XCTUnwrap(fixture.presentation.renderAccess)
        let workflow = try access.withRead {
            let profiles = try WorkspacePackageLifecycleCompatibilityV1
                .legacyV3Registry(package: .illuminatedSignV1)
            let root = try ProductionCompositionRoot(storeSession: fixture.coordinator,
                diagnosticsStore: fixture.diagnostics, profileRegistry: profiles)
            return try root.makeSignWorkflow(signPack: .illuminatedSignV1,
                accessState: { .entitled })
        }
        return try await workflow.firstSign.create(.init(
            siteLabel: "Work route site \(label)", signLabel: "Work route sign \(label)",
            timeZoneID: "America/New_York", isTimeZoneConfirmed: true
        ))
    }

    @MainActor
    func validatedWorkTarget(
        _ sign: FirstSignSnapshot,
        in fixture: V23ProductionMyDayPresentationHarness
    ) throws -> NavigationTargetV1 {
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: sign.assetID)
        let assetRevision = try XCTUnwrap(
            revision.entityRevisions.first { $0.identity == identity }
        ).revision
        return try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID, destination: .work,
            stableEntityID: sign.assetID, requestedMode: .read,
            expectedRevision: assetRevision,
            fallback: try NavigationFallbackV1(root: .work, destination: .work)
        )
    }

    @MainActor
    func validatedReportTarget(
        _ report: (reportID: UUID, assetID: UUID),
        in fixture: V23ProductionMyDayPresentationHarness
    ) throws -> NavigationTargetV1 {
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: .report, id: report.reportID)
        let reportRevision = try XCTUnwrap(
            revision.entityRevisions.first { $0.identity == identity }
        ).revision
        return try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: report.reportID,
            requestedMode: .read,
            expectedRevision: reportRevision,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
    }

    @MainActor
    func reportRoutes(in scene: AppShellSceneStateV1) -> [ReportHistoryRoute] {
        scene.snapshot?.path(for: .reports)?.targets.compactMap { target in
            guard target.destination == .reports,
                  target.requestedMode == .read,
                  let reportID = target.stableEntityID else { return nil }
            return .report(reportID)
        } ?? []
    }

    @MainActor
    func containsAccessibilityIdentifier(
        identifiedBy identifier: String,
        in view: UIView
    ) -> Bool {
        if view.accessibilityIdentifier == identifier { return true }
        for case let element as UIAccessibilityIdentification in view.accessibilityElements ?? [] {
            if element.accessibilityIdentifier == identifier { return true }
        }
        for child in view.subviews {
            if containsAccessibilityIdentifier(identifiedBy: identifier, in: child) { return true }
        }
        return false
    }

    @MainActor
    func navigationControllerPresentingDetail(
        from controller: UIViewController
    ) -> UINavigationController? {
        if let navigation = controller as? UINavigationController,
           navigation.viewControllers.contains(where: {
               containsAccessibilityIdentifier(
                   identifiedBy: ReportDetailView.screenAccessibilityIdentifier,
                   in: $0.view
               )
           }) {
            return navigation
        }
        for child in controller.children {
            if let navigation = navigationControllerPresentingDetail(from: child) {
                return navigation
            }
        }
        return nil
    }

    @MainActor
    func navigationControllerPresenting(
        accessibilityIdentifier: String,
        from controller: UIViewController
    ) -> UINavigationController? {
        if let navigation = controller as? UINavigationController,
           navigation.viewControllers.contains(where: {
               containsAccessibilityIdentifier(identifiedBy: accessibilityIdentifier, in: $0.view)
           }) { return navigation }
        for child in controller.children {
            if let navigation = navigationControllerPresenting(
                accessibilityIdentifier: accessibilityIdentifier, from: child
            ) { return navigation }
        }
        return nil
    }

    @MainActor
    func waitForAccessibilityIdentifier(_ identifier: String, in view: UIView) async -> Bool {
        for _ in 0..<200 {
            if containsAccessibilityIdentifier(identifiedBy: identifier, in: view) { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    @MainActor
    func waitForNativeRoot(_ identifier: String, from host: UIViewController) async -> Bool {
        for _ in 0..<200 {
            if let navigation = navigationControllerPresenting(accessibilityIdentifier: identifier, from: host),
               navigation.viewControllers.count == 1 { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    @MainActor
    func waitForPersistedWorkRoot(
        _ access: AppAccessPresentationV1.SceneNavigationAccess
    ) async -> Bool {
        for _ in 0..<200 {
            if let loaded = try? access.load(), case let .restored(snapshot) = loaded,
               snapshot.path(for: .work)?.targets == [] { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

// INSERT inside V23ProductionFourRootShellTests.  This fragment deliberately
// uses the app's production access and FinalizationService readback; it does
// not construct a test-only RoundSessionLiveAuthorityReadingV1.

    @MainActor
    func assertCompletionTransitionDenied(context: V23RoundRouteHarness, active: RoundSessionV1) async throws {
        let before = try context.work.store.workspaceWriter.currentRevision()
        let write = try context.access.prepareSessionTransition(expected: active, transition: .pause,
            recordedByName: "Denied completion recorder")
        do {
            _ = try await context.access.executeSessionTransition(write) {}
            XCTFail("Completion authority must deny before a PAUSE writer effect")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
        XCTAssertEqual(write.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func makeActualFinalizedCompletion(in context: V23RoundRouteHarness, label: String,
        asset: FirstSignSnapshot? = nil) async throws
        -> (reference: RoundItemCompletionReferenceV1, snapshotURL: URL) {
        let selectedAsset = asset ?? context.work.sign
        let now = roundTimestamp()
        _ = try context.work.workflow.checkRunner.beginCheck(assetID: selectedAsset.assetID,
            timeZoneID: "America/New_York", isTimeZoneConfirmed: true, afterDarkAccepted: true,
            safePositionAccepted: true, observedAt: now)
        let finalized = try await context.work.workflow.checkRunner.finalize(assetID: selectedAsset.assetID,
            selection: .couldNotVerify(reasonKey: "required_view_obstructed", note: nil), completedAt: now,
            snapshotCreatedAt: now.addingTimeInterval(0.001),
            sourceApp: .init(build: "round-completion-\(label)", version: "1"))
        let release = try roundShippingRelease(stage: .check)
        let finalizer = try FinalizationService(modelContext: context.work.store.modelContext,
            signPack: .illuminatedSignV1, generationRootURL: context.work.store.generationRootURL,
            workspaceWriter: context.work.store.workspaceWriter)
        let reference = try XCTUnwrap(finalizer.completedInspectionReference(recordID: finalized.recordID,
            expectedAssetID: selectedAsset.assetID, expectedRelease: release))
        XCTAssertEqual(reference.completionID, finalized.recordID, "completionID is the WorkflowRecord ID")
        let report = try XCTUnwrap(context.work.store.modelContext.fetch(FetchDescriptor<Report>())
            .first { $0.id == finalized.reportID })
        return (reference, context.work.store.generationRootURL.appendingPathComponent(report.snapshotRelativePath))
    }

    @MainActor
    func makeActualCompletedActiveRound(in context: V23RoundRouteHarness, label: String) async throws -> RoundSessionV1 {
        let finalized = try await makeActualFinalizedCompletion(in: context, label: label)
        return try makeCompletedActiveRound(in: context, completion: finalized.reference,
            requirement: context.round.items[0].requirement, recordedAt: Date())
    }

    @MainActor
    func makeCompletedActiveRound(in context: V23RoundRouteHarness,
        completion: RoundItemCompletionReferenceV1, requirement: RoundPackageContentRequirementV1,
        recordedAt: Date) throws -> RoundSessionV1 {
        var initial = context.round
        if requirement != initial.items[0].requirement {
            let item = try XCTUnwrap(initial.items.first)
            let replacement = try RoundItemV1(itemID: item.itemID, order: item.order,
                selection: item.selection, requirement: requirement)
            let revised = try RoundSessionV1(workspaceID: initial.workspaceID, sessionID: initial.sessionID,
                predecessor: initial, revision: initial.revision + 1, mutationID: MutationIDV1(rawValue: UUID()),
                state: .draft, transition: .reviseSelection, items: [replacement], recordedBy: initial.recordedBy,
                recordedAt: initial.recordedAt)
            _ = try context.work.store.workspaceWriter.commitRoundSession(.init(workspaceID: revised.workspaceID,
                expectedRevision: initial.revision, mutationID: revised.mutationID, session: revised))
            initial = revised
        }
        let timestamp = roundTimestamp(max(recordedAt, initial.recordedAt))
        let start = try RoundSessionV1(workspaceID: initial.workspaceID, sessionID: initial.sessionID,
            predecessor: initial, revision: initial.revision + 1, mutationID: MutationIDV1(rawValue: UUID()),
            state: .active, transition: .start, items: initial.items, recordedBy: initial.recordedBy,
            recordedAt: timestamp)
        _ = try context.work.store.workspaceWriter.commitRoundSession(.init(workspaceID: start.workspaceID,
            expectedRevision: initial.revision, mutationID: start.mutationID, session: start))
        let initialItem = try XCTUnwrap(start.items.first)
        let visit = try RoundItemVisitV1(visitedAt: timestamp, recordedBy: initial.recordedBy)
        let visitedItem = try RoundItemV1(itemID: initialItem.itemID, order: initialItem.order,
            selection: initialItem.selection, requirement: requirement, disposition: .visited, visit: visit)
        let visited = try RoundSessionV1(workspaceID: start.workspaceID, sessionID: start.sessionID,
            predecessor: start, revision: start.revision + 1, mutationID: MutationIDV1(rawValue: UUID()),
            state: .active, transition: .visitItem, transitionItemID: visitedItem.itemID, items: [visitedItem],
            recordedBy: initial.recordedBy, recordedAt: timestamp)
        _ = try context.work.store.workspaceWriter.commitRoundSession(.init(workspaceID: visited.workspaceID,
            expectedRevision: start.revision, mutationID: visited.mutationID, session: visited))
        let completedItem = try RoundItemV1(itemID: visitedItem.itemID, order: visitedItem.order,
            selection: visitedItem.selection, requirement: requirement, disposition: .completed, visit: visit,
            completion: completion)
        let completed = try RoundSessionV1(workspaceID: visited.workspaceID, sessionID: visited.sessionID,
            predecessor: visited, revision: visited.revision + 1, mutationID: MutationIDV1(rawValue: UUID()),
            state: .active, transition: .completeItem, transitionItemID: completedItem.itemID,
            items: [completedItem], recordedBy: initial.recordedBy, recordedAt: timestamp)
        _ = try context.work.store.workspaceWriter.commitRoundSession(.init(workspaceID: completed.workspaceID,
            expectedRevision: visited.revision, mutationID: completed.mutationID, session: completed))
        return completed
    }

    @MainActor
    func roundShippingRelease(stage: WorkflowStage) throws -> InspectionPackageReleaseV1 {
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let workflow = try ShippingIlluminatedSignAdapterV1.finalizationWorkflow(from: .illuminatedSignV1,
            stage: stage)
        return try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(.makeDraft(package: package, workflow: workflow))).release
    }

    @MainActor
    func roundTimestamp(_ date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
    }

    @MainActor
    func startActualRound(in context: V23RoundRouteHarness, recorder: String) async throws -> RoundSessionV1 {
        let write = try context.access.prepareSessionTransition(expected: context.round, transition: .start,
            recordedByName: recorder)
        let receipt = try await context.access.executeSessionTransition(write) {}
        XCTAssertEqual(receipt.sessionFrontier, try write.proposedSession.reference)
        return try await context.access.readSession(sessionID: context.round.sessionID,
            expectedRevision: write.proposedSession.revision)
    }



    @MainActor
    func prepareActualCaptureStep(in context: V23RoundRouteHarness, sourceDraftID: UUID,
        action: RepetitiveCaptureProgressActionV2, completionRecordID: UUID? = nil) async throws
        -> AppAccessPresentationV1.RoundAccess.RepetitiveCaptureStepV2 {
        let read = try context.access.readRepetitiveCaptureProgress(sourceDraftID: sourceDraftID)
        let readiness = try await context.access.rebuildReadiness(for: read.chain.currentRound, previous: nil)
        return try context.access.prepareRepetitiveCaptureStep(read: read, readiness: readiness,
            action: action, focus: .facts, completionRecordID: completionRecordID,
            recordedByName: "Capture recorder")
    }

    @MainActor
    struct C36ActualCaptureReopenedAuthority {
        let router: StartupRouter
        let session: ProductionAppAccessSessionV1
        let presentation: AppAccessPresentationV1
        let coordinator: StoreSessionCoordinator
    }

    actor C36ActualCaptureAuthentication: LocalAuthenticationClient {
        func availability() -> LocalAuthenticationAvailabilityV1 {
            .systemValue(status: .available, biometry: .faceID)
        }
        func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
            .authenticated
        }
        func cancel(attemptID: UUID) {}
    }

    @MainActor
    final class C36ActualCaptureNotificationSystem: NotificationSystemPortV1 {
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

    @MainActor
    func reopenActualCaptureAuthority(support: URL, defaults: UserDefaults) async throws
        -> C36ActualCaptureReopenedAuthority {
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: C36ActualCaptureAuthentication(),
            notificationSystem: C36ActualCaptureNotificationSystem())
        let presentation = AppAccessPresentationV1(startupRouter: router, sessionFactory: { session })
        let published = expectation(description: "Disk-cold production authority publishes Round access")
        let observation = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in published.fulfill() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        observation.cancel()
        guard case .ready(let coordinator, _, _) = router.route else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return .init(router: router, session: session, presentation: presentation,
            coordinator: coordinator)
    }



}

final class V23ProductionFourRootShellTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualNativeShellRestoresEachPersistedRootAndPreservesAcceptedTabIdentities() async throws {
        #if DEBUG
        let fixture = try await makeFixture("native-tabs")
        defer { fixture.cleanUp() }
        let sceneAccess = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        let state = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: sceneAccess, registry: try RouteRegistryV1())
        try state.restore()
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let expectedTitles = ["Today", "Work", "Assets", "Reports"]
        let expectedIdentifiers = ["v23.tab.today", "v23.tab.work", "s1.tab.signs", "s1.tab.reports"]
        for (root, title) in zip(AppRootV1.frozenOrder, expectedTitles) {
            try state.select(root)
            let bound = expectation(description: "Actual native shell restores \(title)")
            var observedTabBar: UITabBar?
            var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
                storeSession: fixture.coordinator,
                contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
                sceneNavigationAccess: sceneAccess,
                myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
                diagnosticsStore: fixture.diagnostics,
                metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
                feedbackConfiguration: .production,
                mailComposerAdapter: .unavailable,
                entitlementProcessor: fixture.router.entitlementProcessor)
            shell.onNativeTabsBoundForTesting = { tabBar in
                guard observedTabBar == nil, tabBar.selectedItem?.title == title else { return }
                observedTabBar = tabBar
                bound.fulfill()
            }
            let host = UIHostingController(rootView: shell.modelContext(fixture.coordinator.modelContext))
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKeyAndVisible()
            }
            host.view.layoutIfNeeded()
            await fulfillment(of: [bound], timeout: 20)
            let tabBar = try XCTUnwrap(observedTabBar)
            XCTAssertEqual(tabBar.items?.map(\.title), expectedTitles.map(Optional.some))
            XCTAssertEqual(tabBar.items?.map(\.accessibilityIdentifier),
                expectedIdentifiers.map(Optional.some))
            XCTAssertEqual(tabBar.selectedItem?.title, title)
            let restored = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
                access: sceneAccess, registry: try RouteRegistryV1())
            try restored.restore()
            XCTAssertEqual(restored.snapshot?.selectedRoot, root)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
        #else
        throw XCTSkip("Native tab observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testAllRootsShareActualMyDayReadWithQuantizedClockAndNoCanonicalEffects() async throws {
        let fixture = try await makeFixture("four-roots")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        let clock = V23ShellReadClock(Date(timeIntervalSince1970: 1_800_300_000.1234))
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: access, clock: clock)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        try scene.restore()
        for root in AppRootV1.frozenOrder {
            try scene.select(root)
            await source.refresh()
            let snapshot = try XCTUnwrap(source.snapshot)
            XCTAssertEqual(scene.snapshot?.selectedRoot, root)
            XCTAssertEqual(snapshot.workspaceID, fixture.coordinator.workspaceID)
            XCTAssertEqual(snapshot.evaluatedAt,
                Date(timeIntervalSince1970: 1_800_300_000.123))
            XCTAssertFalse(source.isLoading)
            XCTAssertFalse(source.couldNotLoad)
        }
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<MyDayCarryoverReceiptRowV1>()), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testActualStartupRestoresReadyReportIntoExistingDetailAndBackPersistsThroughScenePort() async throws {
        #if DEBUG
        let fixture = try await makeFixture("reports-detail-route")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture)
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let reportIdentity = try WorkspaceEntityIdentityV1(kind: .report, id: report.reportID)
        let reportRevision = try XCTUnwrap(
            revision.entityRevisions.first { $0.identity == reportIdentity }
        ).revision
        let target = try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: report.reportID,
            requestedMode: .read,
            expectedRevision: reportRevision,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        let sceneAccess = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: sceneAccess, registry: try RouteRegistryV1())
        try scene.restore()
        let beforeRoute = try fixture.coordinator.workspaceWriter.currentRevision()
        let missing = try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: UUID(),
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        let stale = try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: report.reportID,
            requestedMode: .read,
            expectedRevision: reportRevision + 1,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        let wrongFamily = try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: report.assetID,
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        let foreign = try NavigationTargetV1(
            workspaceID: WorkspaceID(),
            destination: .reports,
            stableEntityID: report.reportID,
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        for (candidate, reason) in [
            (missing, RouteFallbackReasonV1.deletedOrTombstoned),
            (stale, .staleRevision),
            (wrongFamily, .invalidTarget),
            (foreign, .wrongWorkspace),
        ] {
            try scene.open(candidate)
            XCTAssertEqual(scene.lastRestoration?.receipt.result.reason, reason)
            XCTAssertEqual(scene.lastRestoration?.receipt.canonicalMutationCount, 0)
            XCTAssertFalse(scene.lastRestoration?.receipt.startsAutomaticWork ?? true)
            XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [])
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeRoute)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
        try scene.open(target)
        XCTAssertEqual(scene.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [target])
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeRoute)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)

        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: fixture.coordinator,
            contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
            sceneNavigationAccess: sceneAccess,
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production,
            mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        let host = UIHostingController(rootView: shell.modelContext(fixture.coordinator.modelContext))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
        host.view.layoutIfNeeded()
        let detailVisible = await Task { @MainActor in
            for _ in 0..<200 {
                if self.containsAccessibilityIdentifier(
                    identifiedBy: ReportDetailView.screenAccessibilityIdentifier,
                    in: host.view
                ) {
                    return true
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return false
        }.value
        XCTAssertTrue(detailVisible, "Actual Reports startup must render ready detail")

        let navigation = try XCTUnwrap(
            navigationControllerPresentingDetail(from: host)
        )
        navigation.popToRootViewController(animated: false)
        let persistedBackPath = await Task { @MainActor in
            for _ in 0..<200 {
                if let loaded = try? sceneAccess.load(),
                   case let .restored(snapshot) = loaded,
                   snapshot.path(for: .reports)?.targets == [] {
                    return true
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return false
        }.value
        XCTAssertTrue(persistedBackPath, "Shell back navigation must clear the saved Reports path")
        XCTAssertFalse(containsAccessibilityIdentifier(
            identifiedBy: ReportDetailView.screenAccessibilityIdentifier,
            in: host.view
        ))
        let reopened = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: sceneAccess, registry: try RouteRegistryV1())
        try reopened.restore()
        XCTAssertEqual(reopened.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(reopened.snapshot?.path(for: .reports)?.targets, [])
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeRoute)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        #else
        throw XCTSkip("Native report-detail observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testTransientReportComparisonSuffixCannotReattachAfterValidatedCanonicalPathChanges() async throws {
        let fixture = try await makeFixture("reports-transient-anchor")
        defer { fixture.cleanUp() }
        let first = try await makeReadyReport(in: fixture, label: "first")
        let second = try await makeReadyReport(in: fixture, label: "second")
        let firstTarget = try validatedReportTarget(first, in: fixture)
        let secondTarget = try validatedReportTarget(second, in: fixture)
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        try scene.restore()
        try scene.open(firstTarget)
        var presentation = ReportsNavigationPresentationV1()
        let comparisonID = UUID()
        let descendantReportID = UUID()
        let initialRoutes: [ReportHistoryRoute] = [
            .report(first.reportID),
            .comparison(comparisonID),
            .report(descendantReportID),
        ]
        let original = presentation.setPresentedRoutes(
            initialRoutes,
            snapshotID: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(original, [.report(first.reportID)])
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            initialRoutes,
            "comparison descendants remain transient only while their canonical prefix is current"
        )
        let beforeSelectRoutes = reportRoutes(in: scene)
        let beforeSelectSnapshotID = scene.snapshot?.snapshotID
        try scene.select(.today)
        presentation.refreshCanonicalSnapshot(
            from: beforeSelectRoutes,
            snapshotIDBefore: beforeSelectSnapshotID,
            to: reportRoutes(in: scene),
            snapshotIDAfter: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            initialRoutes,
            "A root selection with the same Reports path keeps its in-memory comparison suffix"
        )
        let beforeRestoreRoutes = reportRoutes(in: scene)
        let beforeRestoreSnapshotID = scene.snapshot?.snapshotID
        try scene.restore()
        presentation.refreshCanonicalSnapshot(
            from: beforeRestoreRoutes,
            snapshotIDBefore: beforeRestoreSnapshotID,
            to: reportRoutes(in: scene),
            snapshotIDAfter: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            initialRoutes,
            "Restoring the same persisted Reports path keeps its in-memory comparison suffix"
        )

        // Do not reconcile between these writes: the final canonical route starts with the
        // original report again, but its snapshot is a different persisted state.
        let anchoredSnapshotID = scene.snapshot?.snapshotID
        try scene.open(secondTarget)
        try scene.open(firstTarget)
        let changedCanonicalRoutes = reportRoutes(in: scene)
        XCTAssertEqual(changedCanonicalRoutes, [.report(first.reportID)])
        XCTAssertNotEqual(scene.snapshot?.snapshotID, anchoredSnapshotID)
        let beforeChangedSelectSnapshotID = scene.snapshot?.snapshotID
        try scene.select(.reports)
        presentation.refreshCanonicalSnapshot(
            from: changedCanonicalRoutes,
            snapshotIDBefore: beforeChangedSelectSnapshotID,
            to: reportRoutes(in: scene),
            snapshotIDAfter: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            reportRoutes(in: scene),
            "A coalesced A-to-B-to-A canonical change cannot reattach the stale comparison suffix"
        )
        let beforeChangedRestoreRoutes = reportRoutes(in: scene)
        let beforeChangedRestoreSnapshotID = scene.snapshot?.snapshotID
        try scene.restore()
        presentation.refreshCanonicalSnapshot(
            from: beforeChangedRestoreRoutes,
            snapshotIDBefore: beforeChangedRestoreSnapshotID,
            to: reportRoutes(in: scene),
            snapshotIDAfter: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            reportRoutes(in: scene),
            "Restoring after the coalesced change cannot recover the stale comparison suffix"
        )
    }

    @MainActor
    func testCoverAfterCompletedAccessReadDeniesFinalStatePublication() async throws {
        #if DEBUG
        let fixture = try await makeFixture("final-cover")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: access)
        var reachedFinalBoundary = false
        source.afterSnapshotReadyForTesting = {
            reachedFinalBoundary = true
            fixture.presentation.receive(.sceneInactive)
        }
        await source.refresh()
        XCTAssertTrue(reachedFinalBoundary)
        XCTAssertNil(source.snapshot)
        XCTAssertFalse(source.isLoading)
        XCTAssertTrue(source.couldNotLoad)
        XCTAssertThrowsError(try access.withCurrentPresentation {}) {
            XCTAssertEqual($0 as? AppAccessContractFailureV1, .accessDenied)
        }
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testStateChangeObserverCanCoverBeforePublicationWithoutReenteringTokenLock() async throws {
        let fixture = try await makeFixture("observer-cover")
        defer { fixture.cleanUp() }
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.myDayAccess))
        var covered = false
        let observation = source.objectWillChange.sink {
            if source.isLoading && !covered {
                covered = true
                fixture.presentation.receive(.sceneInactive)
            }
        }
        await source.refresh()
        observation.cancel()
        XCTAssertTrue(covered)
        XCTAssertNil(source.snapshot)
        XCTAssertFalse(source.isLoading)
        XCTAssertTrue(source.couldNotLoad)
    }

    @MainActor
    func testDiscardDuringCompletedReadPreventsSuccessOrErrorFromReappearing() async throws {
        #if DEBUG
        let fixture = try await makeFixture("discard")
        defer { fixture.cleanUp() }
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.myDayAccess))
        for shouldThrow in [false, true] {
            source.afterSnapshotReadyForTesting = {
                source.discard()
                if shouldThrow { throw CancellationError() }
            }
            await source.refresh()
            XCTAssertNil(source.snapshot)
            XCTAssertFalse(source.isLoading)
            XCTAssertFalse(source.couldNotLoad)
        }
        source.afterSnapshotReadyForTesting = nil
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testOlderCompletedReadCannotReplaceNewerSuccessWithValueOrFailure() async throws {
        #if DEBUG
        let fixture = try await makeFixture("overlap")
        defer { fixture.cleanUp() }
        let clock = V23ShellReadClock(Date(timeIntervalSince1970: 1_800_300_100))
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.myDayAccess), clock: clock)
        for shouldThrow in [false, true] {
            let parked = expectation(description: "Older real snapshot reached final boundary")
            let gate = V23ShellReadGate()
            clock.set(Date(timeIntervalSince1970: 1_800_300_100))
            source.afterSnapshotReadyForTesting = {
                source.afterSnapshotReadyForTesting = nil
                parked.fulfill()
                await gate.wait()
                if shouldThrow { throw CancellationError() }
            }
            let older = Task { await source.refresh() }
            await fulfillment(of: [parked], timeout: 10)
            guard gate.isWaiting else {
                gate.release()
                older.cancel()
                await older.value
                return XCTFail("The original production read never reached its final boundary")
            }
            clock.set(Date(timeIntervalSince1970: 1_800_300_200))
            await source.refresh()
            XCTAssertEqual(source.snapshot?.evaluatedAt,
                Date(timeIntervalSince1970: 1_800_300_200))
            gate.release()
            await older.value
            XCTAssertEqual(source.snapshot?.evaluatedAt,
                Date(timeIntervalSince1970: 1_800_300_200))
            XCTAssertFalse(source.isLoading)
            XCTAssertFalse(source.couldNotLoad)
        }
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testWrongWorkspaceAndCancelledReadNeverPublishSourceValues() async throws {
        let fixture = try await makeFixture("denied")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let foreign = ProductionMyDaySourceStateV1(workspaceID: WorkspaceID(), access: access)
        await foreign.refresh()
        XCTAssertNil(foreign.snapshot)
        XCTAssertTrue(foreign.couldNotLoad)
        XCTAssertFalse(foreign.isLoading)
        #if DEBUG
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: access)
        let parked = expectation(description: "Real read completed before cancellation")
        let gate = V23ShellReadGate()
        source.afterSnapshotReadyForTesting = {
            parked.fulfill()
            await gate.wait()
        }
        let read = Task { await source.refresh() }
        await fulfillment(of: [parked], timeout: 10)
        read.cancel()
        gate.release()
        await read.value
        source.afterSnapshotReadyForTesting = nil
        XCTAssertNil(source.snapshot)
        XCTAssertTrue(source.couldNotLoad)
        XCTAssertFalse(source.isLoading)
        #endif
    }
}


/// Canonical package rows are explicit published-package fixtures here;
/// package promotion itself is not a result of these route tests. Assets and
/// every Round frontier are produced by their actual existing writers.
@MainActor
struct V23RoundRouteHarness {
    let work: V23WorkRouteHarness
    let access: AppAccessPresentationV1.RoundAccess
    let round: RoundSessionV1

    static func make(in fixture: V23ProductionMyDayPresentationHarness,
                     label: String) async throws -> Self {
        let work = try await V23WorkRouteHarness.make(in: fixture, label: label)
        let access = try XCTUnwrap(fixture.presentation.roundAccess)
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let workflow = try ShippingIlluminatedSignAdapterV1.finalizationWorkflow(
            from: .illuminatedSignV1, stage: .check)
        let release = try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(.makeDraft(package: package, workflow: workflow))).release
        let existing = try work.store.modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>())
            .map { try $0.value() }.filter { $0.packageRelease.packageReleaseID == release.packageReleaseID }
        if existing.isEmpty {
            let promoted = try PromotedPackageReleaseV1(releaseRecordID: UUID(),
                workspaceID: work.store.workspaceID, packageRelease: release,
                mutationID: MutationIDV1(rawValue: UUID()), promotedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 * 1_000) / 1_000))
            work.store.modelContext.insert(try PromotedPackageReleaseRow(promoted))
            try work.store.modelContext.save()
        } else {
            XCTAssertEqual(existing.count, 1)
            XCTAssertEqual(existing.first?.packageRelease, release)
        }
        let key = try MyDayKeyV1(workspaceID: work.store.workspaceID,
            civilDate: .init("2026-09-13"), ianaTimeZoneIdentifier: "America/New_York")
        let actor = try XCTUnwrap(fixture.presentation.myDayAccess)
            .captureConfirmedPlanningContext(for: key, recordedByName: "Round route recorder").recordedBy
        let requirement = try RoundPackageContentRequirementV1(packageRelease: .init(release), requiredContent: [])
        let item = try RoundItemV1(itemID: UUID(), order: 0,
            selection: .init(assetID: work.sign.assetID, siteID: work.sign.siteID,
                labelAtSelection: work.sign.signLabel), requirement: requirement)
        let round = try RoundSessionV1(workspaceID: work.store.workspaceID, sessionID: UUID(),
            revision: 1, mutationID: MutationIDV1(rawValue: UUID()), state: .draft, transition: .create,
            items: [item], recordedBy: actor, recordedAt: actor.capturedAt)
        _ = try work.store.workspaceWriter.commitRoundSession(.init(workspaceID: work.store.workspaceID,
            expectedRevision: 0, mutationID: round.mutationID, session: round))
        return .init(work: work, access: access, round: round)
    }

    /// Adds actual first-sign assets through the same existing workflow and
    /// publishes one canonical selection successor for production reorder tests.
    func addingDraftItems(_ additionalCount: Int) async throws -> Self {
        precondition(additionalCount > 0)
        var items = round.items
        let requirement = try XCTUnwrap(items.first).requirement
        for index in 0..<additionalCount {
            let sign = try await work.workflow.firstSign.create(.init(
                siteLabel: "Round ordering site \(index)", signLabel: "Round ordering item \(index)",
                timeZoneID: "America/New_York", isTimeZoneConfirmed: true
            ))
            items.append(try RoundItemV1(itemID: UUID(), order: items.count,
                selection: .init(assetID: sign.assetID, siteID: sign.siteID,
                    labelAtSelection: sign.signLabel), requirement: requirement))
        }
        let expanded = try RoundSessionV1(workspaceID: round.workspaceID, sessionID: round.sessionID,
            predecessor: round, revision: round.revision + 1, mutationID: MutationIDV1(rawValue: UUID()),
            state: .draft, transition: .reviseSelection, items: items,
            recordedBy: round.recordedBy, recordedAt: round.recordedAt)
        _ = try work.store.workspaceWriter.commitRoundSession(.init(workspaceID: round.workspaceID,
            expectedRevision: round.revision, mutationID: expanded.mutationID, session: expanded))
        return .init(work: work, access: access, round: expanded)
    }

    func requiringContent(_ content: [[ContentReferenceV1]]) throws -> Self {
        guard content.count == round.items.count else { throw RoundSessionFailureV1.invalidValue }
        let items = try zip(round.items, content).enumerated().map { offset, pair in
            let requirement = try RoundPackageContentRequirementV1(
                packageRelease: pair.0.requirement.packageRelease, requiredContent: pair.1.sorted { $0.id < $1.id })
            return try RoundItemV1(itemID: pair.0.itemID, order: offset, selection: pair.0.selection,
                requirement: requirement, disposition: pair.0.disposition, visit: pair.0.visit,
                reason: pair.0.reason, completion: pair.0.completion)
        }
        let successor = try RoundSessionV1(workspaceID: round.workspaceID, sessionID: round.sessionID,
            predecessor: round, revision: round.revision + 1, mutationID: MutationIDV1(rawValue: UUID()),
            state: .draft, transition: .reviseSelection, items: items, recordedBy: round.recordedBy,
            recordedAt: round.recordedAt)
        _ = try work.store.workspaceWriter.commitRoundSession(.init(workspaceID: round.workspaceID,
            expectedRevision: round.revision, mutationID: successor.mutationID, session: successor))
        return .init(work: work, access: access, round: successor)
    }

    func target(for value: RoundSessionV1, mode: NavigationRequestedModeV1 = .read,
                expectedRevision: UInt64? = nil, workspaceID: WorkspaceID? = nil) throws -> NavigationTargetV1 {
        try .init(workspaceID: workspaceID ?? work.store.workspaceID, destination: .work,
            stableSessionID: value.sessionID, requestedMode: mode, expectedRevision: expectedRevision,
            fallback: NavigationFallbackV1(root: .work, destination: .work))
    }

    func successor(of prior: RoundSessionV1, state: RoundSessionStateV1,
                   transition: RoundSessionTransitionV1) throws -> RoundSessionV1 {
        let items: [RoundItemV1]
        if transition == .skipItem {
            let item = try XCTUnwrap(prior.items.first)
            items = [try RoundItemV1(itemID: item.itemID, order: item.order, selection: item.selection,
                requirement: item.requirement, disposition: .skipped, reason: .notRequired)]
        } else { items = prior.items }
        let next = try RoundSessionV1(workspaceID: prior.workspaceID, sessionID: prior.sessionID,
            predecessor: prior, revision: prior.revision + 1, mutationID: MutationIDV1(rawValue: UUID()),
            state: state, transition: transition, transitionItemID: transition == .skipItem ? items.first?.itemID : nil,
            items: items, recordedBy: prior.recordedBy, recordedAt: prior.recordedAt.addingTimeInterval(1))
        _ = try work.store.workspaceWriter.commitRoundSession(.init(workspaceID: work.store.workspaceID,
            expectedRevision: prior.revision, mutationID: next.mutationID, session: next))
        return next
    }
}

/// Test ownership around the actual startup publication and production
/// composition. It supplies no replacement scene, gate, writer or renderer.
@MainActor
struct V23WorkRouteHarness {
    let store: StoreSessionCoordinator
    let workflow: ProductionSignWorkflow
    let sign: FirstSignSnapshot
    let scene: AppShellSceneStateV1
    let sceneAccess: AppAccessPresentationV1.SceneNavigationAccess
    let contentAccess: AppAccessPresentationV1.ContentAccess

    static func make(
        in fixture: V23ProductionMyDayPresentationHarness,
        label: String,
        existingSign: FirstSignSnapshot? = nil
    ) async throws -> Self {
        guard case let .ready(store, diagnostics, _) = fixture.router.route else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let content = try XCTUnwrap(fixture.presentation.renderAccess)
        let access = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        let workflow = try content.withRead {
            let profiles = try WorkspacePackageLifecycleCompatibilityV1
                .legacyV3Registry(package: .illuminatedSignV1)
            let root = try ProductionCompositionRoot(storeSession: store,
                diagnosticsStore: diagnostics, profileRegistry: profiles)
            return try root.makeSignWorkflow(signPack: .illuminatedSignV1,
                accessState: { .entitled })
        }
        let sign: FirstSignSnapshot
        if let existingSign {
            sign = existingSign
        } else {
            sign = try await workflow.firstSign.create(.init(
                siteLabel: "Work source site \(label)", signLabel: "Work source sign \(label)",
                timeZoneID: "America/New_York", isTimeZoneConfirmed: true
            ))
        }
        let scene = AppShellSceneStateV1(workspaceID: store.workspaceID,
            access: access, registry: try RouteRegistryV1())
        try scene.restore()
        return .init(store: store, workflow: workflow, sign: sign, scene: scene,
            sceneAccess: access, contentAccess: content)
    }

    func assetRevision() throws -> UInt64 {
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: sign.assetID)
        return try XCTUnwrap(store.workspaceWriter.currentRevision()
            .entityRevisions.first { $0.identity == identity }).revision
    }

    func target(expectedRevision: UInt64?) throws -> NavigationTargetV1 {
        try .init(workspaceID: store.workspaceID, destination: .work,
            stableEntityID: sign.assetID, requestedMode: .read,
            expectedRevision: expectedRevision,
            fallback: NavigationFallbackV1(root: .work, destination: .work))
    }

    func admission(for target: NavigationTargetV1) -> WorkAssetPreflightRouteAdmissionV1 {
        .init(target: target, workflow: workflow, scene: scene, contentAccess: contentAccess)
    }

    func begin(
        using admission: WorkAssetPreflightRouteAdmissionV1,
        displayed: FirstSignSnapshot
    ) throws -> WorkflowRecord {
        try PreflightBeginOperationV1.begin(
            coordinator: workflow.checkRunner, snapshot: displayed,
            timeZoneID: displayed.timeZoneID, isTimeZoneConfirmed: displayed.timeZoneID != nil,
            afterDarkAccepted: true, safePositionAccepted: true, observedAt: Date(),
            beforeBeginRouteValidation: { try admission.validateBeforeBegin(displayedSnapshot: displayed) }
        )
    }
}

private final class V23ShellReadClock: ApplicationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    init(_ instant: Date) { self.instant = instant }
    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }
    func set(_ instant: Date) {
        lock.lock()
        defer { lock.unlock() }
        self.instant = instant
    }
}

@MainActor
private final class V23ShellReadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var isWaiting: Bool { continuation != nil }
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

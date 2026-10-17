import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C41MyDayWorkflowUITests: V23ProductionFourRootShellTestSupport {
    private enum SemanticSelector {
        static let screen = "v23.p04.c41.my-day.screen"
        static let eligibleWork = "v23.p04.c41.my-day.eligible-work"
        static let planOrder = "v23.p04.c41.my-day.plan-order"
        static let readiness = "v23.p04.c41.my-day.readiness"
        static let duration = "v23.p04.c41.my-day.duration"
        static let startResume = "v23.p04.c41.my-day.start-resume"
        static let carryover = "v23.p04.c41.my-day.carryover"
        static let reconciliation = "v23.p04.c41.my-day.reconciliation-boundaries"

        static let all = [
            screen, eligibleWork, planOrder, readiness, duration, startResume, carryover, reconciliation
        ]
    }

    func testV23P04C41SemanticSelectorContractIsClosedAndUnique() {
        XCTAssertEqual(SemanticSelector.all.count, 8)
        XCTAssertEqual(Set(SemanticSelector.all).count, SemanticSelector.all.count)
        XCTAssertTrue(SemanticSelector.all.allSatisfy {
            $0.hasPrefix("v23.p04.c41.my-day.")
                && $0 == $0.lowercased()
                && !$0.contains(where: { $0.isWhitespace })
        })
    }

    @MainActor
    func testV23P04C41WorkflowInitializerBindsCoreContractShapes() {
        let makeDraftItem: (UUID, MyDayEligibleReferenceV1, MyDayEstimateV1?) throws -> MyDayDraftItemV1 = MyDayDraftItemV1.init
        let move: (UUID) -> MyDayAccessibleMoveV1 = { .up(membershipID: $0) }
        let route: (MyDayExistingRouteIntentV1) -> MyDayExistingRouteIntentV1 = { $0 }
        let saveCommand: (MyDaySavePreviewV1) -> MyDayWorkflowCommandV1 = { .save($0) }
        let carryoverCommand: (MyDayCarryoverPreviewV1) -> MyDayWorkflowCommandV1 = { .carryover($0) }
        let coordinator = MyDayWorkflowCoordinatorV1.self
        let initializeSurface: (
            [MyDayEligibleReferenceV1],
            MyDayPlanDraftV1?,
            MyDaySummaryProjectionV1?,
            MyDaySavePreviewV1?,
            MyDayCarryoverPreviewV1?
        ) -> MyDayWorkflowView = { eligible, draft, summary, savePreview, carryoverPreview in
            MyDayWorkflowView(
                eligibleReferences: eligible,
                draft: draft,
                summary: summary,
                savePreview: savePreview,
                carryoverPreview: carryoverPreview,
                onSelectEligible: { _ in },
                onMove: { _ in },
                onRequestRoute: { _ in },
                onPreviewCarryover: {},
                onRefreshSummary: {}
            )
        }

        XCTAssertNotNil(makeDraftItem)
        XCTAssertNotNil(move)
        XCTAssertNotNil(route)
        XCTAssertNotNil(saveCommand)
        XCTAssertNotNil(carryoverCommand)
        XCTAssertNotNil(coordinator)
        XCTAssertNotNil(initializeSurface)
    }

    @MainActor
    func testV23P04C41MyDayWorkflowRemainsContainedBeforeS10() async throws {
        #if DEBUG
        // The historical selector stays stable. Phase 1 contains the added
        // V23 planning surface; accepted S10 is already part of the baseline.
        let fixture = try await makeFixture("c41-shipping-planning-boundary")
        defer { fixture.cleanUp() }
        let context = fixture.coordinator.modelContext
        let writer = fixture.coordinator.workspaceWriter
        let adapter = try writer.makeFieldDraftLifecycleAdapter(modelContext: context)
        let source = try makeC41EligibleCheckpoint(in: fixture)
        _ = try adapter.compareAndSwap(checkpoint: source, expectedDraftRevision: 0,
            expectedBaseRevision: source.baseCanonicalRevision)
        XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: source.workspaceID,
            draftID: source.draftID), source)
        let revisionBefore = try writer.currentRevision()
        let countsBefore = try c41CanonicalRowCounts(in: context)
        XCTAssertFalse(context.hasChanges)
        let reference = MyDayEligibleReferenceV1.resumableDraft(
            workspaceID: source.workspaceID, draftID: source.draftID,
            revision: source.draftRevision, checkpointSHA256: source.checkpointSHA256,
            anchor: source.resumeAnchor)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let snapshot = try await access.snapshot(evaluatedAt: source.updatedAt)
        XCTAssertEqual(snapshot.workspaceID, source.workspaceID)
        XCTAssertEqual(snapshot.eligibleReferences, [reference],
            "The published reader sees the actual writer-owned eligible source")
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c41CanonicalRowCounts(in: context), countsBefore)
        XCTAssertFalse(context.hasChanges)

        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        try scene.restore()
        try scene.select(.today)
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c41CanonicalRowCounts(in: context), countsBefore)
        XCTAssertFalse(context.hasChanges)

        // No gate injection: this is the shipping environment default.
        let shipping = try mountC41Shell(fixture, gate: nil)
        defer { shipping.unmount() }
        let shippingMounted = await waitForMountedScreen(
            ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier,
            from: shipping.host)
        XCTAssertTrue(shippingMounted, "Shipping Today renders its Phase 1 boundary")
        XCTAssertFalse(nativeScreenObservation(
            ProductionMyDayRootViewV1.myDayObservationIdentifier, from: shipping.host).found,
            "The added V23 list, Plan entry and editor branch are not composed")
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c41CanonicalRowCounts(in: context), countsBefore)
        XCTAssertFalse(context.hasChanges)
        shipping.unmount()

        // The same populated fixture supplies a positive control for the
        // exact branch witness used by the shipping negative assertion.
        let enabled = try mountC41Shell(fixture, gate: .allFeatures)
        defer { enabled.unmount() }
        let enabledMounted = await waitForMountedScreen(
            ProductionMyDayRootViewV1.myDayObservationIdentifier, from: enabled.host)
        XCTAssertTrue(enabledMounted, "The all-features control composes V23 My Day")
        XCTAssertFalse(nativeScreenObservation(
            ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier,
            from: enabled.host).found)
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c41CanonicalRowCounts(in: context), countsBefore)
        XCTAssertFalse(context.hasChanges)
        #else
        throw XCTSkip("Native hosted Phase 1 boundary observation is DEBUG-only")
        #endif
    }

    #if DEBUG
    @MainActor
    private func makeC41EligibleCheckpoint(
        in fixture: V23ProductionMyDayPresentationHarness
    ) throws -> FieldDraftCheckpointV1 {
        let writer = fixture.coordinator.workspaceWriter
        return try FieldDraftCheckpointV1(
            draftID: UUID(), workspaceID: fixture.coordinator.workspaceID,
            scope: .init(scopeKind: "V23_MY_DAY_COMMIT_SOURCE", stableComponentIDs: ["source"]),
            purpose: .assetFieldEdit,
            codec: .init(codecID: "v23.my-day.commit-source.v1", codecVersion: 1,
                releaseSHA256: String(repeating: "a", count: 64)),
            baseCanonicalRevision: try writer.currentRevision().revision,
            draftRevision: 1, payloadData: Data("source-revision-1".utf8), stageIDs: [],
            resumeAnchor: .init(sectionID: "source"), state: .active,
            updatedAt: Date(timeIntervalSince1970: 1_789_084_801),
            mutationID: try writer.makeMutationID())
    }

    @MainActor
    private func c41CanonicalRowCounts(in context: ModelContext) throws -> [Int] {
        [try context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
         try context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()),
         try context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()),
         try context.fetchCount(FetchDescriptor<MyDayCarryoverReceiptRowV1>())]
    }

    @MainActor
    private func mountC41Shell(
        _ fixture: V23ProductionMyDayPresentationHarness,
        gate: V23PhaseGateV1?
    ) throws -> SIG1MountedShellV1 {
        let shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: fixture.coordinator,
            contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
            sceneNavigationAccess: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        let content: AnyView
        if let gate {
            content = AnyView(shell.environment(\.v23PhaseGate, gate)
                .modelContext(fixture.coordinator.modelContext))
        } else {
            content = AnyView(shell.modelContext(fixture.coordinator.modelContext))
        }
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: content)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return SIG1MountedShellV1(window: window, host: host,
            previousKeyWindow: previousKeyWindow)
    }
    #endif
}

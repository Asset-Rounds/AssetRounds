import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

#if DEBUG
private enum V23RoundReadinessTestFailure: Error {
    case beforeFinalRead
}
#endif

final class V23ProductionRoundReadinessTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualRoundRoutesReadEveryWriterFrontierWithoutStartingOrResuming() async throws {
        let fixture = try await makeFixture("round-frontier-routes")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "frontier")
        var current = context.round
        let steps: [(RoundSessionStateV1, RoundSessionTransitionV1)] = [
            (.active, .start), (.paused, .pause), (.active, .resume),
            (.active, .skipItem), (.completed, .close), (.archived, .archive),
        ]
        for index in 0...steps.count {
            if index > 0 {
                current = try context.successor(of: current, state: steps[index - 1].0,
                    transition: steps[index - 1].1)
            }
            let before = try context.work.store.workspaceWriter.currentRevision()
            let target = try context.target(for: current, expectedRevision: current.revision)
            try context.work.scene.open(target)
            let state = ProductionRoundSessionPresentationV1(target: target,
                scene: context.work.scene, access: context.access)
            await state.refresh()
            XCTAssertEqual(state.session, current)
            XCTAssertFalse(state.couldNotLoad)
            let read = try await context.access.readSession(sessionID: current.sessionID, expectedRevision: nil)
            XCTAssertEqual(read, current)
            let resume = try context.target(for: current, mode: .resume, expectedRevision: current.revision)
            try context.work.scene.open(resume)
            let resumeState = ProductionRoundSessionPresentationV1(target: resume,
                scene: context.work.scene, access: context.access)
            await resumeState.refresh()
            if [.completed, .archived].contains(current.state) {
                XCTAssertNil(resumeState.session)
                XCTAssertEqual(context.work.scene.lastRestoration?.receipt.result.disposition, .safeFallback)
            } else { XCTAssertEqual(resumeState.session, current) }
            for invalid in [
                try context.target(for: current, expectedRevision: current.revision + 1),
                try context.target(for: current, workspaceID: WorkspaceID()),
            ] {
                try context.work.scene.open(invalid)
                let denied = ProductionRoundSessionPresentationV1(target: invalid,
                    scene: context.work.scene, access: context.access)
                await denied.refresh()
                XCTAssertNil(denied.session)
                XCTAssertNil(denied.readiness)
            }
            XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
            XCTAssertEqual(try context.work.store.modelContext.fetchCount(
                FetchDescriptor<RoundSessionRevisionRowV1>()), Int(current.revision))
            XCTAssertFalse(context.work.store.modelContext.hasChanges)
        }
    }

    @MainActor
    func testActualRoundReadinessPublishesExactSessionAndRejectsWriterAndFinalCoverRaces() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-readiness-races")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "readiness")
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        defer {
            state.afterReadinessReadForTesting = nil
            context.access.setAfterRoundReadinessMaterializationForTesting(nil)
            context.access.setAfterRoundSessionSourceObservationForTesting(nil)
        }
        await state.refresh()
        XCTAssertEqual(state.session, context.round)
        let before = try context.work.store.workspaceWriter.currentRevision()
        await state.rebuildReadiness()
        let manifest = try XCTUnwrap(state.readiness)
        XCTAssertEqual(manifest.session, try context.round.reference)
        XCTAssertFalse(state.couldNotRebuild)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)

        var advanced: RoundSessionV1?
        context.access.setAfterRoundSessionSourceObservationForTesting {
            context.access.setAfterRoundSessionSourceObservationForTesting(nil)
            advanced = try context.successor(of: context.round, state: .active, transition: .start)
        }
        await state.refresh()
        context.access.setAfterRoundSessionSourceObservationForTesting(nil)
        XCTAssertNil(state.session)
        XCTAssertTrue(state.couldNotLoad)
        let current = try XCTUnwrap(advanced)
        let afterAdvance = try context.work.store.workspaceWriter.currentRevision()
        await state.refresh()
        XCTAssertEqual(state.session, current)
        XCTAssertFalse(state.couldNotLoad)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterAdvance)

        context.access.setAfterRoundReadinessMaterializationForTesting {
            context.access.setAfterRoundReadinessMaterializationForTesting(nil)
            _ = try context.work.store.workspaceWriter.execute(.updateSiteTimeZone(.init(
                siteID: context.work.sign.siteID, timeZoneID: "America/Chicago", confirmedAt: Date()
            )), mutationID: MutationIDV1(rawValue: UUID()))
        }
        await state.rebuildReadiness()
        context.access.setAfterRoundReadinessMaterializationForTesting(nil)
        XCTAssertNil(state.readiness)
        XCTAssertTrue(state.couldNotRebuild)
        let afterSiteChange = try context.work.store.workspaceWriter.currentRevision()
        await state.rebuildReadiness()
        XCTAssertEqual(state.readiness?.session, try current.reference,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertFalse(state.couldNotRebuild,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterSiteChange)

        var finalHookCalls = 0
        state.afterReadinessReadForTesting = {
            finalHookCalls += 1
            state.afterReadinessReadForTesting = nil
            _ = try context.work.store.workspaceWriter.execute(.updateSiteTimeZone(.init(
                siteID: context.work.sign.siteID, timeZoneID: "America/Denver", confirmedAt: Date()
            )), mutationID: MutationIDV1(rawValue: UUID()))
        }
        await state.rebuildReadiness()
        state.afterReadinessReadForTesting = nil
        XCTAssertEqual(finalHookCalls, 1,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertNil(state.readiness)
        XCTAssertTrue(state.couldNotRebuild)
        XCTAssertEqual(state.session, current)
        let afterFinalSiteChange = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertGreaterThan(afterFinalSiteChange.revision, afterSiteChange.revision)
        await state.rebuildReadiness()
        XCTAssertEqual(finalHookCalls, 1)
        XCTAssertEqual(state.readiness?.session, try current.reference,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertFalse(state.couldNotRebuild,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterFinalSiteChange)

        state.afterReadinessReadForTesting = {
            finalHookCalls += 1
            fixture.presentation.receive(.sceneInactive)
        }
        await state.rebuildReadiness()
        state.afterReadinessReadForTesting = nil
        XCTAssertEqual(finalHookCalls, 2,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertNil(state.readiness)
        XCTAssertTrue(state.couldNotRebuild)
        XCTAssertNil(fixture.presentation.roundAccess)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterFinalSiteChange)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Actual round source/publication fence observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testReadinessPreFinalHookRejectionDoesNotCarryHookOrWriteIntoNextOperation() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-pre-final-hook-rejection")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "pre-final-hook")
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        defer {
            state.afterReadinessReadForTesting = nil
            context.access.setAfterRoundReadinessMaterializationForTesting(nil)
        }
        await state.refresh()
        XCTAssertEqual(state.session, context.round)
        let before = try context.work.store.workspaceWriter.currentRevision()
        var materializationHookCalls = 0
        var rejectedFinalHookCalls = 0
        context.access.setAfterRoundReadinessMaterializationForTesting {
            materializationHookCalls += 1
            throw V23RoundReadinessTestFailure.beforeFinalRead
        }
        state.afterReadinessReadForTesting = {
            rejectedFinalHookCalls += 1
            _ = try context.work.store.workspaceWriter.execute(.updateSiteTimeZone(.init(
                siteID: context.work.sign.siteID, timeZoneID: "America/Denver", confirmedAt: Date()
            )), mutationID: MutationIDV1(rawValue: UUID()))
        }
        await state.rebuildReadiness()
        state.afterReadinessReadForTesting = nil
        context.access.setAfterRoundReadinessMaterializationForTesting(nil)
        XCTAssertEqual(materializationHookCalls, 1)
        XCTAssertEqual(rejectedFinalHookCalls, 0)
        XCTAssertNil(state.readiness)
        XCTAssertTrue(state.couldNotRebuild)
        XCTAssertEqual(state.session, context.round)
        XCTAssertFalse(state.couldNotLoad)
        XCTAssertFalse(state.isRebuilding)
        let rejection = try XCTUnwrap(state.lastReadinessFailureForTesting)
        XCTAssertEqual(rejection.stage, "readiness-read")
        XCTAssertEqual(rejection.errorType, String(reflecting: V23RoundReadinessTestFailure.self))
        XCTAssertEqual(rejection.errorCode, (V23RoundReadinessTestFailure.beforeFinalRead as NSError).code)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)

        var successfulFinalHookCalls = 0
        state.afterReadinessReadForTesting = { successfulFinalHookCalls += 1 }
        await state.rebuildReadiness()
        state.afterReadinessReadForTesting = nil
        XCTAssertEqual(successfulFinalHookCalls, 1,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertEqual(rejectedFinalHookCalls, 0)
        XCTAssertEqual(materializationHookCalls, 1)
        XCTAssertEqual(state.readiness?.session, try context.round.reference,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertFalse(state.couldNotRebuild)
        XCTAssertNil(state.lastReadinessFailureForTesting)
        XCTAssertEqual(state.session, context.round)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Readiness rejection observations and hooks are DEBUG-only")
        #endif
    }

    @MainActor
    func testActualRoundFinalPublicationRejectsChangedNilRevisionFrontier() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-final-frontier")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "final-frontier")
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        defer {
            state.afterSessionReadForTesting = nil
            state.afterReadinessReadForTesting = nil
        }
        var current = context.round
        state.afterSessionReadForTesting = {
            state.afterSessionReadForTesting = nil
            current = try context.successor(of: current, state: .active, transition: .start)
        }
        await state.refresh()
        state.afterSessionReadForTesting = nil
        XCTAssertNil(state.session)
        XCTAssertTrue(state.couldNotLoad)
        await state.refresh()
        XCTAssertEqual(state.session, current)
        var finalHookCalls = 0
        state.afterReadinessReadForTesting = {
            finalHookCalls += 1
            state.afterReadinessReadForTesting = nil
            current = try context.successor(of: current, state: .paused, transition: .pause)
        }
        await state.rebuildReadiness()
        state.afterReadinessReadForTesting = nil
        XCTAssertEqual(finalHookCalls, 1,
            state.lastReadinessFailureForTesting?.summary ?? "no captured rebuild failure")
        XCTAssertNil(state.readiness)
        XCTAssertNil(state.session)
        XCTAssertTrue(state.couldNotRebuild)
        let beforeFreshRead = try context.work.store.workspaceWriter.currentRevision()
        await state.refresh()
        await state.rebuildReadiness()
        XCTAssertEqual(finalHookCalls, 1)
        XCTAssertEqual(state.session, current)
        XCTAssertEqual(state.readiness?.session, try current.reference)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), beforeFreshRead)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(
            FetchDescriptor<RoundSessionRevisionRowV1>()), 3)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Final Round publication observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualNativeRoundRouteAndBackPreserveReportsWithoutAutomaticWork() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-native-route")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "native")
        let target = try context.target(for: context.round, mode: .resume,
            expectedRevision: context.round.revision)
        let report = try await makeReadyReport(in: fixture, label: "round-retained-report")
        let reportTarget = try validatedReportTarget(report, in: fixture)
        try context.work.scene.open(reportTarget)
        try context.work.scene.open(target)
        let before = try context.work.store.workspaceWriter.currentRevision()
        let workflowCount = try context.work.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>())
        let bound = expectation(description: "The mounted Round uses the actual production scene")
        var actualScene: AppShellSceneStateV1?
        var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: context.work.store, contentAccess: context.work.contentAccess,
            sceneNavigationAccess: context.work.sceneAccess,
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess), roundAccess: context.access,
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        shell.onProductionSceneBoundForTesting = { scene in
            guard actualScene == nil else { return }
            actualScene = scene
            bound.fulfill()
        }
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: shell.modelContext(context.work.store.modelContext))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        await fulfillment(of: [bound], timeout: 20)
        let visible = await waitForMountedScreen(RoundSessionView.screenAccessibilityIdentifier, from: host)
        XCTAssertTrue(visible)
        let scene = try XCTUnwrap(actualScene)
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [target])
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(
            FetchDescriptor<RoundSessionRevisionRowV1>()), 1, "Opening resume never writes a resume successor")
        let navigation = try XCTUnwrap(navigationControllerPresenting(
            accessibilityIdentifier: RoundSessionView.screenAccessibilityIdentifier, from: host))
        navigation.popToRootViewController(animated: false)
        let returned = await waitForPersistedWorkRoot(context.work.sceneAccess)
        XCTAssertTrue(returned)
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), workflowCount)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Native Round route observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualRoundOldPublicationCannotReadAfterFreshSceneActivation() async throws {
        let fixture = try await makeFixture("round-publication-revocation")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "publication")
        let originalAccess = context.access
        let originalRead = try await originalAccess.rebuildReadiness(for: context.round, previous: nil)
        try originalAccess.validateReadinessForPublication(originalRead)
        let beforePause = try context.work.store.workspaceWriter.currentRevision()
        fixture.presentation.receive(.sceneInactive)
        do {
            _ = try await originalAccess.readSession(sessionID: context.round.sessionID, expectedRevision: nil)
            XCTFail("A revoked publication must not return a Round")
        } catch {}
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), beforePause)
        let republished = expectation(description: "Fresh actual scene publication restores Round access")
        let observation = fixture.presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in republished.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [republished], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(fixture.presentation.roundAccess)
        XCTAssertThrowsError(try originalAccess.validateReadinessForPublication(originalRead))
        XCTAssertThrowsError(try fresh.validateReadinessForPublication(originalRead))
        do {
            _ = try await originalAccess.readSession(sessionID: context.round.sessionID, expectedRevision: nil)
            XCTFail("A later publication cannot authorize the old Round capability")
        } catch {}
        let restored = try await fresh.readSession(sessionID: context.round.sessionID,
            expectedRevision: context.round.revision)
        XCTAssertEqual(restored, context.round)
        guard case let .ready(store, _, _) = fixture.router.route else {
            return XCTFail("Expected the actual resumed store")
        }
        let beforeReadiness = try store.workspaceWriter.currentRevision()
        let read = try await fresh.rebuildReadiness(for: restored, previous: nil)
        try fresh.validateReadinessForPublication(read)
        XCTAssertEqual(read.manifest.session, try restored.reference)
        XCTAssertEqual(try store.workspaceWriter.currentRevision(), beforeReadiness)
        XCTAssertEqual(try store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 1)
        XCTAssertFalse(store.modelContext.hasChanges)
    }
}

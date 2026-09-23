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
        accessibilityObservation(identifier, in: view).found
    }

    /// Follow only descendants exported by this host; never inspect other windows
    /// or follow parent/container back-references. Bounds make hostile cycles finite.
    @MainActor
    func accessibilityObservation(
        _ identifier: String, in view: UIView, includeRows: Bool = false
    ) -> (found: Bool, visited: Int, truncated: Bool, rows: [String]) {
        var seen = Set<ObjectIdentifier>()
        var found = false
        var truncated = false
        var rows: [String] = []
        @MainActor
        func visit(_ value: Any, depth: Int, edge: String) {
            guard !found else { return }
            guard depth <= 64, seen.count < 8192 else { truncated = true; return }
            guard let object = value as? NSObject else {
                if (value as? UIAccessibilityIdentification)?.accessibilityIdentifier == identifier {
                    found = true
                }
                return
            }
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            let observedID = (object as? UIView)?.accessibilityIdentifier
                ?? (object as? UIAccessibilityIdentification)?.accessibilityIdentifier
            if includeRows, rows.count < 128 {
                rows.append("depth=\(depth) edge=\(edge) type=\(String(reflecting: type(of: object))) id=\(String((observedID ?? "<nil>").prefix(100)))")
            }
            if observedID == identifier { found = true; return }
            if let childView = object as? UIView {
                if childView.subviews.count > 512 { truncated = true }
                for child in childView.subviews.prefix(512) {
                    visit(child, depth: depth + 1, edge: "subview")
                }
            }
            if let elements = object.accessibilityElements {
                if elements.count > 512 { truncated = true }
                for element in elements.prefix(512) {
                    visit(element, depth: depth + 1, edge: "array")
                }
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                if count > 512 { truncated = true }
                for index in 0..<min(count, 512) {
                    if let element = object.accessibilityElement(at: index) {
                        visit(element, depth: depth + 1, edge: "indexed")
                    }
                }
            }
        }
        visit(view, depth: 0, edge: "host")
        return (found, seen.count, truncated, rows)
    }

    @MainActor
    func logNativeObservation(_ identifier: String, from host: UIViewController, phase: String) {
        let observation = accessibilityObservation(identifier, in: host.view, includeRows: true)
        print("ShellObservation phase=\(phase) found=\(observation.found) visited=\(observation.visited) truncated=\(observation.truncated)")
        observation.rows.forEach { print("ShellObservation " + $0) }
        var seen = Set<ObjectIdentifier>()
        @MainActor
        func visit(_ controller: UIViewController, depth: Int) {
            guard depth < 16, seen.count < 128,
                  seen.insert(ObjectIdentifier(controller)).inserted else { return }
            print("ShellController phase=\(phase) depth=\(depth) type=\(String(reflecting: type(of: controller))) children=\(controller.children.count) navigation_stack=\((controller as? UINavigationController)?.viewControllers.count ?? 0)")
            for child in controller.children.prefix(32) { visit(child, depth: depth + 1) }
        }
        visit(host, depth: 0)
    }

    /// DEBUG host-unit observation of mounted content. This is deliberately
    /// separate from the public accessibility-container traversal above.
    @MainActor
    func nativeScreenObservation(
        _ identifier: String, from host: UIViewController, diagnostics: Bool = false
    ) -> (found: Bool, navigation: UINavigationController?) {
        #if DEBUG
        var diagnosticRows: [String] = []
        @MainActor
        func note(_ message: @autoclosure () -> String) {
            guard diagnostics, diagnosticRows.count < 96 else { return }
            diagnosticRows.append(message())
        }
        defer {
            if diagnostics {
                print("NativeObserver id=\(identifier) host=\(String(reflecting: type(of: host))) loaded=\(host.isViewLoaded) has_window=\(host.viewIfLoaded?.window != nil) rows=\(diagnosticRows.count)")
                diagnosticRows.forEach { print("NativeObserver " + $0) }
            }
        }
        guard host.isViewLoaded, let window = host.view.window, !window.isHidden else {
            note("host_rejected loaded=\(host.isViewLoaded) has_window=\(host.viewIfLoaded?.window != nil) window_hidden=\(host.viewIfLoaded?.window?.isHidden ?? true)")
            return (false, nil)
        }
        var controllers = Set<ObjectIdentifier>()
        var navigationOwners: [ObjectIdentifier: UINavigationController] = [:]
        var presentedRoot: UIView?
        @MainActor
        func visibleControllers(_ controller: UIViewController,
                                navigation: UINavigationController?, depth: Int) {
            guard depth <= 64, controllers.count < 8192,
                  controller.isViewLoaded else {
                note("controller_rejected type=\(String(reflecting: type(of: controller))) depth=\(depth) count=\(controllers.count) loaded=\(controller.isViewLoaded)")
                return
            }
            note("controller_input type=\(String(reflecting: type(of: controller))) object=\(ObjectIdentifier(controller)) depth=\(depth) children=\(controller.children.count)")
            if let presented = controller.presentedViewController, !presented.isBeingDismissed {
                if presented.isViewLoaded { presentedRoot = presented.view }
                note("presentation selected=\(ObjectIdentifier(presented)) loaded=\(presented.isViewLoaded)")
                visibleControllers(presented, navigation: nil, depth: depth + 1)
                return
            }
            let identity = ObjectIdentifier(controller)
            guard controllers.insert(identity).inserted else {
                note("controller_duplicate object=\(identity)")
                return
            }
            let owner = (controller as? UINavigationController) ?? navigation
            if let owner { navigationOwners[identity] = owner }
            if let tabs = controller as? UITabBarController {
                if let selected = tabs.selectedViewController {
                    note("selected_tab object=\(ObjectIdentifier(selected))")
                    visibleControllers(selected, navigation: owner, depth: depth + 1)
                }
            } else if let stack = controller as? UINavigationController {
                if let visible = stack.visibleViewController {
                    note("visible_navigation object=\(ObjectIdentifier(visible)) stack=\(stack.viewControllers.count)")
                    visibleControllers(visible, navigation: stack, depth: depth + 1)
                }
            } else {
                for child in controller.children.prefix(512) {
                    visibleControllers(child, navigation: owner, depth: depth + 1)
                }
            }
        }
        visibleControllers(host, navigation: nil, depth: 0)
        var seen = Set<ObjectIdentifier>()
        @MainActor
        func visit(_ view: UIView, depth: Int) -> (found: Bool, navigation: UINavigationController?) {
            if let anchor = view as? NativeScreenObservationViewV1 {
                note("anchor_candidate object=\(ObjectIdentifier(anchor)) id_match=\(anchor.observationIdentifier == identifier) depth=\(depth) window_match=\(anchor.window === window) hidden=\(anchor.isHidden) alpha=\(anchor.alpha)")
            }
            guard depth <= 64, seen.count < 8192,
                  seen.insert(ObjectIdentifier(view)).inserted,
                  view.window === window, !view.isHidden, view.alpha > 0 else {
                note("view_rejected type=\(String(reflecting: type(of: view))) depth=\(depth) count=\(seen.count) window_match=\(view.window === window) hidden=\(view.isHidden) alpha=\(view.alpha)")
                return (false, nil)
            }
            if let controller = view.next as? UIViewController,
               !controllers.contains(ObjectIdentifier(controller)) {
                note("view_controller_rejected view=\(String(reflecting: type(of: view))) controller=\(String(reflecting: type(of: controller))) object=\(ObjectIdentifier(controller))")
                return (false, nil)
            }
            if let anchor = view as? NativeScreenObservationViewV1,
               anchor.observationIdentifier == identifier {
                var responder: UIResponder? = anchor
                var responders = Set<ObjectIdentifier>()
                while let current = responder, responders.count < 64,
                      responders.insert(ObjectIdentifier(current)).inserted {
                    if let controller = current as? UIViewController {
                        let identity = ObjectIdentifier(controller)
                        guard controllers.contains(identity) else {
                            note("anchor_controller_rejected type=\(String(reflecting: type(of: controller))) object=\(identity)")
                            return (false, nil)
                        }
                        note("anchor_accepted controller=\(identity) has_navigation=\(navigationOwners[identity] != nil)")
                        return (true, navigationOwners[identity])
                    }
                    responder = current.next
                }
                note("anchor_responder_exhausted count=\(responders.count) remaining=\(responder != nil)")
            }
            for child in view.subviews.prefix(512) {
                let result = visit(child, depth: depth + 1)
                if result.found { return result }
            }
            return (false, nil)
        }
        // A real presented controller can live beside the presenting host view.
        // Only its public presentation ownership permits that alternate root.
        let root = presentedRoot ?? host.view!
        note("root_selected type=\(String(reflecting: type(of: root))) presented=\(presentedRoot != nil) controllers=\(controllers.count)")
        // Validate ancestors above a nested caller, too; no cross-window search.
        var ancestor: UIView? = root.superview
        var ancestors = Set<ObjectIdentifier>()
        while let current = ancestor {
            guard ancestors.count < 64, ancestors.insert(ObjectIdentifier(current)).inserted,
                  !current.isHidden, current.alpha > 0,
                  (current === window || current.window === window) else {
                note("ancestor_rejected type=\(String(reflecting: type(of: current))) count=\(ancestors.count) window_match=\(current.window === window) hidden=\(current.isHidden) alpha=\(current.alpha)")
                return (false, nil)
            }
            note("ancestor_accepted type=\(String(reflecting: type(of: current))) object=\(ObjectIdentifier(current))")
            ancestor = current.superview
        }
        let result = visit(root, depth: 0)
        note("walk_complete found=\(result.found) navigation=\(result.navigation != nil) views=\(seen.count) controllers=\(controllers.count)")
        return result
        #else
        return (false, nil)
        #endif
    }

    @MainActor
    func waitForMountedScreen(_ identifier: String, from host: UIViewController) async -> Bool {
        for _ in 0..<200 {
            if nativeScreenObservation(identifier, from: host).found { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        _ = nativeScreenObservation(identifier, from: host, diagnostics: true)
        return false
    }

    @MainActor
    func navigationControllerPresentingDetail(from controller: UIViewController) -> UINavigationController? {
        nativeScreenObservation(ReportDetailView.screenAccessibilityIdentifier, from: controller).navigation
    }

    @MainActor
    func navigationControllerPresenting(
        accessibilityIdentifier: String, from controller: UIViewController
    ) -> UINavigationController? {
        nativeScreenObservation(accessibilityIdentifier, from: controller).navigation
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
    func testPhysicalRestoredReviewDiscardUsesProductionAccessAndColdOriginalReadback() async throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let harness = try RestoreReviewHarness()
        defer { harness.remove() }
        let suite = "v23-restored-review-presentation-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settled: (FieldDraftCheckpointV1, RepetitiveCaptureDestinationDiscardEvidenceV1,
                      MutationHistorySnapshotV1)?
        do {
            let restored = try await harness.restore(try source.package(named: "work-review"), mode: .fork)
            let initial = try harness.onlyReview(in: restored)
            let initialHistory = try harness.history(in: restored)
            let authority = try await reopenActualCaptureAuthority(
                support: harness.support, defaults: defaults)
            defer { try? authority.coordinator.invalidateAndReleaseWriter() }
            let owner = authority
            let access = try XCTUnwrap(owner.presentation.roundAccess)
            let sceneAccess = try XCTUnwrap(owner.presentation.sceneNavigationAccess)
            let scene = AppShellSceneStateV1(workspaceID: initial.workspaceID,
                access: sceneAccess, registry: try RouteRegistryV1())
            try scene.restore()
            try scene.select(.work)
            let expectedScene = try XCTUnwrap(scene.snapshot)
            let reference = MyDayEligibleReferenceV1.resumableDraft(workspaceID: initial.workspaceID,
                draftID: initial.draftID, revision: initial.draftRevision,
                checkpointSHA256: initial.checkpointSHA256, anchor: initial.resumeAnchor)
            let entry = ProductionSavedReviewSheetStateV1()
            let stale = MyDayEligibleReferenceV1.resumableDraft(workspaceID: initial.workspaceID,
                draftID: initial.draftID, revision: initial.draftRevision + 1,
                checkpointSHA256: initial.checkpointSHA256, anchor: initial.resumeAnchor)
            entry.open(stale, scene: scene, sceneAccess: sceneAccess, access: access)
            XCTAssertNil(entry.route)
            XCTAssertNotNil(entry.errorMessage)
            XCTAssertEqual(try harness.history(in: restored), initialHistory)
            entry.dismissError()
            XCTAssertNil(entry.errorMessage)
            entry.open(reference, scene: scene, sceneAccess: sceneAccess, access: access)
            let route = try XCTUnwrap(entry.route)
            XCTAssertEqual(route.sceneSnapshot, expectedScene)
            XCTAssertNil(entry.errorMessage)
            var interruptAfterResolution = false
            let presentation = ProductionRepetitiveCaptureReviewPresentationV1(reference: reference,
                access: access, validateIntent: {
                    try entry.validateIntent(route, scene: scene, sceneAccess: sceneAccess)
                    if interruptAfterResolution,
                       try access.readRepetitiveCaptureDestinationReview(reviewDraftID: initial.draftID)
                        .selectedReview.checkpoint.state == .discardPending {
                        interruptAfterResolution = false
                        throw SceneNavigationFailureV1.invalidSnapshot
                    }
                })
            presentation.load()
            XCTAssertFalse(presentation.couldNotLoad)
            XCTAssertEqual(presentation.checkpoint, initial)
            let provenance = try XCTUnwrap(presentation.provenance)
            let sourceRound = try XCTUnwrap(source.rounds.last)
            XCTAssertEqual(provenance.sourceWorkspaceID, source.workspaceID)
            XCTAssertEqual(provenance.sourceDraftID, try XCTUnwrap(source.checkpoints.first).draftID)
            XCTAssertEqual(provenance.sourceRoundID, sourceRound.sessionID)
            XCTAssertEqual(provenance.recordedAt, sourceRound.recordedAt)
            XCTAssertEqual(provenance.recordedBy, sourceRound.recordedBy.displayNameAtTime)
            XCTAssertEqual(provenance.assetLabels, sourceRound.items.map { $0.selection.labelAtSelection })
            XCTAssertEqual(provenance.restoreMode, .fork)
            presentation.requestDiscard()
            XCTAssertTrue(presentation.wantsConfirmation)
            presentation.cancelConfirmation()
            presentation.confirmDiscard(confirmed: false)
            XCTAssertEqual(try harness.history(in: restored), initialHistory)
            XCTAssertFalse(presentation.isDiscarded)
            interruptAfterResolution = true
            presentation.requestDiscard()
            presentation.confirmDiscard(confirmed: true)
            XCTAssertTrue(presentation.couldNotDiscard)
            XCTAssertFalse(presentation.isDiscarded)
            let pendingHistory = try harness.history(in: restored)
            XCTAssertEqual(pendingHistory.receipts.count, initialHistory.receipts.count + 1)
            presentation.checkSavedResult()
            XCTAssertFalse(presentation.couldNotDiscard)
            XCTAssertEqual(presentation.checkpoint?.state, .discardPending)
            XCTAssertEqual(try harness.history(in: restored), pendingHistory)
            presentation.requestDiscard()
            presentation.confirmDiscard(confirmed: true)
            XCTAssertFalse(presentation.couldNotDiscard)
            XCTAssertTrue(presentation.isDiscarded)
            let terminal = try XCTUnwrap(presentation.checkpoint)
            XCTAssertEqual(terminal.state, .discarded)
            let terminalRead = try XCTUnwrap(access.readRepetitiveCaptureDestinationDiscard(reviewDraftID: initial.draftID))
            XCTAssertEqual(terminalRead.evidence.bundle.discardedCheckpoint, terminal)
            let settledHistory = try harness.history(in: restored)
            XCTAssertEqual(settledHistory.receipts.count, initialHistory.receipts.count + 2)
            for original in initialHistory.receipts {
                XCTAssertTrue(settledHistory.receipts.contains(original))
            }
            presentation.checkSavedResult()
            XCTAssertEqual(try harness.history(in: restored), settledHistory)
            entry.dismiss()
            XCTAssertThrowsError(try entry.validateIntent(route, scene: scene, sceneAccess: sceneAccess))
            presentation.invalidate()
            XCTAssertNil(presentation.provenance)
            presentation.requestDiscard()
            presentation.confirmDiscard(confirmed: true)
            XCTAssertEqual(try harness.history(in: restored), settledHistory)
            settled = (terminal, terminalRead.evidence, settledHistory)
        }
        let (terminal, terminalEvidence, settledHistory) = try XCTUnwrap(settled)
        let reopened = try await reopenActualCaptureAuthority(support: harness.support, defaults: defaults)
        defer { try? reopened.coordinator.invalidateAndReleaseWriter() }
        let reopenedAccess = try XCTUnwrap(reopened.presentation.roundAccess)
        let reopenedReference = MyDayEligibleReferenceV1.resumableDraft(workspaceID: terminal.workspaceID,
            draftID: terminal.draftID, revision: terminal.draftRevision,
            checkpointSHA256: terminal.checkpointSHA256, anchor: terminal.resumeAnchor)
        let reopenedSceneAccess = try XCTUnwrap(reopened.presentation.sceneNavigationAccess)
        let reopenedScene = AppShellSceneStateV1(workspaceID: terminal.workspaceID,
            access: reopenedSceneAccess, registry: try RouteRegistryV1())
        try reopenedScene.restore()
        try reopenedScene.select(.work)
        let reopenedSnapshot = try XCTUnwrap(reopenedScene.snapshot)
        let recovered = ProductionRepetitiveCaptureReviewPresentationV1(reference: reopenedReference,
            access: reopenedAccess, validateIntent: {
                guard reopenedScene.snapshot == reopenedSnapshot,
                      case let .restored(saved) = try reopenedSceneAccess.load(), saved == reopenedSnapshot else {
                    throw SceneNavigationFailureV1.invalidSnapshot
                }
            })
        recovered.load()
        XCTAssertFalse(recovered.couldNotLoad)
        XCTAssertTrue(recovered.isDiscarded)
        XCTAssertFalse(recovered.permitsDiscard)
        XCTAssertEqual(recovered.checkpoint, terminal)
        XCTAssertEqual(recovered.provenance?.sourceWorkspaceID, source.workspaceID)
        XCTAssertEqual(recovered.provenance?.sourceDraftID, try XCTUnwrap(source.checkpoints.first).draftID)
        let recoveredRead = try XCTUnwrap(reopenedAccess.readRepetitiveCaptureDestinationDiscard(reviewDraftID: terminal.draftID))
        XCTAssertEqual(recoveredRead.evidence, terminalEvidence)
        let coldSession = try harness.factory.openOrBootstrapCurrent()
        XCTAssertEqual(try harness.history(in: coldSession), settledHistory)
    }

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
        var observedShellScene: AppShellSceneStateV1?
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
        shell.onProductionSceneBoundForTesting = { boundScene in
            observedShellScene = boundScene
            print("ReportsStartupDiagnostic scene_bound reports_selected=\(boundScene.snapshot?.selectedRoot == .reports) exact_target=\(boundScene.snapshot?.path(for: .reports)?.targets == [target]) target_count=\(boundScene.snapshot?.path(for: .reports)?.targets.count ?? -1)")
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
        let detailVisible = await Task { @MainActor in
            for _ in 0..<200 {
                if self.nativeScreenObservation(
                    ReportDetailView.screenAccessibilityIdentifier, from: host
                ).found {
                    return true
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return false
        }.value
        // Observe the real composed scene and UIKit containers independently of
        // the unchanged detail identifier assertion; never supply navigation state.
        print("ReportsStartupDiagnostic after_wait scene_bound=\(observedShellScene != nil) reports_selected=\(observedShellScene?.snapshot?.selectedRoot == .reports) exact_target=\(observedShellScene?.snapshot?.path(for: .reports)?.targets == [target]) target_count=\(observedShellScene?.snapshot?.path(for: .reports)?.targets.count ?? -1)")
        do {
            if case let .restored(saved) = try sceneAccess.load() {
                print("ReportsStartupDiagnostic persisted reports_selected=\(saved.selectedRoot == .reports) exact_target=\(saved.path(for: .reports)?.targets == [target]) target_count=\(saved.path(for: .reports)?.targets.count ?? -1)")
            } else {
                print("ReportsStartupDiagnostic persisted_not_restored")
            }
        } catch {
            print("ReportsStartupDiagnostic persisted_read_failed type=\(String(reflecting: type(of: error))) code=\((error as NSError).code)")
        }
        let reportsRootObserved = containsAccessibilityIdentifier(
            identifiedBy: ReportsRootView.screenAccessibilityIdentifier, in: host.view
        )
        print("ReportsStartupDiagnostic hierarchy root_identifier=\(reportsRootObserved) detail_identifier=\(detailVisible) context_changes=\(fixture.coordinator.modelContext.hasChanges)")
        @MainActor
        func controllerSummary(_ controller: UIViewController, depth: Int = 0) -> [String] {
            guard depth < 12 else { return ["depth_limit"] }
            let stackCount = (controller as? UINavigationController)?.viewControllers.count ?? 0
            let value = "depth=\(depth) class=\(String(reflecting: type(of: controller))) children=\(controller.children.count) navigation_stack=\(stackCount)"
            return [value] + controller.children.prefix(12).flatMap {
                controllerSummary($0, depth: depth + 1)
            }
        }
        for line in controllerSummary(host).prefix(64) {
            print("ReportsStartupDiagnostic controller \(line)")
        }
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
        XCTAssertFalse(nativeScreenObservation(
            ReportDetailView.screenAccessibilityIdentifier, from: host
        ).found)
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
        guard case let .ready(store, _, _) = fixture.router.route else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let access = try XCTUnwrap(fixture.presentation.roundAccess)
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let workflow = try ShippingIlluminatedSignAdapterV1.finalizationWorkflow(
            from: .illuminatedSignV1, stage: .check)
        let release = try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(.makeDraft(package: package, workflow: workflow))).release
        let existing = try store.modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>())
            .map { try $0.value() }.filter { $0.packageRelease.packageReleaseID == release.packageReleaseID }
        if existing.isEmpty {
            // External package setup must never adopt real writer frontiers.
            guard try store.modelContext.fetchCount(FetchDescriptor<EntityMutationRevisionRow>()) == 0,
                  try store.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()) == 0 else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let journal = try MutationJournalStoreV1(modelContext: store.modelContext,
                identity: store.workspaceIdentity, generationID: store.generationID,
                allowStateBootstrap: false)
            try journal.validateAll()
            let promoted = try PromotedPackageReleaseV1(releaseRecordID: UUID(),
                workspaceID: store.workspaceID, packageRelease: release,
                mutationID: MutationIDV1(rawValue: UUID()), promotedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 * 1_000) / 1_000))
            store.modelContext.insert(try PromotedPackageReleaseRow(promoted))
            XCTAssertThrowsError(try journal.validateAll()) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            XCTAssertThrowsError(try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            let frontier = EntityMutationRevisionRow(identity: try .init(
                kind: .promotedPackageRelease, id: promoted.releaseRecordID), revision: promoted.revision)
            store.modelContext.insert(frontier)
            try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()
            try store.modelContext.save()
            try journal.validateAll()
            XCTAssertEqual(frontier.revision, Int64(promoted.revision))
            XCTAssertEqual(frontier.externalProjectionSHA256, promoted.releaseRecordSHA256)
            frontier.externalProjectionSHA256 = String(repeating: "0", count: 64)
            XCTAssertThrowsError(try journal.validateAll()) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            frontier.externalProjectionSHA256 = promoted.releaseRecordSHA256
            try store.modelContext.save()
            try journal.validateAll()
        } else {
            XCTAssertEqual(existing.count, 1)
            XCTAssertEqual(existing.first?.packageRelease, release)
        }
        let work = try await V23WorkRouteHarness.make(in: fixture, label: label)
        let assetFrontier = try XCTUnwrap(store.modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>())
            .first { $0.kind == WorkspaceEntityKindV1.asset.rawValue && $0.entityID == work.sign.assetID })
        XCTAssertNil(assetFrontier.externalProjectionSHA256)
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

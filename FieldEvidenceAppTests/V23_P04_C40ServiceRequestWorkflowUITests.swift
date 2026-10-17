import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C40ServiceRequestWorkflowUITests: V23ProductionFourRootShellTestSupport {
    private enum SemanticSelector {
        static let screen = "v23.p04.c40.service-request.screen"
        static let mode = "v23.p04.c40.service-request.mode"
        static let draft = "v23.p04.c40.service-request.draft"
        static let duplicates = "v23.p04.c40.service-request.duplicates"
        static let dispositions = "v23.p04.c40.service-request.dispositions"
        static let createWork = "v23.p04.c40.service-request.create-work"
        static let status = "v23.p04.c40.service-request.status"
        static let boundaries = "v23.p04.c40.service-request.boundaries"

        static let all = [screen, mode, draft, duplicates, dispositions, createWork, status, boundaries]
    }

    func testV23P04C40SemanticSelectorContractIsClosedAndUnique() {
        XCTAssertEqual(SemanticSelector.all.count, 8)
        XCTAssertEqual(Set(SemanticSelector.all).count, SemanticSelector.all.count)
        XCTAssertTrue(
            SemanticSelector.all.allSatisfy {
                $0.hasPrefix("v23.p04.c40.service-request.")
                    && $0 == $0.lowercased()
                    && !$0.contains(where: { $0.isWhitespace })
            }
        )
    }

    @MainActor
    func testV23P04C40TypedPreviewAndStatusInitializerShape() {
        let presentManual: (ServiceRequestManualPreviewV1) -> ServiceRequestPreviewPresentationV1 = {
            .manual($0)
        }
        let presentPortable: (ServiceRequestImportPreviewV1) -> ServiceRequestPreviewPresentationV1 = {
            .portable($0)
        }
        let initializeSurface: (
            ServiceRequestPreviewPresentationV1?,
            ServiceRequestStatusArtifactV1?
        ) -> ServiceRequestWorkflowView = { preview, statusArtifact in
            ServiceRequestWorkflowView(
                sourceKind: .phone,
                preview: preview,
                stateProjection: nil,
                statusArtifact: statusArtifact,
                onRefreshPreview: {},
                onCreateWork: {}
            )
        }

        XCTAssertNotNil(presentManual)
        XCTAssertNotNil(presentPortable)
        XCTAssertNotNil(initializeSurface)
    }

    @MainActor
    func testV23P04C40PhaseOneContainmentAndManualPreviewHaveNoImplicitEffects() async throws {
        #if DEBUG
        let fixture = try await makeFixture("c40-contained-manual-preview")
        defer { fixture.cleanUp() }
        // Seed real canonical content before measuring the contained surface.
        // The disposable fixture retains its live SwiftData store on cleanup.
        _ = try await makeWorkAsset(in: fixture, label: "c40-boundary")
        let writer = fixture.coordinator.workspaceWriter
        let context = fixture.coordinator.modelContext
        let manualDuplicates = C40ContainedManualDuplicates()
        let portableDuplicates = C40ContainedPortableDuplicates()
        let contacts = C40ContainedContacts()
        let canonical = ServiceRequestCoordinatorV1(
            duplicates: portableDuplicates,
            writer: writer,
            lifecycle: try ServiceRequestLifecycleAdapterV1(applicationSupportURL: fixture.support),
            contactPromotion: contacts,
            clock: C40ContainedClock(),
            idSource: C40ContainedIDs()
        )
        let workflow = ServiceRequestWorkflowCoordinatorV1(
            canonical: canonical, manualDuplicates: manualDuplicates, clock: C40ContainedClock())
        let initialScene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        try initialScene.restore()
        try initialScene.select(.today)
        let before = try C40ContainedSnapshot(fixture)
        XCTAssertGreaterThan(before.revision.revision, 0)
        XCTAssertFalse(before.receipts.isEmpty, "The preservation check has real prior receipts")
        XCTAssertEqual(before.serviceRequestCounts, [0, 0, 0])
        XCTAssertFalse(context.hasChanges)

        // No gate injection: observe positively loaded shipping Today and Work,
        // then test absence of the exact feature witness used below.
        var boundScene: AppShellSceneStateV1?
        var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: fixture.coordinator,
            contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
            sceneNavigationAccess: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: .init(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        shell.onProductionSceneBoundForTesting = { boundScene = $0 }
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let shipping = C40ContainedMountedHost(
            content: AnyView(shell.modelContext(context)), windowScene: windowScene)
        defer { shipping.unmount() }
        XCTAssertTrue(shipping.host.isViewLoaded)
        XCTAssertTrue(shipping.host.view.window === shipping.window)
        XCTAssertFalse(shipping.window.isHidden)
        let todayLoaded = await waitForMountedScreen(
            ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier,
            from: shipping.host)
        XCTAssertTrue(todayLoaded, "V23-P04-C40 requires a loaded shipping Today control")
        XCTAssertFalse(nativeScreenObservation(SemanticSelector.screen, from: shipping.host).found)
        let scene = try XCTUnwrap(boundScene)
        try scene.select(.work)
        let workLoaded = await waitForMountedScreen(
            ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: shipping.host)
        let completedWorkLoaded = await waitForMountedScreen(
            SignoffEnrollmentView.workRootAccessibilityIdentifier, from: shipping.host)
        XCTAssertTrue(workLoaded, "The real Work source has loaded")
        XCTAssertTrue(completedWorkLoaded, "The incumbent Completed work section is mounted")
        XCTAssertFalse(nativeScreenObservation(SemanticSelector.screen, from: shipping.host).found)
        XCTAssertEqual(try C40ContainedSnapshot(fixture), before)
        XCTAssertFalse(context.hasChanges)
        shipping.unmount()

        // These typed synthetic scope assertions are preview inputs, not proof
        // of live Site/Asset eligibility or permission to commit an intake.
        let intake = try C40ContainedInput.intake()
        let expected = WorkspaceExpectedRevisionV1(snapshot: before.revision)
        let outcome = try await workflow.execute(.previewManual(
            expectedRevision: expected, intake: intake, decision: .needsTriage,
            mutationID: C40ContainedInput.mutation(200)))
        guard case let .manualPreview(preview) = outcome else {
            XCTFail("The real workflow must return a manual preview")
            return
        }
        try preview.validate()
        XCTAssertTrue(preview.zeroWrite)
        XCTAssertEqual(preview.workspaceID, fixture.coordinator.workspaceID)
        XCTAssertEqual(preview.record.source, .phone)
        XCTAssertEqual(preview.record.body, intake.body)
        XCTAssertNil(preview.dispositionEvent)
        XCTAssertEqual(manualDuplicates.bases, [preview.record.recordSHA256])
        XCTAssertEqual(preview.duplicateProjection.basisRequestSHA256, preview.record.recordSHA256)
        XCTAssertTrue(preview.duplicateProjection.candidates.isEmpty)
        XCTAssertEqual(try C40ContainedSnapshot(fixture), before)
        XCTAssertFalse(context.hasChanges)

        let callbacks = C40ContainedCallbacks()
        let surface = ServiceRequestWorkflowView(sourceKind: .phone,
            preview: .manual(preview), stateProjection: nil,
            onRefreshPreview: {
                callbacks.refreshCount += 1
                do {
                    callbacks.refreshedPreview = try canonical.previewManualIntake(
                        expectedRevision: expected, intake: intake, decision: .needsTriage,
                        mutationID: C40ContainedInput.mutation(201),
                        projectDuplicates: { record in
                            try manualDuplicates.projectCandidates(
                                workspaceID: fixture.coordinator.workspaceID, record: record)
                        })
                } catch { callbacks.refreshError = error }
            },
            onCreateWork: { callbacks.createWorkCount += 1 })
        let contained = C40ContainedMountedHost(
            content: AnyView(NavigationStack { surface }.modelContext(context)),
            windowScene: windowScene)
        defer { contained.unmount() }
        XCTAssertTrue(contained.host.isViewLoaded)
        XCTAssertTrue(contained.host.view.window === contained.window)
        XCTAssertFalse(contained.window.isHidden)
        let containedLoaded = await waitForMountedScreen(SemanticSelector.screen, from: contained.host)
        XCTAssertTrue(containedLoaded, "The actual C40 body supplies the positive feature control")
        XCTAssertEqual(callbacks.refreshCount, 0, "Rendering must not refresh or commit an intake")
        XCTAssertEqual(callbacks.createWorkCount, 0, "Rendering must not implicitly create work")
        XCTAssertEqual(try C40ContainedSnapshot(fixture), before)
        XCTAssertFalse(context.hasChanges)

        // Exercise the supplied typed callback/domain path. This is not a UI
        // tap, Create-work eligibility check or live intake/adoption claim.
        surface.onRefreshPreview()
        XCTAssertEqual(callbacks.refreshCount, 1)
        XCTAssertNil(callbacks.refreshError)
        let refreshed = try XCTUnwrap(callbacks.refreshedPreview)
        try refreshed.validate()
        XCTAssertTrue(refreshed.zeroWrite)
        XCTAssertEqual(refreshed.workspaceID, preview.workspaceID)
        XCTAssertEqual(refreshed.record.source, .phone)
        XCTAssertEqual(refreshed.record.body, intake.body)
        XCTAssertNil(refreshed.dispositionEvent)
        XCTAssertEqual(manualDuplicates.bases, [preview.record.recordSHA256, refreshed.record.recordSHA256])
        XCTAssertEqual(refreshed.duplicateProjection.basisRequestSHA256, refreshed.record.recordSHA256)
        XCTAssertEqual(callbacks.createWorkCount, 0)
        XCTAssertEqual(portableDuplicates.calls, 0)
        XCTAssertEqual(contacts.calls, 0)
        XCTAssertEqual(try C40ContainedSnapshot(fixture), before)
        XCTAssertFalse(context.hasChanges)
        contained.unmount()
        XCTAssertEqual(try C40ContainedSnapshot(fixture), before)
        XCTAssertFalse(context.hasChanges)
        #else
        XCTFail("V23-P04-C40 requires the existing DEBUG native observation host; no behavior credit is available here")
        #endif
    }
}

#if DEBUG
private enum C40ContainedInput {
    static let date = Date(timeIntervalSince1970: 1_735_689_600)
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", value))!
    }
    static func mutation(_ value: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(value))
    }
    static func intake() throws -> ServiceRequestManualIntakeV1 {
        try .init(source: .phone,
            scope: .init(siteID: id(1), siteExpectedRevision: 1,
                siteSemanticSHA256: String(repeating: "a", count: 64),
                assets: [.init(assetID: id(2), expectedRevision: 1,
                    semanticSHA256: String(repeating: "b", count: 64))]),
            body: .init(requestText: "Synthetic door closer needs adjustment", urgency: .routine,
                requester: .init(displayName: "Synthetic requester"),
                contact: .init(value: "test@example.invalid"), category: "hardware"),
            mediaManifest: .init(entries: []))
    }
}

private struct C40ContainedClock: ApplicationClock {
    func now() -> Date { C40ContainedInput.date }
}

private final class C40ContainedIDs: ApplicationIDSource, @unchecked Sendable {
    private var next = 100
    func makeID() -> UUID {
        defer { next += 1 }
        return C40ContainedInput.id(next)
    }
}

@MainActor
private final class C40ContainedManualDuplicates: ServiceRequestManualDuplicateProjectingV1 {
    private(set) var bases: [String] = []
    func projectCandidates(workspaceID: WorkspaceID,
        record: ServiceRequestRecordV1) throws -> ServiceRequestDuplicateProjectionV1 {
        XCTAssertEqual(workspaceID, record.workspaceID)
        bases.append(record.recordSHA256)
        return try .init(basisRequestSHA256: record.recordSHA256,
            ruleReleaseSHA256: String(repeating: "d", count: 64), candidates: [])
    }
}

@MainActor
private final class C40ContainedPortableDuplicates: ServiceRequestDuplicateProjectingV1 {
    private(set) var calls = 0
    func projectCandidates(workspaceID: WorkspaceID,
        submission: PortableServiceRequestSubmissionV1,
        canonicalSourceSHA256: String) throws -> ServiceRequestDuplicateProjectionV1 {
        calls += 1
        throw ServiceRequestWorkflowFailureV1.invalidContext
    }
}

@MainActor
private final class C40ContainedContacts: ServiceRequestContactPromotionPreviewingV1 {
    private(set) var calls = 0
    func previewOperationalContactPromotion(request: ServiceRequestRecordV1,
        party: ServicePartyReferenceV1) throws -> ServiceRequestContactPromotionPreviewV1 {
        calls += 1
        throw ServiceRequestWorkflowFailureV1.invalidContext
    }
}

@MainActor
private final class C40ContainedCallbacks {
    var refreshCount = 0
    var createWorkCount = 0
    var refreshedPreview: ServiceRequestManualPreviewV1?
    var refreshError: Error?
}

private struct C40ContainedReceipt: Equatable {
    let workspaceMutationKey: String
    let record: MutationHistoryReceiptRecordV1
}

private struct C40ContainedSnapshot: Equatable {
    let revision: WorkspaceRevisionV1
    let receipts: [C40ContainedReceipt]
    let serviceRequestCounts: [Int]

    @MainActor
    init(_ fixture: V23ProductionMyDayPresentationHarness) throws {
        let context = fixture.coordinator.modelContext
        revision = try fixture.coordinator.workspaceWriter.currentRevision()
        receipts = try context.fetch(FetchDescriptor<MutationReceiptRow>())
            .sorted { $0.workspaceMutationKey < $1.workspaceMutationKey }
            .map { row in
                C40ContainedReceipt(workspaceMutationKey: row.workspaceMutationKey,
                    record: .init(envelopeData: row.envelopeData, receiptData: row.receiptData,
                        reversalBasisData: row.reversalBasisData,
                        semanticReversalData: row.semanticReversalData))
            }
        serviceRequestCounts = [
            try context.fetchCount(FetchDescriptor<ServiceRequestRecordRow>()),
            try context.fetchCount(FetchDescriptor<ServiceRequestDispositionEventRow>()),
            try context.fetchCount(FetchDescriptor<ServiceRequestWorkLinkEventRow>())
        ]
    }
}

@MainActor
private final class C40ContainedMountedHost {
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

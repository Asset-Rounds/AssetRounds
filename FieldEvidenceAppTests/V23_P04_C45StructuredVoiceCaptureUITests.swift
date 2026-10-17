import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

#if DEBUG
/// Owns only the hosted view's requests, not global microphone/permission effects.
@MainActor
private final class C45ContainedRequestsV1 {
    var actions: VoicePushToTalkCaptureActionsForTestingV1?
    var commands: [VoicePushToTalkCaptureCommandV1] = []

    var captureRequestCount: Int {
        commands.filter {
            switch $0 {
            case .start, .stop, .cancel, .retry: return true
            default: return false
            }
        }.count
    }
}

@MainActor
private final class C45MountedSurfaceV1 {
    let host: UIHostingController<AnyView>
    let window: UIWindow
    private let previous: UIWindow?
    private var mounted = true

    init(_ content: AnyView, scene: UIWindowScene) {
        previous = scene.windows.first { $0.isKeyWindow }
        host = UIHostingController(rootView: content)
        window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
    }

    func unmount() {
        guard mounted else { return }
        mounted = false
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
    }
}

/// The incumbent Work fixture obtains a real draft through the one live writer.
@MainActor
private final class C45ExistingDraftV1 {
    let fixture: WorkCanonicalOpenIssueFixtureV1
    let work: WorkCoordinator
    let draft: WorkDraftValue
    let revision: WorkspaceRevisionV1
    let history: MutationHistorySnapshotV1
    let recordCount: Int
    let issueCount: Int
    let targetRevision: UInt64

    init(fixture: WorkCanonicalOpenIssueFixtureV1, work: WorkCoordinator,
         draft: WorkDraftValue) throws {
        self.fixture = fixture
        self.work = work
        self.draft = draft
        // beginWork is deliberate setup and can create a canonical draft.
        // All zero-write comparisons start after that setup, never before it.
        let snapshot = try fixture.storeCoordinator.workspaceWriter.currentRevision()
        revision = snapshot
        history = try fixture.storeCoordinator.workspaceWriter.sourceMutationHistorySnapshot()
        recordCount = try fixture.context.fetchCount(FetchDescriptor<WorkflowRecord>())
        issueCount = try fixture.context.fetchCount(FetchDescriptor<Issue>())
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: fixture.assetID)
        targetRevision = try XCTUnwrap(snapshot.entityRevisions.first {
            $0.identity == identity
        }).revision
    }

    func cleanUp() {
        try? fixture.storeCoordinator.invalidateAndReleaseWriter()
        try? FileManager.default.removeItem(at: fixture.applicationSupportURL)
    }
}
#endif

final class V23_P04_C45StructuredVoiceCaptureUITests: V23ProductionFourRootShellTestSupport {
    func testV23P04C45ContainedSurfaceAccessibilityContract() {
        XCTAssertEqual(VoicePushToTalkCaptureView.fixedAccessibilityIdentifiers, [
            "v23.p04.c45.structured-voice-capture.screen", "v23.p04.c45.structured-voice-capture.draft", "v23.p04.c45.structured-voice-capture.speak-details", "v23.p04.c45.structured-voice-capture.capture", "v23.p04.c45.structured-voice-capture.stop", "v23.p04.c45.structured-voice-capture.countdown", "v23.p04.c45.structured-voice-capture.processing", "v23.p04.c45.structured-voice-capture.transcript", "v23.p04.c45.structured-voice-capture.fields", "v23.p04.c45.structured-voice-capture.manual-fallback", "v23.p04.c45.structured-voice-capture.recovery", "v23.p04.c45.structured-voice-capture.error", "v23.p04.c45.structured-voice-capture.status", "v23.p04.c45.structured-voice-capture.finish-review", "v23.p04.c45.structured-voice-capture.cancel", "v23.p04.c45.structured-voice-capture.reject-proposal", "v23.p04.c45.structured-voice-capture.boundaries", "v23.p04.c45.structured-voice-capture.manual-fallback.field"
        ])
        XCTAssertEqual(VoicePushToTalkCaptureView.fieldAccessibilityIdentifierPrefix, "v23.p04.c45.structured-voice-capture.field.")
        XCTAssertEqual(VoicePushToTalkCaptureView.fieldReviewAccessibilityIdentifierPrefix, "v23.p04.c45.structured-voice-capture.field-review.")
    }

    // This replaces the stale unconditional live-adoption deferral with an
    // explicitly Phase 1 boundary question. It does not pass the later live
    // existing-draft -> microphone -> transcript -> C56 review journey.
    // That complete journey, real permissions/effects, lifecycle/target fences,
    // scratch cleanup, accessibility and qualified UI/owner evidence stay PENDING.
    @MainActor
    func testV23P04C45PhaseOneShippingShellAndExistingDraftHaveNoCaptureEntry() async throws {
        #if DEBUG
        let shellFixture = try await makeFixture("c45-phase-one")
        defer { shellFixture.cleanUp() }
        _ = try await makeWorkAsset(in: shellFixture, label: "c45-existing-asset")
        let before = try shellFixture.coordinator.workspaceWriter.currentRevision()
        let history = try shellFixture.coordinator.workspaceWriter.sourceMutationHistorySnapshot()
        var boundScene: AppShellSceneStateV1?
        var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: shellFixture.coordinator,
            contentAccess: try XCTUnwrap(shellFixture.presentation.renderAccess),
            sceneNavigationAccess: try XCTUnwrap(shellFixture.presentation.sceneNavigationAccess),
            myDayAccess: try XCTUnwrap(shellFixture.presentation.myDayAccess),
            diagnosticsStore: shellFixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: shellFixture.router.entitlementProcessor)
        shell.onProductionSceneBoundForTesting = { boundScene = $0 }
        // No gate injection: observe the same default composition as shipping.
        let mountedShell = try mountC45(AnyView(shell.modelContext(shellFixture.coordinator.modelContext)))
        defer { mountedShell.unmount() }
        let sceneBound = await waitForC45 { boundScene != nil }
        XCTAssertTrue(sceneBound)
        let scene = try XCTUnwrap(boundScene)
        for root in AppRootV1.frozenOrder {
            try scene.select(root)
            let loaded: Bool
            switch root {
            case .today:
                loaded = await waitForMountedScreen(
                    ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier,
                    from: mountedShell.host)
            case .work:
                loaded = await waitForMountedScreen(
                    ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: mountedShell.host)
            case .assets:
                loaded = await waitForAccessibilityIdentifier(
                    SignDetailView.screenAccessibilityIdentifier, in: mountedShell.host.view)
            case .reports:
                loaded = await waitForAccessibilityIdentifier(
                    ReportsRootView.screenAccessibilityIdentifier, in: mountedShell.host.view)
            }
            XCTAssertTrue(loaded, "A real shipping root loaded before testing C45 absence: \(root)")
            assertNoC45CaptureSurface(in: mountedShell)
        }
        XCTAssertEqual(try shellFixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try shellFixture.coordinator.workspaceWriter.sourceMutationHistorySnapshot(), history)
        XCTAssertFalse(shellFixture.coordinator.modelContext.hasChanges)
        mountedShell.unmount()

        let existing = try await makeC45ExistingDraft()
        defer { existing.cleanUp() }
        var completionCount = 0
        let record = RecordWorkView(draft: existing.draft, coordinator: existing.work,
            usesImportedFixtureForUITest: false) { _ in completionCount += 1 }
        let mountedDraft = try mountC45(AnyView(NavigationStack { record }))
        defer { mountedDraft.unmount() }
        let draftLoaded = await waitForMountedScreen(
            RecordWorkView.screenAccessibilityIdentifier, from: mountedDraft.host)
        XCTAssertTrue(draftLoaded, "The actual incumbent draft surface is loaded")
        assertNoC45CaptureSurface(in: mountedDraft)
        XCTAssertEqual(completionCount, 0)
        try assertC45DraftPreserved(existing)
        mountedDraft.unmount()

        // Positive control for the SAME C45 screen/action observations above.
        // A contained, supplied context renders the real Speak details button;
        // no button is pressed and no capture adapter is constructed.
        let requests = C45ContainedRequestsV1()
        let context = try c45Context(existing)
        let control = try mountC45Projection(.init(draft: c45Draft(existing),
            captureContext: context, state: .ready), requests: requests)
        defer { control.unmount() }
        let controlLoaded = await waitForMountedScreen(
            VoicePushToTalkCaptureView.screenAccessibilityIdentifier, from: control.host)
        let draftContextLoaded = await waitForMountedScreen(
            VoicePushToTalkCaptureView.draftAccessibilityIdentifier, from: control.host)
        let captureAction = await waitForMountedScreen(
            VoicePushToTalkCaptureView.speakDetailsAccessibilityIdentifier, from: control.host)
        XCTAssertTrue(controlLoaded)
        XCTAssertTrue(draftContextLoaded)
        XCTAssertTrue(captureAction, "The feature-specific action witness is observable when composed")
        let actions = try await c45Actions(requests)
        XCTAssertTrue(actions.speakDetailsButtonPresent)
        XCTAssertTrue(actions.speakDetailsEnabled)
        XCTAssertEqual(actions.state.model.draft.draftID, existing.draft.recordID)
        XCTAssertEqual(actions.state.model.captureContext, context)
        XCTAssertTrue(requests.commands.isEmpty)
        XCTAssertEqual(requests.captureRequestCount, 0, "Only this view's typed requests are counted")
        try assertC45DraftPreserved(existing)
        #else
        throw XCTSkip("Phase 1 mounted C45 boundary observations require the DEBUG host")
        #endif
    }

    @MainActor
    func testV23P04C45ContainedManualFallbackEmitsOnlyExplicitBoundedRequests() async throws {
        #if DEBUG
        let existing = try await makeC45ExistingDraft()
        defer { existing.cleanUp() }
        for state in [VoicePushToTalkCaptureStateV1.manualFallback, .permissionDenied, .unsupported] {
            let requests = C45ContainedRequestsV1()
            let mounted = try mountC45Projection(.init(draft: c45Draft(existing),
                state: state, canStartCapture: false), requests: requests)
            defer { mounted.unmount() }
            let fieldLoaded = await waitForMountedScreen(
                VoicePushToTalkCaptureView.manualEntryFieldAccessibilityIdentifier, from: mounted.host)
            let continueLoaded = await waitForMountedScreen(
                VoicePushToTalkCaptureView.manualFallbackAccessibilityIdentifier + ".continue", from: mounted.host)
            XCTAssertTrue(fieldLoaded)
            XCTAssertTrue(continueLoaded)
            let initial = try await c45Actions(requests)
            XCTAssertFalse(initial.speakDetailsButtonPresent)
            XCTAssertFalse(initial.speakDetailsEnabled)
            XCTAssertFalse(nativeScreenObservation(
                VoicePushToTalkCaptureView.speakDetailsAccessibilityIdentifier, from: mounted.host).found)
            XCTAssertNil(initial.state.model.captureContext)
            XCTAssertEqual(initial.state.manualText, "Existing typed draft")
            XCTAssertTrue(requests.commands.isEmpty, "Mounting the fallback cannot submit it")

            initial.manualText.wrappedValue = "  Manual correction\n"
            let typed = await waitForC45 { requests.actions?.state.manualText == "  Manual correction\n" }
            XCTAssertTrue(typed)
            XCTAssertTrue(requests.commands.isEmpty, "Typing uses the real binding without submitting")
            let current = try XCTUnwrap(requests.actions)
            try XCTUnwrap(current.continueManualEntry)()
            XCTAssertEqual(requests.commands, [.manualEntry(text: "Manual correction")])

            current.manualText.wrappedValue = " \n "
            let emptyTyped = await waitForC45 { requests.actions?.state.manualText == " \n " }
            XCTAssertTrue(emptyTyped)
            try XCTUnwrap(requests.actions?.continueManualEntry)()
            let emptyRejected = await waitForC45 { requests.actions?.state.errorMessage != nil }
            XCTAssertTrue(emptyRejected)
            let errorRendered = await waitForMountedScreen(
                VoicePushToTalkCaptureView.errorAccessibilityIdentifier, from: mounted.host)
            XCTAssertTrue(errorRendered, "Validation exposes the real error surface")
            XCTAssertEqual(requests.commands, [.manualEntry(text: "Manual correction")])

            let oversized = String(repeating: "x", count: VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes + 1)
            let manualBinding = try XCTUnwrap(requests.actions).manualText
            manualBinding.wrappedValue = oversized
            let oversizedTyped = await waitForC45 { requests.actions?.state.manualText == oversized }
            XCTAssertTrue(oversizedTyped)
            try XCTUnwrap(requests.actions?.continueManualEntry)()
            XCTAssertEqual(requests.commands, [.manualEntry(text: "Manual correction")])
            XCTAssertEqual(requests.captureRequestCount, 0)
            try assertC45DraftPreserved(existing)
            mounted.unmount()
        }
        #else
        throw XCTSkip("Contained C45 action bindings require the DEBUG host")
        #endif
    }

    @MainActor
    func testV23P04C45ContainedFieldReviewEmitsExactRequestsAndHonorsUnavailableState() async throws {
        #if DEBUG
        let existing = try await makeC45ExistingDraft()
        defer { existing.cleanUp() }
        let context = try c45Context(existing)
        let proposal = try c45Proposal(context)
        let requests = C45ContainedRequestsV1()
        let mounted = try mountC45Projection(.init(draft: c45Draft(existing),
            state: .review, proposal: proposal, canStartCapture: false), requests: requests)
        defer { mounted.unmount() }
        for suffix in ["accept", "edit", "reject"] {
            let actionLoaded = await waitForMountedScreen(
                VoicePushToTalkCaptureView.fieldReviewAccessibilityIdentifierPrefix + "note." + suffix,
                from: mounted.host)
            XCTAssertTrue(actionLoaded, "The actual field control is composed: \(suffix)")
        }
        let initial = try await c45Actions(requests)
        XCTAssertTrue(requests.commands.isEmpty, "Presenting a proposal cannot accept a field")
        XCTAssertFalse(initial.finishReviewEnabled)
        XCTAssertEqual(proposal.fields.count, 1)
        let field = try XCTUnwrap(initial.fields.first)
        XCTAssertEqual(field.fieldID, "note")
        try XCTUnwrap(field.accept)()
        let accepted = try VoiceProposalFieldReviewV1(fieldID: "note", disposition: .accept,
            reviewedValue: .text("checked"))
        XCTAssertEqual(requests.commands, [.acceptField(proposalID: proposal.proposalID, review: accepted)])

        try XCTUnwrap(requests.actions?.fields.first?.edit)()
        let editing = await waitForC45 { requests.actions?.state.editingFieldID == "note" }
        XCTAssertTrue(editing)
        for suffix in ["edit-field", "apply-edit", "cancel-edit"] {
            let controlLoaded = await waitForMountedScreen(
                VoicePushToTalkCaptureView.fieldReviewAccessibilityIdentifierPrefix + "note." + suffix,
                from: mounted.host)
            XCTAssertTrue(controlLoaded, "The actual edit control is composed: \(suffix)")
        }
        let editingField = try XCTUnwrap(requests.actions?.fields.first)
        let editBinding = try XCTUnwrap(editingField.editedText)
        editBinding.wrappedValue = "  Corrected by keyboard\n"
        let edited = await waitForC45 { requests.actions?.state.editedValues["note"] == "  Corrected by keyboard\n" }
        XCTAssertTrue(edited)
        XCTAssertEqual(requests.commands.count, 1, "Editing is local until Apply")
        try XCTUnwrap(requests.actions?.fields.first?.cancelEdit)()
        let cancelled = await waitForC45 { requests.actions?.state.editingFieldID == nil }
        XCTAssertTrue(cancelled)
        XCTAssertEqual(requests.commands.count, 1, "Cancel edit sends no review request")

        try XCTUnwrap(requests.actions?.fields.first?.edit)()
        let editingAgain = await waitForC45 { requests.actions?.state.editingFieldID == "note" }
        XCTAssertTrue(editingAgain)
        try XCTUnwrap(requests.actions?.fields.first?.applyEdit)()
        let applied = await waitForC45 { requests.actions?.state.editingFieldID == nil }
        XCTAssertTrue(applied)
        XCTAssertEqual(requests.commands.last, .editField(proposalID: proposal.proposalID,
            fieldID: "note", fieldKind: .noteText, valueText: "Corrected by keyboard"))
        try XCTUnwrap(requests.actions?.fields.first?.reject)()
        let rejected = try VoiceProposalFieldReviewV1(fieldID: "note", disposition: .reject, reviewedValue: nil)
        XCTAssertEqual(requests.commands, [
            .acceptField(proposalID: proposal.proposalID, review: accepted),
            .editField(proposalID: proposal.proposalID, fieldID: "note", fieldKind: .noteText,
                valueText: "Corrected by keyboard"),
            .rejectField(proposalID: proposal.proposalID, review: rejected),
        ])
        XCTAssertFalse(try XCTUnwrap(requests.actions).finishReviewEnabled,
            "Requests do not invent caller-returned reviewed state or completion")
        XCTAssertEqual(requests.captureRequestCount, 0)
        try assertC45DraftPreserved(existing)
        mounted.unmount()

        let unavailable: [(VoicePushToTalkCaptureStateV1, VoicePushToTalkDraftStateV1,
                           Bool, VoicePushToTalkOperationStateV1)] = [
            (.review, .stale, true, .idle),
            (.review, .current, false, .idle),
            (.review, .current, true, .awaitingReceipt),
            (.review, .current, true, .stale),
            (.staleTarget, .current, true, .idle),
        ]
        for (state, draftState, editable, operation) in unavailable {
            let blocked = C45ContainedRequestsV1()
            let surface = try mountC45Projection(.init(
                draft: c45Draft(existing, state: draftState, canEdit: editable), state: state,
                proposal: proposal, operation: .init(state: operation), canStartCapture: false), requests: blocked)
            defer { surface.unmount() }
            let blockedActionRendered = await waitForMountedScreen(
                VoicePushToTalkCaptureView.fieldReviewAccessibilityIdentifierPrefix + "note.accept", from: surface.host)
            XCTAssertTrue(blockedActionRendered, "The actual unavailable field control is composed")
            let blockedActions = try await c45Actions(blocked)
            let blockedField = try XCTUnwrap(blockedActions.fields.first)
            XCTAssertNil(blockedField.accept)
            XCTAssertNil(blockedField.edit)
            XCTAssertNil(blockedField.applyEdit)
            XCTAssertNil(blockedField.reject)
            XCTAssertFalse(blockedActions.finishReviewEnabled)
            if !editable { XCTAssertNil(blockedActions.continueManualEntry) }
            XCTAssertTrue(blocked.commands.isEmpty)
            try assertC45DraftPreserved(existing)
            surface.unmount()
        }
        #else
        throw XCTSkip("Contained C45 action bindings require the DEBUG host")
        #endif
    }
}

#if DEBUG
private extension V23_P04_C45StructuredVoiceCaptureUITests {
    @MainActor
    func mountC45(_ content: AnyView) throws -> C45MountedSurfaceV1 {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return C45MountedSurfaceV1(content, scene: scene)
    }

    @MainActor
    func mountC45Projection(_ projection: VoicePushToTalkCaptureProjectionV1,
                           requests: C45ContainedRequestsV1) throws -> C45MountedSurfaceV1 {
        var view = VoicePushToTalkCaptureView(model: projection) { requests.commands.append($0) }
        view.onActionsBoundForTesting = { requests.actions = $0 }
        return try mountC45(AnyView(NavigationStack { view }))
    }

    @MainActor
    func waitForC45(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return predicate()
    }

    @MainActor
    func c45Actions(_ requests: C45ContainedRequestsV1) async throws -> VoicePushToTalkCaptureActionsForTestingV1 {
        let bound = await waitForC45 { requests.actions != nil }
        XCTAssertTrue(bound, "Actions are bound by the mounted C45 view")
        return try XCTUnwrap(requests.actions)
    }

    @MainActor
    func assertNoC45CaptureSurface(in mounted: C45MountedSurfaceV1,
                                  file: StaticString = #filePath, line: UInt = #line) {
        for identifier in [VoicePushToTalkCaptureView.screenAccessibilityIdentifier,
                           VoicePushToTalkCaptureView.speakDetailsAccessibilityIdentifier] {
            XCTAssertFalse(nativeScreenObservation(identifier, from: mounted.host).found,
                "The loaded shipping surface does not compose C45: \(identifier)", file: file, line: line)
        }
    }

    @MainActor
    func makeC45ExistingDraft() async throws -> C45ExistingDraftV1 {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("C45-ExistingDraft-\(UUID())")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
        var fixture: WorkCanonicalOpenIssueFixtureV1?
        do {
            let opened = try await WorkCanonicalOpenIssueFixtureV1.make(
                applicationSupportURL: support, pack: .illuminatedSignV1)
            fixture = opened
            let work = try WorkCoordinator(modelContext: opened.context, signPack: .illuminatedSignV1,
                generationRootURL: opened.session.generationRootURL,
                checkRunnerCoordinator: opened.runner, lifecycleDependencies: opened.lifecycleDependencies)
            return try C45ExistingDraftV1(fixture: opened, work: work,
                draft: work.beginWork(issueID: opened.issueID))
        } catch {
            try? fixture?.storeCoordinator.invalidateAndReleaseWriter()
            try? FileManager.default.removeItem(at: support)
            throw error
        }
    }

    @MainActor
    func assertC45DraftPreserved(_ existing: C45ExistingDraftV1,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try existing.fixture.storeCoordinator.workspaceWriter.currentRevision(), existing.revision,
            file: file, line: line)
        XCTAssertEqual(try existing.fixture.storeCoordinator.workspaceWriter.sourceMutationHistorySnapshot(), existing.history,
            file: file, line: line)
        XCTAssertEqual(try existing.fixture.context.fetchCount(FetchDescriptor<WorkflowRecord>()), existing.recordCount,
            file: file, line: line)
        XCTAssertEqual(try existing.fixture.context.fetchCount(FetchDescriptor<Issue>()), existing.issueCount,
            file: file, line: line)
        XCTAssertFalse(existing.fixture.context.hasChanges, file: file, line: line)
    }

    @MainActor
    func c45Draft(_ existing: C45ExistingDraftV1, state: VoicePushToTalkDraftStateV1 = .current,
                  canEdit: Bool = true) -> VoicePushToTalkDraftPresentationV1 {
        .init(draftID: existing.draft.recordID, label: "Existing Work draft",
            targetRevision: existing.targetRevision, manualText: "Existing typed draft", state: state, canEdit: canEdit)
    }

    @MainActor
    func c45Context(_ existing: C45ExistingDraftV1) throws -> StructuredVoiceCaptureContextV1 {
        try .init(sessionID: UUID(), capability: .init(capabilityID: "STRUCTURED_VOICE_PROPOSAL",
            version: "STRUCTURED_VOICE_V1", localeIdentifier: "en-US"),
            workspaceID: existing.fixture.storeCoordinator.workspaceID,
            entity: .init(kind: .asset, id: existing.fixture.assetID), targetRevision: existing.targetRevision,
            lifecycleGeneration: .init(permissionGenerationID: UUID(), audioGenerationID: UUID(),
                applicationGenerationID: UUID(), protectedDataGenerationID: UUID(), eraseGenerationID: UUID()))
    }

    @MainActor
    func c45Proposal(_ context: StructuredVoiceCaptureContextV1) throws -> StructuredVoiceProposalV1 {
        let now = Date(timeIntervalSince1970: 1_788_451_200)
        let proposalID = UUID()
        let grammar = try VoiceStructuringGrammarReleaseV1(grammarID: "C45_CONTAINED_EN_US", version: 1,
            localeIdentifier: "en-US", aliases: [.init(spokenAlias: "note", fieldID: "note", fieldKind: .noteText)],
            releasedAt: now)
        let entry = try VoiceStructuringGrammarRegistryEntryV1(release: grammar,
            semanticFields: [.init(purpose: .note)])
        let service = try VoiceStructuringServiceV1(registry: .init(entries: [entry]),
            grammarID: grammar.grammarID, version: grammar.version, localeIdentifier: grammar.localeIdentifier,
            releaseSHA256: grammar.releaseSHA256, now: { now }, makeID: { proposalID })
        let transcript = "note: checked"
        let source = try AssistanceSourceReferenceV1(kind: .leasedScratch, sourceID: "c45-contained-transcript",
            revision: 1, contentSHA256: KernelCanonicalHashV1.sha256(Data(transcript.utf8)))
        return try service.structure(transcript: transcript, context: context.proposalContext(source: source))
    }
}
#endif

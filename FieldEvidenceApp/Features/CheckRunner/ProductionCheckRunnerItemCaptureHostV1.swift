import Combine
import Foundation
import SwiftUI

struct CheckRunnerItemPreflightPresentationV1 {
    let snapshot: FirstSignSnapshot
    let pack: SignPack
}

enum ProductionCheckRunnerItemCaptureFailureV1: Error, Equatable {
    case operationInProgress, missingEditor, retired
}

/// One scene's owner for the existing durable editor and parent service.
/// Construction and restoration only read; explicit actions own every write.
@MainActor
final class ProductionCheckRunnerItemCapturePresentationV1: ObservableObject {
    let source: CheckRunnerRoundItemSourceV1
    let service: ProductionCheckRunnerItemDraftServiceV1
    private let access: AppAccessPresentationV1.RoundAccess
    private let scene: AppShellSceneStateV1
    private let target: NavigationTargetV1
    private var editorObservation: AnyCancellable?
    private var retired = false

    @Published private var retainedCheckpoint: FieldDraftCheckpointV1?
    @Published private(set) var editor: CheckRunnerItemEditingSessionV1?
    @Published private(set) var isPerformingAction = false
    @Published private(set) var preflight: CheckRunnerItemPreflightPresentationV1?

    var checkpoint: FieldDraftCheckpointV1? { editor?.acknowledgement.checkpoint ?? retainedCheckpoint }

    init(source: CheckRunnerRoundItemSourceV1, target: NavigationTargetV1,
         scene: AppShellSceneStateV1, access: AppAccessPresentationV1.RoundAccess) throws {
        self.source = source
        self.target = target
        self.scene = scene
        self.access = access
        self.service = try access.makeCheckRunnerItemService(source: source)
        let operation = try captureOperation()
        try installCurrentRead(authorizing: operation)
    }

    /// Called only for an explicit entry action. A prior acknowledged parent
    /// wins over creating another after a lost response or restored scene.
    func startEditing(preflight: CheckRunnerEditablePreflightV1,
                      outcome: CheckRunnerEditableOutcomeV1 = .init()) throws {
        try requireIdle()
        let operation = try captureOperation()
        guard editor == nil else { return }
        try operation.withAuthorization {
            if try service.readCurrentDraft(source: source) == nil {
                _ = try service.create(source: source, preflight: preflight, outcome: outcome)
            }
        }
        try installCurrentRead(authorizing: operation)
    }

    func replaceEditableValues(_ values: CheckRunnerEditableItemValuesV1) throws {
        try requireIdle()
        guard let editor else { throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor }
        try editor.replaceEditableValues(values)
    }

    /// The actual synchronous navigation effect shares the original operation
    /// with its final proof check; an await cannot silently refresh authority.
    func flushAndPerform(reason: CheckRunnerFieldFlushReasonV1,
                         action: @MainActor () throws -> Void) async throws {
        try requireIdle()
        guard let editor else { throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor }
        let operation = try captureOperation()
        isPerformingAction = true
        defer { isPerformingAction = false }
        let proof = try await editor.forceFlushAndReadBack(reason: reason)
        try editor.validateForPublication(proof)
        try operation.withAuthorization {
            try requireActive()
            guard self.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
            try service.validateForPublication(proof.parent)
            try action()
        }
    }

    func begin(observedAtUTC: Date) async throws {
        try requireIdle()
        guard let editor else { throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor }
        let operation = try captureOperation()
        isPerformingAction = true
        defer { isPerformingAction = false }
        let proof = try await editor.forceFlushAndReadBack(reason: .begin)
        try editor.validateForPublication(proof)
        try operation.withAuthorization {
            try requireActive()
            guard self.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
            try service.validateForPublication(proof.parent)
            let prepared = try service.prepareBegin(draftID: proof.parent.checkpoint.draftID,
                expectedCheckpointSHA256: proof.parent.checkpoint.checkpointSHA256,
                observedAtUTC: observedAtUTC)
            _ = try service.resumeInitialBegin(draftID: prepared.draftID)
        }
        // The old acknowledgement belongs to the pre-Begin parent. Do not
        // publish it as current or leave its scheduler able to write afterward.
        await editor.retire()
        try requireActive()
        try installCurrentRead(authorizing: operation)
    }

    /// Explicit retry/reopen after a parent command. Unsaved input is never
    /// discarded by a background refresh or a new current-writer observation.
    func reload() async throws {
        try requireIdle()
        guard editor?.hasUnacknowledgedEdits != true else {
            throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint
        }
        let operation = try captureOperation()
        isPerformingAction = true
        defer { isPerformingAction = false }
        await editor?.retire()
        try requireActive()
        try installCurrentRead(authorizing: operation)
    }

    func retire() async {
        retired = true
        editorObservation = nil
        await editor?.retire()
    }

    private func captureOperation() throws -> AppAccessPresentationV1.CheckRunnerItemOperationAccess {
        try requireActive()
        return try access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target)
    }

    private func installCurrentRead(authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
        let current = try operation.withAuthorization { try service.readCurrentDraft(source: source) }
        let next: CheckRunnerItemEditingSessionV1?
        var fieldRead: CheckRunnerFieldReadbackV1?
        if let current, current.state == .active,
           try CheckRunnerItemDraftCodecV1.validateCheckpoint(current).phase == .editing {
            let read = try operation.withAuthorization { try service.readEditableFields(draftID: current.draftID) }
            fieldRead = read
            next = try CheckRunnerItemEditingSessionV1(service: service, initialRead: read,
                captureOperation: { [access, service, scene, target] in
                    try CheckRunnerFieldOperationAuthorizationV1(scope:
                        access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target))
                })
        } else {
            next = nil
        }
        // Editor construction validates its own captured operation outside the
        // host's read hold. Never nest two independently captured content locks.
        try operation.withAuthorization {
            guard try service.readCurrentDraft(source: source) == current else {
                throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint
            }
            if let fieldRead { try service.validateForPublication(fieldRead) }
            let presentation = try service.readPreflightPresentation(source: source)
            editorObservation = next?.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            retainedCheckpoint = current
            editor = next
            preflight = presentation
        }
    }

    private func requireActive() throws {
        try Task.checkCancellation()
        guard !retired else { throw ProductionCheckRunnerItemCaptureFailureV1.retired }
    }

    private func requireIdle() throws {
        try requireActive()
        guard !isPerformingAction else { throw ProductionCheckRunnerItemCaptureFailureV1.operationInProgress }
    }
}

/// The existing preflight renderer receives explicit durable actions. The
/// enclosing capture destination owns the post-Begin screen and navigation.
@MainActor
struct ProductionCheckRunnerItemPreflightViewV1: View {
    @ObservedObject var state: ProductionCheckRunnerItemCapturePresentationV1
    let leave: @MainActor () throws -> Void

    var body: some View {
        if let editor = state.editor, let presentation = state.preflight {
            PreflightView(snapshot: presentation.snapshot, pack: presentation.pack,
                durable: .init(values: { editor.values.preflight }, update: { fields in
                    guard state.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
                    try state.replaceEditableValues(.init(preflight: fields, outcome: editor.values.outcome,
                        semanticAnchor: editor.values.semanticAnchor))
                }, begin: {
                    guard state.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
                    let instant = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1_000).rounded(.down) / 1_000)
                    try await state.begin(observedAtUTC: instant)
                }, leave: {
                    guard state.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
                    try await state.flushAndPerform(reason: .back, action: leave)
                }))
                .disabled(state.isPerformingAction)
                .safeAreaInset(edge: .bottom) {
                    Text(durabilityLabel(editor.durabilityState))
                        .font(DesignTokens.Typography.supportingCaption)
                        .padding(DesignTokens.Spacing.space8)
                        .frame(maxWidth: .infinity)
                        .background(DesignTokens.SemanticColors.workBackground)
                        .accessibilityIdentifier("v23.check-runner.preflight.durability")
                }
        } else {
            AssetRoundsEmptyState(title: Text("Check unavailable"),
                message: Text("Your saved check could not be opened."))
        }
    }

    private func durabilityLabel(_ state: DraftDurabilityPresentationStateV1) -> String {
        switch state {
        case .unsavedChanges: "Unsaved changes"
        case .savingOnThisIPhone: "Saving on this iPhone"
        case .savedOnThisIPhone: "Saved on this iPhone"
        case .saveBlocked: "Changes have not been saved"
        case .committing: "Saving check"
        case .conflicted: "Check changed elsewhere; review required"
        case .recoveryRequired: "Recovery review required"
        case .committed: "Check saved"
        case .discarding: "Discard pending"
        case .discarded: "Draft discarded"
        }
    }
}

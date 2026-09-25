import Combine
import Foundation
import SwiftUI

struct CheckRunnerItemPreflightPresentationV1 {
    let snapshot: FirstSignSnapshot
    let pack: SignPack
}

/// Read-only outcome choices for the durable Outcome screen.
struct CheckRunnerItemOutcomePresentationV1 {
    let stage: WorkflowStage
    let issueLabels: [SignPack.RegistryEntry]
    let couldNotVerifyReasons: [SignPack.RegistryEntry]
    let outcomeDisplays: [String: String]

    var isRecheck: Bool { stage == .recheck }
    func outcomeDisplay(_ key: String) -> String { outcomeDisplays[key] ?? key }
}

/// The durable position of one item, derived only from its validated parent.
enum ProductionCheckRunnerItemCaptureStageV1: Equatable {
    case unavailable
    case preflight
    case interruptedBegin
    case capture(WorkflowDraftStep)
    case pendingPhoto(WorkflowDraftStep)
    /// `photosIncomplete` means only Could not verify can be reviewed.
    case outcome(photosIncomplete: Bool)
    case preparedFinalization
    case completed
}

/// The one pending photo child of the current parent and its saved phase.
struct ProductionCheckRunnerPendingPhotoV1: Equatable {
    let childDraftID: UUID
    let step: WorkflowDraftStep
    let checkpoint: FieldDraftCheckpointV1
    let phase: CheckRunnerPhotoDurablePhaseV1

    /// Source bytes were never staged; only an explicit removal can continue.
    var needsSourceAgain: Bool {
        if case .awaitingRawStage = phase { return true }
        return false
    }
}

enum ProductionCheckRunnerItemCaptureFailureV1: Error, Equatable {
    case operationInProgress, missingEditor, retired, notPreparedBegin
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
    @Published private(set) var outcomePresentation: CheckRunnerItemOutcomePresentationV1?
    @Published private(set) var capturePreparation: CapturePreparation?
    @Published private(set) var pendingPhoto: ProductionCheckRunnerPendingPhotoV1?
    /// Bytes selected in this scene, for preview only; never restored or persisted.
    @Published private(set) var selectedPhotoPreview: Data?

    var checkpoint: FieldDraftCheckpointV1? { editor?.acknowledgement.checkpoint ?? retainedCheckpoint }

    /// The durable Begin state, or nil when no parent is presented or it fails
    /// validation. The parent stays in its editing phase after Begin, so
    /// presentation never infers Preflight from editor availability.
    var durableBegin: CheckRunnerBeginStateV1? {
        guard let checkpoint else { return nil }
        return try? CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint).field.begin
    }

    /// Only a receipt-bound Begin has started the check. An interrupted
    /// PREPARED Begin admits no field edit or flush; see `finishPreparedBegin`.
    var hasBoundBegin: Bool {
        if case .bound = durableBegin { return true }
        return false
    }

    var hasPreparedBegin: Bool {
        if case .prepared = durableBegin { return true }
        return false
    }

    /// Derived from the validated parent and the editor's current values; no
    /// read writes, opens the camera or advances Begin/finalization.
    var stage: ProductionCheckRunnerItemCaptureStageV1 {
        guard let checkpoint,
              let payload = try? CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint) else { return .unavailable }
        if checkpoint.state == .committed { return .completed }
        guard checkpoint.state == .active else { return .unavailable }
        if payload.phase == .preparedFinalization { return .preparedFinalization }
        switch payload.field.begin {
        case .notBegun: return editor == nil ? .unavailable : .preflight
        case .prepared: return .interruptedBegin
        case .bound: break
        }
        guard let editor else { return .unavailable }
        var photosIncomplete = false
        for (slot, step) in [(payload.field.wideContext, WorkflowDraftStep.wide), (payload.field.closeDetail, .close)] {
            switch slot {
            case .committed?: continue
            case .pending?: return .pendingPhoto(step)
            case nil:
                if [.outcome, .review].contains(editor.values.semanticAnchor) { photosIncomplete = true; continue }
                return .capture(step)
            }
        }
        return .outcome(photosIncomplete: photosIncomplete)
    }

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

    /// "Cannot complete" before both photos: the saved outcome position moves to
    /// Could not verify. The frozen outcome-entry mode is never changed.
    func openCouldNotVerify() throws {
        try requireIdle()
        guard let editor, hasBoundBegin else { throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor }
        var outcome = editor.values.outcome
        outcome.chooseCouldNotVerify()
        try editor.replaceEditableValues(.init(preflight: editor.values.preflight, outcome: outcome,
                                               semanticAnchor: .outcome))
    }

    /// Leaves an incomplete Could not verify outcome for the next missing photo.
    func returnToPhotos() throws {
        try requireIdle()
        guard let editor, case .outcome(photosIncomplete: true) = stage else {
            throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor
        }
        let payload = try checkpoint.map(CheckRunnerItemDraftCodecV1.validateCheckpoint)
        let anchor: CheckRunnerItemSemanticAnchorV1 = payload?.field.wideContext == nil ? .wideContext : .closeDetail
        try editor.replaceEditableValues(.init(preflight: editor.values.preflight, outcome: editor.values.outcome,
                                               semanticAnchor: anchor))
    }

    /// Explicit selection for the current capture step: forced flush, frozen
    /// proposal, parent selection, private staging, raw publication and the
    /// normalized pair. Nothing commits until the separate explicit Use Photo.
    func stagePhoto(_ data: Data, origin: OriginalContentOriginV1) async throws {
        try requireIdle()
        guard let editor, case let .capture(step) = stage, !data.isEmpty else {
            throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor
        }
        let operation = try captureOperation()
        isPerformingAction = true
        defer { isPerformingAction = false }
        let proof = try await editor.forceFlushAndReadBack(reason: origin == .humanCapture ? .camera : .photos)
        try editor.validateForPublication(proof)
        try requireActive()
        guard self.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
        let parent = proof.parent.checkpoint
        let proposal = try service.makeRawPhotoProposal(parentDraftID: parent.draftID,
            expectedCheckpointSHA256: parent.checkpointSHA256, captureStep: step,
            expectedSourceByteCount: Int64(data.count), origin: origin, authorizing: operation)
        // A private per-selection copy is the only source the stager reads.
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("round-photo-\(proposal.childDraftID.uuidString.lowercased())")
        try data.write(to: sourceURL, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        // The parent slot changes; its old acknowledgement must not write.
        await supersede(editor)
        do {
            _ = try operation.withAuthorization {
                try requireActive()
                return try service.prepareRawPhoto(parentDraftID: parent.draftID,
                    expectedCheckpointSHA256: parent.checkpointSHA256, proposal: proposal)
            }
            try service.prepareLivePhotoStaging(authorizing: operation)
            _ = try await service.publishRawPhoto(parentDraftID: parent.draftID,
                childDraftID: proposal.childDraftID, sourceURL: sourceURL, authorizing: operation)
            _ = try await service.preparePhotoPair(parentDraftID: parent.draftID,
                childDraftID: proposal.childDraftID, authorizing: operation)
        } catch {
            if (try? requireActive()) != nil { try? installCurrentRead(authorizing: operation) }
            throw error
        }
        try requireActive()
        try installCurrentRead(authorizing: operation)
        selectedPhotoPreview = data
    }

    /// Explicit Use Photo, or explicit recovery of a saved selection: pair if
    /// needed, freeze the one commit attempt, publish it and adopt the slot.
    func usePhoto() async throws {
        try requireIdle()
        guard case .pendingPhoto = stage, let pending = pendingPhoto, !pending.needsSourceAgain,
              let parentID = checkpoint?.draftID else {
            throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor
        }
        let operation = try captureOperation()
        isPerformingAction = true
        defer { isPerformingAction = false }
        if let editor {
            let proof = try await editor.forceFlushAndReadBack(reason: .photoPromotion)
            try editor.validateForPublication(proof)
            try requireActive()
            guard self.editor === editor, proof.parent.checkpoint.draftID == parentID else {
                throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint
            }
            await supersede(editor)
        }
        let childID = pending.childDraftID
        do {
            switch pending.phase {
            case .awaitingRawStage:
                throw FieldDraftFailureV1.missingContent
            case .rawReady:
                let pair = try await service.preparePhotoPair(parentDraftID: parentID,
                    childDraftID: childID, authorizing: operation)
                _ = try service.preparePhotoCommit(parentDraftID: parentID, childDraftID: childID,
                    expectedCheckpointSHA256: pair.checkpointSHA256, authorizing: operation)
            case .pairReady:
                _ = try service.preparePhotoCommit(parentDraftID: parentID, childDraftID: childID,
                    expectedCheckpointSHA256: pending.checkpoint.checkpointSHA256, authorizing: operation)
            case .preparedCommit:
                break
            }
            _ = try await service.resumePhotoCommit(parentDraftID: parentID, childDraftID: childID,
                                                    authorizing: operation)
        } catch {
            retainedCheckpoint = nil
            if (try? requireActive()) != nil { try? installCurrentRead(authorizing: operation) }
            throw error
        }
        try requireActive()
        try installCurrentRead(authorizing: operation)
        selectedPhotoPreview = nil
    }

    /// Review of saved values only: the outcome is flushed and read back first.
    func readReview() async throws -> FinalizationReview {
        try requireIdle()
        guard let editor, case .outcome = stage else { throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor }
        let operation = try captureOperation()
        isPerformingAction = true
        defer { isPerformingAction = false }
        let proof = try await editor.forceFlushAndReadBack(reason: .complete)
        try editor.validateForPublication(proof)
        return try operation.withAuthorization {
            try requireActive()
            guard self.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
            try service.validateForPublication(proof.parent)
            return try service.readFinalizationReview(draftID: proof.parent.checkpoint.draftID,
                                                      authorizing: operation)
        }
    }

    func reviewThumbnail(_ evidence: ReviewEvidence) -> Data? {
        guard let operation = try? captureOperation() else { return nil }
        return try? operation.withAuthorization { try service.readReviewThumbnail(evidence, authorizing: operation) }
    }

    /// Explicit Save and finish. A forced flush precedes the one original
    /// finalization; recovery of a PREPARED_FINALIZATION parent only resumes it.
    /// The COMPLETE step is recorded from that finalization's receipt.
    func finish(recordedByName: String, sourceApp: SourceAppSnapshotV1) async throws
        -> AppAccessPresentationV1.RoundAccess.RepetitiveCaptureProgressResultV2 {
        try requireIdle()
        let operation = try captureOperation()
        isPerformingAction = true
        defer { isPerformingAction = false }
        let draftID: UUID
        if let editor {
            guard case .outcome = stage else { throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor }
            let proof = try await editor.forceFlushAndReadBack(reason: .finalization)
            try editor.validateForPublication(proof)
            try requireActive()
            guard self.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
            draftID = proof.parent.checkpoint.draftID
            // No acknowledgement may write while the parent changes phase.
            await supersede(editor)
            do {
                _ = try await access.prepareCheckRunnerFinalization(service: service, draftID: draftID,
                    expectedCheckpointSHA256: proof.parent.checkpoint.checkpointSHA256, sourceApp: sourceApp,
                    authorizing: operation, validateIntent: { try self.requireActive() })
            } catch {
                if (try? requireActive()) != nil { try? installCurrentRead(authorizing: operation) }
                throw error
            }
        } else {
            // Recovery only: resume the saved finalization, or settle its one
            // COMPLETE step when that acknowledgement was lost.
            guard stage == .preparedFinalization || stage == .completed, let checkpoint = retainedCheckpoint else {
                throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor
            }
            draftID = checkpoint.draftID
        }
        do {
            let result = try await access.resumeCheckRunnerFinalization(service: service, draftID: draftID,
                focus: .facts, recordedByName: recordedByName, authorizing: operation,
                validateIntent: { try self.requireActive() })
            try requireActive()
            try installCurrentRead(authorizing: operation)
            return result
        } catch {
            retainedCheckpoint = nil
            if (try? requireActive()) != nil { try? installCurrentRead(authorizing: operation) }
            throw error
        }
    }

    /// Explicit DEFER_AND_NEXT or KEEP_OPEN_AND_NEXT after a forced flush. The
    /// parent draft is retained; a lost step acknowledgement resumes the original.
    func advance(_ action: RepetitiveCaptureProgressActionV2, recordedByName: String) async throws
        -> AppAccessPresentationV1.RoundAccess.RepetitiveCaptureProgressResultV2 {
        guard action == .defer || action == .keepOpenAndNext else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        try requireIdle()
        switch stage {
        case .preflight, .interruptedBegin, .capture, .pendingPhoto, .outcome: break
        case .preparedFinalization, .completed, .unavailable:
            // A finalizing or finished item completes through its own receipt only.
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let operation = try captureOperation()
        // The scene/publication authority of this host's original operation.
        let validateIntent: @MainActor () throws -> Void = {
            try operation.withAuthorization { try self.requireActive() }
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        if let editor {
            let proof = try await editor.forceFlushAndReadBack(reason: action == .defer ? .deferItem : .keepOpen)
            try editor.validateForPublication(proof)
        }
        try requireActive()
        let itemID = source.originalItem.itemID
        let sourceDraftID = source.sourceCheckpoint.draftID
        let read = try access.readRepetitiveCaptureProgress(sourceDraftID: sourceDraftID)
        guard let tip = read.chain.nodes.last, tip.step.itemID == itemID else {
            throw ScanToWorkFailureV1.stale
        }
        if tip.step.action == action {
            // The original step was saved; settle or reread it without a new step.
            return try await access.resumeRepetitiveCaptureProgress(sourceDraftID: sourceDraftID,
                stepDraftID: tip.checkpoint.draftID, validateIntent: validateIntent)
        }
        guard tip.step.action == .enter, !tip.isPendingRoundEffect else { throw ScanToWorkFailureV1.stale }
        let readiness = try await access.rebuildReadiness(for: read.chain.currentRound, previous: nil)
        try validateIntent()
        let step = try access.prepareRepetitiveCaptureStep(read: read, readiness: readiness, action: action,
            focus: .facts, recordedByName: recordedByName)
        return try await access.executeRepetitiveCaptureStep(step, validateIntent: validateIntent)
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
        do {
            try operation.withAuthorization {
                try requireActive()
                guard self.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
                try service.validateForPublication(proof.parent)
                let prepared = try service.prepareBegin(draftID: proof.parent.checkpoint.draftID,
                    expectedCheckpointSHA256: proof.parent.checkpoint.checkpointSHA256,
                    observedAtUTC: observedAtUTC)
                _ = try service.resumeInitialBegin(draftID: prepared.draftID)
            }
        } catch {
            // Either write may already be durable. Never present the pre-Begin
            // acknowledgement again; reread current state when still active.
            await supersede(editor)
            if (try? requireActive()) != nil { try? installCurrentRead(authorizing: operation) }
            throw error
        }
        // The old acknowledgement belongs to the pre-Begin parent. Do not
        // publish it as current or leave its scheduler able to write afterward.
        await supersede(editor)
        try requireActive()
        try installCurrentRead(authorizing: operation)
    }

    /// Explicit recovery of an interrupted Begin from its frozen original. A
    /// PREPARED parent has no editor, so no field flush or new sample occurs.
    func finishPreparedBegin() throws {
        try requireIdle()
        guard editor == nil, hasPreparedBegin, let expected = retainedCheckpoint else {
            throw ProductionCheckRunnerItemCaptureFailureV1.notPreparedBegin
        }
        let operation = try captureOperation()
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try operation.withAuthorization {
                try requireActive()
                guard retainedCheckpoint == expected,
                      try service.readCurrentDraft(source: source) == expected else {
                    throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint
                }
                _ = try service.resumeInitialBegin(draftID: expected.draftID)
            }
        } catch {
            // The bound write may be durable; present only a fresh reread.
            retainedCheckpoint = nil
            if (try? requireActive()) != nil { try? installCurrentRead(authorizing: operation) }
            throw error
        }
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
        if let editor { await supersede(editor) }
        try requireActive()
        try installCurrentRead(authorizing: operation)
    }

    func retire() async {
        retired = true
        editorObservation = nil
        await editor?.retire()
    }

    /// A superseded acknowledgement is never presented as current. Until an
    /// authenticated reread succeeds, the host has no editor or checkpoint.
    private func supersede(_ superseded: CheckRunnerItemEditingSessionV1) async {
        if editor === superseded {
            editorObservation = nil
            editor = nil
            retainedCheckpoint = nil
        }
        await superseded.retire()
    }

    private func captureOperation() throws -> AppAccessPresentationV1.CheckRunnerItemOperationAccess {
        try requireActive()
        return try access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target)
    }

    private func installCurrentRead(authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
        let current = try operation.withAuthorization { try service.readCurrentDraft(source: source) }
        let next: CheckRunnerItemEditingSessionV1?
        var fieldRead: CheckRunnerFieldReadbackV1?
        var editable = false
        if let current, current.state == .active {
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(current)
            // A PREPARED Begin rejects every field flush, so it gets no editor.
            if case .prepared = payload.field.begin { editable = false } else { editable = payload.phase == .editing }
        }
        if let current, editable {
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
            let outcome = try service.readOutcomePresentation(authorizing: operation)
            var preparation: CapturePreparation?
            var pending: ProductionCheckRunnerPendingPhotoV1?
            if let current, current.state == .active {
                let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(current)
                if case .bound = payload.field.begin, payload.phase == .editing {
                    preparation = try service.readCapturePreparation(authorizing: operation)
                    for slot in [payload.field.wideContext, payload.field.closeDetail] {
                        guard case let .pending(childID, step, _)? = slot else { continue }
                        let read = try service.readPendingPhoto(parentDraftID: current.draftID,
                            childDraftID: childID, authorizing: operation)
                        pending = .init(childDraftID: childID, step: step, checkpoint: read.checkpoint, phase: read.phase)
                        break
                    }
                }
            }
            editorObservation = next?.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            retainedCheckpoint = current
            editor = next
            preflight = presentation
            outcomePresentation = outcome
            capturePreparation = preparation
            pendingPhoto = pending
            if pending == nil { selectedPhotoPreview = nil }
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

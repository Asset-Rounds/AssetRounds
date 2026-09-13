import Foundation
import SwiftData

enum RepetitiveCaptureCheckpointAttemptStateV2: Equatable { case notAttempted, checkpointWriteAttempted }

/// A read of authenticated C36 and Round history. It grants no field-entry or
/// mutation permission; the original publication and fresh readiness are separate.
struct ProductionRepetitiveCaptureReadV2 {
    let chain: ReviewedRepetitiveCaptureProgressChainV2
    fileprivate let ownerID: UUID
    fileprivate let revision: WorkspaceRevisionV1
}

@MainActor
final class PreparedRepetitiveCaptureSourceV2 {
    let checkpoint: FieldDraftCheckpointV1
    private(set) var attemptState: RepetitiveCaptureCheckpointAttemptStateV2 = .notAttempted
    fileprivate let ownerID: UUID
    fileprivate init(checkpoint: FieldDraftCheckpointV1, ownerID: UUID) {
        self.checkpoint = checkpoint; self.ownerID = ownerID
    }
    fileprivate func markAttempted() { attemptState = .checkpointWriteAttempted }
}

@MainActor
final class PreparedRepetitiveCaptureStepV2 {
    let checkpoint: FieldDraftCheckpointV1
    let step: RepetitiveCaptureProgressStepV2
    private(set) var attemptState: RepetitiveCaptureCheckpointAttemptStateV2 = .notAttempted
    fileprivate let ownerID: UUID
    fileprivate init(checkpoint: FieldDraftCheckpointV1, step: RepetitiveCaptureProgressStepV2,
                     ownerID: UUID) {
        self.checkpoint = checkpoint; self.step = step; self.ownerID = ownerID
    }
    fileprivate func markAttempted() { attemptState = .checkpointWriteAttempted }
}

/// Production composition of the existing draft and Round owners. All methods
/// run inside the caller's original visible-publication capability. This service
/// does not implement fields, media, pose, camera startup or navigation.
@MainActor
final class ProductionRepetitiveCaptureProgressServiceV2 {
    private weak var session: StoreSessionCoordinator?
    private weak var originalWriter: WorkspaceWriterV1?
    private let workspaceID: WorkspaceID
    private let generationID: UUID
    private let uiGenerationToken: UInt64
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let ownerID = UUID()
    private let transitions: ProductionRoundSessionTransitionServiceV1

    init(session: StoreSessionCoordinator, transitions: ProductionRoundSessionTransitionServiceV1,
         clock: any ApplicationClock, idSource: any ApplicationIDSource) throws {
        self.session = session; originalWriter = session.workspaceWriter
        workspaceID = session.workspaceID; generationID = session.generationID
        uiGenerationToken = session.uiGenerationToken
        rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        self.transitions = transitions; self.clock = clock; self.idSource = idSource
        try transitions.validateRepetitiveCaptureOwner(session)
    }

    func prepareSource(round: RoundSessionV1, manifest: OfflineReadinessManifestV1) throws
        -> PreparedRepetitiveCaptureSourceV2 {
        _ = try currentSession()
        guard round.workspaceID == workspaceID, round.state == .active,
              round.items.contains(where: { !$0.disposition.isTerminal }),
              manifest.session == (try round.reference) else { throw ScanToWorkFailureV1.authorityMismatch }
        let planID = idSource.makeID(), draftID = idSource.makeID(), mutationID = idSource.makeID()
        guard Set([planID, draftID, mutationID]).count == 3 else { throw ScanToWorkFailureV1.duplicate }
        let launch = try RepetitiveCaptureLaunchSourceV2(planID: planID, round: round,
            readiness: round.items.map { try manifest.scanToWorkProof(assetID: $0.selection.assetID) })
        let anchor = try DraftResumeAnchorV1(sectionID: "facts", selectedStableID:
            round.items.first { $0.itemID == launch.firstIncompleteItemID }?.selection.assetID.uuidString.lowercased())
        let value = try checkpoint(draftID: draftID, mutationID: mutationID,
            scope: RepetitiveCaptureDraftCodecV1.scope(planID: planID, round: round.reference),
            baseRevision: round.revision, payload: .source(launch), anchor: anchor)
        return .init(checkpoint: value, ownerID: ownerID)
    }

    /// Checks exact durable identity before a caller considers replaying the
    /// original pre-write readiness gate. A returned read is an acknowledgement.
    func committedSource(_ prepared: PreparedRepetitiveCaptureSourceV2) throws
        -> ProductionRepetitiveCaptureReadV2? {
        try requireOwner(prepared.ownerID)
        let current = try currentSession(), drafts = try adapter(current)
        guard let stored = try drafts.currentCheckpoint(workspaceID: workspaceID,
                                                        draftID: prepared.checkpoint.draftID) else { return nil }
        guard stored == prepared.checkpoint else { throw ScanToWorkFailureV1.stale }
        return try read(sourceDraftID: stored.draftID)
    }

    func persistSource(_ prepared: PreparedRepetitiveCaptureSourceV2) throws -> ProductionRepetitiveCaptureReadV2 {
        try requireOwner(prepared.ownerID)
        let current = try currentSession()
        prepared.markAttempted()
        _ = try adapter(current).persistRepetitiveCaptureProgressSource(prepared.checkpoint)
        return try read(sourceDraftID: prepared.checkpoint.draftID)
    }

    func read(sourceDraftID: UUID) throws -> ProductionRepetitiveCaptureReadV2 {
        let current = try currentSession()
        let chain = try adapter(current).reviewedRepetitiveCaptureProgress(workspaceID: workspaceID,
                                                                          sourceDraftID: sourceDraftID)
        return .init(chain: chain, ownerID: ownerID, revision: try current.workspaceWriter.currentRevision())
    }

    func validateForPublication(_ value: ProductionRepetitiveCaptureReadV2) throws {
        try requireOwner(value.ownerID)
        let current = try currentSession()
        guard try current.workspaceWriter.currentRevision() == value.revision,
              try read(sourceDraftID: value.chain.sourceCheckpoint.draftID).chain == value.chain else {
            throw ScanToWorkFailureV1.stale
        }
    }

    func prepareStep(read value: ProductionRepetitiveCaptureReadV2,
                     action: RepetitiveCaptureProgressActionV2,
                     focus: RepetitiveCaptureRequirementFocusV1,
                     completionRecordID: UUID?, recordedByName: String) throws
        -> PreparedRepetitiveCaptureStepV2 {
        try validateForPublication(value)
        let chain = value.chain, round = chain.currentRound
        guard chain.nodes.last?.isPendingRoundEffect != true,
              let itemID = chain.nodes.last?.step.navigationItemID ??
                (chain.nodes.isEmpty ? chain.launch.firstIncompleteItemID : nil),
              let index = round.items.firstIndex(where: { $0.itemID == itemID }),
              completionRecordID == nil || action == .complete else { throw ScanToWorkFailureV1.authorityMismatch }
        let completion: RoundItemCompletionReferenceV1?
        if action == .complete {
            guard let completionRecordID else { throw ScanToWorkFailureV1.authorityMismatch }
            completion = try completionReference(recordID: completionRecordID, item: round.items[index])
        } else { completion = nil }
        let transition: RoundSessionTransitionV1?
        switch action {
        case .enter: transition = round.items[index].disposition == .pending ? .visitItem : nil
        case .complete: transition = .completeItem
        case .defer: transition = .deferItem
        case .keepOpenAndNext: transition = nil
        }
        let mutation: RoundSessionMutationV1?
        if let transition {
            let prepared = try transitions.prepareItem(expected: round, itemID: itemID,
                transition: transition, reason: action == .defer ? .userDeferred : nil,
                completion: completion, recordedByName: recordedByName)
            mutation = try transitions.repetitiveCaptureMutation(for: prepared)
        } else { mutation = nil }
        let resulting = mutation?.session ?? round
        let nextID = action == .enter ? itemID :
            resulting.items.dropFirst(index + 1).first { !$0.disposition.isTerminal }?.itemID
        let anchor = try DraftResumeAnchorV1(sectionID: focus.rawValue.lowercased(), selectedStableID:
            resulting.items.first { $0.itemID == nextID }?.selection.assetID.uuidString.lowercased())
        let step = try RepetitiveCaptureProgressStepV2(source: .init(source: chain.sourceCheckpoint),
            prior: chain.nodes.last.map { try .init(source: $0.checkpoint) },
            priorRoundReceipt: chain.nodes.last?.roundReceipt, expectedRound: round,
            itemID: itemID, action: action, roundMutation: mutation,
            requirementFocus: focus, resumeAnchor: anchor)
        try step.validate(sourceCheckpoint: chain.sourceCheckpoint, priorCheckpoint: chain.nodes.last?.checkpoint)
        let draftID = idSource.makeID(), mutationID = idSource.makeID()
        guard draftID != mutationID else { throw ScanToWorkFailureV1.duplicate }
        let checkpoint = try checkpoint(draftID: draftID, mutationID: mutationID,
            scope: chain.sourceCheckpoint.scope, baseRevision: round.revision,
            payload: .progress(step), anchor: anchor)
        return .init(checkpoint: checkpoint, step: step, ownerID: ownerID)
    }

    func committedStep(_ prepared: PreparedRepetitiveCaptureStepV2) throws -> ProductionRepetitiveCaptureReadV2? {
        try requireOwner(prepared.ownerID)
        let current = try currentSession(), drafts = try adapter(current)
        guard let stored = try drafts.currentCheckpoint(workspaceID: workspaceID,
                                                        draftID: prepared.checkpoint.draftID) else { return nil }
        guard stored == prepared.checkpoint else { throw ScanToWorkFailureV1.stale }
        let result = try read(sourceDraftID: prepared.step.source.draftID)
        guard result.chain.nodes.last?.checkpoint == stored else { throw ScanToWorkFailureV1.stale }
        return result
    }

    func persistStep(_ prepared: PreparedRepetitiveCaptureStepV2) throws -> ProductionRepetitiveCaptureReadV2 {
        try requireOwner(prepared.ownerID)
        let current = try currentSession()
        prepared.markAttempted()
        _ = try adapter(current).persistRepetitiveCaptureProgressStep(prepared.checkpoint)
        return try read(sourceDraftID: prepared.step.source.draftID)
    }

    func pendingTransition(sourceDraftID: UUID, stepDraftID: UUID) throws -> PreparedRoundSessionTransitionV1 {
        _ = try currentSession()
        return try transitions.adoptPendingRepetitiveCaptureStep(sourceDraftID: sourceDraftID,
                                                                stepDraftID: stepDraftID)
    }

    private func checkpoint(draftID: UUID, mutationID: UUID, scope: DraftScopeKeyV1,
                            baseRevision: UInt64, payload: RepetitiveCaptureProgressDraftPayloadV2,
                            anchor: DraftResumeAnchorV1) throws -> FieldDraftCheckpointV1 {
        let sampled = clock.now().timeIntervalSince1970
        guard sampled.isFinite, sampled >= 0, (sampled * 1_000).isFinite else {
            throw FieldDraftFailureV1.invalidValue
        }
        let value = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: workspaceID,
            scope: scope, purpose: .repetitiveCapture, codec: RepetitiveCaptureProgressDraftCodecV2.release(),
            baseCanonicalRevision: baseRevision, draftRevision: 1,
            payloadData: RepetitiveCaptureProgressDraftCodecV2.encode(payload), stageIDs: [],
            resumeAnchor: anchor, state: .active,
            updatedAt: Date(timeIntervalSince1970: floor(sampled * 1_000) / 1_000),
            mutationID: .init(rawValue: mutationID))
        try RepetitiveCaptureProgressDraftCodecV2.validateCheckpoint(value)
        return value
    }

    private func requireOwner(_ proposed: UUID) throws {
        guard proposed == ownerID else { throw ScanToWorkFailureV1.authorityMismatch }
    }

    private func completionReference(recordID: UUID, item: RoundItemV1) throws -> RoundItemCompletionReferenceV1 {
        let current = try currentSession()
        let sources = try ProductionOfflineReadinessSourceClosureV1(context: current.modelContext,
                                                                   workspaceID: workspaceID)
        guard let release = try sources.package(for: item.requirement.packageRelease),
              release.packageID == ShippingIlluminatedSignAdapterV1.packageID else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let package = try InspectionPackageCanonicalCodecV2.decode(release.canonicalPackageBytes)
        let signPack = try ShippingIlluminatedSignAdapterV1.signPack(from: package)
        let finalizer = try FinalizationService(modelContext: current.modelContext, signPack: signPack,
            generationRootURL: current.generationRootURL, workspaceWriter: current.workspaceWriter)
        guard let reference = try finalizer.completedInspectionReference(recordID: recordID,
            expectedAssetID: item.selection.assetID, expectedRelease: release) else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        return reference
    }

    private func adapter(_ current: StoreSessionCoordinator) throws -> FieldDraftLifecycleAdapterV1 {
        try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
    }

    private func currentSession() throws -> StoreSessionCoordinator {
        guard let session, let originalWriter, originalWriter === session.workspaceWriter,
              session.workspaceID == workspaceID, session.generationID == generationID,
              session.uiGenerationToken == uiGenerationToken, !session.modelContext.hasChanges,
              try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL) == rootIdentity else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        try transitions.validateRepetitiveCaptureOwner(session)
        _ = try session.workspaceWriter.currentRevision()
        return session
    }
}

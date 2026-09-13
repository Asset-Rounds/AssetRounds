import Foundation
import SwiftData

struct MyDayPlanningPlanSaveRequestV1: Equatable, Sendable {
    let confirmedContext: MyDayPlanningConfirmedContextV1
    let draft: MyDayPlanDraftV1
    let predecessor: MyDayPlanV1?

    init(confirmedContext: MyDayPlanningConfirmedContextV1,
         draft: MyDayPlanDraftV1, predecessor: MyDayPlanV1?) throws {
        _ = try MyDayPlanningDraftPayloadV1(editing: confirmedContext,
            intent: .plan(draft: draft, predecessor: predecessor))
        self.confirmedContext = confirmedContext
        self.draft = draft
        self.predecessor = predecessor
    }
}

/// Both editing forms use the same durable checkpoint and session machinery.
/// The concrete request type rejects a checkpoint of the other intent kind.
protocol MyDayPlanningEditingRequestV1: Equatable, Sendable {
    var confirmedContext: MyDayPlanningConfirmedContextV1 { get }
    var editingIntent: MyDayPlanningEditingIntentV1 { get }
    init(confirmedContext: MyDayPlanningConfirmedContextV1,
         editingIntent: MyDayPlanningEditingIntentV1) throws
    func matchesEditingBase(of other: Self) -> Bool
}

extension MyDayPlanningEditingRequestV1 {
    func matchesEditingBase(of other: Self) -> Bool {
        editingIntent.hasSamePlanningBase(as: other.editingIntent)
    }
}

extension MyDayPlanningPlanSaveRequestV1: MyDayPlanningEditingRequestV1 {
    var editingIntent: MyDayPlanningEditingIntentV1 {
        .plan(draft: draft, predecessor: predecessor)
    }

    init(confirmedContext: MyDayPlanningConfirmedContextV1,
         editingIntent: MyDayPlanningEditingIntentV1) throws {
        guard case let .plan(draft, predecessor) = editingIntent else {
            throw MyDayPlanningExecutionFailureV1.unsupportedCommand
        }
        try self.init(confirmedContext: confirmedContext, draft: draft, predecessor: predecessor)
    }
}

struct MyDayPlanningCarryoverRequestV1: MyDayPlanningEditingRequestV1 {
    let confirmedContext: MyDayPlanningConfirmedContextV1
    let sourcePlan: MyDayPlanReferenceV1
    let selectedMembershipIDs: [UUID]
    let targetPredecessor: MyDayPlanReferenceV1?

    var editingIntent: MyDayPlanningEditingIntentV1 {
        .carryover(sourcePlan: sourcePlan, selectedMembershipIDs: selectedMembershipIDs,
            targetKey: confirmedContext.key, targetPredecessor: targetPredecessor)
    }

    init(confirmedContext: MyDayPlanningConfirmedContextV1, sourcePlan: MyDayPlanReferenceV1,
         selectedMembershipIDs: [UUID], targetPredecessor: MyDayPlanReferenceV1?) throws {
        let intent = MyDayPlanningEditingIntentV1.carryover(sourcePlan: sourcePlan,
            selectedMembershipIDs: selectedMembershipIDs, targetKey: confirmedContext.key,
            targetPredecessor: targetPredecessor)
        _ = try MyDayPlanningDraftPayloadV1(editing: confirmedContext, intent: intent)
        self.confirmedContext = confirmedContext
        self.sourcePlan = sourcePlan
        self.selectedMembershipIDs = selectedMembershipIDs
        self.targetPredecessor = targetPredecessor
    }

    init(confirmedContext: MyDayPlanningConfirmedContextV1,
         editingIntent: MyDayPlanningEditingIntentV1) throws {
        guard case let .carryover(source, memberships, targetKey, predecessor) = editingIntent,
              targetKey == confirmedContext.key else {
            throw MyDayPlanningExecutionFailureV1.unsupportedCommand
        }
        try self.init(confirmedContext: confirmedContext, sourcePlan: source,
            selectedMembershipIDs: memberships, targetPredecessor: predecessor)
    }
}

private extension MyDayPlanningEditingIntentV1 {
    func hasSamePlanningBase(as other: MyDayPlanningEditingIntentV1) -> Bool {
        switch (self, other) {
        case let (.plan(_, predecessor), .plan(_, oldPredecessor)):
            return predecessor == oldPredecessor
        case let (.carryover(source, _, key, predecessor),
                  .carryover(oldSource, _, oldKey, oldPredecessor)):
            return source == oldSource && key == oldKey && predecessor == oldPredecessor
        default:
            return false
        }
    }
}

struct MyDayPlanningCommitOutcomeV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let draftReceipt: DraftCommitReceiptV1
    let targetResult: MyDayCommandResultV1
    let targetReceipt: MutationReceiptV1
    let terminalReceipt: MutationReceiptV1
}

/// Immutable operational bytes are prepared before the first effect. Retain
/// this value through an uncertain acknowledgement instead of sampling again.
struct MyDayPlanningEditingWriteV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let expectedCheckpoint: FieldDraftCheckpointV1?
}

/// Historical review inputs captured together under the original content hold.
/// Only this service can construct the value; it grants no writer authority.
struct MyDayPlanningConflictReviewV1: Equatable, Sendable {
    let pending: PendingReviewedMyDayConflictEvidenceV1
    let originalEditingRequest: MyDayPlanningPlanSaveRequestV1
    let reviewRequest: MyDayPlanningPlanSaveRequestV1
    let capturedTargetBasis: ReviewedMyDayTargetBasisV1

    fileprivate init(pending: PendingReviewedMyDayConflictEvidenceV1,
                     originalEditingRequest: MyDayPlanningPlanSaveRequestV1,
                     reviewRequest: MyDayPlanningPlanSaveRequestV1,
                     capturedTargetBasis: ReviewedMyDayTargetBasisV1) {
        self.pending = pending
        self.originalEditingRequest = originalEditingRequest
        self.reviewRequest = reviewRequest
        self.capturedTargetBasis = capturedTargetBasis
    }
}

/// The exact resolution is prepared once and retained through receipt replay.
struct MyDayPlanningReviewedResolutionWriteV1: Equatable, Sendable {
    let review: MyDayPlanningConflictReviewV1
    let resolution: ReviewedDraftConflictResolutionV1
    let mutation: FieldDraftMutationV1

    fileprivate init(review: MyDayPlanningConflictReviewV1,
                     resolution: ReviewedDraftConflictResolutionV1,
                     mutation: FieldDraftMutationV1) {
        self.review = review
        self.resolution = resolution
        self.mutation = mutation
    }
}


/// A service-created classification of one stale predecessor. It cannot be
/// repurposed for a later checkpoint or a changed canonical target.
struct MyDayPlanningConflictClassificationWriteV1: Equatable, Sendable {
    let evidence: ClassifiableMyDayPlanEvidenceV1
    let observedTarget: MyDayPlanV1?
    let observedTargetBasis: ReviewedMyDayTargetBasisV1
    let checkpoint: FieldDraftCheckpointV1
    let mutation: FieldDraftMutationV1

    fileprivate init(evidence: ClassifiableMyDayPlanEvidenceV1,
                     observedTarget: MyDayPlanV1?,
                     observedTargetBasis: ReviewedMyDayTargetBasisV1,
                     checkpoint: FieldDraftCheckpointV1,
                     mutation: FieldDraftMutationV1) {
        self.evidence = evidence
        self.observedTarget = observedTarget
        self.observedTargetBasis = observedTargetBasis
        self.checkpoint = checkpoint
        self.mutation = mutation
    }
}


struct MyDayPlanningCarryoverConflictClassificationWriteV1: Equatable, Sendable {
    let evidence: ClassifiableMyDayCarryoverEvidenceV1
    let observedTarget: MyDayPlanV1?
    let observedTargetBasis: ReviewedMyDayTargetBasisV1
    let checkpoint: FieldDraftCheckpointV1
    let mutation: FieldDraftMutationV1

    fileprivate init(evidence: ClassifiableMyDayCarryoverEvidenceV1,
                     observedTarget: MyDayPlanV1?,
                     observedTargetBasis: ReviewedMyDayTargetBasisV1,
                     checkpoint: FieldDraftCheckpointV1,
                     mutation: FieldDraftMutationV1) {
        self.evidence = evidence
        self.observedTarget = observedTarget
        self.observedTargetBasis = observedTargetBasis
        self.checkpoint = checkpoint
        self.mutation = mutation
    }
}


/// Captured original carryover selection and the current target for explicit review.
/// Construction is limited to the service and grants no write authority.
struct MyDayPlanningCarryoverConflictReviewV1: Equatable, Sendable {
    let pending: PendingReviewedMyDayCarryoverConflictEvidenceV1
    let originalEditingRequest: MyDayPlanningCarryoverRequestV1
    let reviewRequest: MyDayPlanningCarryoverRequestV1
    let capturedTarget: MyDayPlanV1?
    let capturedTargetBasis: ReviewedMyDayTargetBasisV1

    fileprivate init(pending: PendingReviewedMyDayCarryoverConflictEvidenceV1,
        originalEditingRequest: MyDayPlanningCarryoverRequestV1,
        reviewRequest: MyDayPlanningCarryoverRequestV1, capturedTarget: MyDayPlanV1?,
        capturedTargetBasis: ReviewedMyDayTargetBasisV1) {
        self.pending = pending
        self.originalEditingRequest = originalEditingRequest
        self.reviewRequest = reviewRequest
        self.capturedTarget = capturedTarget
        self.capturedTargetBasis = capturedTargetBasis
    }
}

/// One explicit target review with the original carryover selection retained.
struct MyDayPlanningReviewedCarryoverResolutionWriteV1: Equatable, Sendable {
    let review: MyDayPlanningCarryoverConflictReviewV1
    let resolution: ReviewedDraftConflictResolutionV1
    let mutation: FieldDraftMutationV1

    fileprivate init(review: MyDayPlanningCarryoverConflictReviewV1,
        resolution: ReviewedDraftConflictResolutionV1, mutation: FieldDraftMutationV1) {
        self.review = review
        self.resolution = resolution
        self.mutation = mutation
    }
}

struct MyDayPlanningCheckpointAcknowledgementV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let receipt: MutationReceiptV1
}

/// Operational values only; never persisted or used as a replacement authority.
struct MyDayPlanningDiscardWriteV1: Equatable, Sendable {
    let expectedCheckpoint: FieldDraftCheckpointV1
    let pendingCheckpoint: FieldDraftCheckpointV1
    let plan: DraftDiscardPlanV1
    let terminalBundle: DraftDiscardTerminalBundleV1
}

struct MyDayPlanningDiscardOutcomeV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let draftReceipt: DraftDiscardReceiptV1
    let terminalReceipt: MutationReceiptV1
}

/// Carries the durable draft identity after a save was interrupted. Presentation
/// renders its own reason; the underlying error is never user-facing copy.
struct MyDayPlanningSaveFailureV1: Error {
    let draftID: UUID
    let underlying: Error
}

enum MyDayPlanningExecutionFailureV1: Error, Equatable {
    case missingDraft, unsupportedState, unsupportedCommand, incompleteReadback
}

#if DEBUG
enum MyDayPlanningEffectPointV1: String, Sendable {
    case editingCheckpoint, committingCheckpoint, preparedSaga, contentPromotedSaga
    case targetCommit, targetCommittedSaga, retirePendingSaga, terminalBundle
    case discardPendingCheckpoint, discardTerminalBundle
}
#endif

/// A generation-bound purpose executor. No ModelContext, draft adapter or
/// strong writer is retained across an await; every effect resolves the exact
/// current session under the original presentation's concrete content hold.
@MainActor
final class ProductionMyDayPlanningCommitServiceV1 {
    private weak var session: StoreSessionCoordinator?
    private weak var originalWriter: WorkspaceWriterV1?
    private let workspaceID: WorkspaceID
    private let generationID: UUID
    private let uiGenerationToken: UInt64
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let sourceProvider: ProductionMyDaySourceProviderV1

    #if DEBUG
    var afterEffectForTesting: (@MainActor (MyDayPlanningEffectPointV1) throws -> Void)?
    var afterZeroStagePromotionForTesting: (@MainActor @Sendable () async throws -> Void)?
    var afterZeroStageDiscardForTesting: (@MainActor @Sendable () async throws -> Void)?
    #endif

    init(session: StoreSessionCoordinator, sourceProvider: ProductionMyDaySourceProviderV1,
         clock: any ApplicationClock, idSource: any ApplicationIDSource) {
        self.session = session
        originalWriter = session.workspaceWriter
        workspaceID = session.workspaceID
        generationID = session.generationID
        uiGenerationToken = session.uiGenerationToken
        self.clock = clock
        self.idSource = idSource
        self.sourceProvider = sourceProvider
    }

    /// Called only after the person explicitly confirms the displayed day,
    /// zone and recorder name. This captures a value, not a verified identity.
    func captureConfirmedPlanningContext(for key: MyDayKeyV1, recordedByName: String,
                                         authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningConfirmedContextV1 {
        try authorized(access) { _ in
            try key.validate()
            guard key.workspaceID == workspaceID else { throw MyDayFailureV1.wrongWorkspace }
            let actorID = idSource.makeID()
            let snapshotID = idSource.makeID()
            guard actorID != snapshotID else { throw MyDayFailureV1.invalidValue }
            let actor = try LocalActorReferenceV1(actorReferenceID: actorID,
                workspaceID: workspaceID, displayName: recordedByName)
            let snapshot = try ActorSnapshotV1(snapshotID: snapshotID, workspaceID: workspaceID,
                actor: actor, responsibility: .recordedBy, displayNameAtTime: recordedByName,
                capturedAt: sampledInstant())
            return try MyDayPlanningConfirmedContextV1(key: key, recordedBy: snapshot,
                keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true)
        }
    }

    func nextPlanningMembershipID(authorizing access: AppAccessPresentationV1.ContentAccess) throws -> UUID {
        try authorized(access) { _ in
            let value = idSource.makeID()
            try MyDayLimitsV1.id(value)
            return value
        }
    }

    /// Enumeration does not acknowledge, resume, repair or commit a draft.
    func planningCheckpoints(for key: MyDayKeyV1,
                             authorizing access: AppAccessPresentationV1.ContentAccess) throws -> [FieldDraftCheckpointV1] {
        try authorized(access) { current in
            try key.validate()
            guard key.workspaceID == workspaceID else { throw MyDayFailureV1.wrongWorkspace }
            let scope = try MyDayPlanningDraftCodecV1.scope(for: key)
            let workspace = workspaceID.rawValue
            let rows = try current.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
                predicate: #Predicate { $0.workspaceID == workspace }))
            var result: [FieldDraftCheckpointV1] = []
            for row in rows {
                let checkpoint = try row.value()
                guard checkpoint.purpose == .myDayPlanning else { continue }
                _ = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
                guard checkpoint.scope == scope, checkpoint.state != .committed,
                      checkpoint.state != .discarded else { continue }
                result.append(checkpoint)
            }
            return result.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.draftID.uuidString < $1.draftID.uuidString
            }
        }
    }

    /// Reads only persisted values for the caller's explicit civil-day key.
    /// Selection and confirmation remain separate user actions.
    func planningContext(for key: MyDayKeyV1,
                         authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningContextSnapshotV1 {
        try authorized(access) { current in
            try key.validate()
            guard key.workspaceID == workspaceID else { throw MyDayFailureV1.wrongWorkspace }
            let plan = try current.workspaceWriter.currentPlan(for: key)
            let actors = try PartyAccountabilityLifecycleAdapterV1(
                modelContext: current.modelContext, workspaceID: workspaceID)
                .actorSnapshots().filter { $0.responsibility == .recordedBy }
            return MyDayPlanningContextSnapshotV1(key: key, currentPlan: plan,
                                                 recordedBySnapshots: actors)
        }
    }

    /// Preparing a write consumes IDs/time but performs no persistent effect.
    func prepareEditingWrite(_ request: MyDayPlanningPlanSaveRequestV1,
                             replacing previous: FieldDraftCheckpointV1?,
                             resumeAnchor: DraftResumeAnchorV1,
                             authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningEditingWriteV1 {
        try preparePlanningEditingWrite(request, replacing: previous,
            resumeAnchor: resumeAnchor, authorizing: access)
    }

    func prepareCarryoverEditingWrite(_ request: MyDayPlanningCarryoverRequestV1,
                                     replacing previous: FieldDraftCheckpointV1?,
                                     resumeAnchor: DraftResumeAnchorV1,
                                     authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningEditingWriteV1 {
        try preparePlanningEditingWrite(request, replacing: previous,
            resumeAnchor: resumeAnchor, authorizing: access)
    }

    func preparePlanningEditingWrite<Request: MyDayPlanningEditingRequestV1>(_ request: Request,
                             replacing previous: FieldDraftCheckpointV1?,
                             resumeAnchor: DraftResumeAnchorV1,
                             authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningEditingWriteV1 {
        try authorized(access) { current in
            let payload = try MyDayPlanningDraftPayloadV1(editing: request.confirmedContext,
                intent: request.editingIntent)
            guard request.confirmedContext.key.workspaceID == workspaceID else {
                throw MyDayFailureV1.wrongWorkspace
            }
            if let previous {
                let oldPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(previous)
                guard previous.state == .active, oldPayload.phase == .editing,
                      let oldIntent = oldPayload.editingIntent,
                      request.editingIntent.hasSamePlanningBase(as: oldIntent),
                      oldPayload.confirmedContext?.key == request.confirmedContext.key,
                      previous.draftRevision < UInt64.max else {
                    throw MyDayPlanningExecutionFailureV1.unsupportedState
                }
                let adapter = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
                guard try adapter.currentCheckpoint(workspaceID: workspaceID,
                    draftID: previous.draftID) == previous else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
                _ = try authenticatedEditingReceipt(previous, in: current)
            }
            let draftID = previous?.draftID ?? idSource.makeID()
            let mutationID = try current.workspaceWriter.makeMutationID()
            guard mutationID.rawValue != draftID, mutationID != previous?.mutationID else {
                throw FieldDraftFailureV1.invalidValue
            }
            let instant = try sampledInstant()
            guard previous.map({ instant >= $0.updatedAt }) ?? true else {
                throw FieldDraftFailureV1.invalidValue
            }
            let checkpoint = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: workspaceID,
                scope: MyDayPlanningDraftCodecV1.scope(for: request.confirmedContext.key),
                purpose: .myDayPlanning, codec: MyDayPlanningDraftCodecV1.release(),
                baseCanonicalRevision: request.editingIntent.targetBaseRevision,
                draftRevision: previous.map { $0.draftRevision + 1 } ?? 1,
                payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: [],
                resumeAnchor: resumeAnchor, state: .active, updatedAt: instant, mutationID: mutationID)
            let write = MyDayPlanningEditingWriteV1(checkpoint: checkpoint, expectedCheckpoint: previous)
            try validateEditingWrite(write)
            return write
        }
    }

    /// Replays the original operational receipt before consulting a changed
    /// global frontier; only the exact current checkpoint can be acknowledged.
    func persistEditingWrite(_ write: MyDayPlanningEditingWriteV1,
                             authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        try validateEditingWrite(write)
        let mutation = try editingCheckpointMutation(write.checkpoint)
        let existing: MutationReceiptV1? = try authorized(access) { current in
            if let receipt = try current.workspaceWriter.fieldDraftReceipt(for: mutation) { return receipt }
            let adapter = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            guard try adapter.currentCheckpoint(workspaceID: workspaceID,
                draftID: write.checkpoint.draftID) == write.expectedCheckpoint else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            return nil
        }
        let receipt: MutationReceiptV1
        if let existing { receipt = existing }
        else {
            let coordinator = try makeCoordinator(reconstruction: nil, access: access)
            receipt = try coordinator.checkpoint(write.checkpoint,
                expectedDraftRevision: write.expectedCheckpoint?.draftRevision ?? 0,
                expectedBaseRevision: write.checkpoint.baseCanonicalRevision)
        }
        guard try readCheckpoint(write.checkpoint.draftID, access: access) == write.checkpoint,
              try authorized(access, { try $0.workspaceWriter.fieldDraftReceipt(for: mutation) }) == receipt else {
            throw MyDayPlanningExecutionFailureV1.incompleteReadback
        }
        return .init(checkpoint: write.checkpoint, receipt: receipt)
    }

    /// Classification is an explicit operation over authenticated history,
    /// never a catch-all interpretation of a failed Save.
    func prepareStalePlanPredecessorConflict(draftID: UUID,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningConflictClassificationWriteV1 {
        try authorized(access) { current in
            let evidence = try current.workspaceWriter.classifiableMyDayPlanEvidence(draftID: draftID)
            let original = try classificationOriginalRequest(evidence)
            let target = try current.workspaceWriter.currentPlan(for: original.confirmedContext.key)
            guard target != original.predecessor else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let basis = try reviewedTargetBasis(for: original.confirmedContext.key, target: target, in: current)
            let previous = evidence.currentCheckpoint
            guard previous.draftRevision < UInt64.max else { throw FieldDraftFailureV1.invalidValue }
            let mutationID = try current.workspaceWriter.makeMutationID()
            if let epoch = evidence.preparedEpoch {
                let attempt = try MyDayPlanningDraftCodecV1.reconstructCommit(from: epoch.committingCheckpoint)
                guard !Set([attempt.command.mutationID, attempt.rowMutationIDs.terminalBundleMutationID]
                    + attempt.sagas.map(\.mutationID)).contains(mutationID) else {
                    throw FieldDraftFailureV1.invalidValue
                }
            }
            guard mutationID != previous.mutationID, mutationID.rawValue != previous.draftID else {
                throw FieldDraftFailureV1.invalidValue
            }
            let checkpoint = try FieldDraftCheckpointV1(draftID: previous.draftID,
                workspaceID: previous.workspaceID, scope: previous.scope,
                purpose: previous.purpose, codec: previous.codec,
                baseCanonicalRevision: previous.baseCanonicalRevision,
                draftRevision: previous.draftRevision + 1, payloadData: previous.payloadData,
                stageIDs: previous.stageIDs, resumeAnchor: previous.resumeAnchor,
                state: .conflicted, lastDurableMutationID: previous.lastDurableMutationID,
                lastReceiptSHA256: previous.lastReceiptSHA256,
                updatedAt: sampledInstant(), mutationID: mutationID)
            try checkpoint.validateSuccessor(of: previous, expectedDraftRevision: previous.draftRevision,
                expectedBaseRevision: previous.baseCanonicalRevision)
            let mutation = try FieldDraftMutationV1(workspaceID: workspaceID,
                expectedRevision: previous.draftRevision,
                expectedBaseCanonicalRevision: previous.baseCanonicalRevision,
                mutationID: mutationID, postImage: .reviseCheckpoint(checkpoint))
            return .init(evidence: evidence, observedTarget: target, observedTargetBasis: basis,
                checkpoint: checkpoint, mutation: mutation)
        }
    }

    func executeStalePlanPredecessorConflict(_ write: MyDayPlanningConflictClassificationWriteV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        try authorized(access) { current in
            let receipt: MutationReceiptV1
            if let originalReceipt = try current.workspaceWriter.fieldDraftReceipt(for: write.mutation) {
                receipt = originalReceipt
            } else {
                guard try current.workspaceWriter.classifiableMyDayPlanEvidence(
                    draftID: write.evidence.currentCheckpoint.draftID) == write.evidence else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
                let original = try classificationOriginalRequest(write.evidence)
                let key = original.confirmedContext.key
                let target = try current.workspaceWriter.currentPlan(for: key)
                guard target != original.predecessor, target == write.observedTarget,
                      try reviewedTargetBasis(for: key, target: target, in: current) == write.observedTargetBasis else {
                    throw WorkspaceMutationFailureV1.staleWorkspaceRevision
                }
                receipt = try current.workspaceWriter.commitFieldDraft(write.mutation)
            }
            let pending = try current.workspaceWriter.pendingReviewedMyDayConflictEvidence(
                draftID: write.checkpoint.draftID)
            guard pending.conflictedCheckpoint == write.checkpoint,
                  pending.conflict.mutation == write.mutation, pending.conflict.receipt == receipt,
                  pending.editing == write.evidence.editing,
                  pending.preparedEpoch == write.evidence.preparedEpoch else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            return .init(checkpoint: write.checkpoint, receipt: receipt)
        }
    }

    func retryStalePlanPredecessorConflict(_ write: MyDayPlanningConflictClassificationWriteV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        try executeStalePlanPredecessorConflict(write, authorizing: access)
    }

    private func classificationOriginalRequest(_ evidence: ClassifiableMyDayPlanEvidenceV1) throws -> MyDayPlanningPlanSaveRequestV1 {
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(evidence.editingCheckpoint)
        guard let context = payload.confirmedContext, let intent = payload.editingIntent,
              context.key.workspaceID == workspaceID else {
            throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        return try .init(confirmedContext: context, editingIntent: intent)
    }


    func prepareStaleCarryoverTargetConflict(draftID: UUID,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCarryoverConflictClassificationWriteV1 {
        let seed = try authorized(access) { current in
            let evidence = try current.workspaceWriter.classifiableMyDayCarryoverEvidence(draftID: draftID)
            return (current, evidence, try classificationOriginalCarryoverRequest(evidence))
        }
        return try sourceProvider.withValidatedPlanningCarryoverSelection(
            sourceReference: seed.2.sourcePlan, membershipIDs: seed.2.selectedMembershipIDs,
            evaluatedAt: sampledInstant(), expectedSession: seed.0, authorizing: access) { current, _ in
            let evidence = try current.workspaceWriter.classifiableMyDayCarryoverEvidence(draftID: draftID)
            guard evidence == seed.1 else { throw FieldDraftFailureV1.staleDraftRevision }
            let original = seed.2
            let target = try current.workspaceWriter.currentPlan(for: original.confirmedContext.key)
            guard (try target.map(MyDayPlanReferenceV1.init)) != original.targetPredecessor else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let basis = try reviewedTargetBasis(for: original.confirmedContext.key, target: target, in: current)
            let previous = evidence.currentCheckpoint
            guard previous.draftRevision < UInt64.max else { throw FieldDraftFailureV1.invalidValue }
            let mutationID = try current.workspaceWriter.makeMutationID()
            if let epoch = evidence.preparedEpoch {
                let attempt = try MyDayPlanningDraftCodecV1.reconstructCommit(from: epoch.committingCheckpoint)
                guard !Set([attempt.command.mutationID, attempt.rowMutationIDs.terminalBundleMutationID]
                    + attempt.sagas.map(\.mutationID)).contains(mutationID) else {
                    throw FieldDraftFailureV1.invalidValue
                }
            }
            guard mutationID != previous.mutationID, mutationID.rawValue != previous.draftID else {
                throw FieldDraftFailureV1.invalidValue
            }
            let checkpoint = try FieldDraftCheckpointV1(draftID: previous.draftID,
                workspaceID: previous.workspaceID, scope: previous.scope,
                purpose: previous.purpose, codec: previous.codec,
                baseCanonicalRevision: previous.baseCanonicalRevision,
                draftRevision: previous.draftRevision + 1, payloadData: previous.payloadData,
                stageIDs: previous.stageIDs, resumeAnchor: previous.resumeAnchor,
                state: .conflicted, lastDurableMutationID: previous.lastDurableMutationID,
                lastReceiptSHA256: previous.lastReceiptSHA256,
                updatedAt: sampledInstant(), mutationID: mutationID)
            try checkpoint.validateSuccessor(of: previous, expectedDraftRevision: previous.draftRevision,
                expectedBaseRevision: previous.baseCanonicalRevision)
            let mutation = try FieldDraftMutationV1(workspaceID: workspaceID,
                expectedRevision: previous.draftRevision,
                expectedBaseCanonicalRevision: previous.baseCanonicalRevision,
                mutationID: mutationID, postImage: .reviseCheckpoint(checkpoint))
            return .init(evidence: evidence, observedTarget: target, observedTargetBasis: basis,
                checkpoint: checkpoint, mutation: mutation)
        }
    }

    func executeStaleCarryoverTargetConflict(_ write: MyDayPlanningCarryoverConflictClassificationWriteV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        let replay = try authorized(access) { current -> MyDayPlanningCheckpointAcknowledgementV1? in
            guard let receipt = try current.workspaceWriter.fieldDraftReceipt(for: write.mutation) else { return nil }
            return try acknowledgeCarryoverClassification(write, receipt: receipt, in: current)
        }
        if let replay { return replay }
        let expectedSession = try authorized(access) { $0 }
        let original = try classificationOriginalCarryoverRequest(write.evidence)
        return try sourceProvider.withValidatedPlanningCarryoverSelection(
            sourceReference: original.sourcePlan, membershipIDs: original.selectedMembershipIDs,
            evaluatedAt: sampledInstant(), expectedSession: expectedSession, authorizing: access) { current, _ in
            guard try current.workspaceWriter.classifiableMyDayCarryoverEvidence(
                draftID: write.evidence.currentCheckpoint.draftID) == write.evidence else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            let key = original.confirmedContext.key
            let target = try current.workspaceWriter.currentPlan(for: key)
            guard (try target.map(MyDayPlanReferenceV1.init)) != original.targetPredecessor,
                  target == write.observedTarget,
                  try reviewedTargetBasis(for: key, target: target, in: current) == write.observedTargetBasis else {
                throw WorkspaceMutationFailureV1.staleWorkspaceRevision
            }
            let receipt = try current.workspaceWriter.commitFieldDraft(write.mutation)
            return try acknowledgeCarryoverClassification(write, receipt: receipt, in: current)
        }
    }

    /// Called synchronously inside the original content hold; no fresh source selection.
    private func acknowledgeCarryoverClassification(_ write: MyDayPlanningCarryoverConflictClassificationWriteV1,
        receipt: MutationReceiptV1, in current: StoreSessionCoordinator) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        let pending = try current.workspaceWriter.pendingReviewedMyDayCarryoverConflictEvidence(
            draftID: write.checkpoint.draftID)
        guard pending.conflictedCheckpoint == write.checkpoint,
              pending.conflict.mutation == write.mutation, pending.conflict.receipt == receipt,
              pending.editing == write.evidence.editing,
              pending.preparedEpoch == write.evidence.preparedEpoch else {
            throw MyDayPlanningExecutionFailureV1.incompleteReadback
        }
        return .init(checkpoint: write.checkpoint, receipt: receipt)
    }

    func retryStaleCarryoverTargetConflict(_ write: MyDayPlanningCarryoverConflictClassificationWriteV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        try executeStaleCarryoverTargetConflict(write, authorizing: access)
    }

    private func classificationOriginalCarryoverRequest(_ evidence: ClassifiableMyDayCarryoverEvidenceV1) throws -> MyDayPlanningCarryoverRequestV1 {
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(evidence.editingCheckpoint)
        guard let context = payload.confirmedContext, let intent = payload.editingIntent,
              context.key.workspaceID == workspaceID else {
            throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        return try .init(confirmedContext: context, editingIntent: intent)
    }


    /// Read the existing conflict with its original source and selection intact.
    func carryoverConflictReview(draftID: UUID,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCarryoverConflictReviewV1 {
        let seed = try authorized(access) { current in
            let pending = try current.workspaceWriter.pendingReviewedMyDayCarryoverConflictEvidence(draftID: draftID)
            let original = try classificationOriginalCarryoverRequest(
                ClassifiableMyDayCarryoverEvidenceV1(editing: pending.editing,
                    preparedEpoch: pending.preparedEpoch))
            return (current, pending, original)
        }
        return try sourceProvider.withValidatedPlanningCarryoverSelection(
            sourceReference: seed.2.sourcePlan, membershipIDs: seed.2.selectedMembershipIDs,
            evaluatedAt: sampledInstant(), expectedSession: seed.0, authorizing: access) { current, _ in
            let pending = try current.workspaceWriter.pendingReviewedMyDayCarryoverConflictEvidence(draftID: draftID)
            guard pending == seed.1 else { throw FieldDraftFailureV1.staleDraftRevision }
            let original = seed.2
            let key = original.confirmedContext.key
            let target = try current.workspaceWriter.currentPlan(for: key)
            let basis = try reviewedTargetBasis(for: key, target: target, in: current)
            let request = try MyDayPlanningCarryoverRequestV1(confirmedContext: original.confirmedContext,
                sourcePlan: original.sourcePlan, selectedMembershipIDs: original.selectedMembershipIDs,
                targetPredecessor: target.map(MyDayPlanReferenceV1.init))
            return .init(pending: pending, originalEditingRequest: original, reviewRequest: request,
                capturedTarget: target, capturedTargetBasis: basis)
        }
    }

    func prepareReviewedCarryoverRebase(_ review: MyDayPlanningCarryoverConflictReviewV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningReviewedCarryoverResolutionWriteV1 {
        let expectedSession = try authorized(access) { $0 }
        let original = review.originalEditingRequest
        return try sourceProvider.withValidatedPlanningCarryoverSelection(
            sourceReference: original.sourcePlan, membershipIDs: original.selectedMembershipIDs,
            evaluatedAt: sampledInstant(), expectedSession: expectedSession, authorizing: access) { current, _ in
            try requireCurrentCarryoverConflictReview(review, in: current)
            let request = review.reviewRequest
            let payload = try MyDayPlanningDraftPayloadV1(editing: request.confirmedContext,
                intent: request.editingIntent)
            let previous = review.pending.conflictedCheckpoint
            guard previous.draftRevision < UInt64.max else { throw FieldDraftFailureV1.invalidValue }
            let mutationID = try current.workspaceWriter.makeMutationID()
            let successor = try FieldDraftCheckpointV1(draftID: previous.draftID,
                workspaceID: previous.workspaceID, scope: previous.scope,
                purpose: previous.purpose, codec: previous.codec,
                baseCanonicalRevision: review.capturedTargetBasis.targetRevision,
                draftRevision: previous.draftRevision + 1,
                payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: previous.stageIDs,
                resumeAnchor: previous.resumeAnchor, state: .active, updatedAt: sampledInstant(),
                mutationID: mutationID)
            let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
                expectedCheckpoint: previous, reviewedTargetBasis: review.capturedTargetBasis,
                successorCheckpoint: successor)
            let mutation = try FieldDraftMutationV1(workspaceID: workspaceID,
                expectedRevision: previous.draftRevision,
                expectedBaseCanonicalRevision: previous.baseCanonicalRevision,
                mutationID: mutationID, postImage: .resolveConflict(resolution))
            return .init(review: review, resolution: resolution, mutation: mutation)
        }
    }

    func executeReviewedCarryoverRebase(_ write: MyDayPlanningReviewedCarryoverResolutionWriteV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        let replay = try authorized(access) { current -> MyDayPlanningCheckpointAcknowledgementV1? in
            guard let receipt = try current.workspaceWriter.fieldDraftReceipt(for: write.mutation) else { return nil }
            return try acknowledgeCarryoverResolution(write, receipt: receipt, in: current)
        }
        if let replay { return replay }
        let expectedSession = try authorized(access) { $0 }
        let original = write.review.originalEditingRequest
        return try sourceProvider.withValidatedPlanningCarryoverSelection(
            sourceReference: original.sourcePlan, membershipIDs: original.selectedMembershipIDs,
            evaluatedAt: sampledInstant(), expectedSession: expectedSession, authorizing: access) { current, _ in
            try requireCurrentCarryoverConflictReview(write.review, in: current)
            let receipt = try current.workspaceWriter.commitFieldDraft(write.mutation)
            return try acknowledgeCarryoverResolution(write, receipt: receipt, in: current)
        }
    }

    func retryReviewedCarryoverRebase(_ write: MyDayPlanningReviewedCarryoverResolutionWriteV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        try executeReviewedCarryoverRebase(write, authorizing: access)
    }

    /// Original receipt recovery does not perform a new source eligibility decision.
    private func acknowledgeCarryoverResolution(_ write: MyDayPlanningReviewedCarryoverResolutionWriteV1,
        receipt: MutationReceiptV1, in current: StoreSessionCoordinator) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        guard let evidence = try current.workspaceWriter.reviewedFieldDraftResolutionEvidence(
            mutationID: write.mutation.mutationID),
              evidence.original.mutation == write.mutation,
              evidence.original.receipt == receipt,
              case let .resolveConflict(resolution) = evidence.original.mutation.postImage,
              resolution == write.resolution else {
            throw MyDayPlanningExecutionFailureV1.incompleteReadback
        }
        return .init(checkpoint: write.resolution.successorCheckpoint, receipt: receipt)
    }

    /// Called only within the provider-owned content hold, after source validation.
    private func requireCurrentCarryoverConflictReview(_ review: MyDayPlanningCarryoverConflictReviewV1,
        in current: StoreSessionCoordinator) throws {
        guard review.pending.conflictedCheckpoint.workspaceID == workspaceID,
              try current.workspaceWriter.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: review.pending.conflictedCheckpoint.draftID) == review.pending else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let original = review.originalEditingRequest
        let request = review.reviewRequest
        let key = original.confirmedContext.key
        let target = try current.workspaceWriter.currentPlan(for: key)
        guard request.confirmedContext == original.confirmedContext,
              request.sourcePlan == original.sourcePlan,
              request.selectedMembershipIDs == original.selectedMembershipIDs,
              request.targetPredecessor == (try target.map(MyDayPlanReferenceV1.init)),
              target == review.capturedTarget,
              try reviewedTargetBasis(for: key, target: target, in: current) == review.capturedTargetBasis else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
    }

    func planningConflictReview(draftID: UUID,
                                authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningConflictReviewV1 {
        try authorized(access) { current in
            let pending = try current.workspaceWriter.pendingReviewedMyDayConflictEvidence(draftID: draftID)
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(pending.editingCheckpoint)
            guard payload.phase == .editing, let context = payload.confirmedContext,
                  let intent = payload.editingIntent, context.key.workspaceID == workspaceID else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let original = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context, editingIntent: intent)
            let target = try current.workspaceWriter.currentPlan(for: context.key)
            let basis = try reviewedTargetBasis(for: context.key, target: target, in: current)
            let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context,
                draft: original.draft, predecessor: target)
            return .init(pending: pending, originalEditingRequest: original,
                reviewRequest: request, capturedTargetBasis: basis)
        }
    }

    /// The caller edits content only. Context and predecessor remain the exact
    /// originals and current target that were displayed when review opened.
    func prepareReviewedPlanRebase(_ review: MyDayPlanningConflictReviewV1,
                                   editedDraft: MyDayPlanDraftV1,
                                   authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningReviewedResolutionWriteV1 {
        try authorized(access) { current in
            try requireCurrentConflictReview(review, in: current)
            let request = try MyDayPlanningPlanSaveRequestV1(
                confirmedContext: review.originalEditingRequest.confirmedContext,
                draft: editedDraft, predecessor: review.reviewRequest.predecessor)
            let payload = try MyDayPlanningDraftPayloadV1(editing: request.confirmedContext,
                intent: request.editingIntent)
            let previous = review.pending.conflictedCheckpoint
            guard previous.draftRevision < UInt64.max else { throw FieldDraftFailureV1.invalidValue }
            let mutationID = try current.workspaceWriter.makeMutationID()
            let instant = try sampledInstant()
            let successor = try FieldDraftCheckpointV1(draftID: previous.draftID,
                workspaceID: previous.workspaceID, scope: previous.scope,
                purpose: previous.purpose, codec: previous.codec,
                baseCanonicalRevision: review.capturedTargetBasis.targetRevision,
                draftRevision: previous.draftRevision + 1,
                payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: previous.stageIDs,
                resumeAnchor: previous.resumeAnchor, state: .active, updatedAt: instant,
                mutationID: mutationID)
            let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
                expectedCheckpoint: previous, reviewedTargetBasis: review.capturedTargetBasis,
                successorCheckpoint: successor)
            let mutation = try FieldDraftMutationV1(workspaceID: workspaceID,
                expectedRevision: previous.draftRevision,
                expectedBaseCanonicalRevision: previous.baseCanonicalRevision,
                mutationID: mutationID, postImage: .resolveConflict(resolution))
            return .init(review: review, resolution: resolution, mutation: mutation)
        }
    }

    func executeReviewedPlanRebase(_ write: MyDayPlanningReviewedResolutionWriteV1,
                                   authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        try authorized(access) { current in
            let receipt: MutationReceiptV1
            if let existing = try current.workspaceWriter.fieldDraftReceipt(for: write.mutation) {
                receipt = existing
            } else {
                try requireCurrentConflictReview(write.review, in: current)
                receipt = try current.workspaceWriter.commitFieldDraft(write.mutation)
            }
            let successor = write.resolution.successorCheckpoint
            let adapter = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            guard try adapter.currentCheckpoint(workspaceID: workspaceID,
                draftID: successor.draftID) == successor,
                  try authenticatedEditingReceipt(successor, in: current) == receipt else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            return .init(checkpoint: successor, receipt: receipt)
        }
    }

    func retryReviewedPlanRebase(_ write: MyDayPlanningReviewedResolutionWriteV1,
                                 authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        try executeReviewedPlanRebase(write, authorizing: access)
    }

    private func requireCurrentConflictReview(_ review: MyDayPlanningConflictReviewV1,
                                              in current: StoreSessionCoordinator) throws {
        guard review.pending.conflictedCheckpoint.workspaceID == workspaceID,
              try current.workspaceWriter.pendingReviewedMyDayConflictEvidence(
                draftID: review.pending.conflictedCheckpoint.draftID) == review.pending else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let key = review.originalEditingRequest.confirmedContext.key
        let target = try current.workspaceWriter.currentPlan(for: key)
        guard target == review.reviewRequest.predecessor,
              try reviewedTargetBasis(for: key, target: target, in: current) == review.capturedTargetBasis else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
    }

    private func reviewedTargetBasis(for key: MyDayKeyV1, target: MyDayPlanV1?,
                                     in current: StoreSessionCoordinator) throws -> ReviewedMyDayTargetBasisV1 {
        if let target {
            return .existing(identity: try .init(kind: .myDayPlan, id: target.planID),
                key: target.key, revision: target.revision, canonicalSHA256: target.planSHA256)
        }
        return .absent(key: key, expectedWorkspaceRevision: try current.workspaceWriter.currentRevision().revision)
    }


    func loadPlanningCheckpoint(draftID: UUID,
                                authorizing access: AppAccessPresentationV1.ContentAccess) throws -> FieldDraftCheckpointV1 {
        try readCheckpoint(draftID, access: access)
    }

    func editingAcknowledgement(draftID: UUID,
                                authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
        let checkpoint = try readCheckpoint(draftID, access: access)
        return try authorized(access) { current in
            let receipt = try authenticatedEditingReceipt(checkpoint, in: current)
            return .init(checkpoint: checkpoint, receipt: receipt)
        }
    }

    /// Called only inside the incumbent synchronous authority hold. Receipt
    /// origin is immutable even when the active checkpoint came from review.
    private func authenticatedEditingReceipt(_ checkpoint: FieldDraftCheckpointV1,
                                              in current: StoreSessionCoordinator) throws -> MutationReceiptV1 {
        let ordinary = try editingCheckpointMutation(checkpoint)
        if let original = try current.workspaceWriter.fieldDraftEvidence(mutationID: checkpoint.mutationID),
           case let .resolveConflict(resolution) = original.mutation.postImage {
            guard resolution.successorCheckpoint == checkpoint,
                  let reviewed = try current.workspaceWriter.reviewedFieldDraftResolutionEvidence(
                    mutationID: checkpoint.mutationID), reviewed.original == original else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            return original.receipt
        }
        guard let receipt = try current.workspaceWriter.fieldDraftReceipt(for: ordinary) else {
            throw MyDayPlanningExecutionFailureV1.incompleteReadback
        }
        return receipt
    }

    private func editingCheckpointMutation(_ checkpoint: FieldDraftCheckpointV1) throws -> FieldDraftMutationV1 {
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
        guard checkpoint.workspaceID == workspaceID, checkpoint.state == .active,
              payload.phase == .editing, payload.editingIntent != nil,
              checkpoint.lastDurableMutationID == nil, checkpoint.lastReceiptSHA256 == nil else {
            throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        return try FieldDraftMutationV1(workspaceID: workspaceID,
            expectedRevision: checkpoint.draftRevision - 1,
            expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
            mutationID: checkpoint.mutationID,
            postImage: checkpoint.draftRevision == 1 ? .createCheckpoint(checkpoint) : .reviseCheckpoint(checkpoint))
    }

    private func validateEditingWrite(_ write: MyDayPlanningEditingWriteV1) throws {
        _ = try editingCheckpointMutation(write.checkpoint)
        if let previous = write.expectedCheckpoint {
            _ = try editingCheckpointMutation(previous)
            let oldPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(previous)
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(write.checkpoint)
            guard let oldIntent = oldPayload.editingIntent,
                  let intent = payload.editingIntent,
                  intent.hasSamePlanningBase(as: oldIntent),
                  payload.confirmedContext?.key == oldPayload.confirmedContext?.key else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            try write.checkpoint.validateSuccessor(of: previous,
                expectedDraftRevision: previous.draftRevision,
                expectedBaseRevision: previous.baseCanonicalRevision)
        } else if write.checkpoint.draftRevision != 1 {
            throw FieldDraftFailureV1.staleDraftRevision
        }
    }

    func savePlan(_ request: MyDayPlanningPlanSaveRequestV1,
                  authorizing access: AppAccessPresentationV1.ContentAccess) async throws -> MyDayPlanningCommitOutcomeV1 {
        try await savePlanningRequest(request, authorizing: access)
    }

    func saveCarryover(_ request: MyDayPlanningCarryoverRequestV1,
                      authorizing access: AppAccessPresentationV1.ContentAccess) async throws -> MyDayPlanningCommitOutcomeV1 {
        try await savePlanningRequest(request, authorizing: access)
    }

    private func savePlanningRequest<Request: MyDayPlanningEditingRequestV1>(_ request: Request,
                  authorizing access: AppAccessPresentationV1.ContentAccess) async throws -> MyDayPlanningCommitOutcomeV1 {
        let checkpoint = try authorized(access) { current in
            let payload = try MyDayPlanningDraftPayloadV1(editing: request.confirmedContext,
                intent: request.editingIntent)
            guard request.confirmedContext.key.workspaceID == workspaceID else {
                throw MyDayFailureV1.wrongWorkspace
            }
            let draftID = idSource.makeID()
            let mutationID = try current.workspaceWriter.makeMutationID()
            guard draftID != mutationID.rawValue else { throw FieldDraftFailureV1.invalidValue }
            return try FieldDraftCheckpointV1(draftID: draftID, workspaceID: workspaceID,
                scope: MyDayPlanningDraftCodecV1.scope(for: request.confirmedContext.key),
                purpose: .myDayPlanning, codec: MyDayPlanningDraftCodecV1.release(),
                baseCanonicalRevision: request.editingIntent.targetBaseRevision, draftRevision: 1,
                payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: [],
                resumeAnchor: .init(sectionID: "planning"), state: .active,
                updatedAt: sampledInstant(), mutationID: mutationID)
        }
        // The adapter may have committed even if a later acknowledgement
        // failed, so preserve this identity in every subsequent failure.
        do {
            try persistCheckpoint(checkpoint, expectedRevision: 0, access: access)
            return try await retryPlanningCommit(draftID: checkpoint.draftID, authorizing: access)
        } catch {
            throw MyDayPlanningSaveFailureV1(draftID: checkpoint.draftID, underlying: error)
        }
    }

    func retryPlanSave(draftID: UUID,
                       authorizing access: AppAccessPresentationV1.ContentAccess) async throws -> MyDayPlanningCommitOutcomeV1 {
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(
            readCheckpoint(draftID, access: access))
        switch payload.phase {
        case .editing:
            guard case .plan? = payload.editingIntent else {
                throw MyDayPlanningExecutionFailureV1.unsupportedCommand
            }
        case .preparedCommit:
            guard case .save? = payload.commitAttempt?.command else {
                throw MyDayPlanningExecutionFailureV1.unsupportedCommand
            }
        }
        return try await retryPlanningCommit(draftID: draftID, authorizing: access)
    }

    func retryPlanningCommit(draftID: UUID,
                       authorizing access: AppAccessPresentationV1.ContentAccess) async throws -> MyDayPlanningCommitOutcomeV1 {
        try Task.checkCancellation()
        var checkpoint = try readCheckpoint(draftID, access: access)
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
        if checkpoint.state == .committed {
            return try terminalReadback(checkpoint: checkpoint, access: access)
        }
        if checkpoint.state == .active, payload.phase == .editing {
            checkpoint = try prepare(checkpoint: checkpoint, payload: payload, access: access)
        }
        guard checkpoint.state == .committing else {
            throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        let reconstruction = try MyDayPlanningDraftCodecV1.reconstructCommit(from: checkpoint)
        let coordinator = try makeCoordinator(reconstruction: reconstruction, access: access)
        let receipt = try await coordinator.commit(plan: reconstruction.plan, checkpoint: checkpoint,
            items: [], prepared: reconstruction.prepared, contentPromoted: reconstruction.contentPromoted,
            targetCommitted: reconstruction.targetCommitted, retirePending: reconstruction.retirePending,
            retired: reconstruction.retired, commitReceiptID: reconstruction.commitReceiptID,
            terminalCheckpointUpdatedAt: reconstruction.terminalCheckpointUpdatedAt,
            rowMutationIDs: reconstruction.rowMutationIDs)
        try Task.checkCancellation()
        let outcome = try terminalReadback(checkpoint: readCheckpoint(draftID, access: access), access: access)
        guard outcome.draftReceipt == receipt else { throw MyDayPlanningExecutionFailureV1.incompleteReadback }
        return outcome
    }

    fileprivate func authorized<T>(_ access: AppAccessPresentationV1.ContentAccess,
                                    _ body: (StoreSessionCoordinator) throws -> T) throws -> T {
        try Task.checkCancellation()
        return try access.withRead {
            guard let session, let originalWriter,
                  session.workspaceID == workspaceID, session.generationID == generationID,
                  session.uiGenerationToken == uiGenerationToken,
                  session.workspaceWriter === originalWriter else {
                throw MyDaySourceReadFailureV1.sessionChanged
            }
            try sourceProvider.validatePlanningBinding(access, expectedSession: session)
            _ = try originalWriter.currentRevision()
            return try body(session)
        }
    }

    private func sampledInstant() throws -> Date {
        let milliseconds = (clock.now().timeIntervalSince1970 * 1_000).rounded(.toNearestOrAwayFromZero)
        let value = Date(timeIntervalSince1970: milliseconds / 1_000)
        try MyDayLimitsV1.millisecondInstant(value)
        return value
    }

    private func readCheckpoint(_ draftID: UUID,
                                access: AppAccessPresentationV1.ContentAccess) throws -> FieldDraftCheckpointV1 {
        try authorized(access) { current in
            let adapter = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            guard let checkpoint = try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: draftID) else {
                throw MyDayPlanningExecutionFailureV1.missingDraft
            }
            try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
            if checkpoint.state == .active {
                _ = try authenticatedEditingReceipt(checkpoint, in: current)
                return checkpoint
            }
            if checkpoint.state == .committing {
                let mutation = try FieldDraftMutationV1(workspaceID: workspaceID,
                    expectedRevision: checkpoint.draftRevision - 1,
                    expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
                    mutationID: checkpoint.mutationID,
                    postImage: checkpoint.draftRevision == 1 ? .createCheckpoint(checkpoint) : .reviseCheckpoint(checkpoint))
                guard try current.workspaceWriter.fieldDraftReceipt(for: mutation) != nil else {
                    throw MyDayPlanningExecutionFailureV1.incompleteReadback
                }
            }
            return checkpoint
        }
    }

    private func persistCheckpoint(_ checkpoint: FieldDraftCheckpointV1, expectedRevision: UInt64,
                                   access: AppAccessPresentationV1.ContentAccess) throws {
        let coordinator = try makeCoordinator(reconstruction: nil, access: access)
        let receipt = try coordinator.checkpoint(checkpoint,
            expectedDraftRevision: expectedRevision, expectedBaseRevision: checkpoint.baseCanonicalRevision)
        let mutation = try FieldDraftMutationV1(workspaceID: workspaceID,
            expectedRevision: expectedRevision, expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
            mutationID: checkpoint.mutationID,
            postImage: expectedRevision == 0 ? .createCheckpoint(checkpoint) : .reviseCheckpoint(checkpoint))
        guard try readCheckpoint(checkpoint.draftID, access: access) == checkpoint,
              try authorized(access, { try $0.workspaceWriter.fieldDraftReceipt(for: mutation) }) == receipt else {
            throw MyDayPlanningExecutionFailureV1.incompleteReadback
        }
    }

    private func prepare(checkpoint: FieldDraftCheckpointV1, payload: MyDayPlanningDraftPayloadV1,
                         access: AppAccessPresentationV1.ContentAccess) throws -> FieldDraftCheckpointV1 {
        guard let intent = payload.editingIntent else {
            throw MyDayPlanningExecutionFailureV1.unsupportedCommand
        }
        let prepared: FieldDraftCheckpointV1
        switch intent {
        case .plan:
            prepared = try authorized(access) { current in
                guard let context = payload.confirmedContext,
                      case let .plan(draft, predecessor)? = payload.editingIntent else {
                    throw MyDayPlanningExecutionFailureV1.unsupportedCommand
                }
                let instant = try sampledInstant()
                guard instant >= checkpoint.updatedAt, checkpoint.draftRevision < UInt64.max else {
                    throw FieldDraftFailureV1.invalidValue
                }
                var allocated = Set([checkpoint.draftID, checkpoint.mutationID.rawValue])
                func nextID() throws -> UUID {
                    let id = idSource.makeID()
                    try MyDayLimitsV1.id(id)
                    guard allocated.insert(id).inserted else { throw FieldDraftFailureV1.invalidValue }
                    return id
                }
                @MainActor func nextMutation() throws -> MutationIDV1 {
                    let id = try current.workspaceWriter.makeMutationID()
                    guard allocated.insert(id.rawValue).inserted else { throw FieldDraftFailureV1.invalidValue }
                    return id
                }
                let planID = try predecessor?.planID ?? nextID()
                let commandID = try nextMutation()
                let workflow = MyDayWorkflowCoordinatorV1(canonical: MyDayCoordinatorV1(
                    writer: current.workspaceWriter, sourceReader: MyDayPlanningUnusedPreviewSourcesV1()),
                    clock: MyDayPlanningFrozenClockV1(instant: instant))
                let preview = try workflow.previewSave(draft: draft, predecessor: predecessor,
                    planID: planID, mutationID: commandID, actor: context.recordedBy)
                let command = MyDayCommandV1.save(successor: preview.successor,
                    predecessor: preview.predecessor)
                let attempt = try MyDayPlanningCommitAttemptInputsV1(
                    command: command,
                    fieldDraftPlanID: nextID(), preparedSagaID: nextID(), contentPromotedSagaID: nextID(),
                    targetCommittedSagaID: nextID(), draftRetirePendingSagaID: nextID(), draftRetiredSagaID: nextID(),
                    preparedSagaMutationID: nextMutation(), contentPromotedSagaMutationID: nextMutation(),
                    targetCommittedSagaMutationID: nextMutation(), draftRetirePendingSagaMutationID: nextMutation(),
                    terminalBundleMutationID: nextMutation(), commitReceiptID: nextID(),
                    preparedSagaUpdatedAt: instant, contentPromotedSagaUpdatedAt: instant,
                    targetCommittedSagaUpdatedAt: instant, draftRetirePendingSagaUpdatedAt: instant,
                    draftRetiredSagaUpdatedAt: instant, terminalCheckpointUpdatedAt: instant)
                return try FieldDraftCheckpointV1(draftID: checkpoint.draftID, workspaceID: workspaceID,
                    scope: checkpoint.scope, purpose: checkpoint.purpose, codec: checkpoint.codec,
                    baseCanonicalRevision: checkpoint.baseCanonicalRevision, draftRevision: checkpoint.draftRevision + 1,
                    payloadData: MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt)), stageIDs: [],
                    resumeAnchor: checkpoint.resumeAnchor, state: .committing, updatedAt: instant,
                    mutationID: nextMutation())
            }
        case let .carryover(source, memberships, targetKey, predecessor):
            let inputs = try authorized(access) { current in
                guard let context = payload.confirmedContext else {
                    throw MyDayPlanningExecutionFailureV1.unsupportedCommand
                }
                let instant = try sampledInstant()
                guard instant >= checkpoint.updatedAt, checkpoint.draftRevision < UInt64.max else {
                    throw FieldDraftFailureV1.invalidValue
                }
                var allocated = Set([checkpoint.draftID, checkpoint.mutationID.rawValue])
                func nextID() throws -> UUID {
                    let id = idSource.makeID()
                    try MyDayLimitsV1.id(id)
                    guard allocated.insert(id).inserted else { throw FieldDraftFailureV1.invalidValue }
                    return id
                }
                @MainActor func nextMutation() throws -> MutationIDV1 {
                    let id = try current.workspaceWriter.makeMutationID()
                    guard allocated.insert(id.rawValue).inserted else { throw FieldDraftFailureV1.invalidValue }
                    return id
                }
                let targetPlanID = try predecessor?.planID ?? nextID()
                let commandID = try nextMutation()
                return MyDayPlanningCarryoverPreparationV1(
                    sourceReference: source, membershipIDs: memberships, targetKey: targetKey,
                    targetReference: predecessor, actor: context.recordedBy, instant: instant,
                    targetPlanID: targetPlanID, commandID: commandID,
                    allocated: allocated, expectedSession: current)
            }
            let command = try sourceProvider.preparePlanningCarryover(
                sourceReference: inputs.sourceReference, targetKey: inputs.targetKey,
                targetReference: inputs.targetReference, membershipIDs: inputs.membershipIDs,
                targetPlanID: inputs.targetPlanID, mutationID: inputs.commandID,
                actor: inputs.actor, authoredAt: inputs.instant,
                expectedSession: inputs.expectedSession, authorizing: access)
            prepared = try authorized(access) { current in
                guard current === inputs.expectedSession else {
                    throw MyDaySourceReadFailureV1.sessionChanged
                }
                var allocated = inputs.allocated
                func nextID() throws -> UUID {
                    let id = idSource.makeID()
                    try MyDayLimitsV1.id(id)
                    guard allocated.insert(id).inserted else { throw FieldDraftFailureV1.invalidValue }
                    return id
                }
                @MainActor func nextMutation() throws -> MutationIDV1 {
                    let id = try current.workspaceWriter.makeMutationID()
                    guard allocated.insert(id.rawValue).inserted else { throw FieldDraftFailureV1.invalidValue }
                    return id
                }
                let attempt = try MyDayPlanningCommitAttemptInputsV1(
                    command: command,
                    fieldDraftPlanID: nextID(), preparedSagaID: nextID(), contentPromotedSagaID: nextID(),
                    targetCommittedSagaID: nextID(), draftRetirePendingSagaID: nextID(), draftRetiredSagaID: nextID(),
                    preparedSagaMutationID: nextMutation(), contentPromotedSagaMutationID: nextMutation(),
                    targetCommittedSagaMutationID: nextMutation(), draftRetirePendingSagaMutationID: nextMutation(),
                    terminalBundleMutationID: nextMutation(), commitReceiptID: nextID(),
                    preparedSagaUpdatedAt: inputs.instant, contentPromotedSagaUpdatedAt: inputs.instant,
                    targetCommittedSagaUpdatedAt: inputs.instant, draftRetirePendingSagaUpdatedAt: inputs.instant,
                    draftRetiredSagaUpdatedAt: inputs.instant, terminalCheckpointUpdatedAt: inputs.instant)
                return try FieldDraftCheckpointV1(draftID: checkpoint.draftID, workspaceID: workspaceID,
                    scope: checkpoint.scope, purpose: checkpoint.purpose, codec: checkpoint.codec,
                    baseCanonicalRevision: checkpoint.baseCanonicalRevision, draftRevision: checkpoint.draftRevision + 1,
                    payloadData: MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt)), stageIDs: [],
                    resumeAnchor: checkpoint.resumeAnchor, state: .committing, updatedAt: inputs.instant,
                    mutationID: nextMutation())
            }
        }
        try persistCheckpoint(prepared, expectedRevision: checkpoint.draftRevision, access: access)
        return try readCheckpoint(checkpoint.draftID, access: access)
    }

    /// A discard decision binds the complete value shown to the person. Freeze
    /// both effects before writing so an uncertain reply cannot resample them.
    func preparePlanningDiscard(expectedCheckpoint: FieldDraftCheckpointV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningDiscardWriteV1 {
        try authorized(access) { current in
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(expectedCheckpoint)
            guard expectedCheckpoint.workspaceID == workspaceID, payload.phase == .editing,
                  [.active, .recoveryRequired, .discardPending].contains(expectedCheckpoint.state) else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            try requireDiscardCheckpoint(expectedCheckpoint, current: current)
            try Self.validateDiscardCapacity(state: expectedCheckpoint.state,
                draftRevision: expectedCheckpoint.draftRevision,
                workspaceRevision: current.workspaceWriter.currentRevision().revision)
            try Self.requireZeroDiscardContent(draftID: expectedCheckpoint.draftID, current: current)
            guard try discardReceipts(draftID: expectedCheckpoint.draftID, current: current).isEmpty else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            let instant = try sampledInstant()
            guard instant >= expectedCheckpoint.updatedAt else { throw FieldDraftFailureV1.invalidValue }
            var ids = Set([expectedCheckpoint.draftID, expectedCheckpoint.mutationID.rawValue])
            if let last = expectedCheckpoint.lastDurableMutationID { ids.insert(last.rawValue) }
            let pending: FieldDraftCheckpointV1
            if expectedCheckpoint.state == .discardPending {
                pending = expectedCheckpoint
            } else {
                let mutationID = try current.workspaceWriter.makeMutationID()
                guard ids.insert(mutationID.rawValue).inserted else { throw FieldDraftFailureV1.invalidValue }
                pending = try Self.discardCheckpoint(from: expectedCheckpoint, state: .discardPending,
                    instant: instant, mutationID: mutationID, receipt: nil)
            }
            let plan = try Self.discardPlan(for: pending)
            let receiptID = idSource.makeID()
            let terminalMutationID = try current.workspaceWriter.makeMutationID()
            guard ids.insert(receiptID).inserted,
                  ids.insert(terminalMutationID.rawValue).inserted else { throw FieldDraftFailureV1.invalidValue }
            let receipt = try DraftDiscardReceiptV1(receiptID: receiptID, workspaceID: workspaceID,
                draftID: pending.draftID, planSHA256: plan.planSHA256, disposedStageIDs: [],
                quarantinedReservationIDs: [], discardedAt: instant, mutationID: terminalMutationID)
            let terminal = try Self.discardCheckpoint(from: pending, state: .discarded,
                instant: instant, mutationID: terminalMutationID, receipt: receipt)
            let write = MyDayPlanningDiscardWriteV1(expectedCheckpoint: expectedCheckpoint,
                pendingCheckpoint: pending, plan: plan,
                terminalBundle: try .init(discardedCheckpoint: terminal, receipt: receipt))
            try Self.validateDiscardWrite(write)
            return write
        }
    }

    func discardPlanningDraft(_ write: MyDayPlanningDiscardWriteV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) async throws -> MyDayPlanningDiscardOutcomeV1 {
        try Self.validateDiscardWrite(write)
        let observed = try readCheckpoint(write.pendingCheckpoint.draftID, access: access)
        if observed == write.terminalBundle.discardedCheckpoint {
            let outcome = try discardedPlanningAcknowledgement(expectedCheckpoint: observed, authorizing: access)
            guard outcome.draftReceipt == write.terminalBundle.receipt else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            return outcome
        }
        guard observed == write.expectedCheckpoint || observed == write.pendingCheckpoint else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        try authorized(access) { current in
            try requireDiscardCheckpoint(observed, current: current)
            try Self.requireZeroDiscardContent(draftID: observed.draftID, current: current)
            guard try discardReceipts(draftID: observed.draftID, current: current).isEmpty else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
        }
        let coordinator = try makeCoordinator(reconstruction: nil, discardWrite: write, access: access)
        if observed != write.pendingCheckpoint {
            let receipt = try coordinator.checkpoint(write.pendingCheckpoint,
                expectedDraftRevision: observed.draftRevision, expectedBaseRevision: observed.baseCanonicalRevision)
            try authorized(access) { current in
                try requireDiscardCheckpoint(write.pendingCheckpoint, current: current)
                guard try current.workspaceWriter.fieldDraftReceipt(for:
                    Self.discardCheckpointMutation(write.pendingCheckpoint)) == receipt else {
                    throw MyDayPlanningExecutionFailureV1.incompleteReadback
                }
            }
        }
        try authorized(access) { current in
            try requireDiscardCheckpoint(write.pendingCheckpoint, current: current)
            try Self.requireZeroDiscardContent(draftID: observed.draftID, current: current)
            guard try discardReceipts(draftID: observed.draftID, current: current).isEmpty else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
        }
        let frozen = write.terminalBundle.receipt
        let receipt = try await coordinator.discard(plan: write.plan, checkpoint: write.pendingCheckpoint,
            reservations: [], disposedStageIDs: [], discardReceiptID: frozen.receiptID,
            at: frozen.discardedAt, mutationID: frozen.mutationID)
        let outcome = try discardedPlanningAcknowledgement(
            expectedCheckpoint: write.terminalBundle.discardedCheckpoint, authorizing: access)
        guard receipt == frozen, outcome.draftReceipt == frozen else {
            throw MyDayPlanningExecutionFailureV1.incompleteReadback
        }
        return outcome
    }

    /// Terminal proof uses the actual terminal bundle and journal receipt.
    /// The pending mutation ID has been replaced; no pending history is invented.
    func discardedPlanningAcknowledgement(expectedCheckpoint: FieldDraftCheckpointV1,
        authorizing access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningDiscardOutcomeV1 {
        try authorized(access) { current in
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(expectedCheckpoint)
            guard payload.phase == .editing, expectedCheckpoint.state == .discarded,
                  expectedCheckpoint.workspaceID == workspaceID, expectedCheckpoint.draftRevision > 1 else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let adapter = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            guard try adapter.currentCheckpoint(workspaceID: workspaceID,
                draftID: expectedCheckpoint.draftID) == expectedCheckpoint else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            try Self.requireZeroDiscardContent(draftID: expectedCheckpoint.draftID, current: current)
            let receipts = try discardReceipts(draftID: expectedCheckpoint.draftID, current: current)
            guard receipts.count == 1, let receipt = receipts.first,
                  receipt.workspaceID == workspaceID, receipt.draftID == expectedCheckpoint.draftID,
                  receipt.mutationID == expectedCheckpoint.mutationID,
                  receipt.discardedAt == expectedCheckpoint.updatedAt,
                  receipt.disposedStageIDs.isEmpty, receipt.quarantinedReservationIDs.isEmpty,
                  receipt.planSHA256 == (try Self.discardPlan(for: expectedCheckpoint)).planSHA256 else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            let bundle = try DraftDiscardTerminalBundleV1(discardedCheckpoint: expectedCheckpoint, receipt: receipt)
            let mutation = try FieldDraftMutationV1(workspaceID: workspaceID,
                expectedRevision: expectedCheckpoint.draftRevision - 1,
                expectedBaseCanonicalRevision: expectedCheckpoint.baseCanonicalRevision,
                mutationID: expectedCheckpoint.mutationID, postImage: .applyDiscardTerminal(bundle))
            guard let terminalReceipt = try current.workspaceWriter.fieldDraftReceipt(for: mutation) else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            return .init(checkpoint: expectedCheckpoint, draftReceipt: receipt, terminalReceipt: terminalReceipt)
        }
    }

    /// The existing rows store signed 64-bit revisions. This is a pure
    /// admission check; the real writer still validates each actual effect.
    static func validateDiscardCapacity(state: FieldDraftStateV1, draftRevision: UInt64,
                                        workspaceRevision: UInt64) throws {
        let steps: UInt64
        switch state {
        case .active, .recoveryRequired: steps = 2
        case .discardPending: steps = 1
        default: throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        let ceiling = UInt64(Int64.max)
        guard draftRevision > 0, draftRevision <= ceiling - steps,
              workspaceRevision <= ceiling - steps else {
            throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
    }

    fileprivate static func requireZeroDiscardContent(draftID: UUID, current: StoreSessionCoordinator) throws {
        let stages = try current.modelContext.fetch(FetchDescriptor<AttachmentStagingItemRow>(
            predicate: #Predicate { $0.draftID == draftID }))
        let reservations = try current.modelContext.fetch(FetchDescriptor<DraftContentReservationRow>(
            predicate: #Predicate { $0.draftID == draftID }))
        let sagas = try current.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>(
            predicate: #Predicate { $0.draftID == draftID }))
        let commits = try current.modelContext.fetch(FetchDescriptor<DraftCommitReceiptRow>(
            predicate: #Predicate { $0.draftID == draftID }))
        guard stages.isEmpty, reservations.isEmpty, sagas.isEmpty, commits.isEmpty else {
            throw MyDayPlanningExecutionFailureV1.incompleteReadback
        }
    }

    fileprivate func requireDiscardCheckpoint(_ checkpoint: FieldDraftCheckpointV1,
                                               current: StoreSessionCoordinator) throws {
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
        guard payload.phase == .editing, checkpoint.workspaceID == workspaceID,
              [.active, .recoveryRequired, .discardPending].contains(checkpoint.state) else {
            throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        let adapter = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
        guard try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: checkpoint.draftID) == checkpoint else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        if checkpoint.state == .active {
            _ = try authenticatedEditingReceipt(checkpoint, in: current)
            return
        }
        guard try current.workspaceWriter.fieldDraftReceipt(for: Self.discardCheckpointMutation(checkpoint)) != nil else {
            throw MyDayPlanningExecutionFailureV1.incompleteReadback
        }
    }

    fileprivate func discardReceipts(draftID: UUID, current: StoreSessionCoordinator) throws -> [DraftDiscardReceiptV1] {
        try current.modelContext.fetch(FetchDescriptor<DraftDiscardReceiptRow>(
            predicate: #Predicate { $0.draftID == draftID })).map { try $0.value() }
    }

    private static func discardCheckpointMutation(_ checkpoint: FieldDraftCheckpointV1) throws -> FieldDraftMutationV1 {
        try .init(workspaceID: checkpoint.workspaceID, expectedRevision: checkpoint.draftRevision - 1,
            expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision, mutationID: checkpoint.mutationID,
            postImage: checkpoint.draftRevision == 1 ? .createCheckpoint(checkpoint) : .reviseCheckpoint(checkpoint))
    }

    private static func discardPlan(for checkpoint: FieldDraftCheckpointV1) throws -> DraftDiscardPlanV1 {
        guard [.discardPending, .discarded].contains(checkpoint.state), checkpoint.draftRevision > 1 else {
            throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        return try .init(planID: checkpoint.draftID, workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID,
            expectedDraftRevision: checkpoint.draftRevision - (checkpoint.state == .discarded ? 1 : 0),
            nonemptyPayload: true, stageIDs: [], reservationIDs: [], estimatedBytes: Int64(checkpoint.payloadData.count))
    }

    private static func discardCheckpoint(from prior: FieldDraftCheckpointV1, state: FieldDraftStateV1,
        instant: Date, mutationID: MutationIDV1, receipt: DraftDiscardReceiptV1?) throws -> FieldDraftCheckpointV1 {
        guard prior.draftRevision < UInt64.max else { throw FieldDraftFailureV1.staleDraftRevision }
        let value = try FieldDraftCheckpointV1(draftID: prior.draftID, workspaceID: prior.workspaceID,
            scope: prior.scope, purpose: prior.purpose, codec: prior.codec,
            baseCanonicalRevision: prior.baseCanonicalRevision, draftRevision: prior.draftRevision + 1,
            payloadData: prior.payloadData, stageIDs: prior.stageIDs, resumeAnchor: prior.resumeAnchor,
            state: state, lastDurableMutationID: receipt?.mutationID ?? prior.lastDurableMutationID,
            lastReceiptSHA256: receipt?.receiptSHA256 ?? prior.lastReceiptSHA256,
            updatedAt: instant, mutationID: mutationID)
        try value.validateSuccessor(of: prior, expectedDraftRevision: prior.draftRevision,
            expectedBaseRevision: prior.baseCanonicalRevision)
        try MyDayPlanningDraftCodecV1.validateCheckpointPayload(value)
        return value
    }

    private static func validateDiscardWrite(_ write: MyDayPlanningDiscardWriteV1) throws {
        let expected = write.expectedCheckpoint, pending = write.pendingCheckpoint
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(expected)
        guard payload.phase == .editing,
              [.active, .recoveryRequired, .discardPending].contains(expected.state),
              pending.state == .discardPending else { throw MyDayPlanningExecutionFailureV1.unsupportedState }
        if expected.state == .discardPending {
            guard expected == pending else { throw FieldDraftFailureV1.invalidValue }
        } else {
            guard pending == (try discardCheckpoint(from: expected, state: .discardPending,
                instant: pending.updatedAt, mutationID: pending.mutationID, receipt: nil)) else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
        guard write.plan == (try discardPlan(for: pending)) else { throw FieldDraftFailureV1.invalidValue }
        let receipt = write.terminalBundle.receipt
        let terminal = write.terminalBundle.discardedCheckpoint
        try write.terminalBundle.validate()
        let receiptIDs = [expected.draftID, pending.mutationID.rawValue, receipt.receiptID, receipt.mutationID.rawValue]
        guard Set(receiptIDs).count == receiptIDs.count,
              receipt.receiptID != expected.mutationID.rawValue,
              receipt.mutationID != expected.mutationID,
              receipt.planSHA256 == write.plan.planSHA256,
              receipt.disposedStageIDs.isEmpty, receipt.quarantinedReservationIDs.isEmpty,
              terminal == (try discardCheckpoint(from: pending, state: .discarded,
                instant: receipt.discardedAt, mutationID: receipt.mutationID, receipt: receipt)) else {
            throw FieldDraftFailureV1.invalidValue
        }
    }
    private func makeCoordinator(reconstruction: MyDayPlanningCommitReconstructionV1?,
                                 discardWrite: MyDayPlanningDiscardWriteV1? = nil,
                                 access: AppAccessPresentationV1.ContentAccess) throws -> FieldDraftCoordinatorV1 {
        let content = ProductionMyDayZeroStageContentPortV1(expectedPlan: reconstruction?.plan,
            afterPromotion: { [weak self] in
                #if DEBUG
                try await self?.afterZeroStagePromotionForTesting?()
                #endif
            }, expectedDiscardPlan: discardWrite?.plan, afterQuarantine: { [weak self] in
                #if DEBUG
                try await self?.afterZeroStageDiscardForTesting?()
                #endif
            })
        return FieldDraftCoordinatorV1(purposeAuthority: try MyDayPlanningDraftPurposeAuthorityV1(),
            writer: MyDayPlanningAuthorizedDraftWriterV1(service: self, access: access, discardWrite: discardWrite), content: content,
            target: MyDayPlanningCanonicalTargetV1(service: self, access: access,
                reconstruction: reconstruction, sourceProvider: sourceProvider))
    }

    /// A committed checkpoint is not an original COMMITTING checkpoint. Read
    /// and bind the retained five-event saga instead of inventing its revision.
    private func terminalReadback(checkpoint: FieldDraftCheckpointV1,
                                  access: AppAccessPresentationV1.ContentAccess) throws -> MyDayPlanningCommitOutcomeV1 {
        try authorized(access) { current in
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
            guard checkpoint.state == .committed, let attempt = payload.commitAttempt else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let successor = attempt.command.productionPlanningTarget
            let baseRevision = attempt.command.productionPlanningBaseRevision
            let draftID = checkpoint.draftID
            let sagaRows = try current.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>(
                predicate: #Predicate { $0.draftID == draftID }))
            let allSagas = try sagaRows.map { try $0.value() }
            let ids = [attempt.preparedSagaID, attempt.contentPromotedSagaID,
                attempt.targetCommittedSagaID, attempt.draftRetirePendingSagaID, attempt.draftRetiredSagaID]
            let mutations = attempt.sagaMutationIDs + [attempt.terminalBundleMutationID]
            let states: [DraftCommitSagaStateV1] = [.prepared, .contentPromotedUnbound,
                .targetCommitted, .draftRetirePending, .draftRetired]
            var chain: [DraftCommitSagaV1] = []
            for index in ids.indices {
                let matches = allSagas.filter { $0.sagaID == ids[index] }
                guard matches.count == 1, let saga = matches.first,
                      saga.workspaceID == workspaceID, saga.draftID == draftID,
                      saga.mutationID == mutations[index], saga.state == states[index],
                      saga.revision == UInt64(index + 1), saga.updatedAt == attempt.sagaUpdatedAts[index] else {
                    throw MyDayPlanningExecutionFailureV1.incompleteReadback
                }
                if let prior = chain.last { try saga.validateSuccessor(of: prior) }
                else if saga.predecessorSagaID != nil { throw MyDayPlanningExecutionFailureV1.incompleteReadback }
                chain.append(saga)
            }
            guard let retired = chain.last, let prepared = chain.first,
                  allSagas.filter({ $0.plan.planID == attempt.fieldDraftPlanID }).count == 5,
                  retired.plan.draftRevision < UInt64.max,
                  checkpoint.draftRevision == retired.plan.draftRevision + 1 else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            let expectedPlan = try DraftCommitPlanV1(planID: attempt.fieldDraftPlanID,
                workspaceID: workspaceID, draftID: draftID, draftRevision: prepared.plan.draftRevision,
                baseCanonicalRevision: baseRevision, payloadSHA256: checkpoint.payloadSHA256,
                stageDigests: [], targetCommandKind: .applyMyDay, expectedTargetRevision: baseRevision,
                mutationID: attempt.command.mutationID,
                outputKeys: attempt.command.productionPlanningOutputKeys)
            guard chain.allSatisfy({ $0.plan == expectedPlan }) else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            let receiptID = attempt.commitReceiptID
            let receiptRows = try current.modelContext.fetch(FetchDescriptor<DraftCommitReceiptRow>(
                predicate: #Predicate { $0.receiptID == receiptID }))
            guard receiptRows.count == 1, let receiptRow = receiptRows.first else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            let draftReceipt = try receiptRow.value()
            let bundle = try DraftCommitTerminalBundleV1(retiredSaga: retired,
                committedCheckpoint: checkpoint, receipt: draftReceipt)
            let terminalMutation = try FieldDraftMutationV1(workspaceID: workspaceID,
                expectedRevision: prepared.plan.draftRevision,
                expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
                mutationID: attempt.terminalBundleMutationID,
                postImage: .applyCommitTerminal(bundle, expectedSagaRevision: chain[3].revision))
            guard draftReceipt.sagaEventSHA256Chain == chain.map(\.sagaSHA256),
                  draftReceipt.consumedStageToContentID.isEmpty,
                  let terminalReceipt = try current.workspaceWriter.fieldDraftReceipt(for: terminalMutation),
                  let targetReceipt = try current.workspaceWriter.durableReceipt(mutationID: attempt.command.mutationID),
                  let result = try current.workspaceWriter.result(workspaceID: workspaceID,
                    mutationID: attempt.command.mutationID),
                  result.plan == successor,
                  try current.workspaceWriter.currentPlan(for: successor.key) == successor,
                  draftReceipt.targetReceiptSHA256 == targetReceipt.resultSHA256,
                  draftReceipt.committedAt == targetReceipt.committedAt else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            try result.receipt.validate(command: attempt.command)
            for index in 0..<4 {
                let mutation = try FieldDraftMutationV1(workspaceID: workspaceID,
                    expectedRevision: index == 0 ? 0 : chain[index - 1].revision,
                    expectedBaseCanonicalRevision: expectedPlan.baseCanonicalRevision,
                    mutationID: chain[index].mutationID,
                    postImage: index == 0 ? .appendCommitSaga(chain[index]) : .advanceCommitSaga(chain[index]))
                guard try current.workspaceWriter.fieldDraftReceipt(for: mutation) != nil else {
                    throw MyDayPlanningExecutionFailureV1.incompleteReadback
                }
            }
            return .init(checkpoint: checkpoint, draftReceipt: draftReceipt, targetResult: result,
                targetReceipt: targetReceipt, terminalReceipt: terminalReceipt)
        }
    }
}

private struct MyDayPlanningCarryoverPreparationV1 {
    let sourceReference: MyDayPlanReferenceV1
    let membershipIDs: [UUID]
    let targetKey: MyDayKeyV1
    let targetReference: MyDayPlanReferenceV1?
    let actor: ActorSnapshotV1
    let instant: Date
    let targetPlanID: UUID
    let commandID: MutationIDV1
    let allocated: Set<UUID>
    let expectedSession: StoreSessionCoordinator
}

private struct MyDayPlanningFrozenClockV1: ApplicationClock {
    let instant: Date
    func now() -> Date { instant }
}

/// PreviewSave does not query sources. Fail closed if that contract changes;
/// the real source reader is composed only at the canonical target operation.
@MainActor
private final class MyDayPlanningUnusedPreviewSourcesV1: MyDaySourceFrontierReadingV1 {
    func sourceFrontiers(for plan: MyDayPlanV1, evaluatedAt: Date) throws -> [MyDaySourceFrontierV1] {
        throw MyDayPlanningExecutionFailureV1.unsupportedCommand
    }
}

struct ProductionMyDayZeroStageContentPortV1: DraftContentPromotionPortV1 {
    let expectedPlan: DraftCommitPlanV1?
    let afterPromotion: (@MainActor @Sendable () async throws -> Void)?
    let expectedDiscardPlan: DraftDiscardPlanV1?
    let afterQuarantine: (@MainActor @Sendable () async throws -> Void)?

    init(expectedPlan: DraftCommitPlanV1?,
         afterPromotion: (@MainActor @Sendable () async throws -> Void)?,
         expectedDiscardPlan: DraftDiscardPlanV1? = nil,
         afterQuarantine: (@MainActor @Sendable () async throws -> Void)? = nil) {
        self.expectedPlan = expectedPlan; self.afterPromotion = afterPromotion
        self.expectedDiscardPlan = expectedDiscardPlan; self.afterQuarantine = afterQuarantine
    }

    func promote(plan: DraftCommitPlanV1, items: [AttachmentStagingItemV1],
                 reservationMutationIDs: [UUID: MutationIDV1]) async throws -> [DraftContentReservationV1] {
        try plan.validate()
        guard expectedPlan == plan, plan.targetCommandKind == .applyMyDay,
              plan.stageDigests.isEmpty, items.isEmpty, reservationMutationIDs.isEmpty else {
            throw FieldDraftFailureV1.invalidValue
        }
        try await afterPromotion?()
        return []
    }

    func quarantine(reservations: [DraftContentReservationV1], for plan: DraftDiscardPlanV1) async throws {
        try plan.validate()
        guard expectedDiscardPlan == plan, plan.stageIDs.isEmpty,
              plan.reservationIDs.isEmpty, reservations.isEmpty else {
            throw FieldDraftFailureV1.invalidValue
        }
        try await afterQuarantine?()
    }
}

@MainActor
private final class MyDayPlanningAuthorizedDraftWriterV1: FieldDraftWritingV1 {
    private let service: ProductionMyDayPlanningCommitServiceV1
    private let access: AppAccessPresentationV1.ContentAccess
    private let discardWrite: MyDayPlanningDiscardWriteV1?
    init(service: ProductionMyDayPlanningCommitServiceV1, access: AppAccessPresentationV1.ContentAccess,
         discardWrite: MyDayPlanningDiscardWriteV1? = nil) {
        self.service = service; self.access = access; self.discardWrite = discardWrite
    }

    private func perform<T>(_ body: (FieldDraftLifecycleAdapterV1) throws -> T) throws -> T {
        try service.authorized(access) { current in
            try body(current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext))
        }
    }

    func currentCheckpoint(workspaceID: WorkspaceID, draftID: UUID) throws -> FieldDraftCheckpointV1? {
        try perform { try $0.currentCheckpoint(workspaceID: workspaceID, draftID: draftID) }
    }
    func compareAndSwap(checkpoint: FieldDraftCheckpointV1, expectedDraftRevision: UInt64,
                        expectedBaseRevision: UInt64) throws -> MutationReceiptV1 {
        let receipt: MutationReceiptV1
        if let discardWrite {
            receipt = try service.authorized(access) { current in
                guard checkpoint == discardWrite.pendingCheckpoint,
                      expectedDraftRevision == discardWrite.expectedCheckpoint.draftRevision,
                      expectedBaseRevision == discardWrite.expectedCheckpoint.baseCanonicalRevision else {
                    throw FieldDraftFailureV1.invalidValue
                }
                try service.requireDiscardCheckpoint(discardWrite.expectedCheckpoint, current: current)
                try ProductionMyDayPlanningCommitServiceV1.validateDiscardCapacity(
                    state: discardWrite.expectedCheckpoint.state,
                    draftRevision: discardWrite.expectedCheckpoint.draftRevision,
                    workspaceRevision: current.workspaceWriter.currentRevision().revision)
                try ProductionMyDayPlanningCommitServiceV1.requireZeroDiscardContent(
                    draftID: checkpoint.draftID, current: current)
                guard try service.discardReceipts(draftID: checkpoint.draftID, current: current).isEmpty else {
                    throw MyDayPlanningExecutionFailureV1.incompleteReadback
                }
                return try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
                    .compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: expectedDraftRevision,
                                    expectedBaseRevision: expectedBaseRevision)
            }
        } else {
            receipt = try perform { try $0.compareAndSwap(checkpoint: checkpoint,
                expectedDraftRevision: expectedDraftRevision, expectedBaseRevision: expectedBaseRevision) }
        }
        #if DEBUG
        let point: MyDayPlanningEffectPointV1 = checkpoint.state == .discardPending ? .discardPendingCheckpoint :
            (checkpoint.state == .active ? .editingCheckpoint : .committingCheckpoint)
        try service.afterEffectForTesting?(point)
        #endif
        return receipt
    }
    func append(saga: DraftCommitSagaV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        let receipt = try perform { try $0.append(saga: saga, expectedRevision: expectedRevision) }
        #if DEBUG
        let point: MyDayPlanningEffectPointV1
        switch saga.state {
        case .prepared: point = .preparedSaga
        case .contentPromotedUnbound: point = .contentPromotedSaga
        case .targetCommitted: point = .targetCommittedSaga
        case .draftRetirePending: point = .retirePendingSaga
        default: throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        try service.afterEffectForTesting?(point)
        #endif
        return receipt
    }
    func apply(commitTerminalBundle: DraftCommitTerminalBundleV1, expectedDraftRevision: UInt64,
               expectedSagaRevision: UInt64) throws -> MutationReceiptV1 {
        let receipt = try perform { try $0.apply(commitTerminalBundle: commitTerminalBundle,
            expectedDraftRevision: expectedDraftRevision, expectedSagaRevision: expectedSagaRevision) }
        #if DEBUG
        try service.afterEffectForTesting?(.terminalBundle)
        #endif
        return receipt
    }
    func append(stagingItem: AttachmentStagingItemV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        throw MyDayPlanningExecutionFailureV1.unsupportedCommand
    }
    func append(reservation: DraftContentReservationV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        throw MyDayPlanningExecutionFailureV1.unsupportedCommand
    }
    func apply(discardTerminalBundle: DraftDiscardTerminalBundleV1,
               expectedDraftRevision: UInt64) throws -> MutationReceiptV1 {
        guard let discardWrite, discardTerminalBundle == discardWrite.terminalBundle,
              expectedDraftRevision == discardWrite.pendingCheckpoint.draftRevision else {
            throw MyDayPlanningExecutionFailureV1.unsupportedCommand
        }
        let receipt = try service.authorized(access) { current in
            try service.requireDiscardCheckpoint(discardWrite.pendingCheckpoint, current: current)
            try ProductionMyDayPlanningCommitServiceV1.validateDiscardCapacity(
                state: .discardPending, draftRevision: discardWrite.pendingCheckpoint.draftRevision,
                workspaceRevision: current.workspaceWriter.currentRevision().revision)
            try ProductionMyDayPlanningCommitServiceV1.requireZeroDiscardContent(
                draftID: discardWrite.pendingCheckpoint.draftID, current: current)
            guard try service.discardReceipts(draftID: discardWrite.pendingCheckpoint.draftID, current: current).isEmpty else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            return try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
                .apply(discardTerminalBundle: discardTerminalBundle, expectedDraftRevision: expectedDraftRevision)
        }
        #if DEBUG
        try service.afterEffectForTesting?(.discardTerminalBundle)
        #endif
        return receipt
    }
}

@MainActor
private final class MyDayPlanningCanonicalTargetV1: DraftCanonicalCommitPortV1 {
    private let service: ProductionMyDayPlanningCommitServiceV1
    private let access: AppAccessPresentationV1.ContentAccess
    private let reconstruction: MyDayPlanningCommitReconstructionV1?
    private let sourceProvider: ProductionMyDaySourceProviderV1
    private var committedResult: MyDayCommandResultV1?

    init(service: ProductionMyDayPlanningCommitServiceV1, access: AppAccessPresentationV1.ContentAccess,
         reconstruction: MyDayPlanningCommitReconstructionV1?, sourceProvider: ProductionMyDaySourceProviderV1) {
        self.service = service; self.access = access
        self.reconstruction = reconstruction; self.sourceProvider = sourceProvider
    }

    func commit(plan: DraftCommitPlanV1, reservations: [DraftContentReservationV1]) throws -> MutationReceiptV1 {
        guard let reconstruction, plan == reconstruction.plan, reservations.isEmpty else {
            throw MyDayPlanningExecutionFailureV1.unsupportedCommand
        }
        // No nested hold: the source provider owns the entire synchronous
        // source-check/CAS/write operation under this same concrete access.
        let expectedSession = try service.authorized(access) { $0 }
        let result = try sourceProvider.commitPlanningCommand(reconstruction.command,
            expectedSession: expectedSession, authorizing: access)
        committedResult = result
        #if DEBUG
        try service.afterEffectForTesting?(.targetCommit)
        #endif
        return try service.authorized(access) { current in
            guard let receipt = try current.workspaceWriter.durableReceipt(mutationID: plan.mutationID) else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            return receipt
        }
    }

    func readBackMatches(plan: DraftCommitPlanV1, receipt: MutationReceiptV1) throws -> Bool {
        guard let reconstruction, reconstruction.plan == plan, let committedResult else { return false }
        let successor = reconstruction.command.productionPlanningTarget
        return try service.authorized(access) { current in
            guard try current.workspaceWriter.durableReceipt(mutationID: plan.mutationID) == receipt,
                  try current.workspaceWriter.result(workspaceID: plan.workspaceID,
                    mutationID: plan.mutationID) == committedResult,
                  committedResult.plan == successor,
                  try current.workspaceWriter.currentPlan(for: successor.key) == successor else { return false }
            try committedResult.receipt.validate(command: reconstruction.command)
            return true
        }
    }
}

struct MyDayPlanningContextSnapshotV1: Equatable, Sendable {
    let key: MyDayKeyV1
    let currentPlan: MyDayPlanV1?
    let recordedBySnapshots: [ActorSnapshotV1]
}

private extension MyDayCommandV1 {
    var productionPlanningTarget: MyDayPlanV1 {
        switch self {
        case .save(let successor, _): return successor
        case .carryover(_, _, let target, _): return target
        }
    }

    var productionPlanningBaseRevision: UInt64 {
        switch self {
        case .save(_, let predecessor): return predecessor?.revision ?? 0
        case .carryover(let plan, _, _, _): return plan.expectedTargetPlan?.revision ?? 0
        }
    }

    var productionPlanningOutputKeys: [String] {
        get throws {
            var keys = [try WorkspaceEntityIdentityV1(kind: .myDayPlan,
                id: productionPlanningTarget.planID).stableKey]
            if case .carryover = self {
                keys.append(try WorkspaceEntityIdentityV1(kind: .myDayCarryoverReceipt,
                    id: mutationID.rawValue).stableKey)
            }
            return keys.sorted()
        }
    }
}

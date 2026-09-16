import Foundation
import SwiftData

/// Read-only application projection for one authenticated parent/photo target.
/// The private owner and revision binding must be rechecked before a later actor
/// uses the value; the projection itself grants no media or mutation authority.
fileprivate final class CurrentPhotoTargetReadOwnerV1 {}

struct CurrentPhotoTargetReadV1 {
    let parentCheckpoint: FieldDraftCheckpointV1
    let parent: CheckRunnerPhotoParentEvidenceV1
    let historicalSource: CheckRunnerRoundItemSourceV1
    let currentTarget: CheckRunnerPhotoCurrentTargetEvidenceV1

    fileprivate let owner: CurrentPhotoTargetReadOwnerV1
    fileprivate let revision: WorkspaceRevisionV1
}

struct CurrentPhotoMediaReadV1 {
    let targetRead: CurrentPhotoTargetReadV1
    let media: CheckRunnerPhotoMediaReadbackV1
}

/// Only the current application owner can issue this capability. The media
/// actor receives immutable preparation inputs; final effects return here and
/// run under the original writer fence and the prepared attachment-root lock.
@MainActor
final class CheckRunnerPhotoRawPublicationAuthorityV1 {
    nonisolated let payload: CheckRunnerPhotoDraftPayloadV1
    nonisolated let publishedRawReady: CheckRunnerPhotoRawReadyV1?
    nonisolated let applicationSupportURL: URL
    fileprivate let evidence: CheckRunnerPhotoRawStageEvidenceV1
    fileprivate let revision: WorkspaceRevisionV1
    fileprivate let owner: CurrentPhotoTargetReadOwnerV1
    fileprivate weak var service: ProductionCheckRunnerItemDraftServiceV1?
    fileprivate weak var writer: WorkspaceWriterV1?

    fileprivate init(service: ProductionCheckRunnerItemDraftServiceV1,
        writer: WorkspaceWriterV1, owner: CurrentPhotoTargetReadOwnerV1,
        evidence: CheckRunnerPhotoRawStageEvidenceV1, revision: WorkspaceRevisionV1,
        applicationSupportURL: URL) {
        self.service = service; self.writer = writer; self.owner = owner
        self.evidence = evidence; self.revision = revision
        payload = evidence.initialPayload; publishedRawReady = evidence.rawReady
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
    }

    func publish(_ prepared: DraftPreparedRawPhotoPublicationV1) throws -> FieldDraftCommittedEvidenceV1 {
        guard let service else { throw ScanToWorkFailureV1.authorityMismatch }
        return try service.publishPreparedRawPhoto(authority: self, prepared: prepared)
    }
}

/// An original rawReady observation owned by this service. Read verification
/// and normalization are separate uses; only proven pair absence grants the
/// latter. No caller can construct or upgrade this capability.
@MainActor
final class CheckRunnerPhotoRawReadAuthorityV1 {
    nonisolated let rawReady: CheckRunnerPhotoRawReadyV1
    nonisolated let applicationSupportURL: URL
    nonisolated let normalizationAllowed: Bool
    fileprivate let evidence: CheckRunnerPhotoContinuationEvidenceV1
    fileprivate let revision: WorkspaceRevisionV1
    fileprivate let owner: CurrentPhotoTargetReadOwnerV1
    fileprivate weak var service: ProductionCheckRunnerItemDraftServiceV1?
    fileprivate weak var writer: WorkspaceWriterV1?

    fileprivate init(service: ProductionCheckRunnerItemDraftServiceV1, writer: WorkspaceWriterV1,
        owner: CurrentPhotoTargetReadOwnerV1, evidence: CheckRunnerPhotoContinuationEvidenceV1,
        revision: WorkspaceRevisionV1, applicationSupportURL: URL, normalizationAllowed: Bool) {
        self.service = service; self.writer = writer; self.owner = owner; self.evidence = evidence
        self.revision = revision; rawReady = evidence.raw
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
        self.normalizationAllowed = normalizationAllowed
    }

    func validate(adapterIdentity: ObjectIdentifier) throws {
        guard let service else { throw ScanToWorkFailureV1.authorityMismatch }
        try service.validateRawPhotoRead(self, adapterIdentity: adapterIdentity)
    }
}

/// The immutable request is derived from the actual original COMMITTING
/// checkpoint. Publication returns through the retained application owner.
@MainActor
final class CheckRunnerPhotoRawPromotionAuthorityV1 {
    nonisolated let committingCheckpoint: FieldDraftCheckpointV1
    nonisolated let applicationSupportURL: URL
    fileprivate let evidence: CheckRunnerPhotoContinuationEvidenceV1
    fileprivate let revision: WorkspaceRevisionV1
    fileprivate let owner: CurrentPhotoTargetReadOwnerV1
    fileprivate weak var service: ProductionCheckRunnerItemDraftServiceV1?
    fileprivate weak var writer: WorkspaceWriterV1?

    fileprivate init(service: ProductionCheckRunnerItemDraftServiceV1, writer: WorkspaceWriterV1,
        owner: CurrentPhotoTargetReadOwnerV1, evidence: CheckRunnerPhotoContinuationEvidenceV1,
        revision: WorkspaceRevisionV1, applicationSupportURL: URL) throws {
        guard let committing = evidence.committing,
              case let .reviseCheckpoint(checkpoint) = committing.mutation.postImage,
              evidence.checkpoint == checkpoint, checkpoint.state == .committing else {
            throw FieldDraftFailureV1.invalidTransition
        }
        committingCheckpoint = checkpoint
        self.service = service; self.writer = writer; self.owner = owner; self.evidence = evidence
        self.revision = revision; self.applicationSupportURL = applicationSupportURL.standardizedFileURL
    }

    func validateBeforeImmutableWrite(_ prepared: DraftPreparedRawPhotoPromotionV1) throws {
        guard let service else { throw ScanToWorkFailureV1.authorityMismatch }
        try service.validateRawPhotoPromotion(self, prepared: prepared)
    }

    func publish(_ prepared: DraftPreparedRawPhotoPromotionV1) throws -> DraftContentReservationV1 {
        guard let service else { throw ScanToWorkFailureV1.authorityMismatch }
        return try service.publishPreparedRawPhotoPromotion(authority: self, prepared: prepared)
    }
}

struct CheckRunnerPhotoMediaOwnerV1 {
    let store: EvidenceBundleStore
    let generationRootURL: URL
    let rootIdentity: ReportPDFAnchoredFile.RootIdentity
}

@MainActor
fileprivate final class CurrentPhotoOperationReadV1 {
    weak var service: ProductionCheckRunnerItemDraftServiceV1?
    let writer: WorkspaceWriterV1
    let owner: CurrentPhotoTargetReadOwnerV1
    let evidence: CheckRunnerPhotoContinuationEvidenceV1
    let revision: WorkspaceRevisionV1
    let media: CheckRunnerPhotoMediaOwnerV1
    let applicationSupportURL: URL

    init(service: ProductionCheckRunnerItemDraftServiceV1, writer: WorkspaceWriterV1,
         owner: CurrentPhotoTargetReadOwnerV1, evidence: CheckRunnerPhotoContinuationEvidenceV1,
         revision: WorkspaceRevisionV1, media: CheckRunnerPhotoMediaOwnerV1, applicationSupportURL: URL) {
        self.service = service; self.writer = writer; self.owner = owner; self.evidence = evidence
        self.revision = revision; self.media = media
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
    }
}

@MainActor
final class CheckRunnerPhotoPairPublicationAuthorityV1 {
    fileprivate let read: CurrentPhotoOperationReadV1
    fileprivate var rawVerification: DraftPreparedRawPhotoVerificationV1?
    fileprivate var publishing = false

    fileprivate init(read: CurrentPhotoOperationReadV1) { self.read = read }

    func validatePreparation() throws {
        guard let service = read.service else { throw ScanToWorkFailureV1.authorityMismatch }
        try service.validatePhotoOperation(read)
        guard read.evidence.checkpoint.state == .active else { throw FieldDraftFailureV1.invalidTransition }
        switch read.evidence.payload.phase {
        case .rawReady, .pairReady: break
        default: throw FieldDraftFailureV1.invalidTransition
        }
    }

    func revalidatePreparedPairPublication(_ prepared: CheckRunnerPhotoPreparedPairPublicationV1) throws {
        guard publishing, let service = read.service else { throw ScanToWorkFailureV1.authorityMismatch }
        try service.validatePreparedPairPublication(self, prepared: prepared)
    }

    func publish(_ prepared: CheckRunnerPhotoPreparedPairPublicationV1) throws -> FieldDraftCheckpointV1 {
        guard let service = read.service else { throw ScanToWorkFailureV1.authorityMismatch }
        return try service.publishPreparedPair(authority: self, prepared: prepared)
    }
}

@MainActor
final class CheckRunnerPhotoPairPromotionAuthorityV1 {
    fileprivate let read: CurrentPhotoOperationReadV1
    fileprivate var publishing = false

    fileprivate init(read: CurrentPhotoOperationReadV1) { self.read = read }

    func validatePreparation() throws {
        guard let service = read.service else { throw ScanToWorkFailureV1.authorityMismatch }
        try service.validatePhotoOperation(read)
        guard read.evidence.checkpoint.state == .committing,
              read.evidence.committing != nil, read.evidence.pairPublication != nil,
              read.evidence.sagas.count >= 2 else {
            throw FieldDraftFailureV1.invalidTransition
        }
    }

    func revalidatePreparedPairPromotion(_ prepared: CheckRunnerPhotoPreparedPairPromotionV1) throws {
        guard publishing, let service = read.service else { throw ScanToWorkFailureV1.authorityMismatch }
        try service.validatePreparedPairPromotion(self, prepared: prepared)
    }

    func publish(_ prepared: CheckRunnerPhotoPreparedPairPromotionV1) throws -> MutationReceiptV1 {
        guard let service = read.service else { throw ScanToWorkFailureV1.authorityMismatch }
        return try service.publishPreparedPairPromotion(authority: self, prepared: prepared)
    }
}

/// Adapts the one frozen photo attempt to the incumbent coordinator. It owns
/// no replacement saga, writer, clock or durable identity source.
@MainActor
fileprivate final class CheckRunnerPhotoCommitPortV1: DraftContentPromotionPortV1, DraftAsyncCanonicalCommitPortV1 {
    private weak var service: ProductionCheckRunnerItemDraftServiceV1?
    private let parentDraftID: UUID
    private let reconstruction: CheckRunnerPhotoCommitReconstructionV1

    init(service: ProductionCheckRunnerItemDraftServiceV1, parentDraftID: UUID,
         reconstruction: CheckRunnerPhotoCommitReconstructionV1) {
        self.service = service; self.parentDraftID = parentDraftID; self.reconstruction = reconstruction
    }

    func promote(plan: DraftCommitPlanV1, items: [AttachmentStagingItemV1],
                 reservationMutationIDs: [UUID: MutationIDV1]) async throws -> [DraftContentReservationV1] {
        guard let service, plan == reconstruction.draftCommit.plan, items == reconstruction.draftCommit.items,
              reservationMutationIDs == reconstruction.draftCommit.rowMutationIDs.reservationByStageID else {
            throw FieldDraftFailureV1.digestMismatch
        }
        return [try await service.promotePhotoRaw(parentDraftID: parentDraftID, reconstruction: reconstruction)]
    }

    func quarantine(reservations: [DraftContentReservationV1], for plan: DraftDiscardPlanV1) async throws {
        throw FieldDraftFailureV1.invalidTransition
    }

    func commit(plan: DraftCommitPlanV1, reservations: [DraftContentReservationV1]) async throws -> MutationReceiptV1 {
        guard let service, plan == reconstruction.draftCommit.plan else { throw FieldDraftFailureV1.digestMismatch }
        return try await service.commitPhotoTarget(parentDraftID: parentDraftID,
            reconstruction: reconstruction, reservations: reservations)
    }

    func readBackMatches(plan: DraftCommitPlanV1, receipt: MutationReceiptV1) throws -> Bool {
        guard let service, plan == reconstruction.draftCommit.plan else { throw FieldDraftFailureV1.digestMismatch }
        return try service.photoTargetReadback(parentDraftID: parentDraftID, reconstruction: reconstruction, receipt: receipt)
    }
}

/// Durable Begin and receipt-bound photo staging through the existing owners.
/// Factory registration awaits complete promotion, restore and lifecycle gates.
@MainActor
final class ProductionCheckRunnerItemDraftServiceV1 {
    private weak var session: StoreSessionCoordinator?
    private weak var originalWriter: WorkspaceWriterV1?
    private let workspaceID: WorkspaceID
    private let progress: ProductionRepetitiveCaptureProgressServiceV2
    private let coordinator: CheckRunnerCoordinator
    private let publishedRelease: InspectionPackageReleaseV1
    private let clock: any ApplicationClock
    private let ids: any ApplicationIDSource
    private let attachmentStaging: DraftAttachmentStagingAdapterV1?
    private let currentPhotoReadOwner = CurrentPhotoTargetReadOwnerV1()
    private var photoOperations: Set<UUID> = []
#if DEBUG
    /// Observation after durable target publication, outside publication locks.
    var beforePhotoTargetAcknowledgementForTesting: (() throws -> Void)?
#endif

    init(session: StoreSessionCoordinator, progress: ProductionRepetitiveCaptureProgressServiceV2,
         coordinator: CheckRunnerCoordinator, publishedRelease: InspectionPackageReleaseV1,
         clock: any ApplicationClock, ids: any ApplicationIDSource,
         attachmentStaging: DraftAttachmentStagingAdapterV1? = nil) throws {
        try progress.validateCheckRunnerOwner(writer: session.workspaceWriter, modelContext: session.modelContext)
        self.session = session; originalWriter = session.workspaceWriter; workspaceID = session.workspaceID
        self.progress = progress; self.coordinator = coordinator; self.publishedRelease = publishedRelease
        self.clock = clock; self.ids = ids
        self.attachmentStaging = attachmentStaging
    }

    /// The first checkpoint has no workflow record identity or target effect.
    /// Raw editable fields retain their bytes, including incomplete input.
    func create(source: CheckRunnerRoundItemSourceV1, preflight: CheckRunnerEditablePreflightV1,
                outcome: CheckRunnerEditableOutcomeV1 = .init()) throws -> FieldDraftCheckpointV1 {
        let current = try currentSession()
        let read = try progress.read(sourceDraftID: source.sourceCheckpoint.draftID)
        let observed = try coordinator.captureFrozenBeginSource(read: read, progress: progress,
            itemID: source.originalItem.itemID, publishedRelease: publishedRelease,
            requestedEntry: source.requestedEntry)
        guard observed == source else { throw FieldDraftFailureV1.digestMismatch }
        let scope = try CheckRunnerItemDraftCodecV1.scope(source: source)
        let workspace = workspaceID.rawValue
        let rows = try current.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
            predicate: #Predicate { $0.workspaceID == workspace }))
        guard try rows.allSatisfy({ try $0.value().scope != scope }) else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let payload = try CheckRunnerItemDraftPayloadV1(editing: source, field: .init(
            preflight: preflight, begin: .notBegun, outcome: outcome,
            wideContext: nil, closeDetail: nil, semanticAnchor: .preflight))
        let checkpoint = try makeCheckpoint(payload: payload, predecessor: nil)
        _ = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            .compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: 0,
                            expectedBaseRevision: checkpoint.baseCanonicalRevision)
        return try self.read(draftID: checkpoint.draftID)
    }

    func read(draftID: UUID) throws -> FieldDraftCheckpointV1 {
        let current = try currentSession()
        let id = draftID
        let rows = try current.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
            predicate: #Predicate { $0.draftID == id }))
        guard rows.count == 1, let row = rows.first else { throw FieldDraftFailureV1.missingReceipt }
        let checkpoint = try row.value()
        _ = try Self.authenticateCurrent(checkpoint, writer: current.workspaceWriter, context: current.modelContext)
        return checkpoint
    }

    /// Joins the authenticated current parent to its original committed child,
    /// current workflow/evidence frontier and original Round ENTRY. The returned
    /// value is observational only and carries no raw-media or effect authority.
    func readCurrentPhotoTarget(parentDraftID: UUID, childDraftID: UUID) throws
        -> CurrentPhotoTargetReadV1? {
        let current = try currentSession()
        let revision = try current.workspaceWriter.currentRevision()
        let target = try current.workspaceWriter.checkRunnerPhotoCurrentTargetEvidence(
            workspaceID: workspaceID, parentDraftID: parentDraftID,
            childDraftID: childDraftID)
        guard let target else {
            guard try currentSession().workspaceWriter.currentRevision() == revision else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            return nil
        }
        let parentCheckpoint = target.parent.checkpoint
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(parentCheckpoint)
        let source = payload.source
        let progressRead = try progress.read(sourceDraftID: source.sourceCheckpoint.draftID)
        try coordinator.validateHistoricalCheckRunnerSource(source, read: progressRead,
            progress: progress, publishedRelease: publishedRelease)

        // Close the synchronous read interval with fresh owner, historical
        // source, exact checkpoint and workspace revision checks.
        guard try read(draftID: parentDraftID) == parentCheckpoint,
              try current.workspaceWriter.currentRevision() == revision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        return .init(parentCheckpoint: parentCheckpoint, parent: target.parent,
            historicalSource: source, currentTarget: target,
            owner: currentPhotoReadOwner, revision: revision)
    }

    /// Required immediately before a later publication or actor uses a saved
    /// projection. This repeats every live owner/source/target check.
    func validateForPublication(_ value: CurrentPhotoTargetReadV1) throws {
        guard value.owner === currentPhotoReadOwner else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let current = try currentSession()
        guard try current.workspaceWriter.currentRevision() == value.revision,
              let refreshed = try readCurrentPhotoTarget(
                parentDraftID: value.parentCheckpoint.draftID,
                childDraftID: value.parent.slot.childDraftID),
              refreshed.parentCheckpoint == value.parentCheckpoint,
              refreshed.parent == value.parent,
              refreshed.historicalSource == value.historicalSource,
              refreshed.currentTarget == value.currentTarget else {
            throw ScanToWorkFailureV1.stale
        }
    }

    /// Fresh physical bytes are joined only to the complete authenticated
    /// current target. A missing/corrupt owned file is an error, never repair.
    func readCurrentPhotoMedia(parentDraftID: UUID, childDraftID: UUID) async throws
        -> CurrentPhotoMediaReadV1? {
        guard let target = try readCurrentPhotoTarget(parentDraftID: parentDraftID,
            childDraftID: childDraftID) else { return nil }
        let media = try await coordinator.readCheckRunnerPhotoMedia(
            target: target.currentTarget, progress: progress)
        try validateForPublication(target)
        return .init(targetRead: target, media: media)
    }

    /// A saved filesystem observation is not a publication capability. Repeat
    /// the logical and physical reads, closing the owner interval after await.
    func validateForPublication(_ value: CurrentPhotoMediaReadV1) async throws {
        try validateForPublication(value.targetRead)
        let observed = try await coordinator.readCheckRunnerPhotoMedia(
            target: value.targetRead.currentTarget, progress: progress)
        try validateForPublication(value.targetRead)
        guard observed == value.media else { throw ScanToWorkFailureV1.stale }
    }

    /// Persist the parent selection before its child. The proposal is only a
    /// value: full original history, current source and access authorize writes.
    /// A surviving pending slot can create only its exact selected child.
    func prepareRawPhoto(parentDraftID: UUID, expectedCheckpointSHA256: String,
        proposal: CheckRunnerPhotoDraftPayloadV1) throws -> FieldDraftCheckpointV1 {
        try proposal.validate()
        guard case .awaitingRawStage = proposal.phase,
              proposal.parentDraftID == parentDraftID, proposal.workspaceID == workspaceID else {
            throw FieldDraftFailureV1.invalidValue
        }
        let current = try currentSession()
        let writer = current.workspaceWriter
        guard let frontier = try writer.checkRunnerPhotoPreparationEvidence(workspaceID: workspaceID,
            parentDraftID: parentDraftID, captureStep: proposal.captureStep) else {
            throw FieldDraftFailureV1.missingReceipt
        }
        let checkpoint = frontier.parentCheckpoint
        guard checkpoint.checkpointSHA256 == expectedCheckpointSHA256 else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        try coordinator.validatePhotoPreparation(parentCheckpoint: checkpoint, photo: proposal,
            workflowEvidence: frontier.workflow, timeZoneEvidence: frontier.timeZone,
            progress: progress, publishedRelease: publishedRelease)
        let parent = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        let slot = CheckRunnerPhotoSlotV1.pending(childDraftID: proposal.childDraftID,
            captureStep: proposal.captureStep, purposeKey: proposal.purposeKey)
        let selected = proposal.captureStep == .wide ? parent.field.wideContext : parent.field.closeDetail
        guard selected == nil || selected == slot else { throw FieldDraftFailureV1.staleDraftRevision }
        let childID = proposal.childDraftID
        var descriptor = FetchDescriptor<FieldDraftCheckpointRow>(predicate: #Predicate { $0.draftID == childID })
        descriptor.fetchLimit = 2
        let existing = try current.modelContext.fetch(descriptor)
        if !existing.isEmpty {
            guard selected == slot, existing.count == 1 else { throw FieldDraftFailureV1.staleDraftRevision }
            let original = try currentRawPhotoEvidence(parentDraftID: parentDraftID, childDraftID: childID)
            guard original.initialPayload == proposal else { throw FieldDraftFailureV1.digestMismatch }
            return original.currentCheckpoint
        }
        let stageID = proposal.phase.intent.stageID
        var stageDescriptor = FetchDescriptor<AttachmentStagingItemRow>(predicate: #Predicate { $0.stageID == stageID })
        stageDescriptor.fetchLimit = 2
        guard try current.modelContext.fetch(stageDescriptor).isEmpty,
              try writer.durableReceipt(mutationID: proposal.phase.intent.stageMutationID) == nil else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let pending: FieldDraftCheckpointV1
        if selected == nil {
            let field = parent.field
            let payload = try CheckRunnerItemDraftPayloadV1(editing: parent.source, field: .init(
                preflight: field.preflight, begin: field.begin, outcome: field.outcome,
                wideContext: proposal.captureStep == .wide ? slot : field.wideContext,
                closeDetail: proposal.captureStep == .close ? slot : field.closeDetail,
                semanticAnchor: field.semanticAnchor))
            // Both durable edges share the original logical capture instant.
            // Their authenticated receipts establish the actual write order.
            pending = try makeCheckpoint(payload: payload, predecessor: checkpoint,
                                         frozenUpdatedAt: proposal.phase.intent.stageCreatedAt)
            try proposal.validate(parent: payload, parentDraftID: parentDraftID)
        } else { pending = checkpoint }
        try proposal.validateRawStageIntent(parentSlotCheckpointUpdatedAt: pending.updatedAt)
        let child = try FieldDraftCheckpointV1(draftID: childID, workspaceID: workspaceID,
            scope: CheckRunnerPhotoDraftCodecV1.scope(payload: proposal), purpose: .inspectionReview,
            codec: CheckRunnerPhotoDraftCodecV1.release(), baseCanonicalRevision: parent.source.roundAtEntry.revision,
            draftRevision: 1, payloadData: CheckRunnerPhotoDraftCodecV1.encode(proposal), stageIDs: [],
            resumeAnchor: CheckRunnerPhotoDraftCodecV1.resumeAnchor(payload: proposal), state: .active,
            updatedAt: proposal.phase.intent.stageCreatedAt, mutationID: .init(rawValue: ids.makeID()))
        guard Set([pending.mutationID.rawValue, child.mutationID.rawValue,
                   proposal.phase.intent.stageMutationID.rawValue, proposal.phase.intent.evidenceID]).count == 4,
              try writer.durableReceipt(mutationID: child.mutationID) == nil,
              try writer.durableReceipt(mutationID: .init(rawValue: proposal.phase.intent.evidenceID)) == nil,
              try selected != nil || writer.durableReceipt(mutationID: pending.mutationID) == nil else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let lifecycle = try writer.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
        if selected == nil {
            _ = try lifecycle.compareAndSwap(checkpoint: pending, expectedDraftRevision: checkpoint.draftRevision,
                                            expectedBaseRevision: checkpoint.baseCanonicalRevision)
        }
        guard let observed = try writer.checkRunnerPhotoPreparationEvidence(workspaceID: workspaceID,
            parentDraftID: parentDraftID, captureStep: proposal.captureStep),
              observed.parentCheckpoint == pending else { throw FieldDraftFailureV1.missingReceipt }
        try proposal.validate(parent: CheckRunnerItemDraftCodecV1.validateCheckpoint(pending),
                              parentDraftID: parentDraftID)
        try coordinator.validatePhotoPreparation(parentCheckpoint: pending, photo: proposal,
            workflowEvidence: observed.workflow, timeZoneEvidence: observed.timeZone,
            progress: progress, publishedRelease: publishedRelease)
        _ = try lifecycle.compareAndSwap(checkpoint: child, expectedDraftRevision: 0,
                                        expectedBaseRevision: child.baseCanonicalRevision)
        let original = try currentRawPhotoEvidence(parentDraftID: parentDraftID, childDraftID: childID)
        guard original.initialPayload == proposal, original.currentCheckpoint == child else {
            throw FieldDraftFailureV1.missingReceipt
        }
        return child
    }

    /// The original pending checkpoint supplies every durable identity and
    /// timestamp. Exact retries adopt existing physical and canonical originals.
    func publishRawPhoto(parentDraftID: UUID, childDraftID: UUID, sourceURL: URL) async throws
        -> FieldDraftCommittedEvidenceV1 {
        try Task.checkCancellation()
        guard let attachmentStaging else { throw FieldDraftFailureV1.invalidValue }
        let current = try currentSession()
        let writer = current.workspaceWriter
        let revision = try writer.currentRevision()
        let evidence = try currentRawPhotoEvidence(parentDraftID: parentDraftID, childDraftID: childDraftID)
        guard try currentSession().workspaceWriter.currentRevision() == revision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let authority = CheckRunnerPhotoRawPublicationAuthorityV1(service: self, writer: writer,
            owner: currentPhotoReadOwner, evidence: evidence, revision: revision,
            applicationSupportURL: current.checkRunnerPhotoApplicationSupportURL)
        return try await attachmentStaging.stageRawPhoto(sourceURL: sourceURL, authority: authority)
    }

    private func currentRawPhotoEvidence(parentDraftID: UUID, childDraftID: UUID) throws
        -> CheckRunnerPhotoRawStageEvidenceV1 {
        let current = try currentSession()
        guard let evidence = try current.workspaceWriter.checkRunnerPhotoRawStageEvidence(
            workspaceID: workspaceID, parentDraftID: parentDraftID, childDraftID: childDraftID) else {
            throw FieldDraftFailureV1.missingReceipt
        }
        try coordinator.validatePendingPhotoPublication(evidence, progress: progress,
                                                       publishedRelease: publishedRelease)
        return evidence
    }

    private func currentPhotoContinuation(parentDraftID: UUID, childDraftID: UUID) throws
        -> CheckRunnerPhotoContinuationEvidenceV1 {
        let current = try currentSession()
        guard let evidence = try current.workspaceWriter.checkRunnerPhotoContinuationEvidence(
            workspaceID: workspaceID, parentDraftID: parentDraftID, childDraftID: childDraftID) else {
            throw FieldDraftFailureV1.missingReceipt
        }
        try coordinator.validatePhotoContinuation(evidence, progress: progress, publishedRelease: publishedRelease)
        return evidence
    }

    private func photoOperationRead(_ evidence: CheckRunnerPhotoContinuationEvidenceV1) throws -> CurrentPhotoOperationReadV1 {
        let current = try currentSession()
        let revision = try current.workspaceWriter.currentRevision()
        let media = try coordinator.checkRunnerPhotoMediaOwner(progress: progress)
        guard try currentPhotoContinuation(parentDraftID: evidence.parentCheckpoint.draftID,
            childDraftID: evidence.checkpoint.draftID) == evidence,
              try current.workspaceWriter.currentRevision() == revision else { throw FieldDraftFailureV1.staleDraftRevision }
        return .init(service: self, writer: current.workspaceWriter, owner: currentPhotoReadOwner,
            evidence: evidence, revision: revision, media: media,
            applicationSupportURL: current.checkRunnerPhotoApplicationSupportURL)
    }

    fileprivate func validatePhotoOperation(_ value: CurrentPhotoOperationReadV1) throws {
        try Task.checkCancellation()
        guard value.service === self, value.owner === currentPhotoReadOwner else { throw ScanToWorkFailureV1.authorityMismatch }
        let current = try currentSession()
        let media = try coordinator.checkRunnerPhotoMediaOwner(progress: progress)
        guard current.workspaceWriter === value.writer,
              current.checkRunnerPhotoApplicationSupportURL.standardizedFileURL == value.applicationSupportURL,
              media.store === value.media.store, media.generationRootURL == value.media.generationRootURL,
              media.rootIdentity == value.media.rootIdentity,
              try current.workspaceWriter.currentRevision() == value.revision,
              try currentPhotoContinuation(parentDraftID: value.evidence.parentCheckpoint.draftID,
                  childDraftID: value.evidence.checkpoint.draftID) == value.evidence else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
    }

    private func rawReadAuthority(_ value: CurrentPhotoOperationReadV1, normalizationAllowed: Bool)
        -> CheckRunnerPhotoRawReadAuthorityV1 {
        .init(service: self, writer: value.writer, owner: currentPhotoReadOwner,
            evidence: value.evidence, revision: value.revision, applicationSupportURL: value.applicationSupportURL,
            normalizationAllowed: normalizationAllowed)
    }

    /// Exact marked pairs are adopted without the picker or normalizer. A
    /// retained pairReady claim cannot authorize replacement of missing bytes.
    func preparePhotoPair(parentDraftID: UUID, childDraftID: UUID) async throws -> FieldDraftCheckpointV1 {
        guard photoOperations.insert(childDraftID).inserted else { throw FieldDraftFailureV1.staleDraftRevision }
        defer { photoOperations.remove(childDraftID) }
        guard let attachmentStaging else { throw FieldDraftFailureV1.invalidValue }
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
        let read = try photoOperationRead(evidence)
        let authority = CheckRunnerPhotoPairPublicationAuthorityV1(read: read)
        try authority.validatePreparation()
        let root = read.media.rootIdentity
        let existing = try await read.media.store.readStagedCheckRunnerPhotoPair(childDraftID: childDraftID,
            parentDraftID: parentDraftID, raw: evidence.raw,
            expectedGenerationRootIdentity: (root.device, root.inode))
        try validatePhotoOperation(read)
        let normalized: NormalizedMediaWithSourceFactsV1?
        if let existing {
            if case let .pairReady(pair) = evidence.payload.phase {
                guard pair.normalizedPair == existing.marker.normalizedPair,
                      pair.pairPublicationMarkerSHA256 == existing.markerSHA256 else { throw FieldDraftFailureV1.digestMismatch }
            }
            normalized = nil
        } else {
            guard case .rawReady = evidence.payload.phase else { throw FieldDraftFailureV1.missingContent }
            normalized = try await attachmentStaging.normalizeRawPhoto(
                authority: rawReadAuthority(read, normalizationAllowed: true))
        }
        try validatePhotoOperation(read)
        let prepared = try await read.media.store.prepareCheckRunnerPhotoPair(authority: authority,
            childDraftID: childDraftID, parentDraftID: parentDraftID, raw: evidence.raw, normalized: normalized,
            expectedGenerationRootIdentity: (root.device, root.inode))
        try validatePhotoOperation(read)
        authority.rawVerification = try await attachmentStaging.prepareRawPhotoVerification(
            authority: rawReadAuthority(read, normalizationAllowed: false))
        return try authority.publish(prepared)
    }

    fileprivate func validatePreparedPairPublication(_ authority: CheckRunnerPhotoPairPublicationAuthorityV1,
        prepared: CheckRunnerPhotoPreparedPairPublicationV1) throws {
        try authority.validatePreparation()
        let read = authority.read
        guard prepared.storeIdentity == ObjectIdentifier(read.media.store),
              prepared.generationRootURL == read.media.generationRootURL,
              prepared.rootIdentity == read.media.rootIdentity,
              let verification = authority.rawVerification, let attachmentStaging,
              verification.adapterIdentity == ObjectIdentifier(attachmentStaging),
              verification.applicationSupportURL.standardizedFileURL == read.applicationSupportURL,
              verification.rawReady == read.evidence.raw else { throw ScanToWorkFailureV1.authorityMismatch }
        try prepared.readback.marker.validate(childDraftID: read.evidence.checkpoint.draftID,
            parentDraftID: read.evidence.parentCheckpoint.draftID, raw: read.evidence.raw)
        if case let .pairReady(pair) = read.evidence.payload.phase {
            guard pair.normalizedPair == prepared.readback.marker.normalizedPair,
                  pair.pairPublicationMarkerSHA256 == prepared.readback.markerSHA256 else { throw FieldDraftFailureV1.digestMismatch }
        }
    }

    fileprivate func publishPreparedPair(authority: CheckRunnerPhotoPairPublicationAuthorityV1,
        prepared: CheckRunnerPhotoPreparedPairPublicationV1) throws -> FieldDraftCheckpointV1 {
        let read = authority.read
        guard !authority.publishing, let verification = authority.rawVerification else { throw ScanToWorkFailureV1.authorityMismatch }
        let current = try currentSession()
        return try current.withCheckRunnerPhotoPublication(expectedWriter: read.writer,
            applicationSupportURL: read.applicationSupportURL) {
            authority.publishing = true
            defer { authority.publishing = false }
            return try verification.withVerificationLock {
                try prepared.withPublicationLock(authority: authority) { publish in
                    try validatePreparedPairPublication(authority, prepared: prepared)
                    let readback = try publish()
                    let pair = try CheckRunnerPhotoPairReadyV1(raw: read.evidence.raw,
                        normalizedPair: readback.marker.normalizedPair, pairPublicationMarkerSHA256: readback.markerSHA256)
                    let checkpoint: FieldDraftCheckpointV1
                    if case let .pairReady(original) = read.evidence.payload.phase {
                        guard original == pair else { throw FieldDraftFailureV1.digestMismatch }
                        checkpoint = read.evidence.checkpoint
                    } else {
                        checkpoint = try photoCheckpoint(replacing: read.evidence, phase: .pairReady(pair),
                            state: .active, updatedAt: canonicalPhotoCheckpointInstant())
                        _ = try read.writer.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
                            .compareAndSwap(checkpoint: checkpoint,
                                expectedDraftRevision: read.evidence.checkpoint.draftRevision,
                                expectedBaseRevision: read.evidence.checkpoint.baseCanonicalRevision)
                    }
                    let observed = try currentPhotoContinuation(parentDraftID: read.evidence.parentCheckpoint.draftID,
                        childDraftID: read.evidence.checkpoint.draftID)
                    guard observed.checkpoint == checkpoint, observed.pairPublication != nil,
                          case let .pairReady(saved) = observed.payload.phase, saved == pair else { throw FieldDraftFailureV1.missingReceipt }
                    return checkpoint
                }
            }
        }
    }

    /// Proposal supplies only values. The original pairReady receipt and live
    /// workflow frontier authorize freezing this one attempt before effects.
    func preparePhotoCommit(parentDraftID: UUID, childDraftID: UUID, expectedCheckpointSHA256: String,
                            proposal: CheckRunnerPhotoCommitAttemptV1) throws -> FieldDraftCheckpointV1 {
        guard !photoOperations.contains(childDraftID) else { throw FieldDraftFailureV1.staleDraftRevision }
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
        if case let .preparedCommit(_, original) = evidence.payload.phase {
            guard original == proposal, let pairPublication = evidence.pairPublication,
                  case let .reviseCheckpoint(pairCheckpoint) = pairPublication.mutation.postImage,
                  expectedCheckpointSHA256 == evidence.checkpoint.checkpointSHA256
                    || expectedCheckpointSHA256 == pairCheckpoint.checkpointSHA256 else { throw FieldDraftFailureV1.staleDraftRevision }
            return evidence.checkpoint
        }
        guard evidence.checkpoint.checkpointSHA256 == expectedCheckpointSHA256,
              case let .pairReady(pair) = evidence.payload.phase,
              proposal.expectedWorkflowRecordRevision == evidence.currentWorkflowPostImage.revision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        try proposal.validate()
        guard try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoCommitAttemptV1.self,
            from: FieldDraftCanonicalCodecV1.encode(proposal)) == proposal else {
            throw FieldDraftFailureV1.invalidValue
        }
        let committedStage = try CheckRunnerPhotoContinuationEvidenceV1.committedStage(raw: pair.raw, attempt: proposal)
        let checkpoint = try photoCheckpoint(replacing: evidence, phase: .preparedCommit(pair, proposal),
            state: .committing, updatedAt: proposal.preparedUpdatedAt)
        let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
        try payload.validateCommitPreparation(pairReadyCheckpointUpdatedAt: evidence.checkpoint.updatedAt)
        let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: checkpoint)
        let current = try currentSession()
        let mutationIDs = [checkpoint.mutationID, committedStage.mutationID,
            proposal.targetMutationID, proposal.reservationMutationID,
            proposal.preparedSagaMutationID, proposal.contentPromotedSagaMutationID,
            proposal.targetCommittedSagaMutationID, proposal.draftRetirePendingSagaMutationID,
            proposal.terminalBundleMutationID]
        guard Set(mutationIDs).count == mutationIDs.count else { throw FieldDraftFailureV1.invalidValue }
        for mutationID in mutationIDs {
            guard try current.workspaceWriter.durableReceipt(mutationID: mutationID) == nil else { throw FieldDraftFailureV1.staleDraftRevision }
        }
        guard reconstruction.draftCommit.checkpoint == checkpoint else { throw FieldDraftFailureV1.digestMismatch }
        _ = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            .compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: evidence.checkpoint.draftRevision,
                            expectedBaseRevision: evidence.checkpoint.baseCanonicalRevision)
        let observed = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
        guard observed.checkpoint == checkpoint, observed.committing != nil else { throw FieldDraftFailureV1.missingReceipt }
        return checkpoint
    }

    private func canonicalPhotoCheckpointInstant() throws -> Date {
        let sampled = clock.now().timeIntervalSince1970
        guard sampled.isFinite, sampled >= 0, (sampled * 1_000).isFinite else {
            throw FieldDraftFailureV1.invalidValue
        }
        return Date(timeIntervalSince1970: floor(sampled * 1_000) / 1_000)
    }

    private func photoCheckpoint(replacing evidence: CheckRunnerPhotoContinuationEvidenceV1,
        phase: CheckRunnerPhotoDurablePhaseV1, state: FieldDraftStateV1, updatedAt: Date) throws -> FieldDraftCheckpointV1 {
        let original = evidence.payload, previous = evidence.checkpoint
        guard previous.draftRevision < UInt64.max else { throw FieldDraftFailureV1.invalidValue }
        let payload = try CheckRunnerPhotoDraftPayloadV1(workspaceID: original.workspaceID,
            childDraftID: original.childDraftID, parentDraftID: original.parentDraftID,
            recordID: original.recordID, assetID: original.assetID, sourceBinding: original.sourceBinding,
            workflowStage: original.workflowStage, captureStep: original.captureStep, purposeKey: original.purposeKey,
            origin: original.origin, phase: phase)
        let checkpoint = try FieldDraftCheckpointV1(draftID: previous.draftID, workspaceID: previous.workspaceID,
            scope: previous.scope, purpose: previous.purpose, codec: previous.codec,
            baseCanonicalRevision: previous.baseCanonicalRevision, draftRevision: previous.draftRevision + 1,
            payloadData: CheckRunnerPhotoDraftCodecV1.encode(payload), stageIDs: phase.declaredStageIDs,
            resumeAnchor: CheckRunnerPhotoDraftCodecV1.resumeAnchor(payload: payload), state: state,
            updatedAt: updatedAt, mutationID: .init(rawValue: ids.makeID()))
        try checkpoint.validateSuccessor(of: previous, expectedDraftRevision: previous.draftRevision,
                                         expectedBaseRevision: previous.baseCanonicalRevision)
        return checkpoint
    }

    /// Replays the incumbent coordinator from the one saved attempt. It always
    /// reads an actual target receipt before considering another target effect.
    func resumePhotoCommit(parentDraftID: UUID, childDraftID: UUID) async throws -> FieldDraftCheckpointV1 {
        guard photoOperations.insert(childDraftID).inserted else { throw FieldDraftFailureV1.staleDraftRevision }
        defer { photoOperations.remove(childDraftID) }
        let current = try currentSession()
        var rows = FetchDescriptor<FieldDraftCheckpointRow>(predicate: #Predicate { $0.draftID == childDraftID })
        rows.fetchLimit = 2
        let found = try current.modelContext.fetch(rows)
        guard found.count == 1, let row = found.first else { throw FieldDraftFailureV1.missingReceipt }
        let observed = try row.value()
        if observed.state == .committed {
            return try completePhotoParentSlot(parentDraftID: parentDraftID, childDraftID: childDraftID)
        }
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
        guard evidence.checkpoint.state == .committing, let committing = evidence.committing,
              case let .reviseCheckpoint(checkpoint) = committing.mutation.postImage,
              checkpoint == evidence.checkpoint else { throw FieldDraftFailureV1.invalidTransition }
        let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: checkpoint)
        let commit = reconstruction.draftCommit
        let port = CheckRunnerPhotoCommitPortV1(service: self, parentDraftID: parentDraftID, reconstruction: reconstruction)
        let lifecycle = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
        let drafts = FieldDraftCoordinatorV1(purposeAuthority: try CheckRunnerDraftPurposeAuthorityV1(),
            writer: lifecycle, content: port, asyncTarget: port)
        _ = try await drafts.commit(plan: commit.plan, checkpoint: checkpoint, items: commit.items,
            prepared: commit.prepared, contentPromoted: commit.contentPromoted, targetCommitted: commit.targetCommitted,
            retirePending: commit.retirePending, retired: commit.retired, commitReceiptID: commit.commitReceiptID,
            terminalCheckpointUpdatedAt: commit.terminalCheckpointUpdatedAt, rowMutationIDs: commit.rowMutationIDs)
        return try completePhotoParentSlot(parentDraftID: parentDraftID, childDraftID: childDraftID)
    }

    fileprivate func promotePhotoRaw(parentDraftID: UUID, reconstruction: CheckRunnerPhotoCommitReconstructionV1)
        async throws -> DraftContentReservationV1 {
        guard let attachmentStaging else { throw FieldDraftFailureV1.invalidValue }
        let current = try currentSession()
        let revision = try current.workspaceWriter.currentRevision()
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID,
            childDraftID: reconstruction.draftCommit.checkpoint.draftID)
        guard evidence.checkpoint == reconstruction.draftCommit.checkpoint,
              evidence.sagas.first == reconstruction.draftCommit.prepared,
              try current.workspaceWriter.currentRevision() == revision else { throw FieldDraftFailureV1.staleDraftRevision }
        let authority = try CheckRunnerPhotoRawPromotionAuthorityV1(service: self, writer: current.workspaceWriter,
            owner: currentPhotoReadOwner, evidence: evidence, revision: revision,
            applicationSupportURL: current.checkRunnerPhotoApplicationSupportURL)
        return try await attachmentStaging.promoteRawPhoto(authority: authority)
    }

    fileprivate func commitPhotoTarget(parentDraftID: UUID, reconstruction: CheckRunnerPhotoCommitReconstructionV1,
        reservations: [DraftContentReservationV1]) async throws -> MutationReceiptV1 {
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID,
            childDraftID: reconstruction.draftCommit.checkpoint.draftID)
        guard evidence.checkpoint == reconstruction.draftCommit.checkpoint,
              case let .preparedCommit(pair, attempt) = evidence.payload.phase,
              reservations == [try CheckRunnerPhotoContinuationEvidenceV1.reservation(
                raw: pair.raw, plan: reconstruction.draftCommit.plan, attempt: attempt)],
              evidence.currentStage == (try CheckRunnerPhotoContinuationEvidenceV1.committedStage(raw: pair.raw, attempt: attempt)) else {
            throw FieldDraftFailureV1.digestMismatch
        }
        let read = try photoOperationRead(evidence)
        let authority = CheckRunnerPhotoPairPromotionAuthorityV1(read: read)
        try authority.validatePreparation()
        let root = read.media.rootIdentity
        let prepared = try await read.media.store.prepareCheckRunnerPhotoPromotion(authority: authority,
            childDraftID: evidence.checkpoint.draftID, parentDraftID: parentDraftID, pair: pair,
            expectedGenerationRootIdentity: (root.device, root.inode))
        let receipt = try authority.publish(prepared)
#if DEBUG
        try beforePhotoTargetAcknowledgementForTesting?()
#endif
        return receipt
    }

    fileprivate func validatePreparedPairPromotion(_ authority: CheckRunnerPhotoPairPromotionAuthorityV1,
        prepared: CheckRunnerPhotoPreparedPairPromotionV1) throws {
        try authority.validatePreparation()
        let read = authority.read
        guard prepared.storeIdentity == ObjectIdentifier(read.media.store),
              prepared.generationRootURL == read.media.generationRootURL,
              prepared.rootIdentity == read.media.rootIdentity,
              case let .preparedCommit(pair, attempt) = read.evidence.payload.phase,
              prepared.pair == pair,
              read.evidence.currentStage == (try CheckRunnerPhotoContinuationEvidenceV1.committedStage(raw: pair.raw, attempt: attempt)) else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
    }

    fileprivate func publishPreparedPairPromotion(authority: CheckRunnerPhotoPairPromotionAuthorityV1,
        prepared: CheckRunnerPhotoPreparedPairPromotionV1) throws -> MutationReceiptV1 {
        guard !authority.publishing else { throw ScanToWorkFailureV1.authorityMismatch }
        let read = authority.read, current = try currentSession()
        return try current.withCheckRunnerPhotoPublication(expectedWriter: read.writer,
            applicationSupportURL: read.applicationSupportURL) {
            authority.publishing = true
            defer { authority.publishing = false }
            return try prepared.withPromotionLock(authority: authority) { promote in
                try validatePreparedPairPromotion(authority, prepared: prepared)
                let promoted = try promote()
                let pair = prepared.pair.normalizedPair
                guard promoted.evidenceID == pair.evidenceID,
                      promoted.originalRelativePath == pair.originalRelativePath,
                      promoted.thumbnailRelativePath == pair.thumbnailRelativePath,
                      Int64(promoted.originalByteCount) == pair.originalByteCount,
                      Int64(promoted.thumbnailByteCount) == pair.thumbnailByteCount,
                      promoted.originalSHA256 == pair.originalSHA256,
                      promoted.thumbnailSHA256 == pair.thumbnailSHA256 else { throw FieldDraftFailureV1.digestMismatch }
                let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: read.evidence.checkpoint)
                let receipt: MutationReceiptV1
                if let original = read.evidence.target {
                    guard original.command == reconstruction.targetCommand else { throw FieldDraftFailureV1.digestMismatch }
                    receipt = original.receipt
                } else {
                    let revision = try read.writer.currentRevision()
                    let workflow = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: read.evidence.payload.recordID)
                    let evidence = try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: pair.evidenceID)
                    let known = Dictionary(uniqueKeysWithValues: revision.entityRevisions.map { ($0.identity, $0.revision) })
                    let expectedRevision = reconstruction.draftCommit.plan.expectedTargetRevision
                    guard known[workflow] == expectedRevision, known[evidence, default: 0] == 0 else { throw FieldDraftFailureV1.staleDraftRevision }
                    let expected = try WorkspaceExpectedRevisionV1(workspaceID: revision.workspaceID,
                        generationID: revision.generationID, writerInstanceID: revision.writerInstanceID,
                        workspaceRevision: revision.revision,
                        entityRevisions: [.init(identity: workflow, revision: expectedRevision), .init(identity: evidence, revision: 0)])
                    _ = try read.writer.execute(.init(mutationID: reconstruction.draftCommit.plan.mutationID,
                        expectedRevision: expected, command: .acceptCheckEvidence(reconstruction.targetCommand)))
                    guard let original = try read.writer.checkRunnerPhotoEvidence(workspaceID: workspaceID,
                        mutationID: reconstruction.draftCommit.plan.mutationID), original.command == reconstruction.targetCommand else {
                        throw FieldDraftFailureV1.missingReceipt
                    }
                    receipt = original.receipt
                }
                guard try photoTargetReadback(parentDraftID: read.evidence.parentCheckpoint.draftID,
                    reconstruction: reconstruction, receipt: receipt) else { throw FieldDraftFailureV1.missingReceipt }
                return receipt
            }
        }
    }

    fileprivate func photoTargetReadback(parentDraftID: UUID, reconstruction: CheckRunnerPhotoCommitReconstructionV1,
        receipt: MutationReceiptV1) throws -> Bool {
        let observed = try currentPhotoContinuation(parentDraftID: parentDraftID,
            childDraftID: reconstruction.draftCommit.checkpoint.draftID)
        guard observed.checkpoint == reconstruction.draftCommit.checkpoint, let target = observed.target else { return false }
        return target.receipt == receipt && target.command == reconstruction.targetCommand
    }

    /// A terminal child can replace only its own selected slot. All unrelated
    /// parent fields come from the current authenticated checkpoint.
    private func completePhotoParentSlot(parentDraftID: UUID, childDraftID: UUID) throws -> FieldDraftCheckpointV1 {
        guard let readback = try readCurrentPhotoTarget(parentDraftID: parentDraftID, childDraftID: childDraftID),
              case let .applyCommitTerminal(terminal, _) = readback.parent.child.terminal.mutation.postImage else {
            throw FieldDraftFailureV1.missingReceipt
        }
        let parent = try CheckRunnerItemDraftCodecV1.validateCheckpoint(readback.parentCheckpoint)
        let slot = readback.parent.slot
        let selected = slot.captureStep == .wide ? parent.field.wideContext : parent.field.closeDetail
        if selected == slot { return terminal.committedCheckpoint }
        let expected = CheckRunnerPhotoSlotV1.pending(childDraftID: childDraftID,
            captureStep: slot.captureStep, purposeKey: slot.purposeKey)
        guard selected == expected else { throw FieldDraftFailureV1.staleDraftRevision }
        try slot.validateReplacement(of: expected)
        let continuation = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
        guard continuation.terminal == readback.parent.child,
              continuation.parentCheckpoint == readback.parentCheckpoint else { throw FieldDraftFailureV1.staleDraftRevision }
        let field = parent.field
        let payload = try CheckRunnerItemDraftPayloadV1(editing: parent.source, field: .init(
            preflight: field.preflight, begin: field.begin, outcome: field.outcome,
            wideContext: slot.captureStep == .wide ? slot : field.wideContext,
            closeDetail: slot.captureStep == .close ? slot : field.closeDetail, semanticAnchor: field.semanticAnchor))
        let instant = max(clock.now(), max(readback.parentCheckpoint.updatedAt, terminal.committedCheckpoint.updatedAt))
        let checkpoint = try makeCheckpoint(payload: payload, predecessor: readback.parentCheckpoint, frozenUpdatedAt: instant)
        let current = try currentSession()
        _ = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            .compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: readback.parentCheckpoint.draftRevision,
                            expectedBaseRevision: readback.parentCheckpoint.baseCanonicalRevision)
        guard let adopted = try readCurrentPhotoTarget(parentDraftID: parentDraftID, childDraftID: childDraftID),
              adopted.parentCheckpoint == checkpoint, adopted.parent.slot == slot else { throw FieldDraftFailureV1.missingReceipt }
        return terminal.committedCheckpoint
    }

    fileprivate func validateRawPhotoRead(_ authority: CheckRunnerPhotoRawReadAuthorityV1,
                                         adapterIdentity: ObjectIdentifier) throws {
        try Task.checkCancellation()
        guard authority.service === self, authority.owner === currentPhotoReadOwner,
              let writer = authority.writer, let attachmentStaging,
              ObjectIdentifier(attachmentStaging) == adapterIdentity else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let current = try currentSession()
        guard current.workspaceWriter === writer,
              current.checkRunnerPhotoApplicationSupportURL.standardizedFileURL == authority.applicationSupportURL,
              try writer.currentRevision() == authority.revision,
              authority.evidence.checkpoint.state == .active,
              authority.evidence.currentStage == authority.rawReady.readyItem,
              try currentPhotoContinuation(parentDraftID: authority.evidence.parentCheckpoint.draftID,
                  childDraftID: authority.evidence.checkpoint.draftID) == authority.evidence else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        switch authority.evidence.payload.phase {
        case .rawReady: break
        case .pairReady: guard !authority.normalizationAllowed else { throw FieldDraftFailureV1.invalidTransition }
        default: throw FieldDraftFailureV1.invalidTransition
        }
    }

    fileprivate func validateRawPhotoPromotion(_ authority: CheckRunnerPhotoRawPromotionAuthorityV1,
                                               prepared: DraftPreparedRawPhotoPromotionV1) throws {
        try Task.checkCancellation()
        guard authority.service === self, authority.owner === currentPhotoReadOwner,
              let writer = authority.writer, let attachmentStaging,
              prepared.adapterIdentity == ObjectIdentifier(attachmentStaging),
              prepared.applicationSupportURL.standardizedFileURL == authority.applicationSupportURL else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let current = try currentSession()
        guard current.workspaceWriter === writer,
              current.checkRunnerPhotoApplicationSupportURL.standardizedFileURL == authority.applicationSupportURL,
              try writer.currentRevision() == authority.revision,
              try currentPhotoContinuation(parentDraftID: authority.evidence.parentCheckpoint.draftID,
                  childDraftID: authority.evidence.checkpoint.draftID) == authority.evidence,
              case let .preparedCommit(pair, attempt) = authority.evidence.payload.phase else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: authority.committingCheckpoint)
        let plan = reconstruction.draftCommit.plan
        let request = try DraftImmutableContentWriteRequestV1(workspaceID: workspaceID,
            contentID: pair.raw.inspection.rawContentID, digest: pair.raw.inspection.sourceSHA256,
            byteLength: pair.raw.inspection.sourceByteCount, mediaType: pair.raw.inspection.sourceMediaType,
            mutationID: attempt.reservationMutationID,
            createdAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(attempt.promotionAt))
        let stage = try CheckRunnerPhotoContinuationEvidenceV1.committedStage(raw: pair.raw, attempt: attempt)
        guard prepared.rawReady == pair.raw, prepared.plan == plan, prepared.attempt == attempt,
              prepared.request == request, prepared.committedStage == stage,
              prepared.contentReference == stage.contentReference,
              prepared.reservation == (try CheckRunnerPhotoContinuationEvidenceV1.reservation(
                raw: pair.raw, plan: plan, attempt: attempt)) else { throw FieldDraftFailureV1.digestMismatch }
    }

    fileprivate func publishPreparedRawPhotoPromotion(authority: CheckRunnerPhotoRawPromotionAuthorityV1,
        prepared: DraftPreparedRawPhotoPromotionV1) throws -> DraftContentReservationV1 {
        guard let writer = authority.writer else { throw ScanToWorkFailureV1.authorityMismatch }
        let current = try currentSession()
        return try current.withCheckRunnerPhotoPublication(expectedWriter: writer,
            applicationSupportURL: authority.applicationSupportURL) {
            try prepared.withPublicationLock { publish in
                try validateRawPhotoPromotion(authority, prepared: prepared)
                try publish()
                // The immutable content and physical manifest are proven before
                // the incumbent writer records its exact COMMITTED stage.
                let lifecycle = try writer.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
                _ = try lifecycle.append(stagingItem: prepared.committedStage,
                                         expectedRevision: prepared.rawReady.readyItem.revision)
                let observed = try currentPhotoContinuation(parentDraftID: authority.evidence.parentCheckpoint.draftID,
                    childDraftID: authority.evidence.checkpoint.draftID)
                guard observed.checkpoint == authority.committingCheckpoint,
                      observed.currentStage == prepared.committedStage else { throw FieldDraftFailureV1.missingReceipt }
                return prepared.reservation
            }
        }
    }

    fileprivate func publishPreparedRawPhoto(authority: CheckRunnerPhotoRawPublicationAuthorityV1,
        prepared: DraftPreparedRawPhotoPublicationV1) throws -> FieldDraftCommittedEvidenceV1 {
        try Task.checkCancellation()
        guard authority.service === self, authority.owner === currentPhotoReadOwner,
              let writer = authority.writer, let attachmentStaging,
              prepared.adapterIdentity == ObjectIdentifier(attachmentStaging),
              prepared.applicationSupportURL.standardizedFileURL == authority.applicationSupportURL else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let current = try currentSession()
        return try current.withCheckRunnerPhotoPublication(expectedWriter: writer,
            applicationSupportURL: authority.applicationSupportURL) {
            try prepared.withPublicationLock { publish in
                guard try currentSession().workspaceWriter.currentRevision() == authority.revision else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
                let original = authority.evidence
                let observed = try currentRawPhotoEvidence(parentDraftID: original.parentCheckpoint.draftID,
                                                          childDraftID: original.initialPayload.childDraftID)
                guard observed == original,
                      observed.rawReady.map({ $0 == prepared.rawReady }) ?? true else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
                let bundle = try observed.publicationBundle(raw: prepared.rawReady)
                let lifecycle = try writer.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
                try Task.checkCancellation()
                try publish()
                let receipt = try lifecycle.publish(readyStage: bundle)
                guard let committed = try lifecycle.readyStagePublicationEvidence(for: bundle),
                      committed.receipt == receipt,
                      observed.publication.map({ $0 == committed }) ?? true else {
                    throw FieldDraftFailureV1.missingReceipt
                }
                let reread = try currentRawPhotoEvidence(parentDraftID: original.parentCheckpoint.draftID,
                                                        childDraftID: original.initialPayload.childDraftID)
                guard reread.publication == committed, reread.rawReady == prepared.rawReady else {
                    throw FieldDraftFailureV1.missingReceipt
                }
                return committed
            }
        }
    }

    /// Explicit Begin freezes once. A repeated request observes the saved
    /// attempt rather than sampling replacement IDs, time or command fields.
    func prepareBegin(draftID: UUID, expectedCheckpointSHA256: String,
                      observedAtUTC: Date) throws -> FieldDraftCheckpointV1 {
        let checkpoint = try read(draftID: draftID)
        guard checkpoint.checkpointSHA256 == expectedCheckpointSHA256 else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let payload = try requireInitialEditing(checkpoint)
        guard payload.field.begin == .notBegun else { return checkpoint }
        let field = payload.field
        let attempt = try coordinator.prepareFrozenBegin(source: payload.source, progress: progress,
            publishedRelease: publishedRelease, submission: .init(assetID: payload.source.assetID,
                requestedStage: payload.source.requestedEntry.stage, issueID: payload.source.requestedEntry.issueID,
                observedAtUTC: observedAtUTC,
                confirmedTimeZoneID: field.preflight.isTimeZoneConfirmed ? field.preflight.confirmedTimeZoneID : nil,
                afterDarkAccepted: field.preflight.afterDarkAccepted,
                safePositionAccepted: field.preflight.safePositionAccepted))
        return try replaceBegin(.prepared(attempt: attempt), in: checkpoint, payload: payload)
    }

    /// Recovers the initial Begin edge only. Later child/finalizer advancement
    /// needs its separate authenticated chain before production composition.
    func resumeInitialBegin(draftID: UUID) throws -> FieldDraftCheckpointV1 {
        let checkpoint = try read(draftID: draftID)
        let payload = try requireInitialEditing(checkpoint)
        switch payload.field.begin {
        case .notBegun:
            throw FieldDraftFailureV1.missingReceipt
        case .prepared:
            let bound = try coordinator.resumeFrozenBegin(parentCheckpoint: checkpoint, progress: progress,
                                                           publishedRelease: publishedRelease)
            return try replaceBegin(bound, in: checkpoint, payload: payload)
        case .bound:
            try coordinator.validateInitialBoundBegin(parentCheckpoint: checkpoint, progress: progress,
                                                       publishedRelease: publishedRelease)
            return try read(draftID: draftID)
        }
    }

    /// Shared nonmutating current-checkpoint/original-command join. A matching
    /// row or self-computed digest alone never authorizes a Begin effect.
    static func authenticateCurrent(_ checkpoint: FieldDraftCheckpointV1, writer: WorkspaceWriterV1,
                                    context: ModelContext) throws -> CheckRunnerItemDraftPayloadV1 {
        try writer.validateFieldDraftReadContext(context)
        let current = try writer.currentRevision()
        guard checkpoint.workspaceID == current.workspaceID else { throw FieldDraftFailureV1.wrongWorkspace }
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        let id = checkpoint.draftID
        let rows = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>(predicate: #Predicate { $0.draftID == id }))
        guard rows.count == 1, try rows[0].value() == checkpoint,
              let evidence = try writer.fieldDraftEvidence(mutationID: checkpoint.mutationID),
              evidence.mutation.workspaceID == checkpoint.workspaceID,
              evidence.mutation.expectedRevision == checkpoint.draftRevision - 1,
              evidence.mutation.expectedBaseCanonicalRevision == checkpoint.baseCanonicalRevision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        switch evidence.mutation.postImage {
        case let .createCheckpoint(original):
            guard checkpoint.draftRevision == 1, original == checkpoint else { throw FieldDraftFailureV1.digestMismatch }
        case let .reviseCheckpoint(original):
            guard checkpoint.draftRevision > 1, original == checkpoint else { throw FieldDraftFailureV1.digestMismatch }
        default:
            throw FieldDraftFailureV1.missingReceipt
        }
        return payload
    }

    private func requireInitialEditing(_ checkpoint: FieldDraftCheckpointV1) throws -> CheckRunnerItemDraftPayloadV1 {
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        guard checkpoint.state == .active, payload.phase == .editing,
              payload.field.wideContext == nil, payload.field.closeDetail == nil else {
            throw FieldDraftFailureV1.invalidValue
        }
        return payload
    }

    private func replaceBegin(_ begin: CheckRunnerBeginStateV1, in checkpoint: FieldDraftCheckpointV1,
                              payload: CheckRunnerItemDraftPayloadV1) throws -> FieldDraftCheckpointV1 {
        let current = try currentSession()
        _ = try Self.authenticateCurrent(checkpoint, writer: current.workspaceWriter, context: current.modelContext)
        let field = payload.field
        let next = try CheckRunnerItemDraftPayloadV1(editing: payload.source, field: .init(
            preflight: field.preflight, begin: begin, outcome: field.outcome,
            wideContext: field.wideContext, closeDetail: field.closeDetail, semanticAnchor: field.semanticAnchor))
        let successor = try makeCheckpoint(payload: next, predecessor: checkpoint)
        try successor.validateSuccessor(of: checkpoint, expectedDraftRevision: checkpoint.draftRevision,
                                        expectedBaseRevision: checkpoint.baseCanonicalRevision)
        _ = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            .compareAndSwap(checkpoint: successor, expectedDraftRevision: checkpoint.draftRevision,
                            expectedBaseRevision: checkpoint.baseCanonicalRevision)
        return try read(draftID: successor.draftID)
    }

    private func makeCheckpoint(payload: CheckRunnerItemDraftPayloadV1,
                                predecessor: FieldDraftCheckpointV1?,
                                frozenUpdatedAt: Date? = nil) throws -> FieldDraftCheckpointV1 {
        let sampled = (frozenUpdatedAt ?? clock.now()).timeIntervalSince1970
        guard sampled.isFinite, sampled >= 0, (sampled * 1_000).isFinite,
              predecessor.map({ $0.draftRevision < UInt64.max }) ?? true else {
            throw FieldDraftFailureV1.invalidValue
        }
        let updatedAt = Date(timeIntervalSince1970: floor(sampled * 1_000) / 1_000)
        guard predecessor.map({ updatedAt >= $0.updatedAt }) ?? true else { throw FieldDraftFailureV1.invalidValue }
        return try .init(draftID: predecessor?.draftID ?? ids.makeID(), workspaceID: workspaceID,
            scope: CheckRunnerItemDraftCodecV1.scope(source: payload.source), purpose: .inspectionReview,
            codec: CheckRunnerItemDraftCodecV1.release(), baseCanonicalRevision: payload.source.roundAtEntry.revision,
            draftRevision: (predecessor?.draftRevision ?? 0) + 1, payloadData: CheckRunnerItemDraftCodecV1.encode(payload),
            stageIDs: [], resumeAnchor: CheckRunnerItemDraftCodecV1.resumeAnchor(payload: payload), state: .active,
            updatedAt: updatedAt, mutationID: .init(rawValue: ids.makeID()))
    }

    private func currentSession() throws -> StoreSessionCoordinator {
        guard let session, let originalWriter, originalWriter === session.workspaceWriter,
              session.workspaceID == workspaceID else { throw FieldDraftFailureV1.wrongWorkspace }
        try progress.validateCheckRunnerOwner(writer: session.workspaceWriter, modelContext: session.modelContext)
        return session
    }
}

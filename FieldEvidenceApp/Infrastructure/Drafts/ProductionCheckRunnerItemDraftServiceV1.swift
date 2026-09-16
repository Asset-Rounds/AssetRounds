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

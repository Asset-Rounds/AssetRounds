import Foundation
import SwiftData

/// Raw editor values only. Source, Begin and photo ownership never come from
/// an editable snapshot, and incomplete input is not normalized on save.
struct CheckRunnerEditableItemValuesV1: Equatable, Sendable {
    let preflight: CheckRunnerEditablePreflightV1
    let outcome: CheckRunnerEditableOutcomeV1
    let semanticAnchor: CheckRunnerItemSemanticAnchorV1

    init(preflight: CheckRunnerEditablePreflightV1, outcome: CheckRunnerEditableOutcomeV1,
         semanticAnchor: CheckRunnerItemSemanticAnchorV1) {
        self.preflight = preflight; self.outcome = outcome; self.semanticAnchor = semanticAnchor
    }

    fileprivate init(_ field: CheckRunnerItemFieldStateV1) {
        self.init(preflight: field.preflight, outcome: field.outcome, semanticAnchor: field.semanticAnchor)
    }
}

fileprivate final class CheckRunnerFieldReadOwnerV1 {}

/// One immutable CAS attempt. Only its original service can persist it; a
/// failed acknowledgement does not permit a caller to construct a successor.
@MainActor
final class CheckRunnerFieldEditAttemptV1 {
    fileprivate let owner: CheckRunnerFieldReadOwnerV1
    fileprivate let predecessor: FieldDraftCheckpointV1
    fileprivate let successor: FieldDraftCheckpointV1
    fileprivate let values: CheckRunnerEditableItemValuesV1

    fileprivate init(owner: CheckRunnerFieldReadOwnerV1, predecessor: FieldDraftCheckpointV1,
                     successor: FieldDraftCheckpointV1, values: CheckRunnerEditableItemValuesV1) {
        self.owner = owner; self.predecessor = predecessor; self.successor = successor; self.values = values
    }
}

/// Authentic parent-field readback, not media, action or navigation authority.
/// The issuing service must revalidate this observation before publication.
@MainActor
final class CheckRunnerFieldReadbackV1 {
    let checkpoint: FieldDraftCheckpointV1
    let values: CheckRunnerEditableItemValuesV1
    let receipt: MutationReceiptV1
    fileprivate let owner: CheckRunnerFieldReadOwnerV1
    fileprivate let evidence: FieldDraftCommittedEvidenceV1
    fileprivate let observedRevision: WorkspaceRevisionV1

    fileprivate init(checkpoint: FieldDraftCheckpointV1, values: CheckRunnerEditableItemValuesV1,
        owner: CheckRunnerFieldReadOwnerV1, evidence: FieldDraftCommittedEvidenceV1,
        observedRevision: WorkspaceRevisionV1) {
        self.checkpoint = checkpoint; self.values = values; self.receipt = evidence.receipt
        self.owner = owner; self.evidence = evidence; self.observedRevision = observedRevision
    }
}

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
    nonisolated let adoptsExistingOnly: Bool
    fileprivate let liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?
    fileprivate let backupOperation: AppAccessPresentationV1.BackupOperationAccess?
    fileprivate let evidence: CheckRunnerPhotoRawStageEvidenceV1
    fileprivate let revision: WorkspaceRevisionV1
    fileprivate let owner: CurrentPhotoTargetReadOwnerV1
    fileprivate weak var service: ProductionCheckRunnerItemDraftServiceV1?
    fileprivate weak var writer: WorkspaceWriterV1?

    fileprivate init(service: ProductionCheckRunnerItemDraftServiceV1,
        writer: WorkspaceWriterV1, owner: CurrentPhotoTargetReadOwnerV1,
        evidence: CheckRunnerPhotoRawStageEvidenceV1, revision: WorkspaceRevisionV1,
        applicationSupportURL: URL, backupOperation: AppAccessPresentationV1.BackupOperationAccess? = nil,
        liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) {
        self.service = service; self.writer = writer; self.owner = owner
        self.evidence = evidence; self.revision = revision
        payload = evidence.initialPayload; publishedRawReady = evidence.rawReady
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
        self.backupOperation = backupOperation
        adoptsExistingOnly = backupOperation != nil
        self.liveOperation = liveOperation
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
    fileprivate let liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?
    fileprivate let evidence: CheckRunnerPhotoContinuationEvidenceV1
    fileprivate let revision: WorkspaceRevisionV1
    fileprivate let owner: CurrentPhotoTargetReadOwnerV1
    fileprivate weak var service: ProductionCheckRunnerItemDraftServiceV1?
    fileprivate weak var writer: WorkspaceWriterV1?
    fileprivate let backupOperation: AppAccessPresentationV1.BackupOperationAccess?

    fileprivate init(service: ProductionCheckRunnerItemDraftServiceV1, writer: WorkspaceWriterV1,
        owner: CurrentPhotoTargetReadOwnerV1, evidence: CheckRunnerPhotoContinuationEvidenceV1,
        revision: WorkspaceRevisionV1, applicationSupportURL: URL, normalizationAllowed: Bool,
        backupOperation: AppAccessPresentationV1.BackupOperationAccess? = nil,
        liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) {
        self.service = service; self.writer = writer; self.owner = owner; self.evidence = evidence
        self.revision = revision; rawReady = evidence.raw
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
        self.normalizationAllowed = normalizationAllowed
        self.liveOperation = liveOperation
        self.backupOperation = backupOperation
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
    nonisolated let requiresSynchronousImmutablePublication: Bool
    fileprivate let liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?
    nonisolated let applicationSupportURL: URL
    fileprivate let evidence: CheckRunnerPhotoContinuationEvidenceV1
    fileprivate let revision: WorkspaceRevisionV1
    fileprivate let owner: CurrentPhotoTargetReadOwnerV1
    fileprivate weak var service: ProductionCheckRunnerItemDraftServiceV1?
    fileprivate weak var writer: WorkspaceWriterV1?

    fileprivate init(service: ProductionCheckRunnerItemDraftServiceV1, writer: WorkspaceWriterV1,
        owner: CurrentPhotoTargetReadOwnerV1, evidence: CheckRunnerPhotoContinuationEvidenceV1,
        revision: WorkspaceRevisionV1, applicationSupportURL: URL,
        liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws {
        guard let committing = evidence.committing,
              case let .reviseCheckpoint(checkpoint) = committing.mutation.postImage,
              evidence.checkpoint == checkpoint, checkpoint.state == .committing else {
            throw FieldDraftFailureV1.invalidTransition
        }
        committingCheckpoint = checkpoint
        requiresSynchronousImmutablePublication = liveOperation != nil
        self.liveOperation = liveOperation
        self.service = service; self.writer = writer; self.owner = owner; self.evidence = evidence
        self.revision = revision; self.applicationSupportURL = applicationSupportURL.standardizedFileURL
    }

    func validateBeforeImmutableWrite(_ prepared: DraftPreparedRawPhotoPromotionV1) throws {
        guard let service else { throw ScanToWorkFailureV1.authorityMismatch }
        try service.validateRawPhotoPromotion(self, prepared: prepared)
    }

    func publish(_ prepared: DraftPreparedRawPhotoPromotionV1) throws -> DraftContentReservationV1 {
        guard let service else { throw ScanToWorkFailureV1.authorityMismatch }
#if DEBUG
        // The actual C05 preparation has returned; no publication lock is held.
        // Tests may retire the original operation before its real effect fence.
        if requiresSynchronousImmutablePublication {
            try service.beforeRawPhotoImmutablePublicationForTesting?()
        }
#endif
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
    let backupOperation: AppAccessPresentationV1.BackupOperationAccess?
    let liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?

    init(service: ProductionCheckRunnerItemDraftServiceV1, writer: WorkspaceWriterV1,
         owner: CurrentPhotoTargetReadOwnerV1, evidence: CheckRunnerPhotoContinuationEvidenceV1,
         revision: WorkspaceRevisionV1, media: CheckRunnerPhotoMediaOwnerV1, applicationSupportURL: URL,
         backupOperation: AppAccessPresentationV1.BackupOperationAccess? = nil,
         liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) {
        self.service = service; self.writer = writer; self.owner = owner; self.evidence = evidence
        self.revision = revision; self.media = media
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
        self.backupOperation = backupOperation
        self.liveOperation = liveOperation
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
    private let liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?

    init(service: ProductionCheckRunnerItemDraftServiceV1, parentDraftID: UUID,
         reconstruction: CheckRunnerPhotoCommitReconstructionV1,
         liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?) {
        self.service = service; self.parentDraftID = parentDraftID; self.reconstruction = reconstruction
        self.liveOperation = liveOperation
    }

    func promote(plan: DraftCommitPlanV1, items: [AttachmentStagingItemV1],
                 reservationMutationIDs: [UUID: MutationIDV1]) async throws -> [DraftContentReservationV1] {
        guard let service, plan == reconstruction.draftCommit.plan, items == reconstruction.draftCommit.items,
              reservationMutationIDs == reconstruction.draftCommit.rowMutationIDs.reservationByStageID else {
            throw FieldDraftFailureV1.digestMismatch
        }
        return [try await service.promotePhotoRaw(parentDraftID: parentDraftID,
            reconstruction: reconstruction, liveOperation: liveOperation)]
    }

    func quarantine(reservations: [DraftContentReservationV1], for plan: DraftDiscardPlanV1) async throws {
        throw FieldDraftFailureV1.invalidTransition
    }

    func commit(plan: DraftCommitPlanV1, reservations: [DraftContentReservationV1]) async throws -> MutationReceiptV1 {
        guard let service, plan == reconstruction.draftCommit.plan else { throw FieldDraftFailureV1.digestMismatch }
        return try await service.commitPhotoTarget(parentDraftID: parentDraftID,
            reconstruction: reconstruction, reservations: reservations, liveOperation: liveOperation)
    }

    func readBackMatches(plan: DraftCommitPlanV1, receipt: MutationReceiptV1) throws -> Bool {
        guard let service, plan == reconstruction.draftCommit.plan else { throw FieldDraftFailureV1.digestMismatch }
        return try service.withItemOperation(liveOperation) { _ in
            try service.photoTargetReadback(parentDraftID: parentDraftID, reconstruction: reconstruction, receipt: receipt)
        }
    }
}

/// Re-enters the original operation for every incumbent saga/read/CAS call.
/// No authorization lock spans the coordinator's asynchronous media work.
@MainActor
fileprivate final class CheckRunnerAuthorizedDraftWriterV1: FieldDraftWritingV1 {
    private let service: ProductionCheckRunnerItemDraftServiceV1
    private let liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?

    init(service: ProductionCheckRunnerItemDraftServiceV1,
         liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?) {
        self.service = service; self.liveOperation = liveOperation
    }

    private func perform<T>(_ body: (FieldDraftLifecycleAdapterV1) throws -> T) throws -> T {
        try service.withItemOperation(liveOperation) { current in
            try body(current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext))
        }
    }

    func currentCheckpoint(workspaceID: WorkspaceID, draftID: UUID) throws -> FieldDraftCheckpointV1? {
        try perform { try $0.currentCheckpoint(workspaceID: workspaceID, draftID: draftID) }
    }
    func compareAndSwap(checkpoint: FieldDraftCheckpointV1, expectedDraftRevision: UInt64,
                        expectedBaseRevision: UInt64) throws -> MutationReceiptV1 {
        try perform { try $0.compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: expectedDraftRevision,
                                            expectedBaseRevision: expectedBaseRevision) }
    }
    func publish(readyStage bundle: FieldDraftStagePublicationBundleV1) throws -> MutationReceiptV1 {
        try perform { try $0.publish(readyStage: bundle) }
    }
    func append(stagingItem: AttachmentStagingItemV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        try perform { try $0.append(stagingItem: stagingItem, expectedRevision: expectedRevision) }
    }
    func append(saga: DraftCommitSagaV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        try perform { try $0.append(saga: saga, expectedRevision: expectedRevision) }
    }
    func append(reservation: DraftContentReservationV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        try perform { try $0.append(reservation: reservation, expectedRevision: expectedRevision) }
    }
    func apply(commitTerminalBundle: DraftCommitTerminalBundleV1, expectedDraftRevision: UInt64,
               expectedSagaRevision: UInt64) throws -> MutationReceiptV1 {
        try perform { try $0.apply(commitTerminalBundle: commitTerminalBundle,
            expectedDraftRevision: expectedDraftRevision, expectedSagaRevision: expectedSagaRevision) }
    }
    func apply(discardTerminalBundle: DraftDiscardTerminalBundleV1,
               expectedDraftRevision: UInt64) throws -> MutationReceiptV1 {
        try perform { try $0.apply(discardTerminalBundle: discardTerminalBundle,
                                   expectedDraftRevision: expectedDraftRevision) }
    }
}

/// Empty content belongs to this exact parent plan. The existing coordinator
/// still records every saga and the real finalizer supplies the target receipt.
@MainActor
fileprivate final class CheckRunnerParentCommitPortV1: DraftContentPromotionPortV1, DraftAsyncCanonicalCommitPortV1 {
    private weak var service: ProductionCheckRunnerItemDraftServiceV1?
    private let reconstruction: CheckRunnerDraftCommitReconstructionV1
    private let validateIntent: @MainActor () throws -> Void
    private let liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?

    init(service: ProductionCheckRunnerItemDraftServiceV1, reconstruction: CheckRunnerDraftCommitReconstructionV1,
         liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?,
         validateIntent: @escaping @MainActor () throws -> Void) {
        self.service = service; self.reconstruction = reconstruction
        self.validateIntent = validateIntent
        self.liveOperation = liveOperation
    }

    func promote(plan: DraftCommitPlanV1, items: [AttachmentStagingItemV1],
                 reservationMutationIDs: [UUID: MutationIDV1]) async throws -> [DraftContentReservationV1] {
        guard let service, plan == reconstruction.plan, items.isEmpty,
              reconstruction.items.isEmpty, reservationMutationIDs.isEmpty,
              reconstruction.rowMutationIDs.reservationByStageID.isEmpty else {
            throw FieldDraftFailureV1.digestMismatch
        }
        try Task.checkCancellation(); try validateIntent()
        try service.withItemOperation(liveOperation) { _ in }
        try await service.validateParentFinalizationMedia(reconstruction)
        try Task.checkCancellation(); try validateIntent()
        try service.withItemOperation(liveOperation) { _ in }
        return []
    }

    func quarantine(reservations: [DraftContentReservationV1], for plan: DraftDiscardPlanV1) async throws {
        throw FieldDraftFailureV1.invalidTransition
    }

    func commit(plan: DraftCommitPlanV1, reservations: [DraftContentReservationV1]) async throws -> MutationReceiptV1 {
        guard let service, plan == reconstruction.plan, reservations.isEmpty else {
            throw FieldDraftFailureV1.digestMismatch
        }
        return try await service.commitParentFinalizationTarget(reconstruction,
            liveOperation: liveOperation, validateIntent: validateIntent)
    }

    func readBackMatches(plan: DraftCommitPlanV1, receipt: MutationReceiptV1) throws -> Bool {
        guard let service, plan == reconstruction.plan else { throw FieldDraftFailureV1.digestMismatch }
        try Task.checkCancellation(); try validateIntent()
        return try service.withItemOperation(liveOperation) { _ in
            try service.parentFinalizationReadback(reconstruction, receipt: receipt, liveOperation: liveOperation)
        }
    }
}

/// Durable Begin and receipt-bound photo staging through the existing owners.
/// Factory registration awaits complete promotion, restore and lifecycle gates.
enum CheckRunnerItemServiceContextV1: Sendable {
    case standalone
    case backup
    case live(CheckRunnerRoundItemSourceV1)
}

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
    private var attachmentStaging: DraftAttachmentStagingAdapterV1?
    private let serviceContext: CheckRunnerItemServiceContextV1
    private let currentPhotoReadOwner = CurrentPhotoTargetReadOwnerV1()
    private let fieldReadOwner = CheckRunnerFieldReadOwnerV1()
    private var pendingFieldEdits: [UUID: CheckRunnerFieldEditAttemptV1] = [:]
    private var photoOperations: Set<UUID> = []
    private var parentOperations: Set<UUID> = []
#if DEBUG
    /// Observation after durable target publication, outside publication locks.
    var beforePhotoTargetAcknowledgementForTesting: (() throws -> Void)?
    var beforeRawPhotoImmutablePublicationForTesting: (() throws -> Void)?
    var photoCommitObservationForTesting: ((String) -> Void)?
    var beforeParentTargetAcknowledgementForTesting: (() throws -> Void)?
    /// After the real field CAS, before authentic readback and acknowledgement.
    var beforeFieldEditAcknowledgementForTesting: (() throws -> Void)?
    var livePhotoStagingIdentityForTesting: ObjectIdentifier? {
        guard let attachmentStaging else { return nil }
        return ObjectIdentifier(attachmentStaging)
    }
#endif

    init(session: StoreSessionCoordinator, progress: ProductionRepetitiveCaptureProgressServiceV2,
         coordinator: CheckRunnerCoordinator, publishedRelease: InspectionPackageReleaseV1,
         clock: any ApplicationClock, ids: any ApplicationIDSource,
         attachmentStaging: DraftAttachmentStagingAdapterV1? = nil,
         serviceContext: CheckRunnerItemServiceContextV1 = .standalone) throws {
        try progress.validateCheckRunnerOwner(writer: session.workspaceWriter, modelContext: session.modelContext)
        if case let .live(source) = serviceContext {
            try source.validate()
            guard source.roundAtEntry.workspaceID == session.workspaceID,
                  try RoundPackageReleaseReferenceV1(publishedRelease) == source.packageRelease else {
                throw ScanToWorkFailureV1.authorityMismatch
            }
        }
        self.session = session; originalWriter = session.workspaceWriter; workspaceID = session.workspaceID
        self.progress = progress; self.coordinator = coordinator; self.publishedRelease = publishedRelease
        self.clock = clock; self.ids = ids
        self.attachmentStaging = attachmentStaging
        self.serviceContext = serviceContext
    }

    /// Backup and standalone capabilities are never silently adopted as a
    /// live Round editor, including when they happen to share the same writer.
    func validateLiveTarget(_ target: NavigationTargetV1) throws {
        guard case let .live(source) = serviceContext,
              target.workspaceID == workspaceID, target.root == .work, target.destination == .work,
              target.stableSessionID == source.roundAtEntry.sessionID,
              target.stableEntityID == nil || target.stableEntityID == source.assetID else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        _ = try currentSession()
    }

    /// Only an explicit media action creates the staging root. The same
    /// adapter survives retries and is never replaced to refresh authority.
    func prepareLivePhotoStaging(authorizing operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess) throws {
        guard case .live = serviceContext else { throw ScanToWorkFailureV1.authorityMismatch }
        try withItemOperation(operation) { current in
            guard attachmentStaging == nil else { return }
            let media = try coordinator.checkRunnerPhotoMediaOwner(progress: progress)
            attachmentStaging = try current.withCheckRunnerPhotoPublication(expectedWriter: current.workspaceWriter,
                applicationSupportURL: current.checkRunnerPhotoApplicationSupportURL) {
                try coordinator.makeDraftAttachmentStagingAdapter(
                    applicationSupportURL: current.checkRunnerPhotoApplicationSupportURL,
                    workspaceID: workspaceID, immutableContentWriter: media.store)
            }
        }
    }

    fileprivate func withItemOperation<T>(_ operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?,
        _ body: (StoreSessionCoordinator) throws -> T) throws -> T {
        try Task.checkCancellation()
        switch serviceContext {
        case .live:
            guard let operation else { throw ScanToWorkFailureV1.authorityMismatch }
            return try operation.withAuthorization(for: self) { try body(currentSession()) }
        case .standalone, .backup:
            guard operation == nil else { throw ScanToWorkFailureV1.authorityMismatch }
            return try body(currentSession())
        }
    }

    /// The first checkpoint has no workflow record identity or target effect.
    /// Raw editable fields retain their bytes, including incomplete input.
    func create(source: CheckRunnerRoundItemSourceV1, preflight: CheckRunnerEditablePreflightV1,
                outcome: CheckRunnerEditableOutcomeV1 = .init()) throws -> FieldDraftCheckpointV1 {
        if case let .live(expected) = serviceContext, source != expected {
            throw ScanToWorkFailureV1.authorityMismatch
        }
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

    /// Resolve the exact parent scope without creating a draft or staging.
    /// A terminal/prepared parent is retained for explicit recovery, not replaced.
    func readCurrentDraft(source: CheckRunnerRoundItemSourceV1) throws -> FieldDraftCheckpointV1? {
        if case let .live(expected) = serviceContext, source != expected {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let current = try currentSession()
        let scope = try CheckRunnerItemDraftCodecV1.scope(source: source)
        let workspace = workspaceID.rawValue
        let rows = try current.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
            predicate: #Predicate { $0.workspaceID == workspace }))
        let matches = try rows.map { try $0.value() }.filter { $0.scope == scope }
        guard matches.count <= 1 else { throw FieldDraftFailureV1.staleDraftRevision }
        guard let candidate = matches.first else { return nil }
        let authenticated = try read(draftID: candidate.draftID)
        guard try CheckRunnerItemDraftCodecV1.validateCheckpoint(authenticated).source == source else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        return authenticated
    }

    func readPreflightPresentation(source: CheckRunnerRoundItemSourceV1) throws -> CheckRunnerItemPreflightPresentationV1 {
        if case let .live(expected) = serviceContext, source != expected {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let current = try currentSession()
        let assetID = source.assetID
        let assets = try current.modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID }))
        guard assets.count == 1, let asset = assets.first else { throw FieldDraftFailureV1.missingContent }
        let siteID = asset.siteID
        let sites = try current.modelContext.fetch(FetchDescriptor<Site>(predicate: #Predicate { $0.id == siteID }))
        guard sites.count == 1, let site = sites.first else { throw FieldDraftFailureV1.missingContent }
        let pack = try current.lifecycleProfileRegistry.resolve(source.legacyPackageIdentity).package
        guard asset.packID == pack.packID, asset.packSchemaVersion == pack.schemaVersion,
              asset.packContentVersion == pack.contentVersion else { throw ScanToWorkFailureV1.authorityMismatch }
        return .init(snapshot: .init(siteID: site.id, assetID: asset.id, siteLabel: site.label,
            signLabel: asset.label, address: site.address, timeZoneID: site.timeZoneID,
            packID: asset.packID, packSchemaVersion: asset.packSchemaVersion, packContentVersion: asset.packContentVersion),
            pack: pack)
    }

    /// Outcome choices from the same incumbent resolver that review and the
    /// finalizer use. Observational only: no draft, record or media is written.
    func readOutcomePresentation(
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws
        -> CheckRunnerItemOutcomePresentationV1 {
        try withItemOperation(liveOperation) { _ in
            guard case let .live(source) = serviceContext else { throw ScanToWorkFailureV1.authorityMismatch }
            let keys = ["no_visible_issue", "visible_issue", "could_not_verify", "resolved",
                        "issue_still_visible", "original_resolved_different_issue"]
            var displays: [String: String] = [:]
            for key in keys { displays[key] = coordinator.signPackOutcomeDisplay(key: key) }
            return .init(stage: source.requestedEntry.stage, issueLabels: coordinator.signPackIssueLabels,
                         couldNotVerifyReasons: coordinator.couldNotVerifyReasons, outcomeDisplays: displays)
        }
    }

    /// Review of the saved outcome over the Begin record and committed evidence.
    /// It reads only authenticated durable values; unsaved screen input is excluded.
    func readFinalizationReview(draftID: UUID,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws
        -> FinalizationReview {
        try withItemOperation(liveOperation) { _ in
            let checkpoint = try read(draftID: draftID)
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
            guard checkpoint.state == .active, payload.phase == .editing,
                  case let .bound(attempt, _, _) = payload.field.begin,
                  let selection = payload.field.outcome.selection?.liveSelection else {
                throw FieldDraftFailureV1.invalidValue
            }
            let review = try coordinator.prepareReview(assetID: payload.source.assetID, selection: selection)
            guard review.draftID == attempt.recordCommand.recordID,
                  try read(draftID: draftID) == checkpoint else { throw FieldDraftFailureV1.staleDraftRevision }
            return review
        }
    }

    /// The Begin record's current capture step and evidence purpose; no write.
    func readCapturePreparation(
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws
        -> CapturePreparation {
        try withItemOperation(liveOperation) { _ in
            guard case let .live(source) = serviceContext else { throw ScanToWorkFailureV1.authorityMismatch }
            return try coordinator.prepareCapture(assetID: source.assetID)
        }
    }

    /// A pending photo child's current checkpoint and durable phase, joined to
    /// the authenticated parent. Observational only; every effect revalidates.
    func readPendingPhoto(parentDraftID: UUID, childDraftID: UUID,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws
        -> (checkpoint: FieldDraftCheckpointV1, phase: CheckRunnerPhotoDurablePhaseV1) {
        try withItemOperation(liveOperation) { current in
            // Choose the evidence by the saved phase, as discard does; each read
            // authenticates and throws, so an invalid continuation never falls back.
            let adapter = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            guard let saved = try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: childDraftID) else {
                throw FieldDraftFailureV1.missingReceipt
            }
            if case .awaitingRawStage = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(saved).phase {
                let raw = try currentRawPhotoEvidence(parentDraftID: parentDraftID, childDraftID: childDraftID)
                guard raw.currentCheckpoint == saved else { throw FieldDraftFailureV1.staleDraftRevision }
                return (raw.currentCheckpoint, try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(raw.currentCheckpoint).phase)
            }
            let continuation = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
            guard continuation.checkpoint == saved else { throw FieldDraftFailureV1.staleDraftRevision }
            return (continuation.checkpoint, continuation.payload.phase)
        }
    }

    func readReviewThumbnail(_ evidence: ReviewEvidence,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws -> Data {
        try withItemOperation(liveOperation) { _ in try coordinator.reviewThumbnailData(for: evidence) }
    }

    func read(draftID: UUID) throws -> FieldDraftCheckpointV1 {
        let current = try currentSession()
        let id = draftID
        let rows = try current.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
            predicate: #Predicate { $0.draftID == id }))
        guard rows.count == 1, let row = rows.first else { throw FieldDraftFailureV1.missingReceipt }
        let checkpoint = try row.value()
        _ = try Self.authenticateCurrent(checkpoint, writer: current.workspaceWriter, context: current.modelContext)
        if case let .live(expected) = serviceContext {
            guard try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint).source == expected else {
                throw ScanToWorkFailureV1.authorityMismatch
            }
        }
        return checkpoint
    }

    /// Opening an editor is observational. PREPARED Begin remains readable,
    /// but the separate edit admission rejects it until original recovery.
    func readEditableFields(draftID: UUID) throws -> CheckRunnerFieldReadbackV1 {
        let current = try currentSession()
        let revision = try current.workspaceWriter.currentRevision()
        let checkpoint = try read(draftID: draftID)
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        guard checkpoint.state == .active, payload.phase == .editing else {
            throw FieldDraftFailureV1.invalidTransition
        }
        guard let evidence = try current.workspaceWriter.fieldDraftEvidence(mutationID: checkpoint.mutationID),
              evidence.mutation == (try fieldEditMutation(checkpoint: checkpoint)),
              try currentSession().workspaceWriter.currentRevision() == revision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        return .init(checkpoint: checkpoint, values: .init(payload.field), owner: fieldReadOwner,
                     evidence: evidence, observedRevision: revision)
    }

    /// Freezes exact bytes, time and MutationID once. Ordinary edits cannot
    /// alter a frozen Begin, outcome-entry mode, source or child ownership.
    func prepareFieldEdit(draftID: UUID, expectedCheckpointSHA256: String,
        values: CheckRunnerEditableItemValuesV1,
        validateIntent: @MainActor () throws -> Void) throws -> CheckRunnerFieldEditAttemptV1? {
        try Task.checkCancellation(); try validateIntent()
        _ = try currentSession()
        guard !parentOperations.contains(draftID) else { throw FieldDraftFailureV1.staleDraftRevision }
        if let pending = pendingFieldEdits[draftID] {
            guard pending.predecessor.checkpointSHA256 == expectedCheckpointSHA256,
                  pending.values == values else { throw FieldDraftFailureV1.staleDraftRevision }
            return pending
        }
        let saved = try readEditableFields(draftID: draftID)
        let checkpoint = saved.checkpoint
        guard checkpoint.checkpointSHA256 == expectedCheckpointSHA256 else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        try coordinator.validateFieldEditing(parentCheckpoint: checkpoint, progress: progress,
                                              publishedRelease: publishedRelease)
        let field = payload.field
        guard values.outcome.startsWithCouldNotVerify == field.outcome.startsWithCouldNotVerify else {
            throw FieldDraftFailureV1.invalidTransition
        }
        switch field.begin {
        case .notBegun: break
        case .prepared: throw FieldDraftFailureV1.invalidTransition
        case .bound:
            guard values.preflight == field.preflight else { throw FieldDraftFailureV1.invalidTransition }
        }
        try Task.checkCancellation(); try validateIntent(); try validateForPublication(saved)
        guard saved.values != values else { return nil }
        let next = try CheckRunnerItemDraftPayloadV1(editing: payload.source, field: .init(
            preflight: values.preflight, begin: field.begin, outcome: values.outcome,
            wideContext: field.wideContext, closeDetail: field.closeDetail,
            semanticAnchor: values.semanticAnchor))
        let successor = try makeCheckpoint(payload: next, predecessor: checkpoint)
        try successor.validateSuccessor(of: checkpoint, expectedDraftRevision: checkpoint.draftRevision,
                                        expectedBaseRevision: checkpoint.baseCanonicalRevision)
        let attempt = CheckRunnerFieldEditAttemptV1(owner: fieldReadOwner, predecessor: checkpoint,
                                                     successor: successor, values: values)
        pendingFieldEdits[draftID] = attempt
        return attempt
    }

    /// Receipt recovery precedes CAS and every later field revision. A
    /// competing current tip is a conflict, never an implicit field merge.
    func persistFieldEdit(_ attempt: CheckRunnerFieldEditAttemptV1,
        validateIntent: @MainActor () throws -> Void) throws -> CheckRunnerFieldReadbackV1 {
        try Task.checkCancellation(); try validateIntent()
        guard attempt.owner === fieldReadOwner else { throw FieldDraftFailureV1.wrongWorkspace }
        let draftID = attempt.predecessor.draftID
        guard !parentOperations.contains(draftID) else { throw FieldDraftFailureV1.staleDraftRevision }
        let current = try currentSession()
        // One lease proof for this synchronous service call; the compare-and-swap
        // commit still re-fences under the exclusive commit lock.
        return try current.workspaceWriter.withProvenLease {
        let mutation = try fieldEditMutation(checkpoint: attempt.successor)
        if let original = try current.workspaceWriter.fieldDraftEvidence(mutationID: attempt.successor.mutationID) {
            guard original.mutation == mutation else { throw FieldDraftFailureV1.digestMismatch }
        } else {
            guard pendingFieldEdits[draftID] === attempt,
                  try read(draftID: draftID) == attempt.predecessor else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            try coordinator.validateFieldEditing(parentCheckpoint: attempt.predecessor, progress: progress,
                                                  publishedRelease: publishedRelease)
            try Task.checkCancellation(); try validateIntent()
            guard try read(draftID: draftID) == attempt.predecessor else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            _ = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
                .compareAndSwap(checkpoint: attempt.successor,
                    expectedDraftRevision: attempt.predecessor.draftRevision,
                    expectedBaseRevision: attempt.predecessor.baseCanonicalRevision)
#if DEBUG
            try beforeFieldEditAcknowledgementForTesting?()
#endif
        }
        let saved = try readEditableFields(draftID: draftID)
        guard saved.checkpoint == attempt.successor, saved.values == attempt.values,
              saved.evidence.mutation == mutation else { throw FieldDraftFailureV1.staleDraftRevision }
        try coordinator.validateFieldEditing(parentCheckpoint: saved.checkpoint, progress: progress,
                                              publishedRelease: publishedRelease)
        try Task.checkCancellation(); try validateIntent()
        // `saved` was read in this same synchronous scope after the last write,
        // so validateForPublication's revision check and re-read would observe
        // identical state; only its owner check is not implied.
        guard saved.owner === fieldReadOwner else { throw FieldDraftFailureV1.wrongWorkspace }
        if pendingFieldEdits[draftID] === attempt { pendingFieldEdits[draftID] = nil }
        return saved
        }
    }

    func validateForPublication(_ read: CheckRunnerFieldReadbackV1) throws {
        guard read.owner === fieldReadOwner else { throw FieldDraftFailureV1.wrongWorkspace }
        let current = try currentSession()
        try current.workspaceWriter.withProvenLease {
        guard try current.workspaceWriter.currentRevision() == read.observedRevision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let refreshed = try readEditableFields(draftID: read.checkpoint.draftID)
        guard refreshed.checkpoint == read.checkpoint, refreshed.values == read.values,
              refreshed.evidence == read.evidence,
              refreshed.observedRevision == read.observedRevision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        }
    }

    private func fieldEditMutation(checkpoint: FieldDraftCheckpointV1) throws -> FieldDraftMutationV1 {
        guard checkpoint.draftRevision > 0 else { throw FieldDraftFailureV1.invalidValue }
        return try .init(workspaceID: checkpoint.workspaceID, expectedRevision: checkpoint.draftRevision - 1,
            expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision, mutationID: checkpoint.mutationID,
            postImage: checkpoint.draftRevision == 1 ? .createCheckpoint(checkpoint) : .reviseCheckpoint(checkpoint))
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

    /// Selection first freezes its values without writing a parent or child.
    /// The caller retains this proposal across prepareRawPhoto acknowledgement
    /// failure; a proposal alone must never be presented as durable selection.
    func makeRawPhotoProposal(parentDraftID: UUID, expectedCheckpointSHA256: String,
        captureStep: WorkflowDraftStep, expectedSourceByteCount: Int64, origin: OriginalContentOriginV1,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws
        -> CheckRunnerPhotoDraftPayloadV1 {
        try withItemOperation(liveOperation) { current in
            guard let frontier = try current.workspaceWriter.checkRunnerPhotoPreparationEvidence(
                workspaceID: workspaceID, parentDraftID: parentDraftID, captureStep: captureStep),
                  frontier.parentCheckpoint.checkpointSHA256 == expectedCheckpointSHA256 else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            let parent = try CheckRunnerItemDraftCodecV1.validateCheckpoint(frontier.parentCheckpoint)
            guard try read(draftID: parentDraftID) == frontier.parentCheckpoint else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            let selected = captureStep == .wide ? parent.field.wideContext : parent.field.closeDetail
            guard selected == nil, let begin = parent.field.begin.attempt else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            let preparation = try coordinator.prepareCapture(assetID: parent.source.assetID)
            guard preparation.draftID == begin.recordCommand.recordID,
                  preparation.step == captureStep, let purpose = preparation.purpose else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            let instant = try canonicalPhotoCheckpointInstant()
            guard instant >= frontier.parentCheckpoint.updatedAt else { throw FieldDraftFailureV1.invalidValue }
            let evidenceID = ids.makeID()
            let intent = try CheckRunnerPhotoRawStageIntentV1(stageID: ids.makeID(),
                stageMutationID: .init(rawValue: ids.makeID()), stageCreatedAt: instant,
                expectedSourceByteCount: expectedSourceByteCount,
                provenanceID: evidenceID.uuidString.lowercased(), evidenceID: evidenceID, evidenceCreatedAt: instant)
            let proposal = try CheckRunnerPhotoDraftPayloadV1(workspaceID: workspaceID,
                childDraftID: ids.makeID(), parentDraftID: parentDraftID, recordID: preparation.draftID,
                assetID: parent.source.assetID, sourceBinding: parent.source,
                workflowStage: parent.source.requestedEntry.stage, captureStep: captureStep,
                purposeKey: purpose.key, origin: origin, phase: .awaitingRawStage(intent))
            try coordinator.validatePhotoPreparation(parentCheckpoint: frontier.parentCheckpoint, photo: proposal,
                workflowEvidence: frontier.workflow, timeZoneEvidence: frontier.timeZone,
                progress: progress, publishedRelease: publishedRelease)
            return proposal
        }
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
        guard checkpoint.checkpointSHA256 == expectedCheckpointSHA256,
              try read(draftID: parentDraftID) == checkpoint else {
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
    func publishRawPhoto(parentDraftID: UUID, childDraftID: UUID, sourceURL: URL,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) async throws
        -> FieldDraftCommittedEvidenceV1 {
        try withItemOperation(liveOperation) { _ in }
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
            applicationSupportURL: current.checkRunnerPhotoApplicationSupportURL, liveOperation: liveOperation)
        let result = try await attachmentStaging.stageRawPhoto(sourceURL: sourceURL, authority: authority)
        return try withItemOperation(liveOperation) { _ in result }
    }

    /// Export can acknowledge only an already published raw stage. Absence
    /// leaves the original pending child untouched; no source URL is supplied.
    func adoptExistingRawPhotoForBackup(parentDraftID: UUID, childDraftID: UUID,
        authorizing operation: AppAccessPresentationV1.BackupOperationAccess) async throws -> FieldDraftCommittedEvidenceV1? {
        guard let attachmentStaging, photoOperations.insert(childDraftID).inserted else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        defer { photoOperations.remove(childDraftID) }
        let authority = try operation.withAuthorization { store in
            guard try currentSession() === store else { throw ScanToWorkFailureV1.authorityMismatch }
            let writer = store.workspaceWriter
            let revision = try writer.currentRevision()
            let evidence = try currentRawPhotoEvidence(parentDraftID: parentDraftID, childDraftID: childDraftID)
            guard try writer.currentRevision() == revision else { throw FieldDraftFailureV1.staleDraftRevision }
            return CheckRunnerPhotoRawPublicationAuthorityV1(service: self, writer: writer,
                owner: currentPhotoReadOwner, evidence: evidence, revision: revision,
                applicationSupportURL: store.checkRunnerPhotoApplicationSupportURL, backupOperation: operation)
        }
        let result = try await attachmentStaging.adoptExistingRawPhoto(authority: authority)
        return try operation.withAuthorization { store in
            guard try currentSession() === store else { throw ScanToWorkFailureV1.authorityMismatch }
            let observed = try currentRawPhotoEvidence(parentDraftID: parentDraftID, childDraftID: childDraftID)
            if let result {
                guard observed.publication == result else { throw FieldDraftFailureV1.missingReceipt }
            } else {
                guard observed == authority.evidence, try store.workspaceWriter.currentRevision() == authority.revision else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
            }
            return result
        }
    }

    private func currentRawPhotoEvidence(parentDraftID: UUID, childDraftID: UUID) throws
        -> CheckRunnerPhotoRawStageEvidenceV1 {
        let current = try currentSession()
        guard let evidence = try current.workspaceWriter.checkRunnerPhotoRawStageEvidence(
            workspaceID: workspaceID, parentDraftID: parentDraftID, childDraftID: childDraftID) else {
            throw FieldDraftFailureV1.missingReceipt
        }
        guard try read(draftID: parentDraftID) == evidence.parentCheckpoint else {
            throw FieldDraftFailureV1.staleDraftRevision
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
        guard try read(draftID: parentDraftID) == evidence.parentCheckpoint else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        try coordinator.validatePhotoContinuation(evidence, progress: progress, publishedRelease: publishedRelease)
        return evidence
    }

    private func photoOperationRead(_ evidence: CheckRunnerPhotoContinuationEvidenceV1,
        backupOperation: AppAccessPresentationV1.BackupOperationAccess? = nil,
        liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws -> CurrentPhotoOperationReadV1 {
        try withItemOperation(liveOperation) { _ in }
        let current = try currentSession()
        let revision = try current.workspaceWriter.currentRevision()
        let media = try coordinator.checkRunnerPhotoMediaOwner(progress: progress)
        guard try currentPhotoContinuation(parentDraftID: evidence.parentCheckpoint.draftID,
            childDraftID: evidence.checkpoint.draftID) == evidence,
              try current.workspaceWriter.currentRevision() == revision else { throw FieldDraftFailureV1.staleDraftRevision }
        return .init(service: self, writer: current.workspaceWriter, owner: currentPhotoReadOwner,
            evidence: evidence, revision: revision, media: media,
            applicationSupportURL: current.checkRunnerPhotoApplicationSupportURL,
            backupOperation: backupOperation, liveOperation: liveOperation)
    }

    fileprivate func validatePhotoOperation(_ value: CurrentPhotoOperationReadV1) throws {
        return try withItemOperation(value.liveOperation) { _ in
            try Task.checkCancellation()
            if let operation = value.backupOperation {
                guard let session else { throw ScanToWorkFailureV1.authorityMismatch }
                try operation.validate(for: session)
            }
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
    }

    private func rawReadAuthority(_ value: CurrentPhotoOperationReadV1, normalizationAllowed: Bool)
        -> CheckRunnerPhotoRawReadAuthorityV1 {
        .init(service: self, writer: value.writer, owner: currentPhotoReadOwner,
            evidence: value.evidence, revision: value.revision, applicationSupportURL: value.applicationSupportURL,
            normalizationAllowed: normalizationAllowed, backupOperation: value.backupOperation,
            liveOperation: value.liveOperation)
    }

    /// Exact marked pairs are adopted without the picker or normalizer. A
    /// retained pairReady claim cannot authorize replacement of missing bytes.
    func preparePhotoPair(parentDraftID: UUID, childDraftID: UUID,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) async throws -> FieldDraftCheckpointV1 {
        guard let result = try await preparePhotoPair(parentDraftID: parentDraftID,
            childDraftID: childDraftID, backupOperation: nil, liveOperation: liveOperation) else { throw FieldDraftFailureV1.missingContent }
        return result
    }

    func adoptExistingPhotoPairForBackup(parentDraftID: UUID, childDraftID: UUID,
        authorizing operation: AppAccessPresentationV1.BackupOperationAccess) async throws -> FieldDraftCheckpointV1? {
        try await preparePhotoPair(parentDraftID: parentDraftID, childDraftID: childDraftID, backupOperation: operation)
    }

    private func preparePhotoPair(parentDraftID: UUID, childDraftID: UUID,
        backupOperation: AppAccessPresentationV1.BackupOperationAccess?,
        liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) async throws -> FieldDraftCheckpointV1? {
        try withItemOperation(liveOperation) { _ in }
        guard photoOperations.insert(childDraftID).inserted else { throw FieldDraftFailureV1.staleDraftRevision }
        defer { photoOperations.remove(childDraftID) }
        guard let attachmentStaging else { throw FieldDraftFailureV1.invalidValue }
        if let backupOperation {
            guard let session else { throw ScanToWorkFailureV1.authorityMismatch }
            try backupOperation.validate(for: session)
        }
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
        let read = try photoOperationRead(evidence, backupOperation: backupOperation, liveOperation: liveOperation)
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
            if backupOperation != nil { return nil }
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
        return try withItemOperation(authority.read.liveOperation) { _ in
            if let operation = authority.read.backupOperation {
                return try operation.withAuthorization { store in
                    guard try currentSession() === store else { throw ScanToWorkFailureV1.authorityMismatch }
                    return try publishPreparedPairUnderAccess(authority: authority, prepared: prepared)
                }
            }
            return try publishPreparedPairUnderAccess(authority: authority, prepared: prepared)
        }
    }

    private func publishPreparedPairUnderAccess(authority: CheckRunnerPhotoPairPublicationAuthorityV1,
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
    /// Explicit Use Photo freezes a proposal from authenticated durable input.
    /// A retry reuses that proposal before sampling the clock or allocating IDs.
    func preparePhotoCommit(parentDraftID: UUID, childDraftID: UUID, expectedCheckpointSHA256: String,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws
        -> FieldDraftCheckpointV1 {
        try withItemOperation(liveOperation) { _ in
            guard !photoOperations.contains(childDraftID) else { throw FieldDraftFailureV1.staleDraftRevision }
            let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
            if case let .preparedCommit(_, original) = evidence.payload.phase {
                return try preparePhotoCommit(parentDraftID: parentDraftID, childDraftID: childDraftID,
                    expectedCheckpointSHA256: expectedCheckpointSHA256, proposal: original)
            }
            guard evidence.checkpoint.checkpointSHA256 == expectedCheckpointSHA256,
                  case let .pairReady(pair) = evidence.payload.phase else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            let instant = try canonicalPhotoCheckpointInstant()
            guard instant >= evidence.checkpoint.updatedAt else { throw FieldDraftFailureV1.invalidValue }
            let outputs = try [WorkspaceEntityIdentityV1(kind: .workflowRecord, id: evidence.payload.recordID).stableKey,
                WorkspaceEntityIdentityV1(kind: .evidenceFile, id: pair.raw.intent.evidenceID).stableKey].sorted()
            let proposal = try CheckRunnerPhotoCommitAttemptV1(planID: ids.makeID(),
                expectedWorkflowRecordRevision: evidence.currentWorkflowPostImage.revision,
                targetMutationID: .init(rawValue: pair.raw.intent.evidenceID), outputKeys: outputs,
                reservationMutationID: .init(rawValue: ids.makeID()),
                reservationReviewAfter: instant.addingTimeInterval(3_600),
                preparedSagaID: ids.makeID(), preparedSagaMutationID: .init(rawValue: ids.makeID()),
                preparedUpdatedAt: instant, contentPromotedSagaID: ids.makeID(),
                contentPromotedSagaMutationID: .init(rawValue: ids.makeID()), contentPromotedUpdatedAt: instant,
                targetCommittedSagaID: ids.makeID(), targetCommittedSagaMutationID: .init(rawValue: ids.makeID()),
                targetCommittedUpdatedAt: instant, draftRetirePendingSagaID: ids.makeID(),
                draftRetirePendingSagaMutationID: .init(rawValue: ids.makeID()), draftRetirePendingUpdatedAt: instant,
                draftRetiredSagaID: ids.makeID(), draftRetiredUpdatedAt: instant, commitReceiptID: ids.makeID(),
                terminalBundleMutationID: .init(rawValue: ids.makeID()), terminalCheckpointUpdatedAt: instant,
                promotionAt: instant)
            return try preparePhotoCommit(parentDraftID: parentDraftID, childDraftID: childDraftID,
                expectedCheckpointSHA256: expectedCheckpointSHA256, proposal: proposal)
        }
    }

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

    /// Saves the explicit removal request. Media disposal and parent clearing
    /// are separate effects; this acknowledgement claims neither of them.
    func preparePhotoDiscard(parentDraftID: UUID, childDraftID: UUID, expectedCheckpointSHA256: String,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws
        -> CheckRunnerPhotoDiscardV1 {
        try withItemOperation(liveOperation) { current in
            guard !photoOperations.contains(childDraftID), !parentOperations.contains(parentDraftID) else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            let adapter = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
            guard let checkpoint = try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: childDraftID) else {
                throw FieldDraftFailureV1.missingReceipt
            }
            if checkpoint.state == .discardPending {
                let saved = try currentPendingPhotoDiscard(parentDraftID: parentDraftID, childDraftID: childDraftID)
                guard expectedCheckpointSHA256 == saved.activeCheckpoint.checkpointSHA256
                    || expectedCheckpointSHA256 == saved.request.pending.checkpointSHA256 else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
                return saved.request
            }
            guard checkpoint.state == .active, checkpoint.checkpointSHA256 == expectedCheckpointSHA256 else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            let photo = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
            switch photo.phase {
            case .awaitingRawStage, .rawReady:
                guard try currentRawPhotoEvidence(parentDraftID: parentDraftID,
                    childDraftID: childDraftID).currentCheckpoint == checkpoint else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
            case .pairReady:
                guard try currentPhotoContinuation(parentDraftID: parentDraftID,
                    childDraftID: childDraftID).checkpoint == checkpoint else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
            case .preparedCommit: throw FieldDraftFailureV1.invalidTransition
            }
            let request = try CheckRunnerPhotoDiscardV1.prepare(from: checkpoint,
                mutationID: .init(rawValue: ids.makeID()), at: canonicalPhotoCheckpointInstant())
            _ = try adapter.compareAndSwap(checkpoint: request.pending,
                expectedDraftRevision: checkpoint.draftRevision, expectedBaseRevision: checkpoint.baseCanonicalRevision)
            let observed = try currentPendingPhotoDiscard(parentDraftID: parentDraftID, childDraftID: childDraftID)
            guard observed.request == request else { throw FieldDraftFailureV1.missingReceipt }
            return request
        }
    }

    /// Rebuilds the authentic active prefix and original pending edge in one
    /// current writer interval. No historical prefix is substituted for the
    /// physical tip: the latter must equal the saved DISCARD_PENDING receipt.
    private func currentPendingPhotoDiscard(parentDraftID: UUID, childDraftID: UUID) throws
        -> CheckRunnerPhotoPendingDiscardEvidenceV1 {
        let current = try currentSession(), writer = current.workspaceWriter
        try writer.validateFieldDraftReadContext(current.modelContext)
        let revision = try writer.currentRevision()
        let adapter = try writer.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
        guard let checkpoint = try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: childDraftID),
              checkpoint.state == .discardPending else { throw FieldDraftFailureV1.staleDraftRevision }
        let photo = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
        guard photo.parentDraftID == parentDraftID,
              let frontier = try writer.checkRunnerPhotoPreparationEvidence(workspaceID: workspaceID,
                parentDraftID: parentDraftID, captureStep: photo.captureStep) else {
            throw FieldDraftFailureV1.missingReceipt
        }
        guard try read(draftID: parentDraftID) == frontier.parentCheckpoint else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let snapshot = try writer.sourceMutationHistorySnapshot()
        var parentHistory: [FieldDraftCommittedEvidenceV1] = []
        var childHistory: [(FieldDraftCommittedEvidenceV1, FieldDraftCheckpointV1)] = []
        for record in snapshot.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyFieldDraft(mutation) = envelope.command else { continue }
            let value: FieldDraftCheckpointV1
            switch mutation.postImage {
            case let .createCheckpoint(saved), let .reviseCheckpoint(saved): value = saved
            case let .publishReadyStage(saved): value = saved.successorCheckpoint
            case let .applyCommitTerminal(saved, _): value = saved.committedCheckpoint
            case let .applyDiscardTerminal(saved): value = saved.discardedCheckpoint
            default: continue
            }
            guard value.draftID == parentDraftID || value.draftID == childDraftID else { continue }
            guard mutation.workspaceID == workspaceID, record.reversalBasisData == nil,
                  record.semanticReversalData == nil else { throw FieldDraftFailureV1.digestMismatch }
            let evidence = try FieldDraftCommittedEvidenceV1(envelope: envelope,
                receipt: MutationReceiptV1.decodeCanonical(from: record.receiptData))
            if value.draftID == parentDraftID { parentHistory.append(evidence) }
            else { childHistory.append((evidence, value)) }
        }
        childHistory.sort { $0.1.draftRevision < $1.1.draftRevision }
        guard (2...4).contains(childHistory.count), let pending = childHistory.last,
              pending.1 == checkpoint else { throw FieldDraftFailureV1.missingReceipt }
        let active = childHistory[childHistory.count - 2]
        let prefix = Array(childHistory.dropLast()).map { $0.0 }
        let selectedIDs = Set((parentHistory + childHistory.map { $0.0 }).map { $0.mutation.mutationID.rawValue })
        guard !snapshot.quarantines.contains(where: { selectedIDs.contains($0.mutationID) }) else {
            throw WorkspaceMutationFailureV1.mutationIDQuarantined
        }
        let workspaceUUID = workspaceID.rawValue
        let stages = try current.modelContext.fetch(FetchDescriptor<AttachmentStagingItemRow>(predicate: #Predicate {
            $0.workspaceID == workspaceUUID && $0.draftID == childDraftID
        })).map { try $0.value() }
        let sagas = try current.modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>(predicate: #Predicate {
            $0.workspaceID == workspaceUUID && $0.draftID == childDraftID
        }))
        let reservations = try current.modelContext.fetch(FetchDescriptor<DraftContentReservationRow>(predicate: #Predicate {
            $0.workspaceID == workspaceUUID && $0.draftID == childDraftID
        }))
        let commits = try current.modelContext.fetch(FetchDescriptor<DraftCommitReceiptRow>(predicate: #Predicate {
            $0.workspaceID == workspaceUUID && $0.draftID == childDraftID
        }))
        guard stages.count <= 1, sagas.isEmpty, reservations.isEmpty, commits.isEmpty else {
            throw FieldDraftFailureV1.invalidTransition
        }
        switch try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(active.1).phase {
        case .awaitingRawStage, .rawReady:
            _ = try CheckRunnerPhotoRawStageEvidenceV1(parentHistory: parentHistory,
                parentCheckpoint: frontier.parentCheckpoint, workflow: frontier.workflow, timeZone: frontier.timeZone,
                childHistory: prefix, childCheckpoint: active.1, currentStage: stages.first,
                currentWorkflowPostImage: frontier.currentWorkflowPostImage, precedingWide: frontier.precedingWide)
        case .pairReady:
            _ = try CheckRunnerPhotoContinuationEvidenceV1(parentHistory: parentHistory,
                parentCheckpoint: frontier.parentCheckpoint, workflow: frontier.workflow, timeZone: frontier.timeZone,
                history: prefix, checkpoint: active.1, stages: stages, sagas: [], reservations: [], receipts: [],
                precedingWide: frontier.precedingWide?.parent, target: nil,
                currentWorkflowPostImage: frontier.currentWorkflowPostImage, currentEvidencePostImage: nil)
        case .preparedCommit: throw FieldDraftFailureV1.invalidTransition
        }
        let result = try CheckRunnerPhotoPendingDiscardEvidenceV1(activeCheckpoint: active.1,
            activeOriginal: active.0, pendingOriginal: pending.0)
        try coordinator.validatePhotoPreparation(parentCheckpoint: frontier.parentCheckpoint, photo: photo,
            workflowEvidence: frontier.workflow, timeZoneEvidence: frontier.timeZone,
            progress: progress, publishedRelease: publishedRelease)
        guard try currentSession().workspaceWriter.currentRevision() == revision else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        return result
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
    func resumePhotoCommit(parentDraftID: UUID, childDraftID: UUID,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) async throws -> FieldDraftCheckpointV1 {
        try withItemOperation(liveOperation) { _ in }
        guard photoOperations.insert(childDraftID).inserted else { throw FieldDraftFailureV1.staleDraftRevision }
        defer { photoOperations.remove(childDraftID) }
#if DEBUG
        photoCommitObservationForTesting?("resume-session-start")
#endif
        let current = try currentSession()
        var rows = FetchDescriptor<FieldDraftCheckpointRow>(predicate: #Predicate { $0.draftID == childDraftID })
        rows.fetchLimit = 2
        let found = try current.modelContext.fetch(rows)
        guard found.count == 1, let row = found.first else { throw FieldDraftFailureV1.missingReceipt }
        let observed = try row.value()
        if observed.state == .committed {
            return try withItemOperation(liveOperation) { _ in
                try completePhotoParentSlot(parentDraftID: parentDraftID, childDraftID: childDraftID)
            }
        }
#if DEBUG
        photoCommitObservationForTesting?("resume-continuation-start")
#endif
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID, childDraftID: childDraftID)
#if DEBUG
        photoCommitObservationForTesting?("resume-continuation-complete")
#endif
        guard evidence.checkpoint.state == .committing, let committing = evidence.committing,
              case let .reviseCheckpoint(checkpoint) = committing.mutation.postImage,
              checkpoint == evidence.checkpoint else { throw FieldDraftFailureV1.invalidTransition }
        let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: checkpoint)
        let commit = reconstruction.draftCommit
        let port = CheckRunnerPhotoCommitPortV1(service: self, parentDraftID: parentDraftID,
            reconstruction: reconstruction, liveOperation: liveOperation)
        let lifecycle = CheckRunnerAuthorizedDraftWriterV1(service: self, liveOperation: liveOperation)
        let drafts = FieldDraftCoordinatorV1(purposeAuthority: try CheckRunnerDraftPurposeAuthorityV1(),
            writer: lifecycle, content: port, asyncTarget: port)
#if DEBUG
        photoCommitObservationForTesting?("prepared-saga-commit-start")
#endif
        _ = try await drafts.commit(plan: commit.plan, checkpoint: checkpoint, items: commit.items,
            prepared: commit.prepared, contentPromoted: commit.contentPromoted, targetCommitted: commit.targetCommitted,
            retirePending: commit.retirePending, retired: commit.retired, commitReceiptID: commit.commitReceiptID,
            terminalCheckpointUpdatedAt: commit.terminalCheckpointUpdatedAt, rowMutationIDs: commit.rowMutationIDs)
        return try withItemOperation(liveOperation) { _ in
            try completePhotoParentSlot(parentDraftID: parentDraftID, childDraftID: childDraftID)
        }
    }

    fileprivate func promotePhotoRaw(parentDraftID: UUID, reconstruction: CheckRunnerPhotoCommitReconstructionV1,
        liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?)
        async throws -> DraftContentReservationV1 {
        try withItemOperation(liveOperation) { _ in }
#if DEBUG
        photoCommitObservationForTesting?("raw-promotion-entered")
#endif
        guard let attachmentStaging else { throw FieldDraftFailureV1.invalidValue }
        let current = try currentSession()
        let revision = try current.workspaceWriter.currentRevision()
#if DEBUG
        photoCommitObservationForTesting?("raw-continuation-start")
#endif
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID,
            childDraftID: reconstruction.draftCommit.checkpoint.draftID)
#if DEBUG
        photoCommitObservationForTesting?("raw-continuation-complete")
#endif
        guard evidence.checkpoint == reconstruction.draftCommit.checkpoint,
              evidence.sagas.first == reconstruction.draftCommit.prepared,
              try current.workspaceWriter.currentRevision() == revision else { throw FieldDraftFailureV1.staleDraftRevision }
        let authority = try CheckRunnerPhotoRawPromotionAuthorityV1(service: self, writer: current.workspaceWriter,
            owner: currentPhotoReadOwner, evidence: evidence, revision: revision,
            applicationSupportURL: current.checkRunnerPhotoApplicationSupportURL, liveOperation: liveOperation)
#if DEBUG
        photoCommitObservationForTesting?("raw-preparation-start")
#endif
        return try await attachmentStaging.promoteRawPhoto(authority: authority)
    }

    fileprivate func commitPhotoTarget(parentDraftID: UUID, reconstruction: CheckRunnerPhotoCommitReconstructionV1,
        reservations: [DraftContentReservationV1], liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?) async throws -> MutationReceiptV1 {
        try withItemOperation(liveOperation) { _ in }
        let evidence = try currentPhotoContinuation(parentDraftID: parentDraftID,
            childDraftID: reconstruction.draftCommit.checkpoint.draftID)
        guard evidence.checkpoint == reconstruction.draftCommit.checkpoint,
              case let .preparedCommit(pair, attempt) = evidence.payload.phase,
              reservations == [try CheckRunnerPhotoContinuationEvidenceV1.reservation(
                raw: pair.raw, plan: reconstruction.draftCommit.plan, attempt: attempt)],
              evidence.currentStage == (try CheckRunnerPhotoContinuationEvidenceV1.committedStage(raw: pair.raw, attempt: attempt)) else {
            throw FieldDraftFailureV1.digestMismatch
        }
        let read = try photoOperationRead(evidence, liveOperation: liveOperation)
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
        return try withItemOperation(authority.read.liveOperation) { _ in
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
        return try withItemOperation(authority.liveOperation) { _ in
            if let operation = authority.backupOperation {
                guard let session else { throw ScanToWorkFailureV1.authorityMismatch }
                try operation.validate(for: session)
            }
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
    }

    fileprivate func validateRawPhotoPromotion(_ authority: CheckRunnerPhotoRawPromotionAuthorityV1,
                                               prepared: DraftPreparedRawPhotoPromotionV1) throws {
        return try withItemOperation(authority.liveOperation) { _ in
    #if DEBUG
            photoCommitObservationForTesting?("raw-prewrite-validation-start")
    #endif
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
    #if DEBUG
            photoCommitObservationForTesting?("raw-prewrite-validation-complete")
    #endif
        }
    }

    fileprivate func publishPreparedRawPhotoPromotion(authority: CheckRunnerPhotoRawPromotionAuthorityV1,
        prepared: DraftPreparedRawPhotoPromotionV1) throws -> DraftContentReservationV1 {
        return try withItemOperation(authority.liveOperation) { _ in
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
    }

    fileprivate func publishPreparedRawPhoto(authority: CheckRunnerPhotoRawPublicationAuthorityV1,
        prepared: DraftPreparedRawPhotoPublicationV1) throws -> FieldDraftCommittedEvidenceV1 {
        return try withItemOperation(authority.liveOperation) { _ in
            if let operation = authority.backupOperation {
                return try operation.withAuthorization { store in
                    guard try currentSession() === store else { throw ScanToWorkFailureV1.authorityMismatch }
                    return try publishPreparedRawPhotoUnderAccess(authority: authority, prepared: prepared)
                }
            }
            return try publishPreparedRawPhotoUnderAccess(authority: authority, prepared: prepared)
        }
    }

    private func publishPreparedRawPhotoUnderAccess(authority: CheckRunnerPhotoRawPublicationAuthorityV1,
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

    /// App composition must retain this service's exact progress/session owner.
    func validateFinalizationOwner(_ expected: ProductionRepetitiveCaptureProgressServiceV2) throws {
        guard progress === expected else { throw ScanToWorkFailureV1.authorityMismatch }
        _ = try currentSession()
    }

    func terminalFinalizationSource(draftID: UUID, progress expected: ProductionRepetitiveCaptureProgressServiceV2,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil) throws
        -> (source: CheckRunnerRoundItemSourceV1, recordID: UUID) {
        try withItemOperation(liveOperation) { _ in
            try validateFinalizationOwner(expected)
            let checkpoint = try read(draftID: draftID)
            guard checkpoint.state == .committed,
                  let committed = try coordinator.readParentFinalization(parentCheckpoint: checkpoint,
                    progress: progress, publishedRelease: publishedRelease,
                    authorizing: liveOperation) else { throw FieldDraftFailureV1.missingReceipt }
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
            guard case let .bound(begin, _, _) = payload.field.begin,
                  committed.receipt.mutationID.rawValue == payload.finalizationAttempt?.identifiers.mutationID else {
                throw FieldDraftFailureV1.digestMismatch
            }
            return (payload.source, begin.recordCommand.recordID)
        }
    }

    /// Freeze only after the original source, raw editor, committed children
    /// and their physical media have passed the current owners' checks.
    func prepareFinalization(draftID: UUID, expectedCheckpointSHA256: String,
        sourceApp: SourceAppSnapshotV1,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil,
        validateIntent: @MainActor () throws -> Void) async throws -> FieldDraftCheckpointV1 {
        try withItemOperation(liveOperation) { _ in }
        try Task.checkCancellation(); try validateIntent()
        guard parentOperations.insert(draftID).inserted else { throw FieldDraftFailureV1.staleDraftRevision }
        defer { parentOperations.remove(draftID) }
        let checkpoint = try read(draftID: draftID)
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        if payload.phase == .preparedFinalization {
            let current = try currentSession()
            guard let proof = try current.workspaceWriter.checkRunnerItemFinalizationEvidence(
                workspaceID: workspaceID, draftID: draftID), proof.checkpoint == checkpoint,
                  proof.attempt.sourceApp == sourceApp,
                  expectedCheckpointSHA256 == checkpoint.checkpointSHA256
                    || expectedCheckpointSHA256 == proof.editingCheckpoint.checkpointSHA256 else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            try await validateParentFinalizationMedia(proof.reconstruction)
            try Task.checkCancellation(); try validateIntent()
            return try withItemOperation(liveOperation) { _ in
                guard try read(draftID: draftID) == checkpoint else { throw FieldDraftFailureV1.staleDraftRevision }
                return checkpoint
            }
        }
        guard checkpoint.state == .active, checkpoint.checkpointSHA256 == expectedCheckpointSHA256 else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let prepared = try coordinator.prepareParentFinalization(parentCheckpoint: checkpoint,
            progress: progress, publishedRelease: publishedRelease)
        try await validateParentMedia(checkpoint)
        try Task.checkCancellation(); try validateIntent()
        return try withItemOperation(liveOperation) { _ in
            let refreshed = try coordinator.prepareParentFinalization(parentCheckpoint: checkpoint,
                progress: progress, publishedRelease: publishedRelease)
            guard refreshed.outcome == prepared.outcome, refreshed.workflowRevision == prepared.workflowRevision else {
                throw FieldDraftFailureV1.staleDraftRevision
            }
            let instant = try canonicalPhotoCheckpointInstant()
            guard instant >= checkpoint.updatedAt else { throw FieldDraftFailureV1.invalidValue }
            let issueID: UUID?, newIssueID: UUID?
            switch (payload.source.requestedEntry, prepared.outcome.selection) {
            case (.check, .noVisibleIssue), (.check, .couldNotVerify): issueID = nil; newIssueID = nil
            case (.check, .visibleIssue): issueID = ids.makeID(); newIssueID = nil
            case let (.recheck(original), .resolved), let (.recheck(original), .issueStillVisible),
                 let (.recheck(original), .couldNotVerify): issueID = original; newIssueID = nil
            case let (.recheck(original), .originalResolvedDifferentIssue):
                issueID = original; newIssueID = ids.makeID()
            default: throw FieldDraftFailureV1.invalidValue
            }
            let attempt = try CheckRunnerFinalizationAttemptInputsV1(normalizedOutcome: prepared.outcome,
                identifiers: .init(.init(mutationID: ids.makeID(), packetID: ids.makeID(),
                    stableRootID: ids.makeID(), reportID: ids.makeID(), issueID: issueID, newIssueID: newIssueID)),
                completedAt: instant, snapshotCreatedAt: instant, sourceApp: sourceApp,
                expectedWorkflowRecordRevision: prepared.workflowRevision,
                fieldDraftPlanID: ids.makeID(), preparedSagaID: ids.makeID(), contentPromotedSagaID: ids.makeID(),
                targetCommittedSagaID: ids.makeID(), draftRetirePendingSagaID: ids.makeID(), draftRetiredSagaID: ids.makeID(),
                preparedSagaMutationID: .init(rawValue: ids.makeID()),
                contentPromotedSagaMutationID: .init(rawValue: ids.makeID()),
                targetCommittedSagaMutationID: .init(rawValue: ids.makeID()),
                draftRetirePendingSagaMutationID: .init(rawValue: ids.makeID()),
                terminalBundleMutationID: .init(rawValue: ids.makeID()), commitReceiptID: ids.makeID(),
                preparedSagaUpdatedAt: instant, contentPromotedSagaUpdatedAt: instant,
                targetCommittedSagaUpdatedAt: instant, draftRetirePendingSagaUpdatedAt: instant,
                draftRetiredSagaUpdatedAt: instant, terminalCheckpointUpdatedAt: instant)
            let next = try CheckRunnerItemDraftPayloadV1(prepared: payload.source, field: payload.field, attempt: attempt)
            let successor = try makeCheckpoint(payload: next, predecessor: checkpoint,
                frozenUpdatedAt: instant, state: .committing)
            try successor.validateSuccessor(of: checkpoint, expectedDraftRevision: checkpoint.draftRevision,
                expectedBaseRevision: checkpoint.baseCanonicalRevision)
            let reconstruction = try CheckRunnerItemDraftCodecV1.reconstructFinalizationHistory(from: successor)
            let mutationIDs = [successor.mutationID, reconstruction.plan.mutationID]
                + reconstruction.sagas.map(\.mutationID)
            guard Set(mutationIDs).count == mutationIDs.count else { throw FieldDraftFailureV1.invalidValue }
            let current = try currentSession()
            guard try read(draftID: draftID) == checkpoint else { throw FieldDraftFailureV1.staleDraftRevision }
            for mutationID in mutationIDs {
                guard try current.workspaceWriter.durableReceipt(mutationID: mutationID) == nil else {
                    throw FieldDraftFailureV1.staleDraftRevision
                }
            }
            _ = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
                .compareAndSwap(checkpoint: successor, expectedDraftRevision: checkpoint.draftRevision,
                                expectedBaseRevision: checkpoint.baseCanonicalRevision)
            guard try currentParentFinalization(reconstruction) == successor else { throw FieldDraftFailureV1.missingReceipt }
            return successor
        }
    }

    /// The genuine terminal draft precedes Round completion. Its caller must
    /// still persist/resume the exact COMPLETE progress successor before leaving.
    func resumeFinalization(draftID: UUID,
        authorizing liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess? = nil,
        validateIntent: @escaping @MainActor () throws -> Void) async throws
        -> FieldDraftCheckpointV1 {
        try withItemOperation(liveOperation) { _ in }
        try Task.checkCancellation(); try validateIntent()
        guard parentOperations.insert(draftID).inserted else { throw FieldDraftFailureV1.staleDraftRevision }
        defer { parentOperations.remove(draftID) }
        let checkpoint = try read(draftID: draftID)
        let reconstruction = try coordinator.reconstructParentFinalization(parentCheckpoint: checkpoint,
            progress: progress, publishedRelease: publishedRelease)
        try await validateParentFinalizationMedia(reconstruction)
        try Task.checkCancellation(); try validateIntent()
        try withItemOperation(liveOperation) { _ in }
        if checkpoint.state == .committed {
            return try withItemOperation(liveOperation) { _ in
                guard try coordinator.readParentFinalization(parentCheckpoint: checkpoint,
                    progress: progress, publishedRelease: publishedRelease, authorizing: liveOperation) != nil else {
                    throw FieldDraftFailureV1.missingReceipt
                }
                return checkpoint
            }
        }
        let port = CheckRunnerParentCommitPortV1(service: self, reconstruction: reconstruction,
            liveOperation: liveOperation, validateIntent: validateIntent)
        let lifecycle = CheckRunnerAuthorizedDraftWriterV1(service: self, liveOperation: liveOperation)
        let drafts = FieldDraftCoordinatorV1(purposeAuthority: try CheckRunnerDraftPurposeAuthorityV1(),
            writer: lifecycle, content: port, asyncTarget: port)
        _ = try await drafts.commit(plan: reconstruction.plan, checkpoint: reconstruction.checkpoint,
            items: reconstruction.items, prepared: reconstruction.prepared,
            contentPromoted: reconstruction.contentPromoted, targetCommitted: reconstruction.targetCommitted,
            retirePending: reconstruction.retirePending, retired: reconstruction.retired,
            commitReceiptID: reconstruction.commitReceiptID,
            terminalCheckpointUpdatedAt: reconstruction.terminalCheckpointUpdatedAt,
            rowMutationIDs: reconstruction.rowMutationIDs)
        try Task.checkCancellation(); try validateIntent()
        return try withItemOperation(liveOperation) { _ in
            let terminal = try currentParentFinalization(reconstruction)
            guard terminal.state == .committed,
                  try coordinator.readParentFinalization(parentCheckpoint: terminal,
                    progress: progress, publishedRelease: publishedRelease, authorizing: liveOperation) != nil else {
                throw FieldDraftFailureV1.missingReceipt
            }
            return terminal
        }
    }

    private func currentParentFinalization(_ reconstruction: CheckRunnerDraftCommitReconstructionV1) throws
        -> FieldDraftCheckpointV1 {
        let checkpoint = try read(draftID: reconstruction.checkpoint.draftID)
        guard try coordinator.reconstructParentFinalization(parentCheckpoint: checkpoint,
            progress: progress, publishedRelease: publishedRelease) == reconstruction else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        return checkpoint
    }

    private func validateParentMedia(_ checkpoint: FieldDraftCheckpointV1) async throws {
        try Task.checkCancellation()
        guard try read(draftID: checkpoint.draftID) == checkpoint else { throw FieldDraftFailureV1.staleDraftRevision }
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        for slot in [payload.field.wideContext, payload.field.closeDetail].compactMap({ $0 }) {
            guard case .committed = slot,
                  let observed = try await readCurrentPhotoMedia(parentDraftID: checkpoint.draftID,
                    childDraftID: slot.childDraftID), observed.targetRead.parentCheckpoint == checkpoint else {
                throw FieldDraftFailureV1.missingContent
            }
            try Task.checkCancellation()
            guard try read(draftID: checkpoint.draftID) == checkpoint else { throw FieldDraftFailureV1.staleDraftRevision }
        }
        _ = try currentSession()
    }

    fileprivate func validateParentFinalizationMedia(_ reconstruction: CheckRunnerDraftCommitReconstructionV1) async throws {
        let checkpoint = try currentParentFinalization(reconstruction)
        try await validateParentMedia(checkpoint)
        guard try currentParentFinalization(reconstruction) == checkpoint else { throw FieldDraftFailureV1.staleDraftRevision }
    }

    fileprivate func commitParentFinalizationTarget(_ reconstruction: CheckRunnerDraftCommitReconstructionV1,
        liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?,
        validateIntent: @MainActor () throws -> Void) async throws
        -> MutationReceiptV1 {
        try withItemOperation(liveOperation) { _ in }
        try Task.checkCancellation(); try validateIntent()
        try await validateParentFinalizationMedia(reconstruction)
        try Task.checkCancellation(); try validateIntent()
        try withItemOperation(liveOperation) { _ in }
        let checkpoint = try currentParentFinalization(reconstruction)
        let receipt = try await coordinator.commitParentFinalization(parentCheckpoint: checkpoint,
            progress: progress, publishedRelease: publishedRelease, authorizing: liveOperation) { [weak self] in
                try validateIntent()
                guard let self else { throw FieldDraftFailureV1.staleDraftRevision }
                try self.withItemOperation(liveOperation) { _ in
                    guard try self.currentParentFinalization(reconstruction) == checkpoint else {
                        throw FieldDraftFailureV1.staleDraftRevision
                    }
                }
            }
        try await validateParentFinalizationMedia(reconstruction)
        try Task.checkCancellation(); try validateIntent()
        try withItemOperation(liveOperation) { _ in }
#if DEBUG
        try beforeParentTargetAcknowledgementForTesting?()
#endif
        return try withItemOperation(liveOperation) { _ in
            guard try parentFinalizationReadback(reconstruction, receipt: receipt, liveOperation: liveOperation) else {
                throw FieldDraftFailureV1.missingReceipt
            }
            return receipt
        }
    }

    fileprivate func parentFinalizationReadback(_ reconstruction: CheckRunnerDraftCommitReconstructionV1,
        receipt: MutationReceiptV1, liveOperation: AppAccessPresentationV1.CheckRunnerItemOperationAccess?) throws -> Bool {
        try withItemOperation(liveOperation) { _ in
            let checkpoint = try currentParentFinalization(reconstruction)
            return try coordinator.readParentFinalization(parentCheckpoint: checkpoint,
                progress: progress, publishedRelease: publishedRelease, authorizing: liveOperation)?.receipt == receipt
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
                confirmedTimeZoneID: field.preflight.submittedTimeZoneID,
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
        if let payload = try writer.authenticatedCurrentCheckRunnerParentInReadScope(
            checkpoint, modelContext: context) {
            return payload
        }
        try writer.validateFieldDraftReadContext(context)
        let current = try writer.currentRevision()
        guard checkpoint.workspaceID == current.workspaceID else { throw FieldDraftFailureV1.wrongWorkspace }
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        if payload.phase == .preparedFinalization {
            guard let proof = try writer.checkRunnerItemFinalizationEvidence(
                workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID),
                  proof.checkpoint == checkpoint else { throw FieldDraftFailureV1.staleDraftRevision }
            return payload
        }
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
                                frozenUpdatedAt: Date? = nil,
                                state: FieldDraftStateV1 = .active) throws -> FieldDraftCheckpointV1 {
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
            stageIDs: [], resumeAnchor: CheckRunnerItemDraftCodecV1.resumeAnchor(payload: payload), state: state,
            updatedAt: updatedAt, mutationID: .init(rawValue: ids.makeID()))
    }

    private func currentSession() throws -> StoreSessionCoordinator {
        guard let session, let originalWriter, originalWriter === session.workspaceWriter,
              session.workspaceID == workspaceID else { throw FieldDraftFailureV1.wrongWorkspace }
        try progress.validateCheckRunnerOwner(writer: session.workspaceWriter, modelContext: session.modelContext)
        return session
    }
}

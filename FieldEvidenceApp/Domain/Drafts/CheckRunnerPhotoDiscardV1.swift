import Foundation

/// Frozen values for one explicit precommit removal. These are not evidence
/// that the checkpoint was persisted, files were removed or a parent was cleared.
struct CheckRunnerPhotoDiscardV1: Equatable, Sendable {
    let pending: FieldDraftCheckpointV1
    let plan: DraftDiscardPlanV1
    let cleanupStageID: UUID
    let receiptID: UUID
    let terminalMutationID: MutationIDV1

    /// Retains the original payload and stage declarations. DISCARD_PENDING
    /// freezes the requested operation even when physical cleanup is interrupted.
    static func prepare(from active: FieldDraftCheckpointV1, mutationID: MutationIDV1,
                        at instant: Date) throws -> Self {
        let photo = try precommitPayload(active)
        guard active.state == .active, active.draftRevision < UInt64.max,
              instant >= active.updatedAt,
              !reservedIDs(photo, checkpoint: active).contains(mutationID.rawValue) else {
            throw FieldDraftFailureV1.invalidTransition
        }
        let pending = try FieldDraftCheckpointV1(draftID: active.draftID, workspaceID: active.workspaceID,
            scope: active.scope, purpose: active.purpose, codec: active.codec,
            baseCanonicalRevision: active.baseCanonicalRevision, draftRevision: active.draftRevision + 1,
            payloadData: active.payloadData, stageIDs: active.stageIDs, resumeAnchor: active.resumeAnchor,
            state: .discardPending, updatedAt: instant, mutationID: mutationID)
        try pending.validateSuccessor(of: active, expectedDraftRevision: active.draftRevision,
                                      expectedBaseRevision: active.baseCanonicalRevision)
        return try Self(pending: pending)
    }

    /// Cold callers reconstruct identical values from the authenticated pending
    /// checkpoint; no fresh clock sample or ID allocation is needed on retry.
    init(pending: FieldDraftCheckpointV1) throws {
        let photo = try Self.precommitPayload(pending)
        guard pending.state == .discardPending, pending.draftRevision > 1,
              pending.draftRevision < UInt64.max,
              pending.lastDurableMutationID == nil, pending.lastReceiptSHA256 == nil else {
            throw FieldDraftFailureV1.invalidTransition
        }
        let material = "check-runner-photo-discard-v1\u{1f}\(pending.checkpointSHA256)"
        let planID = DraftAttachmentStagingAdapterV1.deterministicUUID(material + "\u{1f}plan")
        let receiptID = DraftAttachmentStagingAdapterV1.deterministicUUID(material + "\u{1f}receipt")
        let terminalID = DraftAttachmentStagingAdapterV1.deterministicUUID(material + "\u{1f}terminal")
        let allocated = Set([planID, receiptID, terminalID])
        guard allocated.count == 3,
              allocated.isDisjoint(with: Self.reservedIDs(photo, checkpoint: pending)) else {
            throw FieldDraftFailureV1.invalidValue
        }
        self.pending = pending
        // An awaiting-raw child can have physically staged bytes whose canonical
        // publication was interrupted. Cleanup must census its original stage ID
        // even though that checkpoint does not yet declare READY_LOCAL media.
        self.cleanupStageID = photo.phase.intent.stageID
        // Canonical disposal receipts retain only published stage-row identities;
        // backup/replay joins each one to its original row. An awaiting-raw
        // physical orphan still belongs to cleanupStageID, not this row census.
        self.plan = try .init(planID: planID, workspaceID: pending.workspaceID, draftID: pending.draftID,
            expectedDraftRevision: pending.draftRevision, nonemptyPayload: true,
            stageIDs: pending.stageIDs, reservationIDs: [],
            estimatedBytes: photo.phase.intent.expectedSourceByteCount)
        self.receiptID = receiptID
        self.terminalMutationID = .init(rawValue: terminalID)
    }

    /// Value construction only. The application must first authenticate the
    /// original pending operation and actual owned-file disposal for cleanupStageID
    /// even when the canonical row census is empty. This exact row census rejects
    /// partial, duplicate and foreign canonical disposal claims.
    func terminalBundle(disposedStageIDs: [UUID]) throws -> DraftDiscardTerminalBundleV1 {
        guard disposedStageIDs.count == plan.stageIDs.count,
              Set(disposedStageIDs) == Set(plan.stageIDs) else { throw FieldDraftFailureV1.invalidValue }
        let receipt = try DraftDiscardReceiptV1(receiptID: receiptID, workspaceID: pending.workspaceID,
            draftID: pending.draftID, planSHA256: plan.planSHA256, disposedStageIDs: plan.stageIDs,
            quarantinedReservationIDs: [], discardedAt: pending.updatedAt, mutationID: terminalMutationID)
        let terminal = try FieldDraftCheckpointV1(draftID: pending.draftID, workspaceID: pending.workspaceID,
            scope: pending.scope, purpose: pending.purpose, codec: pending.codec,
            baseCanonicalRevision: pending.baseCanonicalRevision, draftRevision: pending.draftRevision + 1,
            payloadData: pending.payloadData, stageIDs: pending.stageIDs, resumeAnchor: pending.resumeAnchor,
            state: .discarded, lastDurableMutationID: terminalMutationID,
            lastReceiptSHA256: receipt.receiptSHA256, updatedAt: pending.updatedAt, mutationID: terminalMutationID)
        try terminal.validateSuccessor(of: pending, expectedDraftRevision: pending.draftRevision,
                                       expectedBaseRevision: pending.baseCanonicalRevision)
        _ = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(terminal)
        return try .init(discardedCheckpoint: terminal, receipt: receipt)
    }

    private static func precommitPayload(_ checkpoint: FieldDraftCheckpointV1) throws
        -> CheckRunnerPhotoDraftPayloadV1 {
        let photo = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
        switch photo.phase {
        case .awaitingRawStage, .rawReady, .pairReady: return photo
        case .preparedCommit: throw FieldDraftFailureV1.invalidTransition
        }
    }

    private static func reservedIDs(_ photo: CheckRunnerPhotoDraftPayloadV1,
                                    checkpoint: FieldDraftCheckpointV1) -> Set<UUID> {
        var ids: Set<UUID> = [photo.childDraftID, photo.parentDraftID, photo.recordID, photo.assetID,
            photo.phase.intent.stageID, photo.phase.intent.stageMutationID.rawValue,
            photo.phase.intent.evidenceID, checkpoint.mutationID.rawValue]
        if let raw = photo.phase.raw { ids.insert(raw.stagePublicationMutationID.rawValue) }
        return ids
    }
}

/// Authenticates the discard edge after an independently authenticated active
/// raw/pair prefix. It proves a saved request, never physical file disposal.
struct CheckRunnerPhotoPendingDiscardEvidenceV1: Equatable, Sendable {
    let activeCheckpoint: FieldDraftCheckpointV1
    let request: CheckRunnerPhotoDiscardV1
    let original: FieldDraftCommittedEvidenceV1

    init(activeCheckpoint: FieldDraftCheckpointV1, activeOriginal: FieldDraftCommittedEvidenceV1,
         pendingOriginal: FieldDraftCommittedEvidenceV1) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let predecessor: FieldDraftCheckpointV1
        switch activeOriginal.mutation.postImage {
        case let .createCheckpoint(value), let .reviseCheckpoint(value): predecessor = value
        case let .publishReadyStage(value): predecessor = value.successorCheckpoint
        default: throw failure
        }
        guard predecessor == activeCheckpoint,
              try FieldDraftCommittedEvidenceV1(envelope: activeOriginal.envelope,
                  receipt: activeOriginal.receipt) == activeOriginal,
              case let .reviseCheckpoint(pending) = pendingOriginal.mutation.postImage,
              try FieldDraftCommittedEvidenceV1(envelope: pendingOriginal.envelope,
                  receipt: pendingOriginal.receipt) == pendingOriginal,
              activeOriginal.mutation.workspaceID == activeCheckpoint.workspaceID,
              activeOriginal.mutation.mutationID == activeCheckpoint.mutationID,
              pendingOriginal.mutation == (try FieldDraftMutationV1(workspaceID: activeCheckpoint.workspaceID,
                expectedRevision: activeCheckpoint.draftRevision,
                expectedBaseCanonicalRevision: activeCheckpoint.baseCanonicalRevision,
                mutationID: pending.mutationID, postImage: .reviseCheckpoint(pending))),
              pendingOriginal.envelope.sourceKind == pendingOriginal.receipt.sourceKind,
              pendingOriginal.envelope.causationMutationID == pendingOriginal.receipt.causationMutationID,
              pendingOriginal.envelope.correlationID == pendingOriginal.receipt.correlationID,
              pendingOriginal.envelope.contentDependencyIDs == pendingOriginal.receipt.contentDependencyIDs,
              pendingOriginal.envelope.reversalPlanDigest == nil,
              pendingOriginal.envelope.semanticReversalReplayIdentitySHA256 == nil,
              pendingOriginal.envelope.semanticReversalExecution == nil,
              pendingOriginal.receipt.reversesMutationID == nil else { throw failure }
        let request = try CheckRunnerPhotoDiscardV1.prepare(from: activeCheckpoint,
            mutationID: pending.mutationID, at: pending.updatedAt)
        guard request.pending == pending else { throw failure }
        try CheckRunnerPhotoCommitEvidenceV1.requireOrder(activeOriginal.receipt, pendingOriginal.receipt)
        self.activeCheckpoint = activeCheckpoint
        self.request = request
        self.original = pendingOriginal
    }
}

/// The exact journal terminal after an authenticated active/pending prefix.
/// This proves canonical disposal history, not physical absence of staged media.
/// Backup and live callers must separately validate the complete prefix, current
/// row census, quarantine status and owned media before admitting the result.
struct CheckRunnerPhotoTerminalDiscardEvidenceV1: Equatable, Sendable {
    let pending: CheckRunnerPhotoPendingDiscardEvidenceV1
    let checkpoint: FieldDraftCheckpointV1
    let receipt: DraftDiscardReceiptV1
    let original: FieldDraftCommittedEvidenceV1

    init(pending: CheckRunnerPhotoPendingDiscardEvidenceV1,
         checkpoint: FieldDraftCheckpointV1, receipts: [DraftDiscardReceiptV1],
         terminalOriginal: FieldDraftCommittedEvidenceV1) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let request = pending.request
        let expected = try request.terminalBundle(disposedStageIDs: request.pending.stageIDs)
        guard case let .applyDiscardTerminal(bundle) = terminalOriginal.mutation.postImage,
              bundle == expected, checkpoint == expected.discardedCheckpoint,
              receipts == [expected.receipt],
              try FieldDraftCommittedEvidenceV1(envelope: terminalOriginal.envelope,
                  receipt: terminalOriginal.receipt) == terminalOriginal,
              terminalOriginal.mutation == (try FieldDraftMutationV1(
                  workspaceID: request.pending.workspaceID,
                  expectedRevision: request.pending.draftRevision,
                  expectedBaseCanonicalRevision: request.pending.baseCanonicalRevision,
                  mutationID: request.terminalMutationID, postImage: .applyDiscardTerminal(expected))),
              terminalOriginal.envelope.sourceKind == terminalOriginal.receipt.sourceKind,
              terminalOriginal.envelope.causationMutationID == terminalOriginal.receipt.causationMutationID,
              terminalOriginal.envelope.correlationID == terminalOriginal.receipt.correlationID,
              terminalOriginal.envelope.contentDependencyIDs == terminalOriginal.receipt.contentDependencyIDs,
              terminalOriginal.envelope.reversalPlanDigest == nil,
              terminalOriginal.envelope.semanticReversalReplayIdentitySHA256 == nil,
              terminalOriginal.envelope.semanticReversalExecution == nil,
              terminalOriginal.receipt.reversesMutationID == nil else { throw failure }
        try CheckRunnerPhotoCommitEvidenceV1.requireOrder(pending.original.receipt, terminalOriginal.receipt)
        self.pending = pending
        self.checkpoint = checkpoint
        self.receipt = expected.receipt
        self.original = terminalOriginal
    }
}

/// Splits a complete child's journal without treating its last active phase as
/// its current lifecycle state. The caller must authenticate activeHistory using
/// the existing raw/pair proof and validate quarantine and physical row membership.
struct CheckRunnerPhotoDiscardHistoryV1: Equatable, Sendable {
    let activeHistory: [FieldDraftCommittedEvidenceV1]
    let pending: CheckRunnerPhotoPendingDiscardEvidenceV1
    let terminal: CheckRunnerPhotoTerminalDiscardEvidenceV1?

    init(history: [FieldDraftCommittedEvidenceV1], checkpoint: FieldDraftCheckpointV1,
         receipts: [DraftDiscardReceiptV1]) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard checkpoint.state == .discardPending || checkpoint.state == .discarded else { throw failure }
        let entries = try history.map { evidence -> (FieldDraftCommittedEvidenceV1, FieldDraftCheckpointV1) in
            guard try FieldDraftCommittedEvidenceV1(envelope: evidence.envelope,
                receipt: evidence.receipt) == evidence else { throw failure }
            let value: FieldDraftCheckpointV1
            switch evidence.mutation.postImage {
            case let .createCheckpoint(saved), let .reviseCheckpoint(saved): value = saved
            case let .publishReadyStage(saved): value = saved.successorCheckpoint
            case let .applyDiscardTerminal(saved): value = saved.discardedCheckpoint
            default: throw failure
            }
            guard value.workspaceID == checkpoint.workspaceID, value.draftID == checkpoint.draftID else {
                throw failure
            }
            return (evidence, value)
        }.sorted { $0.1.draftRevision < $1.1.draftRevision }
        let terminalCount = checkpoint.state == .discarded ? 1 : 0
        let activeCount = entries.count - 1 - terminalCount
        guard (1...3).contains(activeCount), entries.last?.1 == checkpoint,
              entries.map({ $0.1.draftRevision }) == Array(1...entries.count).map(UInt64.init),
              case .createCheckpoint = entries[0].0.mutation.postImage,
              entries.prefix(activeCount).allSatisfy({ $0.1.state == .active }) else { throw failure }
        let active = entries[activeCount - 1]
        let pending = try CheckRunnerPhotoPendingDiscardEvidenceV1(activeCheckpoint: active.1,
            activeOriginal: active.0, pendingOriginal: entries[activeCount].0)
        let terminal: CheckRunnerPhotoTerminalDiscardEvidenceV1?
        if terminalCount == 1 {
            terminal = try .init(pending: pending, checkpoint: checkpoint, receipts: receipts,
                terminalOriginal: entries[activeCount + 1].0)
        } else {
            guard receipts.isEmpty, pending.request.pending == checkpoint else { throw failure }
            terminal = nil
        }
        self.activeHistory = entries.prefix(activeCount).map(\.0)
        self.pending = pending
        self.terminal = terminal
    }
}

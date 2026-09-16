import Foundation

/// An authenticated bound parent, with either its original editing history or
/// its complete finalization prefix. This value authorizes no new operation.
struct CheckRunnerItemParentEvidenceV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let history: [FieldDraftCommittedEvidenceV1]
    let workflow: CheckRunnerBeginCommittedEvidenceV1
    let timeZone: CheckRunnerBeginCommittedEvidenceV1?
    let validated: CheckRunnerPhotoParentEvidenceV1.ValidatedCheckpointHistory
    let finalization: CheckRunnerItemFinalizationEvidenceV1?

    init(history: [FieldDraftCommittedEvidenceV1], checkpoint: FieldDraftCheckpointV1,
         sagas: [DraftCommitSagaV1], reservations: [DraftContentReservationV1],
         stages: [AttachmentStagingItemV1], receipts: [DraftCommitReceiptV1],
         workflow: CheckRunnerBeginCommittedEvidenceV1, timeZone: CheckRunnerBeginCommittedEvidenceV1?,
         target: FinalizationCommittedEvidenceV1?) throws {
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        if payload.phase == .preparedFinalization {
            let finalization = try CheckRunnerItemFinalizationEvidenceV1(history: history, checkpoint: checkpoint,
                sagas: sagas, reservations: reservations, stages: stages, receipts: receipts,
                workflow: workflow, timeZone: timeZone, target: target)
            self.finalization = finalization
            validated = finalization.editing
        } else {
            guard sagas.isEmpty, reservations.isEmpty, stages.isEmpty, receipts.isEmpty, target == nil else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            validated = try CheckRunnerPhotoParentEvidenceV1.validateCheckpointHistory(
                history: history, checkpoint: checkpoint, workflow: workflow, timeZone: timeZone)
            finalization = nil
        }
        self.history = history; self.checkpoint = checkpoint
        self.workflow = workflow; self.timeZone = timeZone
    }
}

/// Complete original parent commit history and its physical row projection.
/// This is observational: current source/package/media checks and the actual
/// finalizer snapshot/readback remain with their live or backup member owners.
struct CheckRunnerItemFinalizationEvidenceV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let history: [FieldDraftCommittedEvidenceV1]
    let workflow: CheckRunnerBeginCommittedEvidenceV1
    let timeZone: CheckRunnerBeginCommittedEvidenceV1?
    let editing: CheckRunnerPhotoParentEvidenceV1.ValidatedCheckpointHistory
    let editingHistory: [FieldDraftCommittedEvidenceV1]
    let editingCheckpoint: FieldDraftCheckpointV1
    let committing: FieldDraftCommittedEvidenceV1
    let terminal: FieldDraftCommittedEvidenceV1?
    let reconstruction: CheckRunnerDraftCommitReconstructionV1
    let attempt: CheckRunnerFinalizationAttemptInputsV1
    let target: FinalizationCommittedEvidenceV1?
    let recordedSagaCount: Int

    init(history: [FieldDraftCommittedEvidenceV1], checkpoint: FieldDraftCheckpointV1,
         sagas: [DraftCommitSagaV1], reservations: [DraftContentReservationV1],
         stages: [AttachmentStagingItemV1], receipts: [DraftCommitReceiptV1],
         workflow: CheckRunnerBeginCommittedEvidenceV1, timeZone: CheckRunnerBeginCommittedEvidenceV1?,
         target: FinalizationCommittedEvidenceV1?) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard checkpoint.state == .committing || checkpoint.state == .committed,
              !history.isEmpty, stages.isEmpty, reservations.isEmpty,
              Set(history.map { $0.mutation.mutationID }).count == history.count else { throw failure }
        for value in history {
            guard try FieldDraftCommittedEvidenceV1(envelope: value.envelope, receipt: value.receipt) == value,
                  value.mutation.workspaceID == checkpoint.workspaceID,
                  value.envelope.sourceKind == value.receipt.sourceKind,
                  value.envelope.causationMutationID == value.receipt.causationMutationID,
                  value.envelope.correlationID == value.receipt.correlationID,
                  value.envelope.contentDependencyIDs == value.receipt.contentDependencyIDs,
                  value.envelope.reversalPlanDigest == nil,
                  value.envelope.semanticReversalReplayIdentitySHA256 == nil,
                  value.envelope.semanticReversalExecution == nil,
                  value.receipt.reversesMutationID == nil else { throw failure }
        }
        let checkpoints = history.compactMap { value -> (FieldDraftCommittedEvidenceV1, FieldDraftCheckpointV1)? in
            switch value.mutation.postImage {
            case let .createCheckpoint(cp), let .reviseCheckpoint(cp): return (value, cp)
            default: return nil
            }
        }.sorted { $0.1.draftRevision < $1.1.draftRevision }
        guard checkpoints.count >= 2, let last = checkpoints.last,
              case .reviseCheckpoint = last.0.mutation.postImage,
              last.1.state == .committing else { throw failure }
        let editing = checkpoints[checkpoints.count - 2].1
        let editingHistory = checkpoints.dropLast().map(\.0)
        let parent = try CheckRunnerPhotoParentEvidenceV1.validateCheckpointHistory(
            history: editingHistory, checkpoint: editing, workflow: workflow, timeZone: timeZone)
        let original = last.1
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(original)
        guard payload.phase == .preparedFinalization, let attempt = payload.finalizationAttempt,
              payload.source == parent.parent.source,
              payload.field == parent.parent.field,
              original.lastDurableMutationID == nil, original.lastReceiptSHA256 == nil,
              last.0.mutation.mutationID == original.mutationID,
              last.0.mutation.expectedRevision == editing.draftRevision,
              last.0.mutation.expectedBaseCanonicalRevision == editing.baseCanonicalRevision else { throw failure }
        try original.validateSuccessor(of: editing, expectedDraftRevision: editing.draftRevision,
                                      expectedBaseRevision: editing.baseCanonicalRevision)
        try CheckRunnerPhotoCommitEvidenceV1.requireOrder(checkpoints[checkpoints.count - 2].0.receipt,
                                                        last.0.receipt)
        let commit = try CheckRunnerItemDraftCodecV1.reconstructFinalizationHistory(from: original)
        let terminals = history.filter {
            if case .applyCommitTerminal = $0.mutation.postImage { return true }; return false
        }
        guard terminals.count <= 1,
              (checkpoint.state == .committed) == (terminals.count == 1),
              sagas.count <= 5,
              Set(sagas).count == sagas.count,
              Set(sagas) == Set(commit.sagas.prefix(sagas.count)),
              (terminals.count == 1) == (sagas.count == 5) else { throw failure }

        var required = Set(checkpoints.map { $0.0.mutation.mutationID })
        var previous = last.0.receipt
        var sagaEvidence: [FieldDraftCommittedEvidenceV1] = []
        for (index, saga) in commit.sagas.prefix(min(sagas.count, 4)).enumerated() {
            let mutation = try FieldDraftMutationV1(workspaceID: checkpoint.workspaceID,
                expectedRevision: UInt64(index), expectedBaseCanonicalRevision: original.baseCanonicalRevision,
                mutationID: saga.mutationID,
                postImage: index == 0 ? .appendCommitSaga(saga) : .advanceCommitSaga(saga))
            let matches = history.filter { $0.mutation.mutationID == saga.mutationID }
            guard matches.count == 1, let value = matches.first, value.mutation == mutation else { throw failure }
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(previous, value.receipt)
            previous = value.receipt
            required.insert(saga.mutationID)
            sagaEvidence.append(value)
        }
        if let target {
            guard sagas.count >= 2 else { throw failure }
            try Self.validateTarget(target, reconstruction: commit)
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(sagaEvidence[1].receipt, target.receipt)
            if sagaEvidence.count >= 3 {
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(target.receipt, sagaEvidence[2].receipt)
            }
        } else {
            guard sagas.count <= 2 else { throw failure }
        }
        if let terminal = terminals.first {
            guard let target,
                  case let .applyCommitTerminal(bundle, expectedSagaRevision) = terminal.mutation.postImage,
                  expectedSagaRevision == 4, bundle.retiredSaga == commit.retired else { throw failure }
            let receipt = try DraftCommitReceiptV1(receiptID: commit.commitReceiptID,
                workspaceID: original.workspaceID, draftID: original.draftID,
                sagaID: commit.retired.sagaID, commitPlanSHA256: commit.plan.planSHA256,
                sagaEventSHA256Chain: commit.sagas.map(\.sagaSHA256), targetMutationID: commit.plan.mutationID,
                targetReceiptSHA256: target.receipt.resultSHA256, consumedStageToContentID: [:],
                committedAt: target.receipt.committedAt, mutationID: commit.rowMutationIDs.terminalBundleMutationID)
            let expected = try FieldDraftCheckpointV1(draftID: original.draftID,
                workspaceID: original.workspaceID, scope: original.scope, purpose: original.purpose,
                codec: original.codec, baseCanonicalRevision: original.baseCanonicalRevision,
                draftRevision: original.draftRevision + 1, payloadData: original.payloadData,
                stageIDs: [], resumeAnchor: original.resumeAnchor, state: .committed,
                lastDurableMutationID: commit.rowMutationIDs.terminalBundleMutationID,
                lastReceiptSHA256: receipt.receiptSHA256, updatedAt: commit.terminalCheckpointUpdatedAt,
                mutationID: commit.rowMutationIDs.terminalBundleMutationID)
            guard checkpoint == expected, bundle.committedCheckpoint == expected,
                  bundle.receipt == receipt, receipts == [receipt],
                  terminal.mutation.mutationID == commit.rowMutationIDs.terminalBundleMutationID,
                  terminal.mutation.expectedRevision == original.draftRevision,
                  terminal.mutation.expectedBaseCanonicalRevision == original.baseCanonicalRevision else { throw failure }
            try expected.validateSuccessor(of: original, expectedDraftRevision: original.draftRevision,
                                          expectedBaseRevision: original.baseCanonicalRevision)
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(previous, terminal.receipt)
            required.insert(terminal.mutation.mutationID)
        } else {
            guard checkpoint == original, receipts.isEmpty else { throw failure }
        }
        guard required == Set(history.map { $0.mutation.mutationID }) else { throw failure }
        self.checkpoint = checkpoint
        self.history = history
        self.workflow = workflow
        self.timeZone = timeZone
        self.editing = parent
        self.editingHistory = editingHistory
        editingCheckpoint = editing
        committing = last.0
        terminal = terminals.first
        reconstruction = commit
        self.attempt = attempt
        self.target = target
        recordedSagaCount = sagas.count
    }

    private static func validateTarget(_ evidence: FinalizationCommittedEvidenceV1,
                                       reconstruction: CheckRunnerDraftCommitReconstructionV1) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let checkpoint = reconstruction.checkpoint
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        guard let attempt = payload.finalizationAttempt,
              case let .bound(begin, _, _) = payload.field.begin,
              try FinalizationCommittedEvidenceV1(envelope: evidence.envelope, receipt: evidence.receipt) == evidence,
              case let .finalizeCheck(command) = evidence.envelope.command,
              let authority = command.writerAuthority,
              evidence.envelope.workspaceID == checkpoint.workspaceID,
              evidence.receipt.mutationID == reconstruction.plan.mutationID,
              command.finalizationMutationID == attempt.identifiers.mutationID,
              command.assetID == payload.source.assetID,
              command.recordID == begin.recordCommand.recordID,
              command.packetID == attempt.identifiers.packetID,
              command.reportID == attempt.identifiers.reportID,
              try authority.affectedIdentities.map(\.stableKey).sorted() == reconstruction.plan.outputKeys,
              try evidence.receipt.postImages.map({ try $0.identity.stableKey }).sorted() == reconstruction.plan.outputKeys
        else { throw failure }
        let recordID = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: begin.recordCommand.recordID)
        let expected = evidence.envelope.expectedRevision.entityRevisions.filter { $0.identity == recordID }
        guard expected.count == 1, expected[0].revision == attempt.expectedWorkflowRecordRevision,
              try evidence.workflowRecordRevision(recordID: begin.recordCommand.recordID)
                == attempt.expectedWorkflowRecordRevision + 1,
              authority.payload.workflowRecordAfter.completedAt == attempt.completedAt,
              authority.payload.packetAfter.stableRootID == attempt.identifiers.stableRootID,
              authority.payload.reportInsert?.createdAt == attempt.snapshotCreatedAt else { throw failure }
        try CheckRunnerPhotoCurrentTargetEvidenceV1.validateFinalizationOriginalFields(
            authority, begin: begin.recordCommand)
        switch payload.source.requestedEntry {
        case .check:
            guard authority.payload.issueTransition == nil,
                  authority.payload.issueInsert?.id == attempt.identifiers.issueID else { throw failure }
        case let .recheck(issueID):
            guard authority.payload.issueTransition?.before.id == issueID,
                  authority.payload.issueTransition?.after.id == issueID,
                  authority.payload.issueInsert?.id == attempt.identifiers.newIssueID else { throw failure }
        }
        try validateOutcome(attempt.normalizedOutcome, authority: authority)
    }

    /// Resolves retained prepared claims against the actual published profile.
    /// The historical plan must remain exactly the live reconstruction's value.
    func validatePreparedOutcome(profile: WorkspacePackageLifecycleProfileV1) throws {
        guard try CheckRunnerItemDraftCodecV1.reconstructFinalizationCommit(
            from: reconstruction.checkpoint, signPack: profile.package,
            activeLifecycleProfile: { profile }) == reconstruction else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
    }

    func validateTargetReport(_ report: V4BackupReportDTO) throws {
        guard let target, case let .finalizeCheck(command) = target.envelope.command,
              let original = command.writerAuthority?.payload.reportInsert,
              report.id == original.id, report.packetID == original.packetID,
              report.sourceRecordID == original.sourceRecordID,
              report.snapshotSchemaVersion == original.snapshotSchemaVersion,
              report.snapshotRelativePath == original.snapshotRelativePath,
              report.snapshotSHA256 == original.snapshotSHA256,
              report.createdAt == original.createdAt, report.replacesReportID == original.replacesReportID else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
    }

    /// Joins the exact immutable report member to its original target. Decoding,
    /// canonical bytes, SHA, ownership and complete snapshot validation belong
    /// to the incumbent finalizer/backup member reader before this call.
    func validateTargetSnapshot(_ snapshot: ReportSnapshotV1) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(reconstruction.checkpoint)
        guard let target, case let .finalizeCheck(command) = target.envelope.command,
              let authority = command.writerAuthority, let attempt = payload.finalizationAttempt,
              case let .bound(begin, _, _) = payload.field.begin,
              snapshot.reportID == attempt.identifiers.reportID,
              snapshot.packetID == attempt.identifiers.packetID,
              snapshot.stableRootID == attempt.identifiers.stableRootID,
              snapshot.sourceRecordID == begin.recordCommand.recordID,
              snapshot.stage == payload.source.requestedEntry.stage.rawValue,
              snapshot.snapshotCreatedAt == attempt.snapshotCreatedAt,
              snapshot.sourceApp == attempt.sourceApp,
              snapshot.outcome == authority.payload.workflowRecordAfter.outcomeKey,
              snapshot.note == authority.payload.workflowRecordAfter.note else { throw failure }
        let expected = Self.outcomeFields(attempt.normalizedOutcome)
        guard snapshot.outcome == expected.key, snapshot.display.outcome == expected.display,
              snapshot.couldNotVerify == expected.reason, snapshot.note == expected.note else { throw failure }
    }

    private static func validateOutcome(_ outcome: CheckRunnerOutcomeSnapshotV1,
                                        authority: FinalizationWriterAuthorityV1) throws {
        let expected = outcomeFields(outcome)
        let record = authority.payload.workflowRecordAfter
        guard record.outcomeKey == expected.key, record.note == expected.note,
              record.couldNotVerifyKey == expected.reason?.key,
              record.couldNotVerifyDisplaySnapshot == expected.reason?.display,
              record.couldNotVerifyRegistryVersion == expected.reason?.registryVersion else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        if let label = expected.label {
            guard authority.payload.issueInsert?.labelKey == label.key,
                  authority.payload.issueInsert?.labelDisplaySnapshot == label.display else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
    }

    private static func outcomeFields(_ outcome: CheckRunnerOutcomeSnapshotV1)
        -> (key: String, display: String, note: String?, reason: CouldNotVerifySnapshotV1?,
            label: (key: String, display: String)?) {
        switch outcome {
        case let .noVisibleIssue(key, display): return (key, display, nil, nil, nil)
        case let .visibleIssue(key, display, label, labelDisplay):
            return (key, display, nil, nil, (label, labelDisplay))
        case let .couldNotVerify(key, display, reason, reasonDisplay, version, note):
            return (key, display, note, .init(display: reasonDisplay, key: reason, registryVersion: version), nil)
        case let .resolved(key, display, note), let .issueStillVisible(key, display, note):
            return (key, display, note, nil, nil)
        case let .originalResolvedDifferentIssue(key, display, label, labelDisplay, note):
            return (key, display, note, nil, (label, labelDisplay))
        }
    }
}

import Foundation

/// Values for the existing coordinator, reconstructed from a frozen COMMITTING
/// checkpoint. They authenticate no current row, content promotion or target
/// receipt and do not permit a production write by themselves.
struct CheckRunnerDraftCommitReconstructionV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let plan: DraftCommitPlanV1
    let items: [AttachmentStagingItemV1]
    let prepared: DraftCommitSagaV1
    let contentPromoted: DraftCommitSagaV1
    let targetCommitted: DraftCommitSagaV1
    let retirePending: DraftCommitSagaV1
    let retired: DraftCommitSagaV1
    let commitReceiptID: UUID
    let terminalCheckpointUpdatedAt: Date
    let rowMutationIDs: DraftCommitRowMutationIDsV1

    var sagas: [DraftCommitSagaV1] {
        [prepared, contentPromoted, targetCommitted, retirePending, retired]
    }

    fileprivate init(checkpoint: FieldDraftCheckpointV1, plan: DraftCommitPlanV1,
        items: [AttachmentStagingItemV1], frozenEvents: [CheckRunnerFrozenSagaInputV1],
        commitReceiptID: UUID, terminalCheckpointUpdatedAt: Date,
        rowMutationIDs: DraftCommitRowMutationIDsV1) throws {
        try checkpoint.validate(authority: CheckRunnerDraftPurposeAuthorityV1())
        try plan.validate()
        try FieldDraftValidationV1.id(commitReceiptID)
        try FieldDraftValidationV1.instant(terminalCheckpointUpdatedAt)
        for item in items { try item.validate() }
        guard checkpoint.state == .committing,
              checkpoint.draftRevision < UInt64.max,
              checkpoint.mutationID != rowMutationIDs.terminalBundleMutationID,
              terminalCheckpointUpdatedAt >= checkpoint.updatedAt,
              plan.workspaceID == checkpoint.workspaceID, plan.draftID == checkpoint.draftID,
              plan.draftRevision == checkpoint.draftRevision,
              plan.baseCanonicalRevision == checkpoint.baseCanonicalRevision,
              plan.payloadSHA256 == checkpoint.payloadSHA256,
              items.map(\.stageID) == checkpoint.stageIDs,
              items.allSatisfy({ $0.workspaceID == plan.workspaceID && $0.draftID == plan.draftID
                  && $0.state == .readyLocal }),
              items.map(\.stageSHA256).sorted() == plan.stageDigests,
              frozenEvents.count == 5,
              frozenEvents.last?.mutationID == rowMutationIDs.terminalBundleMutationID else {
            throw FieldDraftFailureV1.invalidTransition
        }
        try rowMutationIDs.validate(stageIDs: items.map(\.stageID), targetMutationID: plan.mutationID,
            sagaMutationIDs: frozenEvents.dropLast().map(\.mutationID))
        let states: [DraftCommitSagaStateV1] = [
            .prepared, .contentPromotedUnbound, .targetCommitted, .draftRetirePending, .draftRetired,
        ]
        var events: [DraftCommitSagaV1] = []
        for (index, input) in frozenEvents.enumerated() {
            let event = try DraftCommitSagaV1(sagaID: input.id, workspaceID: plan.workspaceID,
                draftID: plan.draftID, plan: plan, state: states[index],
                predecessorSagaID: events.last?.sagaID, revision: UInt64(index + 1),
                mutationID: input.mutationID, updatedAt: input.updatedAt)
            if let predecessor = events.last { try event.validateSuccessor(of: predecessor) }
            events.append(event)
        }
        guard terminalCheckpointUpdatedAt >= events[4].updatedAt else {
            throw FieldDraftFailureV1.invalidTransition
        }
        self.checkpoint = checkpoint; self.plan = plan; self.items = items
        prepared = events[0]; contentPromoted = events[1]; targetCommitted = events[2]
        retirePending = events[3]; retired = events[4]
        self.commitReceiptID = commitReceiptID
        self.terminalCheckpointUpdatedAt = terminalCheckpointUpdatedAt
        self.rowMutationIDs = rowMutationIDs
    }
}

fileprivate struct CheckRunnerFrozenSagaInputV1 {
    let id: UUID
    let mutationID: MutationIDV1
    let updatedAt: Date
}

/// The command is a value projection, not evidence that its target was saved.
/// Promotion reservations and target receipts come from their actual owners.
struct CheckRunnerPhotoCommitReconstructionV1: Equatable, Sendable {
    let draftCommit: CheckRunnerDraftCommitReconstructionV1
    let targetCommand: CheckEvidenceMutationV1

    fileprivate init(draftCommit: CheckRunnerDraftCommitReconstructionV1,
                     targetCommand: CheckEvidenceMutationV1) {
        self.draftCommit = draftCommit; self.targetCommand = targetCommand
    }
}

extension CheckRunnerItemDraftCodecV1 {
    static func reconstructFinalizationCommit(from checkpoint: FieldDraftCheckpointV1,
        signPack: SignPack,
        activeLifecycleProfile: () throws -> WorkspacePackageLifecycleProfileV1) throws
        -> CheckRunnerDraftCommitReconstructionV1 {
        let payload = try validateCheckpoint(checkpoint)
        guard checkpoint.state == .committing, payload.phase == .preparedFinalization,
              let attempt = payload.finalizationAttempt,
              case let .bound(begin, _, _) = payload.field.begin else {
            throw FieldDraftFailureV1.invalidTransition
        }
        try payload.validatePreparedOutcome(signPack: signPack,
            activeLifecycleProfile: activeLifecycleProfile)
        // Attempt validation already proves the seven outcome/identifier cases.
        // The actual finalizer must later return this exact affected identity set.
        var outputs = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: begin.recordCommand.recordID),
            WorkspaceEntityIdentityV1(kind: .packet, id: attempt.identifiers.packetID),
            WorkspaceEntityIdentityV1(kind: .report, id: attempt.identifiers.reportID),
        ]
        for issueID in [attempt.identifiers.issueID, attempt.identifiers.newIssueID].compactMap({ $0 }) {
            outputs.append(try WorkspaceEntityIdentityV1(kind: .issue, id: issueID))
        }
        let plan = try DraftCommitPlanV1(planID: attempt.fieldDraftPlanID,
            workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID,
            draftRevision: checkpoint.draftRevision, baseCanonicalRevision: checkpoint.baseCanonicalRevision,
            payloadSHA256: checkpoint.payloadSHA256, stageDigests: [], targetCommandKind: .finalizeCheck,
            expectedTargetRevision: attempt.expectedWorkflowRecordRevision,
            mutationID: .init(rawValue: attempt.identifiers.mutationID),
            outputKeys: outputs.map(\.stableKey).sorted())
        let rows = try DraftCommitRowMutationIDsV1(reservationByStageID: [:],
            terminalBundleMutationID: attempt.terminalBundleMutationID)
        return try .init(checkpoint: checkpoint, plan: plan, items: [], frozenEvents: [
            .init(id: attempt.preparedSagaID, mutationID: attempt.preparedSagaMutationID,
                  updatedAt: attempt.preparedSagaUpdatedAt),
            .init(id: attempt.contentPromotedSagaID, mutationID: attempt.contentPromotedSagaMutationID,
                  updatedAt: attempt.contentPromotedSagaUpdatedAt),
            .init(id: attempt.targetCommittedSagaID, mutationID: attempt.targetCommittedSagaMutationID,
                  updatedAt: attempt.targetCommittedSagaUpdatedAt),
            .init(id: attempt.draftRetirePendingSagaID, mutationID: attempt.draftRetirePendingSagaMutationID,
                  updatedAt: attempt.draftRetirePendingSagaUpdatedAt),
            .init(id: attempt.draftRetiredSagaID, mutationID: attempt.terminalBundleMutationID,
                  updatedAt: attempt.draftRetiredSagaUpdatedAt),
        ], commitReceiptID: attempt.commitReceiptID,
            terminalCheckpointUpdatedAt: attempt.terminalCheckpointUpdatedAt, rowMutationIDs: rows)
    }
}

extension CheckRunnerPhotoDraftCodecV1 {
    static func reconstructPhotoCommit(from checkpoint: FieldDraftCheckpointV1) throws
        -> CheckRunnerPhotoCommitReconstructionV1 {
        let payload = try validateCheckpoint(checkpoint)
        guard checkpoint.state == .committing,
              case let .preparedCommit(pair, attempt) = payload.phase else {
            throw FieldDraftFailureV1.invalidTransition
        }
        // This is the frozen READY_LOCAL witness. Current stage state, original
        // publication, pair files and parent/target receipts need separate proof.
        let ready = pair.raw.readyItem
        let plan = try DraftCommitPlanV1(planID: attempt.planID, workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID, draftRevision: checkpoint.draftRevision,
            baseCanonicalRevision: checkpoint.baseCanonicalRevision, payloadSHA256: checkpoint.payloadSHA256,
            stageDigests: [ready.stageSHA256], targetCommandKind: .acceptCheckEvidence,
            expectedTargetRevision: attempt.expectedWorkflowRecordRevision,
            mutationID: attempt.targetMutationID, outputKeys: attempt.outputKeys)
        let draftCommit = try CheckRunnerDraftCommitReconstructionV1(checkpoint: checkpoint,
            plan: plan, items: [ready], frozenEvents: [
                .init(id: attempt.preparedSagaID, mutationID: attempt.preparedSagaMutationID,
                      updatedAt: attempt.preparedUpdatedAt),
                .init(id: attempt.contentPromotedSagaID, mutationID: attempt.contentPromotedSagaMutationID,
                      updatedAt: attempt.contentPromotedUpdatedAt),
                .init(id: attempt.targetCommittedSagaID, mutationID: attempt.targetCommittedSagaMutationID,
                      updatedAt: attempt.targetCommittedUpdatedAt),
                .init(id: attempt.draftRetirePendingSagaID, mutationID: attempt.draftRetirePendingSagaMutationID,
                      updatedAt: attempt.draftRetirePendingUpdatedAt),
                .init(id: attempt.draftRetiredSagaID, mutationID: attempt.terminalBundleMutationID,
                      updatedAt: attempt.draftRetiredUpdatedAt),
            ], commitReceiptID: attempt.commitReceiptID,
            terminalCheckpointUpdatedAt: attempt.terminalCheckpointUpdatedAt,
            rowMutationIDs: attempt.rowMutationIDs(stageID: ready.stageID))
        let normalized = pair.normalizedPair
        guard let originalByteCount = Int(exactly: normalized.originalByteCount),
              let thumbnailByteCount = Int(exactly: normalized.thumbnailByteCount) else {
            throw FieldDraftFailureV1.invalidValue
        }
        let command = CheckEvidenceMutationV1(evidenceID: pair.raw.intent.evidenceID,
            draftID: payload.recordID, purposeKey: payload.purposeKey,
            relativePath: normalized.originalRelativePath, mimeType: MediaContractV1.durableMIMEType,
            byteCount: originalByteCount, sha256: normalized.originalSHA256,
            thumbnailRelativePath: normalized.thumbnailRelativePath,
            thumbnailByteCount: thumbnailByteCount, thumbnailSHA256: normalized.thumbnailSHA256,
            nextDraftStepKey: payload.captureStep == .wide ? WorkflowDraftStep.close.rawValue : WorkflowDraftStep.outcome.rawValue,
            createdAt: pair.raw.intent.evidenceCreatedAt)
        return .init(draftCommit: draftCommit, targetCommand: command)
    }
}

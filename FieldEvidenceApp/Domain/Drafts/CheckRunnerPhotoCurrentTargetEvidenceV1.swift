import Foundation

/// Authenticated current target of an original parent/child photo commit.
/// The journal supplies every later receipt touching either target identity.
/// Media, source-owner freshness and adoption effects remain separate duties.
struct CheckRunnerPhotoCurrentTargetEvidenceV1: Equatable, Sendable {
    let parent: CheckRunnerPhotoParentEvidenceV1
    let workflow: V4BackupWorkflowRecordDTO
    let workflowPostImage: MutationPostImageV1
    let evidence: V4BackupEvidenceFileDTO
    let evidencePostImage: MutationPostImageV1
    let laterPhotos: [CheckRunnerPhotoCommittedEvidenceV1]
    let finalization: FinalizationCommittedEvidenceV1?

    init(parent: CheckRunnerPhotoParentEvidenceV1,
         workflow: V4BackupWorkflowRecordDTO, workflowPostImage: MutationPostImageV1,
         evidence: V4BackupEvidenceFileDTO, evidencePostImage: MutationPostImageV1,
         laterReceipts: [(MutationEnvelopeV1, MutationReceiptV1)]) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let original = parent.child.target
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(parent.checkpoint)
        guard let attempt = payload.field.begin.attempt,
              attempt.sourceWorkspaceID == parent.checkpoint.workspaceID,
              original.envelope.workspaceID == parent.checkpoint.workspaceID,
              try CheckRunnerPhotoCommittedEvidenceV1(envelope: original.envelope,
                  receipt: original.receipt) == original else { throw failure }
        let command = original.command
        let recordID = command.draftID
        let workflowIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: recordID)
        let evidenceIdentity = try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: command.evidenceID)
        guard attempt.recordCommand.recordID == recordID,
              command.purposeKey == parent.slot.purposeKey,
              (parent.slot.captureStep == .wide && command.nextDraftStepKey == WorkflowDraftStep.close.rawValue)
                || (parent.slot.captureStep == .close && command.nextDraftStepKey == WorkflowDraftStep.outcome.rawValue),
              try workflowPostImage.identity == workflowIdentity,
              try evidencePostImage.identity == evidenceIdentity,
              evidencePostImage.revision == 1,
              evidence == Self.evidenceDTO(command),
              original.receipt.postImages.contains(evidencePostImage) else { throw failure }

        var frontier = try Self.workflowImage(original.receipt, identity: workflowIdentity)
        var previous = original.receipt
        var step = command.nextDraftStepKey
        var laterPhotos: [CheckRunnerPhotoCommittedEvidenceV1] = []
        var finalization: FinalizationCommittedEvidenceV1?
        var seen = Set([original.receipt.mutationID])
        for (envelope, receipt) in laterReceipts {
            guard finalization == nil,
                  envelope.workspaceID == parent.checkpoint.workspaceID,
                  receipt.identity.workspaceID == parent.checkpoint.workspaceID,
                  seen.insert(receipt.mutationID).inserted,
                  receipt.resultingRevision.workspaceRevision > previous.resultingRevision.workspaceRevision,
                  try !receipt.postImages.contains(where: { try $0.identity == evidenceIdentity }),
                  frontier.revision < UInt64.max else { throw failure }
            let next = try Self.workflowImage(receipt, identity: workflowIdentity)
            let expected = receipt.expectedRevision.entityRevisions.filter { $0.identity == workflowIdentity }
            guard expected.count == 1, expected[0].revision == frontier.revision,
                  next.revision == frontier.revision + 1 else { throw failure }
            switch envelope.command {
            case .acceptCheckEvidence:
                let photo = try CheckRunnerPhotoCommittedEvidenceV1(envelope: envelope, receipt: receipt)
                guard parent.slot.captureStep == .wide, step == WorkflowDraftStep.close.rawValue,
                      laterPhotos.isEmpty, photo.command.draftID == recordID,
                      photo.command.evidenceID != command.evidenceID,
                      photo.command.purposeKey == "close_detail",
                      photo.command.nextDraftStepKey == WorkflowDraftStep.outcome.rawValue else { throw failure }
                laterPhotos.append(photo)
                step = photo.command.nextDraftStepKey
            case let .finalizeCheck(value):
                guard value.recordID == recordID, value.assetID == attempt.recordCommand.assetID,
                      let authority = value.writerAuthority,
                      authority.workspaceID == parent.checkpoint.workspaceID,
                      envelope.reversalPlanDigest == nil,
                      envelope.semanticReversalReplayIdentitySHA256 == nil,
                      envelope.semanticReversalExecution == nil else { throw failure }
                try authority.validate(envelope: envelope)
                let completed = authority.payload.workflowRecordAfter
                let allowsIncomplete = completed.outcomeKey == "could_not_verify"
                    && completed.couldNotVerifyKey != nil
                    && completed.couldNotVerifyDisplaySnapshot != nil
                    && completed.couldNotVerifyRegistryVersion != nil
                guard step == WorkflowDraftStep.outcome.rawValue
                    || (step == WorkflowDraftStep.close.rawValue && allowsIncomplete) else { throw failure }
                let finalized = try FinalizationCommittedEvidenceV1(envelope: envelope, receipt: receipt)
                guard try finalized.workflowRecordRevision(recordID: recordID) == next.revision,
                      workflow.state == WorkflowState.completed.rawValue,
                      workflow.finalizationMutationID == value.finalizationMutationID,
                      workflow == Self.finalizedWorkflow(authority) else { throw failure }
                finalization = finalized
            default:
                throw failure
            }
            frontier = next
            previous = receipt
        }
        guard workflowPostImage == frontier else { throw failure }
        try Self.validateOriginalFields(workflow, command: attempt.recordCommand,
                                        finalized: finalization != nil)
        if finalization == nil {
            guard workflow.state == WorkflowState.draft.rawValue, workflow.draftStepKey == step,
                  workflow.packetID == nil, workflow.completedAt == nil,
                  workflow.outcomeKey == nil, workflow.couldNotVerifyKey == nil,
                  workflow.couldNotVerifyDisplaySnapshot == nil, workflow.couldNotVerifyRegistryVersion == nil,
                  workflow.workPerformedLocalDate == nil, workflow.workDescription == nil,
                  workflow.note == nil, workflow.finalizationMutationID == nil else { throw failure }
        }
        self.parent = parent
        self.workflow = workflow
        self.workflowPostImage = workflowPostImage
        self.evidence = evidence
        self.evidencePostImage = evidencePostImage
        self.laterPhotos = laterPhotos
        self.finalization = finalization
    }

    private static func workflowImage(_ receipt: MutationReceiptV1,
                                      identity: WorkspaceEntityIdentityV1) throws -> MutationPostImageV1 {
        let images = try receipt.postImages.filter { try $0.identity == identity }
        let revisions = receipt.resultingRevision.entityRevisions.filter { $0.identity == identity }
        guard images.count == 1, let image = images.first,
              case .workflowRecord = image,
              revisions.count == 1, revisions[0].revision == image.revision else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return image
    }

    private static func evidenceDTO(_ command: CheckEvidenceMutationV1) -> V4BackupEvidenceFileDTO {
        .init(id: command.evidenceID, schemaVersion: 1, recordID: command.draftID,
            purposeKey: command.purposeKey, relativePath: command.relativePath, mimeType: command.mimeType,
            byteCount: command.byteCount, sha256: command.sha256, createdAt: command.createdAt,
            thumbnailRelativePath: command.thumbnailRelativePath, thumbnailByteCount: command.thumbnailByteCount,
            thumbnailSHA256: command.thumbnailSHA256)
    }

    /// The finalizer's payload preserves its older optional-field shape. The
    /// authenticated source binding supplies companion bytes, as in the journal.
    private static func finalizedWorkflow(_ authority: FinalizationWriterAuthorityV1) -> V4BackupWorkflowRecordDTO {
        let row = authority.payload.workflowRecordAfter
        return V4BackupWorkflowRecordDTO(id: row.id, schemaVersion: row.schemaVersion,
            assetID: row.assetID, packetID: row.packetID, issueID: row.issueID, parentRecordID: row.parentRecordID,
            recordRevisionRootID: row.recordRevisionRootID, revisesRecordID: row.revisesRecordID,
            evidenceSourceRecordID: row.evidenceSourceRecordID, revisionKind: row.revisionKind,
            stage: row.stage, state: row.state, draftStepKey: row.draftStepKey,
            startedAt: row.startedAt, completedAt: row.completedAt, observedAtUTC: row.observedAtUTC,
            timeZoneID: row.timeZoneID, utcOffsetMinutes: row.utcOffsetMinutes,
            localDate: row.localDate, localTime: row.localTime,
            afterDarkAcknowledgementKey: row.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: row.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: row.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: row.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: row.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: row.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: row.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: row.safePositionAcknowledgementAccepted,
            packID: row.packID, packSchemaVersion: row.packSchemaVersion, packContentVersion: row.packContentVersion,
            pdfTemplateID: row.pdfTemplateID, pdfTemplateVersion: row.pdfTemplateVersion,
            outcomeKey: row.outcomeKey, couldNotVerifyKey: row.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: row.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: row.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: row.workPerformedLocalDate, workDescription: row.workDescription,
            note: row.note, finalizationMutationID: row.finalizationMutationID
        ).replacingObservationAndTime(basisData: authority.sourceBinding.observationBasisV1Data,
                                    temporalData: authority.sourceBinding.temporalContextV1Data)
    }

    private static func validateOriginalFields(_ record: V4BackupWorkflowRecordDTO,
                                              command: CheckDraftMutationV1, finalized: Bool) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard record.schemaVersion == 1, record.revisionKind == WorkflowRevisionKind.original.rawValue,
              record.recordRevisionRootID == command.recordID, record.revisesRecordID == nil,
              record.evidenceSourceRecordID == nil,
              finalized || record.issueID == command.issueID else { throw failure }
        // The allowed successor operations change the draft step and final
        // outcome. Every original Begin field remains bound to its command.
        let actual = CheckDraftMutationV1(recordID: record.id, assetID: record.assetID,
            issueID: command.issueID, parentRecordID: record.parentRecordID, stage: record.stage,
            draftStepKey: command.draftStepKey, startedAt: record.startedAt, observedAtUTC: record.observedAtUTC,
            timeZoneID: record.timeZoneID, utcOffsetMinutes: record.utcOffsetMinutes,
            localDate: record.localDate, localTime: record.localTime,
            afterDarkAcknowledgementKey: record.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: record.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: record.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: record.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: record.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: record.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: record.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: record.safePositionAcknowledgementAccepted,
            packID: record.packID, packSchemaVersion: record.packSchemaVersion,
            packContentVersion: record.packContentVersion, pdfTemplateID: record.pdfTemplateID,
            pdfTemplateVersion: record.pdfTemplateVersion,
            observationBasis: command.observationBasis, temporalContext: command.temporalContext)
        let basis = try command.observationBasis ?? ObservationAndTimeLegacyMigrationV1.observationBasis(
            couldNotVerifyKey: nil, displaySnapshot: nil, registryVersion: nil)
        let temporal = try command.temporalContext ?? ObservationAndTimeLegacyMigrationV1.temporalContext(
            observedAtUTC: command.observedAtUTC, recordedAtUTC: command.startedAt, timeZoneID: command.timeZoneID,
            utcOffsetMinutes: command.utcOffsetMinutes, localDate: command.localDate, localTime: command.localTime)
        guard actual == command, let basis, let temporal,
              record.observationBasisV1Data == (try ObservationAndTimeCodecV1.encode(basis)),
              record.temporalContextV1Data == (try ObservationAndTimeCodecV1.encode(temporal)) else { throw failure }
    }
}

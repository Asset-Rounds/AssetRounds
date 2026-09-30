import Foundation

/// The two releases bind one reviewed parent/child wire grammar and the source
/// metadata profile. Definition lookup does not register a production route or
/// authenticate a checkpoint receipt, source history, stage or target effect.
private enum CheckRunnerDraftGrammarV1 {
    static let descriptor = [
        "grammar=assetrounds.check-runner.parent-photo.v1",
        "canonical=FieldDraftCanonicalCodecV1.sortedKeys.withoutEscapingSlashes.millisecondsSince1970.byteExactReencode",
        "closed=unknownKeysRejectedAtEveryIntroducedObject;unknownTagsRejected;phaseSpecificKeysOnly",
        "text=preserveRawUTF8;noTrim;noNFC;noSilentTruncation;generic512OnlyWhereDeclared",
        "dates=finite;sampledOperationalInstantsNonnegativeMillisecondFloor;historyNeverRerounded",
        "parent.schemaVersion=\(CheckRunnerItemDraftPayloadV1.schemaVersion)",
        "parent.maximumPayloadBytes=\(CheckRunnerItemDraftPayloadV1.maximumPayloadBytes)",
        "parent.EDITING.keys=schemaVersion,phase,source,field",
        "parent.PREPARED_FINALIZATION.keys=schemaVersion,phase,source,field,finalizationAttempt",
        "parent.source=CheckRunnerRoundItemSourceV1.exactSourceAndEntryCheckpointReferences.roundAtEntry.originalItem.itemAtEntry.assetID.packageRelease.legacyPackageIdentity.requestedEntry",
        "parent.field.keys=preflight,begin,outcome,wideContext,closeDetail,semanticAnchor",
        "parent.preflight=CheckRunnerEditablePreflightV1.rawEditorValues",
        "parent.outcome=CheckRunnerEditableOutcomeV1.rawEditorValuesAndStartsWithCouldNotVerify",
        "parent.begin.NOT_BEGUN.keys=tag",
        "parent.begin.PREPARED.keys=tag,attempt",
        "parent.begin.BOUND.keys=tag,attempt,workflowReceiptReference,timeZoneReceiptReference?",
        "parent.begin.attempt=CheckRunnerFrozenBeginAttemptV1.exactSourceRecordCommandOptionalTimeZoneAndFrozenInstants",
        "parent.begin.receipt=CheckRunnerBeginReceiptReferenceV1.originalCommandEnvelopeResultPostimageAndCommittedAt",
        "parent.slot.PENDING.keys=tag,childDraftID,captureStep,purposeKey",
        "parent.slot.COMMITTED.keys=tag,childDraftID,captureStep,purposeKey,committedChildDraftRevision,committedChildCheckpointSHA256,childCommitReceiptID,childCommitReceiptSHA256,evidenceID,targetMutationID,targetReceiptSHA256",
        "parent.slot=wide:wide_context;close:close_detail;distinctChildAndEvidenceIDs;pendingAndCommittedAreDistinctValues",
        "parent.anchor=\(CheckRunnerItemSemanticAnchorV1.allCases.map(\.rawValue).joined(separator: "|"))",
        "parent.normalizedOutcome=NO_VISIBLE_ISSUE|VISIBLE_ISSUE|COULD_NOT_VERIFY|RESOLVED|ISSUE_STILL_VISIBLE|ORIGINAL_RESOLVED_DIFFERENT_ISSUE",
        "parent.normalizedOutcomeAuthority=ShippingIlluminatedSignAdapterV1.exactResolverInverseAndSevenOutcomeMediaRows",
        "parent.identifiers.keys=mutationID,packetID,stableRootID,reportID,issueID?,newIssueID?",
        "parent.finalizationAttempt.keys=normalizedOutcome,identifiers,completedAt,snapshotCreatedAt,sourceApp,expectedWorkflowRecordRevision,fieldDraftPlanID,preparedSagaID,contentPromotedSagaID,targetCommittedSagaID,draftRetirePendingSagaID,draftRetiredSagaID,preparedSagaMutationID,contentPromotedSagaMutationID,targetCommittedSagaMutationID,draftRetirePendingSagaMutationID,terminalBundleMutationID,commitReceiptID,preparedSagaUpdatedAt,contentPromotedSagaUpdatedAt,targetCommittedSagaUpdatedAt,draftRetirePendingSagaUpdatedAt,draftRetiredSagaUpdatedAt,terminalCheckpointUpdatedAt",
        "parent.scope=INSPECTION_REVIEW:[roundAtEntry.sessionID.lowercaseUUID,originalItem.itemID.lowercaseUUID];noWorkflowRecordID",
        "parent.resumeAnchor=semanticAnchor.lowercased;selectedStableID=assetID.lowercaseUUID;fieldID=nil;boundedPosition=nil",
        "parent.definition=INSPECTION_REVIEW;finalize_check;RETIRE_AFTER_COMMIT;WORKSPACE_PRIVATE;attachments=[];maximumStageItems=0",
        "parent.excludes=rawMedia;attachmentStageRows;derivedPlanSagaCheckpointPayloadDigests;liveModelObjects",
        "child.schemaVersion=\(CheckRunnerPhotoDraftPayloadV1.schemaVersion)",
        "child.maximumPayloadBytes=\(CheckRunnerPhotoDraftPayloadV1.maximumPayloadBytes)",
        "child.keys=schemaVersion,workspaceID,childDraftID,parentDraftID,recordID,assetID,sourceBinding,workflowStage,captureStep,purposeKey,origin,phase",
        "child.sourceBinding=exactCheckRunnerRoundItemSourceV1;workspaceAssetAndWorkflowStageEqualSource",
        "child.AWAITING_RAW_STAGE.keys=tag,intent;stageIDs=[]",
        "child.RAW_READY.keys=tag,raw;stageIDs=[intent.stageID]",
        "child.PAIR_READY.keys=tag,pair;stageIDs=[pair.raw.intent.stageID]",
        "child.PREPARED_COMMIT.keys=tag,pair,attempt;stageIDs=[pair.raw.intent.stageID]",
        "child.intent.keys=stageID,stageMutationID,stageCreatedAt,expectedSourceByteCount,provenanceID,evidenceID,evidenceCreatedAt",
        "child.inspection.keys=sourceByteCount,sourceSHA256,detectedUTI,sourceMediaType,pixelWidth,pixelHeight,decodedPixelCount,frameCount,rawContentID,provenanceID",
        "child.raw.keys=intent,inspection,readyItem,stagePublicationMutationID,originalProvenance",
        "child.raw=exactREADY_LOCAL.photo.stageDraftWorkspaceLeaseCountDigestMutationAndOriginalProvenanceJoins",
        "child.normalizedPair.keys=evidenceID,originalRelativePath,originalByteCount,originalSHA256,originalPixelWidth,originalPixelHeight,thumbnailRelativePath,thumbnailByteCount,thumbnailSHA256,thumbnailPixelWidth,thumbnailPixelHeight,sourceBinding,sanitizedDerivative,thumbnailDerivative",
        "child.pair.keys=raw,normalizedPair,pairPublicationMarkerSHA256",
        "child.pair=exactEvidencePaths;boundedJPEGOutputs;sourceAndDerivativeJoins;markerBindsParentChildRawAndBothOutputs",
        "child.attempt.keys=planID,expectedWorkflowRecordRevision,targetMutationID,outputKeys,reservationMutationID,reservationReviewAfter,preparedSagaID,preparedSagaMutationID,preparedUpdatedAt,contentPromotedSagaID,contentPromotedSagaMutationID,contentPromotedUpdatedAt,targetCommittedSagaID,targetCommittedSagaMutationID,targetCommittedUpdatedAt,draftRetirePendingSagaID,draftRetirePendingSagaMutationID,draftRetirePendingUpdatedAt,draftRetiredSagaID,draftRetiredUpdatedAt,commitReceiptID,terminalBundleMutationID,terminalCheckpointUpdatedAt,promotionAt",
        "child.attempt=nonzeroDistinctFrozenOperationIDs;targetMutationEqualsEvidenceID;exactSortedWorkflowAndEvidenceOutputKeys;causalInstants;terminalSagaReusesTerminalBundleMutation",
        "child.scope=INSPECTION_REVIEW_PHOTO:[parentDraftID.lowercaseUUID,childDraftID.lowercaseUUID];nonzeroDistinctIDs",
        "child.resumeAnchor=wide:wide_context|close:close_detail;selectedStableID=assetID.lowercaseUUID;fieldID=nil;boundedPosition=nil",
        "child.definition=INSPECTION_REVIEW;capture_evidence;RETIRE_AFTER_COMMIT;RESTRICTED_EVIDENCE;attachments=[PHOTO];maximumStageItems=1",
        "child.excludes=rawBytes;prematureSourceOrPairClaims;enclosingPublicationReceiptOrCheckpointDigest;derivedPlanSagaDigests",
        "checkpoint.baseCanonicalRevision=source.roundAtEntry.revision;targetExpectedEntityRevisionIsSeparate",
        "checkpoint.lifecycle=FieldDraftStateV1;payloadPhaseGrantsNoEffectOrDispositionAuthority",
        "media.profileID=\(CheckRunnerPhotoSourceMetadataProfileV1.profileID)",
        "media.profileVersion=\(CheckRunnerPhotoSourceMetadataProfileV1.profileVersion)",
        "media.sourceUTIToMediaType=\(CheckRunnerPhotoSourceMetadataProfileV1.sourceUTIToMediaType.map { "\($0.key):\($0.value)" }.sorted().joined(separator: "|"))",
        "media.sanitizer=\(CheckRunnerPhotoSourceMetadataProfileV1.normalizerSanitizerID)@\(CheckRunnerPhotoSourceMetadataProfileV1.normalizerSanitizerVersion)",
        "media.thumbnailRenderer=\(CheckRunnerPhotoSourceMetadataProfileV1.thumbnailRendererID)@\(CheckRunnerPhotoSourceMetadataProfileV1.thumbnailRendererVersion)",
        "media.rawByteCount=1...\(MediaContractV1.sourceByteCountMaximum);frameCount=1;sourceAxis=\(MediaContractV1.sourceAxisMinimum)...\(MediaContractV1.sourceAxisMaximum);decodedPixelCountMaximum=\(MediaContractV1.decodedPixelCountMaximum)",
        "media.output=\(MediaContractV1.durableMIMEType);originalLongestEdgeMaximum=\(MediaContractV1.originalLongestEdgeMaximum);originalByteCountMaximum=\(MediaContractV1.originalByteCountMaximum);thumbnailLongestEdgeMaximum=\(MediaContractV1.thumbnailLongestEdgeMaximum);thumbnailByteCountMaximum=\(MediaContractV1.thumbnailByteCountMaximum)",
        "registration=requiresVerifiedLifecycleAndLiveTargetPrerequisites;definitionLookupIsNotRegistration",
    ].joined(separator: "\n")

    static func release(codecID: String, codecVersion: UInt64, descriptor: String,
                        expectedSHA256: String) throws -> DraftPayloadCodecReleaseV1 {
        try CheckRunnerPhotoSourceMetadataProfileV1.validate()
        guard FieldDraftCanonicalCodecV1.sha256(Data(descriptor.utf8)) == expectedSHA256 else {
            throw FieldDraftFailureV1.digestMismatch
        }
        return try .init(codecID: codecID, codecVersion: codecVersion, releaseSHA256: expectedSHA256)
    }
}

enum CheckRunnerItemDraftCodecV1 {
    static let codecID = "assetrounds.check-runner-item.v1"
    static let codecVersion: UInt64 = 1
    static let maximumPayloadBytes = CheckRunnerItemDraftPayloadV1.maximumPayloadBytes
    static let grammarDescriptor = "codecID=\(codecID)\ncodecVersion=\(codecVersion)\n" + CheckRunnerDraftGrammarV1.descriptor
    static let releaseSHA256 = "e2f9c5cfa69006a5dc7f3bb86c36a030998afc1c8f8b421def6981dd42f72292"

    static func release() throws -> DraftPayloadCodecReleaseV1 {
        try CheckRunnerDraftGrammarV1.release(codecID: codecID, codecVersion: codecVersion,
            descriptor: grammarDescriptor, expectedSHA256: releaseSHA256)
    }

    static func definition() throws -> DraftPurposeDefinitionV1 {
        try .init(purpose: .inspectionReview, codec: release(), maximumPayloadBytes: maximumPayloadBytes,
            maximumStageItems: 0, targetCommandKind: .finalizeCheck, retention: .retireAfterCommit,
            attachmentKinds: [], privacyClass: .workspacePrivate)
    }

    static func encode(_ payload: CheckRunnerItemDraftPayloadV1) throws -> Data {
        _ = try release()
        return try CheckRunnerItemDraftPayloadV1.encode(payload)
    }

    static func decode(_ data: Data) throws -> CheckRunnerItemDraftPayloadV1 {
        _ = try release()
        return try CheckRunnerItemDraftPayloadV1.decode(data)
    }

    static func scope(source: CheckRunnerRoundItemSourceV1) throws -> DraftScopeKeyV1 {
        try source.validate()
        return try .init(scopeKind: DraftPurposeV1.inspectionReview.rawValue,
            stableComponentIDs: [source.roundAtEntry.sessionID.uuidString.lowercased(),
                                 source.originalItem.itemID.uuidString.lowercased()])
    }

    static func resumeAnchor(payload: CheckRunnerItemDraftPayloadV1) throws -> DraftResumeAnchorV1 {
        try payload.validate()
        return try payload.field.semanticAnchor.resumeAnchor(assetID: payload.source.assetID)
    }

    /// Pure envelope equality, usable for historical values. Current source,
    /// receipts, target state and permitted lifecycle operations are separate.
    static func validateCheckpoint(_ checkpoint: FieldDraftCheckpointV1) throws -> CheckRunnerItemDraftPayloadV1 {
        try checkpoint.validate(authority: CheckRunnerDraftPurposeAuthorityV1())
        guard checkpoint.codec == (try release()) else { throw FieldDraftFailureV1.unknownCodec }
        let payload = try decode(checkpoint.payloadData)
        guard checkpoint.workspaceID == payload.source.roundAtEntry.workspaceID,
              checkpoint.baseCanonicalRevision == payload.source.roundAtEntry.revision,
              checkpoint.scope == (try scope(source: payload.source)),
              checkpoint.resumeAnchor == (try resumeAnchor(payload: payload)),
              checkpoint.stageIDs.isEmpty else { throw FieldDraftFailureV1.invalidValue }
        return payload
    }
}

enum CheckRunnerPhotoDraftCodecV1 {
    static let codecID = "assetrounds.check-runner-photo.v1"
    static let codecVersion: UInt64 = 1
    static let maximumPayloadBytes = CheckRunnerPhotoDraftPayloadV1.maximumPayloadBytes
    static let grammarDescriptor = "codecID=\(codecID)\ncodecVersion=\(codecVersion)\n" + CheckRunnerDraftGrammarV1.descriptor
    static let releaseSHA256 = "91ab8725776d6c6508e2e1b937fbe4a89df487a99a58c4203328ba8e5bb4f5d2"

    static func release() throws -> DraftPayloadCodecReleaseV1 {
        try CheckRunnerDraftGrammarV1.release(codecID: codecID, codecVersion: codecVersion,
            descriptor: grammarDescriptor, expectedSHA256: releaseSHA256)
    }

    static func definition() throws -> DraftPurposeDefinitionV1 {
        try .init(purpose: .inspectionReview, codec: release(), maximumPayloadBytes: maximumPayloadBytes,
            maximumStageItems: 1, targetCommandKind: .acceptCheckEvidence, retention: .retireAfterCommit,
            attachmentKinds: [.photo], privacyClass: .restrictedEvidence)
    }

    static func encode(_ payload: CheckRunnerPhotoDraftPayloadV1) throws -> Data {
        _ = try release()
        return try CheckRunnerPhotoDraftPayloadV1.encode(payload)
    }

    static func decode(_ data: Data) throws -> CheckRunnerPhotoDraftPayloadV1 {
        _ = try release()
        return try CheckRunnerPhotoDraftPayloadV1.decode(data)
    }

    static func scope(payload: CheckRunnerPhotoDraftPayloadV1) throws -> DraftScopeKeyV1 {
        try payload.validate()
        return try .init(scopeKind: "INSPECTION_REVIEW_PHOTO",
            stableComponentIDs: [payload.parentDraftID.uuidString.lowercased(), payload.childDraftID.uuidString.lowercased()])
    }

    static func resumeAnchor(payload: CheckRunnerPhotoDraftPayloadV1) throws -> DraftResumeAnchorV1 {
        try payload.validate()
        return try .init(sectionID: payload.captureStep == .wide ? "wide_context" : "close_detail",
                         selectedStableID: payload.assetID.uuidString.lowercased())
    }

    /// Checks the stored child envelope without converting its frozen raw witness
    /// into a claim about the current stage, parent, manifest or writer receipts.
    static func validateCheckpoint(_ checkpoint: FieldDraftCheckpointV1) throws -> CheckRunnerPhotoDraftPayloadV1 {
        try checkpoint.validate(authority: CheckRunnerDraftPurposeAuthorityV1())
        guard checkpoint.codec == (try release()) else { throw FieldDraftFailureV1.unknownCodec }
        let payload = try decode(checkpoint.payloadData)
        guard checkpoint.draftID == payload.childDraftID,
              checkpoint.workspaceID == payload.workspaceID,
              checkpoint.baseCanonicalRevision == payload.sourceBinding.roundAtEntry.revision,
              checkpoint.scope == (try scope(payload: payload)),
              checkpoint.resumeAnchor == (try resumeAnchor(payload: payload)),
              checkpoint.stageIDs == payload.phase.declaredStageIDs else {
            throw FieldDraftFailureV1.invalidValue
        }
        return payload
    }
}

struct CheckRunnerDraftPurposeAuthorityV1: DraftPurposeDefinitionResolvingV1, Sendable {
    private let parent: DraftPurposeDefinitionV1
    private let photo: DraftPurposeDefinitionV1

    init() throws {
        parent = try CheckRunnerItemDraftCodecV1.definition()
        photo = try CheckRunnerPhotoDraftCodecV1.definition()
    }

    func require(_ purpose: DraftPurposeV1, codec: DraftPayloadCodecReleaseV1) throws -> DraftPurposeDefinitionV1 {
        guard purpose == .inspectionReview else { throw FieldDraftFailureV1.unknownPurpose }
        if codec == parent.codec { return parent }
        if codec == photo.codec { return photo }
        throw FieldDraftFailureV1.unknownCodec
    }
}

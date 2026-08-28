import Foundation

@MainActor protocol DraftRecoveryRecordSourceV1:AnyObject{
    func checkpoints(workspaceID:WorkspaceID)throws->[FieldDraftCheckpointV1]
    func stagingItems(workspaceID:WorkspaceID,draftID:UUID)throws->[AttachmentStagingItemV1]
    func currentTargetRevision(workspaceID:WorkspaceID,scope:DraftScopeKeyV1,targetCommandKind:WorkspaceCommandKindV1)throws->UInt64?
}

@MainActor final class DraftRecoveryProjectionCoordinatorV1{
    private let source:any DraftRecoveryRecordSourceV1;private let registry:DraftPurposeRegistryV1
    init(source:any DraftRecoveryRecordSourceV1,registry:DraftPurposeRegistryV1){self.source=source;self.registry=registry}
    func projections(workspaceID:WorkspaceID)throws->[DraftRecoveryProjectionV1]{
        let candidates=try source.checkpoints(workspaceID:workspaceID).filter{$0.workspaceID==workspaceID}
        guard candidates.count<=8_192 else{throw FieldDraftFailureV1.limitExceeded}
        try candidates.forEach{$0.validate()}
        var current:[UUID:FieldDraftCheckpointV1]=[:]
        for value in candidates{if let prior=current[value.draftID]{if value.draftRevision==prior.draftRevision&&value.checkpointSHA256 != prior.checkpointSHA256{throw FieldDraftFailureV1.conflictRequired};if value.draftRevision>prior.draftRevision{current[value.draftID]=value}}else{current[value.draftID]=value}}
        let checkpoints=current.values.filter{$0.state != .committed&&$0.state != .discarded}
        return try checkpoints.map{checkpoint in
            let definition=try? registry.require(checkpoint.purpose,codec:checkpoint.codec)
            let targetRevision=try definition.map{try source.currentTargetRevision(workspaceID:workspaceID,scope:checkpoint.scope,targetCommandKind:$0.targetCommandKind) ?? 0}
            let targetStale=targetRevision.map{$0 != checkpoint.baseCanonicalRevision} ?? false
            let items=try source.stagingItems(workspaceID:workspaceID,draftID:checkpoint.draftID).filter{$0.workspaceID==workspaceID&&$0.draftID==checkpoint.draftID}
            try items.forEach{$0.validate()}
            let ready=items.filter{$0.state == .readyLocal}.count
            let failed=items.filter{$0.state == .failedRetryable||$0.state == .failedFinal}.count
            let missing=checkpoint.stageIDs.filter{id in !items.contains(where:{$0.stageID==id})}.count
            let status:DraftRecoveryStatusV1;let action:DraftRecoverySafeActionV1
            if definition == nil{status = .unsupportedCodec;action = .openSafeParent}
            else if checkpoint.state == .conflicted{status = .conflict;action = .reviewConflict}
            else if checkpoint.state == .recoveryRequired{status = .recoveryRequired;action = .resumeReview}
            else if targetStale{status = .staleTarget;action = .reviewConflict}
            else if items.contains(where:{$0.protectionState == .protectedDataUnavailable}){status = .protectedData;action = .unlockDevice}
            else if items.contains(where:{$0.protectionState == .lowStorage}){status = .lowStorage;action = .freeStorage}
            else if missing>0{status = .missingMedia;action = .resumeReview}
            else if failed>0{status = .partialStage;action = .retryItem}
            else{status = .resumable;action = .resumeReview}
            return .init(workspaceID:workspaceID,draftID:checkpoint.draftID,purpose:checkpoint.purpose,status:status,safeAction:action,readyItemCount:ready,failedItemCount:failed,missingItemCount:missing,updatedAt:checkpoint.updatedAt)
        }.sorted{$0.updatedAt>$1.updatedAt}
    }
}

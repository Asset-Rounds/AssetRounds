import Foundation

@MainActor final class DictationLocationProposalCoordinatorV1 {
    private let policy:DictationLocationCapabilityPolicyV1
    private let access:any AppAccessGatePortV1
    private let speech:any SpeechCapabilityAdapterV1
    private let location:any OneShotLocationCapabilityAdapterV1
    private let scratch:any DictationAudioScratchLifecycleV1
    private let assistance:AssistanceCoordinatorV1

    init(policy:DictationLocationCapabilityPolicyV1,access:any AppAccessGatePortV1,
         speech:any SpeechCapabilityAdapterV1,
         location:any OneShotLocationCapabilityAdapterV1,
         scratch:any DictationAudioScratchLifecycleV1,
         assistance:AssistanceCoordinatorV1)throws{
        try policy.validate();self.policy=policy;self.access=access;self.speech=speech
        self.location=location;self.scratch=scratch;self.assistance=assistance
    }

    func currentSpeechPermission()async throws->SpeechPermissionDispositionV1{
        try await speech.permissionDisposition()
    }
    func currentLocationPermission()async throws->LocationPermissionDispositionV1{
        try await location.permissionDisposition()
    }
    func requestMicrophonePermission()async throws->SpeechPermissionDispositionV1{
        guard policy.dictationActivation == .enabledOnDevice else{throw DictationLocationProposalFailureV1.unavailable}
        try await speech.requestMicrophonePermission()
    }
    func requestSpeechRecognitionPermission()async throws->SpeechPermissionDispositionV1{
        guard policy.dictationActivation == .enabledOnDevice else{throw DictationLocationProposalFailureV1.unavailable}
        try await speech.requestSpeechRecognitionPermission()
    }
    func requestWhenInUseLocationPermission()async throws->LocationPermissionDispositionV1{
        guard policy.locationActivation == .enabledOnDevice else{throw DictationLocationProposalFailureV1.unavailable}
        try await location.requestWhenInUsePermission()
    }

    func dictate(_ request:OnDeviceDictationRequestV1)async throws->DictationLocationProposalOutcomeV1{
        try request.validate();_ = try await access.requireDictationProposalContentAccess()
        guard policy.dictationActivation == .enabledOnDevice,
              policy.supportedDictationLocales.contains(request.localeIdentifier) else{
            return .manualDictation(DictationManualFallbackV1.allCases)
        }
        let permission=try await speech.permissionDisposition()
        guard permission.permitsOnDeviceDictation else{
            return .manualDictation(DictationManualFallbackV1.allCases)
        }
        do{
            try await scratch.prepare(request)
            let value=try await speech.dictateOnDevice(request)
            guard value.permission == permission else{throw DictationLocationProposalFailureV1.permissionDenied}
            try value.validate(policy:policy)
            return .dictation(value)
        }catch{
            do{try await scratch.discardAfterFailedDictation(request)}
            catch{throw AssistanceContractFailureV1.scratchCleanupFailed}
            throw error
        }
    }

    func locate(_ request:OneShotLocationRequestV1)async throws->DictationLocationProposalOutcomeV1{
        try request.validate();_ = try await access.requireOneShotLocationProposalContentAccess()
        guard policy.locationActivation == .enabledOnDevice else{
            return .manualLocation(LocationManualFallbackV1.allCases)
        }
        let permission=try await location.permissionDisposition()
        guard permission.permitsOneShotForegroundLocation else{
            return .manualLocation(LocationManualFallbackV1.allCases)
        }
        let value=try await location.requestOneShotForegroundLocation(request)
        guard value.permission == permission else{throw DictationLocationProposalFailureV1.permissionDenied}
        try value.validate(policy:policy)
        return .location(value)
    }

    func present(_ value:OnDeviceDictationProposalV1,
                 context:AssistanceProposalEvaluationContextV1)async throws{
        try value.validate(policy:policy);try await assistance.present(value.proposal,context:context)
    }
    func present(_ value:OneShotLocationProposalV1,
                 context:AssistanceProposalEvaluationContextV1)async throws{
        try value.validate(policy:policy);try await assistance.present(value.proposal,context:context)
    }

    func accept(_ value:OnDeviceDictationProposalV1,
        targetMutation:AssistanceCanonicalTargetMutationV1,
        expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
        acceptedBy:ActorSnapshotV1,acceptedAt:Date,
        context:AssistanceProposalEvaluationContextV1)async throws->AssistanceAcceptanceReceiptV1{
        try value.validate(policy:policy)
        return try await assistance.accept(proposalID:value.proposal.proposalID,
            targetMutation:targetMutation,expectedRevision:expectedRevision,mutationID:mutationID,
            acceptedBy:acceptedBy,acceptedAt:acceptedAt,context:context)
    }
    func accept(_ value:OneShotLocationProposalV1,
        targetMutation:AssistanceCanonicalTargetMutationV1,
        expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
        acceptedBy:ActorSnapshotV1,acceptedAt:Date,
        context:AssistanceProposalEvaluationContextV1)async throws->AssistanceAcceptanceReceiptV1{
        try value.validate(policy:policy)
        return try await assistance.accept(proposalID:value.proposal.proposalID,
            targetMutation:targetMutation,expectedRevision:expectedRevision,mutationID:mutationID,
            acceptedBy:acceptedBy,acceptedAt:acceptedAt,context:context)
    }

    func applyReview(_ review:DictationLocationProposalReviewV1,
                     dictation:OnDeviceDictationProposalV1,
                     correctedProposalID:UUID?,
                     context:AssistanceProposalEvaluationContextV1)async throws->AssistanceProposalV1?{
        try dictation.validate(policy:policy)
        return try await applyReview(review,original:dictation.proposal,
            evidenceSHA256:dictation.proposalEvidenceSHA256,
            correctedProposalID:correctedProposalID,context:context)
    }
    func applyReview(_ review:DictationLocationProposalReviewV1,
                     location:OneShotLocationProposalV1,
                     correctedProposalID:UUID?,
                     context:AssistanceProposalEvaluationContextV1)async throws->AssistanceProposalV1?{
        try location.validate(policy:policy)
        return try await applyReview(review,original:location.proposal,
            evidenceSHA256:location.proposalEvidenceSHA256,
            correctedProposalID:correctedProposalID,context:context)
    }
    private func applyReview(_ review:DictationLocationProposalReviewV1,
        original:AssistanceProposalV1,evidenceSHA256:String,correctedProposalID:UUID?,
        context:AssistanceProposalEvaluationContextV1)async throws->AssistanceProposalV1?{
        try review.validate(originalProposalID:original.proposalID,
            evidenceSHA256:evidenceSHA256,originalValue:original.value)
        guard review.reviewedBy.workspaceID==original.target.workspaceID,
              review.reviewedAt>=original.createdAt,review.reviewedAt<original.expiresAt else{
            throw DictationLocationProposalFailureV1.staleTarget
        }
        switch review.disposition{
        case .rejected:
            guard correctedProposalID==nil else{throw DictationLocationProposalFailureV1.invalidValue}
            _=try await assistance.reject(proposalID:original.proposalID);return nil
        case .accepted:
            guard correctedProposalID==nil else{throw DictationLocationProposalFailureV1.invalidValue}
            return original
        case .edited:
            guard let correctedProposalID,let value=review.reviewedValue else{throw DictationLocationProposalFailureV1.invalidValue}
            let corrected=try original.correctedForAssistanceReview(proposalID:correctedProposalID,
                value:value,createdAt:review.reviewedAt)
            try await assistance.replaceForReview(originalProposalID:original.proposalID,
                with:corrected,context:context)
            return corrected
        }
    }

    func acceptReviewed(_ acceptedProposal:AssistanceProposalV1,
        dictation:OnDeviceDictationProposalV1,review:DictationLocationProposalReviewV1,
        targetMutation:AssistanceCanonicalTargetMutationV1,
        expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
        context:AssistanceProposalEvaluationContextV1)async throws->AssistanceAcceptanceReceiptV1{
        try dictation.validate(policy:policy)
        try DictationLocationReviewedAcceptanceV1.validate(dictation:dictation,review:review,
            acceptedProposal:acceptedProposal,targetMutation:targetMutation,
            expectedRevision:expectedRevision,mutationID:mutationID,context:context)
        let receipt=try await assistance.accept(proposalID:acceptedProposal.proposalID,
            targetMutation:targetMutation,expectedRevision:expectedRevision,mutationID:mutationID,
            acceptedBy:review.reviewedBy,acceptedAt:review.reviewedAt,context:context)
        try receipt.validate(dictation:dictation,review:review,acceptedProposal:acceptedProposal)
        return receipt
    }
    func acceptReviewed(_ acceptedProposal:AssistanceProposalV1,
        location:OneShotLocationProposalV1,review:DictationLocationProposalReviewV1,
        targetMutation:AssistanceCanonicalTargetMutationV1,
        expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
        context:AssistanceProposalEvaluationContextV1)async throws->AssistanceAcceptanceReceiptV1{
        try location.validate(policy:policy)
        try DictationLocationReviewedAcceptanceV1.validate(location:location,review:review,
            acceptedProposal:acceptedProposal,targetMutation:targetMutation,
            expectedRevision:expectedRevision,mutationID:mutationID,context:context)
        let receipt=try await assistance.accept(proposalID:acceptedProposal.proposalID,
            targetMutation:targetMutation,expectedRevision:expectedRevision,mutationID:mutationID,
            acceptedBy:review.reviewedBy,acceptedAt:review.reviewedAt,context:context)
        try receipt.validate(location:location,review:review,acceptedProposal:acceptedProposal)
        return receipt
    }

    func reject(_ proposal:AssistanceProposalV1)async throws->AssistanceRemovalDispositionV1{
        try proposal.validate();return try await assistance.reject(proposalID:proposal.proposalID)
    }
    func cancel(_ proposal:AssistanceProposalV1)async throws->AssistanceRemovalDispositionV1{
        try proposal.validate();return try await assistance.cancel(proposalID:proposal.proposalID)
    }
}

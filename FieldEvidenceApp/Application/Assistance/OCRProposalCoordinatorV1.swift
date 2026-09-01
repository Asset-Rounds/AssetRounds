import Foundation

/// AppAccess is always evaluated before the injected OCR provider can inspect
/// source content. Shipping activation remains disabled; manual entry is the
/// truthful production result until a later authorized activation card.
@MainActor final class OCRProposalCoordinatorV1 {
    private let policy: OCRCapabilityPolicyV1
    private let access: any AppAccessGatePortV1
    private let extractor: any OCRProposalExtractingV1
    private let scratch: any OCRProposalScratchLifecycleV1
    private let assistance: AssistanceCoordinatorV1

    init(policy: OCRCapabilityPolicyV1, access: any AppAccessGatePortV1,
         extractor: any OCRProposalExtractingV1, scratch: any OCRProposalScratchLifecycleV1,
         assistance: AssistanceCoordinatorV1) throws {
        try policy.validate();self.policy=policy;self.access=access
        self.extractor=extractor;self.scratch=scratch;self.assistance=assistance
    }

    func extractText(_ request: OCRExtractionRequestV1) async throws -> OCRProposalOutcomeV1 {
        try request.validate()
        let permit = try await access.requireOCRProposalContentAccess()
        try OCRProposalAppAccessBoundaryV1.validate(permit)
        guard Set(request.requestedLanguageIdentifiers).isSubset(of: Set(policy.supportedLanguageIdentifiers)) else {
            return .manualFallback(policy.manualFallback)
        }
        guard policy.activation == .enabledOnDevice else {
            return .manualFallback(policy.manualFallback)
        }
        do {
            try await scratch.prepare(request)
            let values = try await extractor.extract(request)
            guard values.count == 1, values[0].request == request,
                  values[0].proposal.proposalID == request.requestID else {
                throw OCRProposalFailureV1.invalidValue
            }
            try values[0].validate(policy:policy)
            return .proposals(values)
        } catch {
            do { try await scratch.discardAfterFailedExtraction(request) }
            catch { throw AssistanceContractFailureV1.scratchCleanupFailed }
            throw error
        }
    }

    func present(_ evidence: OCRProposalEvidenceV1,
                 context: AssistanceProposalEvaluationContextV1) async throws {
        try evidence.validate(policy:policy)
        try await assistance.present(evidence.proposal, context: context)
    }

    func accept(_ evidence: OCRProposalEvidenceV1,
                targetMutation: AssistanceCanonicalTargetMutationV1,
                expectedRevision: WorkspaceExpectedRevisionV1,
                mutationID: MutationIDV1, acceptedBy: ActorSnapshotV1,
                acceptedAt: Date, context: AssistanceProposalEvaluationContextV1) async throws -> AssistanceAcceptanceReceiptV1 {
        try evidence.validate(policy:policy)
        return try await assistance.accept(proposalID:evidence.proposal.proposalID,
            targetMutation:targetMutation,expectedRevision:expectedRevision,mutationID:mutationID,
            acceptedBy:acceptedBy,acceptedAt:acceptedAt,context:context)
    }

    func acceptReviewed(_ proposal:AssistanceProposalV1,review:OCRFieldReviewV1,
        evidence:OCRProposalEvidenceV1,targetMutation:AssistanceCanonicalTargetMutationV1,
        expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
        acceptedBy:ActorSnapshotV1,acceptedAt:Date,
        context:AssistanceProposalEvaluationContextV1)async throws->AssistanceAcceptanceReceiptV1{
        try evidence.validate(policy:policy);try review.validate(evidence:evidence);try proposal.validate()
        guard review.disposition != .rejected,review.reviewedValue==proposal.value,
              proposal.target==evidence.proposal.target,proposal.source==evidence.proposal.source,
              proposal.capability==evidence.proposal.capability,proposal.quality==evidence.proposal.quality else{throw OCRProposalFailureV1.invalidValue}
        return try await assistance.accept(proposalID:proposal.proposalID,targetMutation:targetMutation,
            expectedRevision:expectedRevision,mutationID:mutationID,acceptedBy:acceptedBy,
            acceptedAt:acceptedAt,context:context)
    }

    func reject(_ evidence: OCRProposalEvidenceV1) async throws -> AssistanceRemovalDispositionV1 {
        try evidence.validate(policy:policy);return try await assistance.reject(proposalID:evidence.proposal.proposalID)
    }

    func cancel(_ evidence: OCRProposalEvidenceV1) async throws -> AssistanceRemovalDispositionV1 {
        try evidence.validate(policy:policy);return try await assistance.cancel(proposalID:evidence.proposal.proposalID)
    }

    /// Materializes the exact per-field review. Edited text becomes a fresh
    /// unverified proposal; it still requires the ordinary explicit accept API.
    func applyReview(_ review: OCRFieldReviewV1, evidence: OCRProposalEvidenceV1,
                     correctedProposalID: UUID?,
                     context: AssistanceProposalEvaluationContextV1) async throws -> AssistanceProposalV1? {
        try evidence.validate(policy:policy);try review.validate(evidence:evidence)
        switch review.disposition {
        case .rejected:
            _ = try await reject(evidence); return nil
        case .accepted:
            guard correctedProposalID == nil else { throw OCRProposalFailureV1.invalidValue }
            return evidence.proposal
        case .edited:
            guard let correctedProposalID, let value=review.reviewedValue else { throw OCRProposalFailureV1.invalidValue }
            _ = try await assistance.reject(proposalID:evidence.proposal.proposalID)
            let corrected=try evidence.proposal.correctedForOCR(proposalID:correctedProposalID,
                value:value,createdAt:review.reviewedAt,expiresAt:evidence.proposal.expiresAt)
            try await assistance.present(corrected,context:context)
            return corrected
        }
    }
}

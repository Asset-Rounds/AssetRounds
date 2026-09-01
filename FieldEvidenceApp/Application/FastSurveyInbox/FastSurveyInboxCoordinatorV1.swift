import Foundation

/// Coordinates C11's local inbox through the incumbent canonical writer.
/// It intentionally owns neither bytes nor a persistence store: capture,
/// promotion, and snippet history become true only after the writer returns a
/// durable typed receipt. Snippet insertion is an explicit preview, never a
/// canonical answer or observation.
@MainActor
final class FastSurveyInboxCoordinatorV1 {
    typealias Submit = (FastSurveyInboxMutationCommandV1) throws -> FastSurveyInboxMutationReceiptV1
    typealias Query = (FastSurveyInboxQueryV1) throws -> FastSurveyInboxQueryResultV1
    typealias ReceiptLookup = (FastSurveyInboxMutationCommandV1) throws -> FastSurveyInboxMutationReceiptV1?

    enum ActionResult: Equatable, Sendable {
        case captured(CaptureInboxItemV1, FastSurveyInboxMutationReceiptV1)
        case promoted(CapturePromotionV1, CaptureInboxItemV1, FastSurveyInboxMutationReceiptV1)
        case snippetSaved(SnippetV1, FastSurveyInboxMutationReceiptV1)
        case insertionPreview(SnippetInsertionPreviewV1)
        case insertionSaved(SnippetInsertionV1, FastSurveyInboxMutationReceiptV1)
        case queried(FastSurveyInboxQueryResultV1)
        case cancelled
    }

    private let submit: Submit
    private let query: Query
    private let receiptLookup: ReceiptLookup

    init(
        submit: @escaping Submit,
        query: @escaping Query,
        receiptLookup: @escaping ReceiptLookup
    ) {
        self.submit = submit
        self.query = query
        self.receiptLookup = receiptLookup
    }

    /// The supplied query is read-only and must be sourced from the lifecycle
    /// owner. This production binding introduces no second writer or store.
    convenience init(
        workspaceWriter: WorkspaceWriterV1,
        query: @escaping Query
    ) {
        self.init(
            submit: { try workspaceWriter.commitFastSurveyInbox($0) },
            query: query,
            receiptLookup: { try workspaceWriter.fastSurveyInboxReceipt(for: $0) }
        )
    }

    func capture(
        item: CaptureInboxItemV1,
        admission: FastSurveyInboxCaptureAdmissionV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        submittedAt: Date
    ) throws -> ActionResult {
        try item.validate()
        try admission.requireAdmission()
        guard admission.workspaceID == item.workspaceID,
              item.workspaceID == expectedRevision.workspaceID else {
            throw FastSurveyInboxFailureV1.wrongWorkspace
        }
        let command = try makeCommand(
            workspaceID: item.workspaceID,
            expectedRevision: expectedRevision,
            mutationID: item.mutationID,
            payload: .putInboxItem(item),
            admission: .capture(admission),
            submittedAt: submittedAt
        )
        return .captured(item, try submitOrRecover(command))
    }

    /// Promotion is always destination-typed and revision-bound. The core
    /// contract verifies that the promoted item is a successor of the original
    /// immutable inbox item and preserves its content/provenance byte binding.
    func promote(
        promotion: CapturePromotionV1,
        promotedItem: CaptureInboxItemV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        submittedAt: Date
    ) throws -> ActionResult {
        try promotedItem.validate()
        guard promotion.workspaceID == promotedItem.workspaceID,
              promotion.workspaceID == expectedRevision.workspaceID else {
            throw FastSurveyInboxFailureV1.wrongWorkspace
        }
        let command = try makeCommand(
            workspaceID: promotion.workspaceID,
            expectedRevision: expectedRevision,
            mutationID: promotion.mutationID,
            payload: .promote(promotion, promotedItem),
            admission: .notApplicable,
            submittedAt: submittedAt
        )
        return .promoted(promotion, promotedItem, try submitOrRecover(command))
    }

    /// Create, edit, and retirement all use a versioned snippet postimage.
    /// The result is only a saved local aid; it does not insert text anywhere.
    func saveSnippet(
        _ snippet: SnippetV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        submittedAt: Date
    ) throws -> ActionResult {
        try snippet.validate()
        guard snippet.workspaceID == expectedRevision.workspaceID else {
            throw FastSurveyInboxFailureV1.wrongWorkspace
        }
        let command = try makeCommand(
            workspaceID: snippet.workspaceID,
            expectedRevision: expectedRevision,
            mutationID: snippet.mutationID,
            payload: .putSnippet(snippet),
            admission: .notApplicable,
            submittedAt: submittedAt
        )
        return .snippetSaved(snippet, try submitOrRecover(command))
    }

    func previewInsertion(
        snippet: SnippetV1,
        targetDraftID: UUID,
        targetDraftRevision: UInt64
    ) throws -> ActionResult {
        .insertionPreview(try SnippetInsertionPreviewV1(
            snippet: snippet,
            targetDraftID: targetDraftID,
            targetDraftRevision: targetDraftRevision
        ))
    }

    /// Preview remains zero-write. Persisting frozen text requires an explicit
    /// user-save insertion whose target identity, revision, and digest are
    /// independently re-resolved by the canonical writer transaction.
    func saveInsertion(
        _ insertion: SnippetInsertionV1,
        snippet: SnippetV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        submittedAt: Date
    ) throws -> ActionResult {
        try insertion.validate(snippet: snippet)
        guard insertion.workspaceID == expectedRevision.workspaceID,
              snippet.workspaceID == expectedRevision.workspaceID else {
            throw FastSurveyInboxFailureV1.wrongWorkspace
        }
        let command = try makeCommand(
            workspaceID: insertion.workspaceID,
            expectedRevision: expectedRevision,
            mutationID: insertion.mutationID,
            payload: .insertSnippet(insertion, snippet),
            admission: .notApplicable,
            submittedAt: submittedAt
        )
        return .insertionSaved(insertion, try submitOrRecover(command))
    }

    func projection(_ request: FastSurveyInboxQueryV1) throws -> ActionResult {
        .queried(try query(request))
    }

    func cancel() -> ActionResult { .cancelled }

    /// Commits only explicitly accepted/edited values. The complete batch is
    /// validated before the first write, and each request is bound to the same
    /// exact target mutation used by keyboard/paste/manual entry.
    func applyReviewedOCRFields(
        _ batch: FastSurveyInboxOCRReviewBatchV1,
        targetMutations: [UUID: AssistanceCanonicalTargetMutationV1],
        manualEquivalentMutations: [UUID: AssistanceCanonicalTargetMutationV1],
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationIDs: [UUID: MutationIDV1],
        workspaceWriter: WorkspaceWriterV1
    ) throws -> FastSurveyInboxOCRReviewOutcomeV1 {
        guard batch.workspaceID == expectedRevision.workspaceID,
              Set(mutationIDs.values.map { $0.rawValue }).count == mutationIDs.count else {
            throw FastSurveyInboxFailureV1.staleRevision
        }
        var requests: [AssistanceAcceptanceRequestV1] = []
        var rejected: [UUID] = []
        for index in batch.evidence.indices {
            let review = batch.reviews[index]
            guard let proposal = try batch.reviewedProposal(at: index) else {
                rejected.append(review.proposalID)
                continue
            }
            guard let target = targetMutations[review.proposalID],
                  let manual = manualEquivalentMutations[review.proposalID],
                  let mutationID = mutationIDs[review.proposalID], target == manual else {
                throw FastSurveyInboxFailureV1.invalidPromotion
            }
            let request = try AssistanceAcceptanceRequestV1(
                proposal: proposal, targetMutation: target,
                expectedRevision: expectedRevision, mutationID: mutationID,
                acceptedBy: review.reviewedBy, acceptedAt: review.reviewedAt
            )
            try request.validateManualPathEquivalence(to: manual)
            requests.append(request)
        }
        let acceptedIDs = Set(requests.map { $0.proposal.proposalID })
        guard Set(targetMutations.keys) == acceptedIDs,
              Set(manualEquivalentMutations.keys) == acceptedIDs,
              Set(mutationIDs.keys) == acceptedIDs else {
            throw FastSurveyInboxFailureV1.invalidPromotion
        }
        let evidenceByProposal = Dictionary(uniqueKeysWithValues:
            batch.evidence.map { ($0.proposal.proposalID, $0) })
        let reviewByProposal = Dictionary(uniqueKeysWithValues:
            batch.reviews.map { ($0.proposalID, $0) })
        let receipts = try requests.map { request -> AssistanceAcceptanceReceiptV1 in
            let receipt = try workspaceWriter.commitAssistanceAcceptance(request)
            try receipt.validate(request: request)
            if reviewByProposal[request.proposal.proposalID]?.disposition == .accepted,
               let evidence = evidenceByProposal[request.proposal.proposalID] {
                try receipt.validate(ocrEvidence: evidence)
            }
            return receipt
        }
        return .reviewed(receipts: receipts, rejectedProposalIDs: rejected.sorted { $0.uuidString < $1.uuidString })
    }

    func applyReviewedAssistedCaptureFields(
        _ batch: AssistedCaptureReviewBatchV1,
        targetMutations: [UUID: AssistanceCanonicalTargetMutationV1],
        manualEquivalentMutations: [UUID: AssistanceCanonicalTargetMutationV1],
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationIDs: [UUID: MutationIDV1],
        workspaceWriter: WorkspaceWriterV1
    ) throws -> FastSurveyInboxOCRReviewOutcomeV1 {
        guard batch.workspaceID==expectedRevision.workspaceID,
              Set(mutationIDs.values.map{$0.rawValue}).count==mutationIDs.count else{throw FastSurveyInboxFailureV1.staleRevision}
        let accepted=batch.reviews.filter{$0.disposition != .rejected}
        let acceptedIDs=Set(accepted.map{$0.source.proposal.proposalID})
        guard Set(targetMutations.keys)==acceptedIDs,Set(manualEquivalentMutations.keys)==acceptedIDs,
              Set(mutationIDs.keys)==acceptedIDs else{throw FastSurveyInboxFailureV1.invalidPromotion}
        var requests:[AssistanceAcceptanceRequestV1]=[]
        for review in accepted {
            let id=review.source.proposal.proposalID
            guard let proposal=try review.canonicalProposal(),let target=targetMutations[id],
                  let manual=manualEquivalentMutations[id],target==manual,let mutationID=mutationIDs[id] else{
                throw FastSurveyInboxFailureV1.invalidPromotion
            }
            let request=try AssistanceAcceptanceRequestV1(proposal:proposal,targetMutation:target,
                expectedRevision:expectedRevision,mutationID:mutationID,acceptedBy:review.reviewedBy,
                acceptedAt:review.reviewedAt)
            try request.validateManualPathEquivalence(to:manual);requests.append(request)
        }
        let reviewsByID=Dictionary(uniqueKeysWithValues:batch.reviews.map{($0.source.proposal.proposalID,$0)})
        let receipts=try requests.map{request in
            let receipt=try workspaceWriter.commitAssistanceAcceptance(request);try receipt.validate(request:request)
            if let reviewed=reviewsByID[request.proposal.proposalID],reviewed.disposition == .accepted{
                switch reviewed.source{case .dictation(let value):try receipt.validate(dictation:value);case .location(let value):try receipt.validate(location:value)}
            }
            return receipt
        }
        return .reviewed(receipts:receipts,rejectedProposalIDs:batch.reviews.filter{$0.disposition == .rejected}.map{$0.source.proposal.proposalID}.sorted{$0.uuidString<$1.uuidString})
    }

    private func submitOrRecover(
        _ command: FastSurveyInboxMutationCommandV1
    ) throws -> FastSurveyInboxMutationReceiptV1 {
        try command.validate()
        if let existing = try receiptLookup(command) {
            try existing.validate(command: command)
            return existing
        }
        let receipt = try submit(command)
        try receipt.validate(command: command)
        return receipt
    }

    private func makeCommand(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        payload: FastSurveyInboxMutationPayloadV1,
        admission: FastSurveyInboxMutationAdmissionV1,
        submittedAt: Date
    ) throws -> FastSurveyInboxMutationCommandV1 {
        try .init(
            commandID: UUID(),
            workspaceID: workspaceID,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            payload: payload,
            admission: admission,
            submittedAt: submittedAt
        )
    }
}

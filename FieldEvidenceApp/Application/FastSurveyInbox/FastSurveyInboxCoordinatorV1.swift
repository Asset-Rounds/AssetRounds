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

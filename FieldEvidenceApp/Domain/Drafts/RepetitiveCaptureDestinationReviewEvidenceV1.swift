import Foundation

/// Historical first-create evidence. Only this reader can construct it after
/// complete history validation and retained-source reconstruction. It grants
/// no current-state, restore-publication, continuation or effect authority.
struct RepetitiveCaptureDestinationReviewEvidenceV1: Equatable, Sendable {
    let original: RepetitiveCaptureSourceHistoryRecordV2
    let checkpoint: FieldDraftCheckpointV1
    let payload: RepetitiveCaptureDestinationReviewPayloadV1
    let retainedSource: RepetitiveCaptureRetainedOriginalsV2

    fileprivate init(original: RepetitiveCaptureSourceHistoryRecordV2,
                     checkpoint: FieldDraftCheckpointV1,
                     payload: RepetitiveCaptureDestinationReviewPayloadV1,
                     retainedSource: RepetitiveCaptureRetainedOriginalsV2) {
        self.original = original
        self.checkpoint = checkpoint
        self.payload = payload
        self.retainedSource = retainedSource
    }
}

enum RepetitiveCaptureDestinationReviewHistoryV1 {
    /// Import callers must supply full projection coverage. The live-journal
    /// overload below preserves foreign originals without current source rows.
    static func firstReview(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                            in snapshot: MutationHistorySnapshotV1) throws
        -> RepetitiveCaptureDestinationReviewEvidenceV1 {
        let facts = try MutationJournalStoreV1.validatedImportedSnapshotFacts(snapshot)
        return try firstReview(workspaceID: workspaceID, mutationID: mutationID,
            in: snapshot, validatedBy: facts)
    }

    static func firstReview(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                            in snapshot: MutationHistorySnapshotV1,
                            validatedBy facts: MutationHistoryImportedValidationFactsV1) throws
        -> RepetitiveCaptureDestinationReviewEvidenceV1 {
        guard facts.receiptStableKeys(matching: snapshot) != nil else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return try reconstruct(workspaceID: workspaceID, mutationID: mutationID,
            snapshot: snapshot) { reference in
                try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
                    for: reference, in: snapshot, validatedBy: facts)
            }
    }

    static func firstReview(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                            in history: RepetitiveCaptureRetainedJournalHistoryV2) throws
        -> RepetitiveCaptureDestinationReviewEvidenceV1 {
        try reconstruct(workspaceID: workspaceID, mutationID: mutationID,
            snapshot: history.snapshot) { reference in
                try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(for: reference, in: history)
            }
    }

    private static func reconstruct(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                                    snapshot: MutationHistorySnapshotV1,
                                    source: (RepetitiveCaptureSourceGraphReferenceV2) throws
                                        -> RepetitiveCaptureRetainedOriginalsV2) throws
        -> RepetitiveCaptureDestinationReviewEvidenceV1 {
        let history = try RepetitiveCaptureSourceGraphReviewV2.History(snapshot: snapshot)
        let original = try history.authenticated(workspaceID: workspaceID, mutationID: mutationID)
        // Complete history validation owns reversal metadata. Preserve its
        // original bytes rather than inventing a review-specific prohibition.
        guard !history.isQuarantined(original) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let committed = try FieldDraftCommittedEvidenceV1(envelope: original.envelope, receipt: original.receipt)
        guard case let .createCheckpoint(checkpoint) = committed.mutation.postImage,
              committed.mutation.expectedRevision == 0,
              committed.mutation.expectedBaseCanonicalRevision == checkpoint.baseCanonicalRevision else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        try RepetitiveCaptureDestinationReviewCodecV1.validateInitialCheckpoint(checkpoint,
            creationGenerationID: original.envelope.expectedRevision.generationID)
        let payload = try RepetitiveCaptureDestinationReviewCodecV1.decode(checkpoint.payloadData)
        guard payload.provenance.immediatePredecessor == nil else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let retained = try source(payload.source)
        try payload.validateFirstSource(against: retained)
        // Derivation must still be fresh with respect to the preserved source
        // identities; a self-consistent create receipt cannot waive collisions.
        var unavailable = Set(payload.provenance.ultimateToDestinationPairs.flatMap { [$0.sourceID, $0.destinationID] })
        unavailable.formUnion(retained.requiredHistory.map { $0.envelope.mutationID.rawValue })
        guard !unavailable.contains(checkpoint.draftID),
              !unavailable.contains(checkpoint.mutationID.rawValue),
              checkpoint.draftID != checkpoint.mutationID.rawValue else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        // This exact original remains useful after subsequent lifecycle
        // mutations. Do not pretend it authenticates their current frontier.
        return .init(original: original, checkpoint: checkpoint, payload: payload, retainedSource: retained)
    }
}

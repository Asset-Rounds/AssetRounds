import Foundation

/// An anchored historical command prefix. State values are preserved history,
/// not proof of a current target, approved disposition or operational draft.
struct RepetitiveCaptureReviewHistoryV1: Equatable, Sendable {
    let initialCheckpoint: FieldDraftCheckpointV1
    let checkpoint: FieldDraftCheckpointV1
    let payload: RepetitiveCaptureDestinationReviewPayloadV1
    let anchor: RepetitiveCaptureSourceHistoryRecordV2
    let prefix: [RepetitiveCaptureSourceHistoryRecordV2]

    fileprivate init(initialCheckpoint: FieldDraftCheckpointV1, checkpoint: FieldDraftCheckpointV1,
                     payload: RepetitiveCaptureDestinationReviewPayloadV1,
                     anchor: RepetitiveCaptureSourceHistoryRecordV2,
                     prefix: [RepetitiveCaptureSourceHistoryRecordV2]) {
        self.initialCheckpoint = initialCheckpoint
        self.checkpoint = checkpoint
        self.payload = payload
        self.anchor = anchor
        self.prefix = prefix
    }
}

/// Journal-derived, flat ancestry with exact originals. Construction is sealed
/// here; it never conveys a live lease, target approval, CAS or effect permit.
struct RepetitiveCaptureReviewLineageV1: Equatable, Sendable {
    let selectedReview: RepetitiveCaptureReviewHistoryV1
    let reviews: [RepetitiveCaptureReviewHistoryV1] // Oldest to selected.
    let retainedSource: RepetitiveCaptureRetainedOriginalsV2
    let requiredHistory: [RepetitiveCaptureSourceHistoryRecordV2]

    fileprivate init(selectedReview: RepetitiveCaptureReviewHistoryV1,
                     reviews: [RepetitiveCaptureReviewHistoryV1],
                     retainedSource: RepetitiveCaptureRetainedOriginalsV2,
                     requiredHistory: [RepetitiveCaptureSourceHistoryRecordV2]) {
        self.selectedReview = selectedReview
        self.reviews = reviews
        self.retainedSource = retainedSource
        self.requiredHistory = requiredHistory
    }
}

enum RepetitiveCaptureReviewLineageReaderV1 {
    static func read(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                     in snapshot: MutationHistorySnapshotV1) throws -> RepetitiveCaptureReviewLineageV1 {
        let facts = try MutationJournalStoreV1.validatedImportedSnapshotFacts(snapshot)
        return try read(workspaceID: workspaceID, mutationID: mutationID, in: snapshot, validatedBy: facts)
    }

    static func read(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                     in snapshot: MutationHistorySnapshotV1,
                     validatedBy facts: MutationHistoryImportedValidationFactsV1) throws
        -> RepetitiveCaptureReviewLineageV1 {
        guard facts.receiptStableKeys(matching: snapshot) != nil else { throw invalid() }
        return try reconstruct(workspaceID: workspaceID, mutationID: mutationID, snapshot: snapshot) { first in
            try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
                workspaceID: first.initialCheckpoint.workspaceID,
                mutationID: first.initialCheckpoint.mutationID, in: snapshot, validatedBy: facts)
        }
    }

    static func read(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                     in history: RepetitiveCaptureRetainedJournalHistoryV2) throws
        -> RepetitiveCaptureReviewLineageV1 {
        try reconstruct(workspaceID: workspaceID, mutationID: mutationID, snapshot: history.snapshot) { first in
            try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
                workspaceID: first.initialCheckpoint.workspaceID,
                mutationID: first.initialCheckpoint.mutationID, in: history)
        }
    }

    private static func reconstruct(workspaceID: WorkspaceID, mutationID: MutationIDV1,
                                    snapshot: MutationHistorySnapshotV1,
                                    firstEvidence: (RepetitiveCaptureReviewHistoryV1) throws
                                        -> RepetitiveCaptureDestinationReviewEvidenceV1) throws
        -> RepetitiveCaptureReviewLineageV1 {
        let cap = MutationJournalStoreV1.maximumReceiptValidationCount
        guard !snapshot.receipts.isEmpty, snapshot.receipts.count <= cap else { throw invalid() }
        let history = try RepetitiveCaptureSourceGraphReviewV2.History(snapshot: snapshot)
        var pending = try history.authenticated(workspaceID: workspaceID, mutationID: mutationID)
        var visited = Set<String>()
        var drafts = Set<RepetitiveCaptureSourceGraphReviewV2.WorkspaceObjectKey>()
        var descending: [RepetitiveCaptureReviewHistoryV1] = []
        while true {
            guard visited.insert(pending.receipt.identity.stableKey).inserted,
                  visited.count <= cap else { throw invalid() }
            let review = try prefix(through: pending, history: history)
            guard drafts.insert(.init(workspaceID: review.checkpoint.workspaceID,
                                      id: review.checkpoint.draftID)).inserted else { throw invalid() }
            descending.append(review)
            guard let predecessor = review.payload.provenance.immediatePredecessor else { break }
            pending = try history.authenticated(workspaceID: predecessor.workspaceID,
                                                 mutationID: predecessor.reviewMutationID)
        }
        let reviews = Array(descending.reversed())
        guard let first = reviews.first, let selected = reviews.last else { throw invalid() }
        let root = try firstEvidence(first)
        guard root.payload == first.payload, root.checkpoint == first.initialCheckpoint else { throw invalid() }
        var originals = Dictionary(uniqueKeysWithValues: root.retainedSource.requiredHistory.map {
            (RepetitiveCaptureSourceGraphReviewV2.key($0.envelope), $0)
        })
        var unavailable = Set(root.retainedSource.requiredHistory.map { $0.envelope.mutationID.rawValue })
        var previous: RepetitiveCaptureReviewHistoryV1?
        for review in reviews {
            guard review.payload.source == root.payload.source else { throw invalid() }
            if let previous {
                try review.payload.validatePredecessor(against: previous.payload, original: previous.anchor,
                                                       checkpoint: previous.checkpoint)
            } else {
                guard review.payload.provenance.immediatePredecessor == nil else { throw invalid() }
            }
            let pairIDs = Set(review.payload.provenance.ultimateToDestinationPairs.flatMap {
                [$0.sourceID, $0.destinationID]
            })
            let initial = review.initialCheckpoint
            guard !unavailable.contains(initial.draftID), !unavailable.contains(initial.mutationID.rawValue),
                  !pairIDs.contains(initial.draftID), !pairIDs.contains(initial.mutationID.rawValue),
                  initial.draftID != initial.mutationID.rawValue else { throw invalid() }
            unavailable.formUnion(pairIDs)
            unavailable.insert(initial.draftID)
            for original in review.prefix {
                let key = RepetitiveCaptureSourceGraphReviewV2.key(original.envelope)
                if let existing = originals[key] { guard existing == original else { throw invalid() } }
                originals[key] = original
                guard originals.count <= cap else { throw invalid() }
                unavailable.insert(original.envelope.mutationID.rawValue)
            }
            previous = review
        }
        return .init(selectedReview: selected, reviews: reviews, retainedSource: root.retainedSource,
                     requiredHistory: originals.values.sorted(by: RepetitiveCaptureSourceGraphReviewV2.recordLess))
    }

    private static func prefix(through anchor: RepetitiveCaptureSourceHistoryRecordV2,
                               history: RepetitiveCaptureSourceGraphReviewV2.History) throws
        -> RepetitiveCaptureReviewHistoryV1 {
        let anchorEvidence = try FieldDraftCommittedEvidenceV1(envelope: anchor.envelope, receipt: anchor.receipt)
        guard let tip = RepetitiveCaptureSourceGraphReviewV2.checkpointPostImage(anchorEvidence.mutation.postImage)
        else { throw invalid() }
        try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(tip)
        let payload = try RepetitiveCaptureDestinationReviewCodecV1.decode(tip.payloadData)
        var candidates: [(record: RepetitiveCaptureSourceHistoryRecordV2, checkpoint: FieldDraftCheckpointV1)] = []
        for record in history.fieldDraftHistory(workspaceID: tip.workspaceID, draftID: tip.draftID) {
            guard case let .applyFieldDraft(mutation) = record.envelope.command,
                  let checkpoint = RepetitiveCaptureSourceGraphReviewV2.checkpointPostImage(mutation.postImage)
            else { throw invalid() } // Review codecs have no stage, reservation or saga stream.
            if checkpoint.draftRevision <= tip.draftRevision { candidates.append((record, checkpoint)) }
        }
        candidates.sort {
            $0.checkpoint.draftRevision == $1.checkpoint.draftRevision
                ? $0.record.receipt.identity.stableKey < $1.record.receipt.identity.stableKey
                : $0.checkpoint.draftRevision < $1.checkpoint.draftRevision
        }
        guard let first = candidates.first,
              case let .applyFieldDraft(firstMutation) = first.record.envelope.command,
              case .createCheckpoint = firstMutation.postImage else { throw invalid() }
        try RepetitiveCaptureDestinationReviewCodecV1.validateInitialCheckpoint(first.checkpoint,
            creationGenerationID: first.record.envelope.expectedRevision.generationID)
        var previous: FieldDraftCheckpointV1?
        var previousReceipt: MutationReceiptV1?
        var originals: [RepetitiveCaptureSourceHistoryRecordV2] = []
        for candidate in candidates {
            let record = try history.authenticated(RepetitiveCaptureSourceGraphReviewV2.key(candidate.record.envelope))
            guard !history.isQuarantined(record) else { throw invalid() }
            let evidence = try FieldDraftCommittedEvidenceV1(envelope: record.envelope, receipt: record.receipt)
            let value = candidate.checkpoint
            try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(value)
            guard value.workspaceID == tip.workspaceID, value.draftID == tip.draftID,
                  value.payloadData == first.checkpoint.payloadData,
                  value.mutationID == evidence.mutation.mutationID else { throw invalid() }
            if let previous, let previousReceipt {
                guard record.envelope.expectedRevision.workspaceRevision >= previousReceipt.resultingRevision.workspaceRevision,
                      record.receipt.resultingRevision.workspaceRevision > previousReceipt.resultingRevision.workspaceRevision
                else { throw invalid() }
                try transition(evidence.mutation, from: previous, to: value)
            } else {
                guard case .createCheckpoint = evidence.mutation.postImage,
                      evidence.mutation.expectedRevision == 0,
                      evidence.mutation.expectedBaseCanonicalRevision == value.baseCanonicalRevision else { throw invalid() }
            }
            previous = value
            previousReceipt = record.receipt
            originals.append(record)
        }
        guard previous == tip, originals.last == anchor else { throw invalid() }
        return .init(initialCheckpoint: first.checkpoint, checkpoint: tip, payload: payload,
                     anchor: anchor, prefix: originals)
    }

    private static func transition(_ mutation: FieldDraftMutationV1,
                                   from previous: FieldDraftCheckpointV1,
                                   to value: FieldDraftCheckpointV1) throws {
        switch mutation.postImage {
        case .reviseCheckpoint:
            try value.validateSuccessor(of: previous, expectedDraftRevision: mutation.expectedRevision,
                                        expectedBaseRevision: mutation.expectedBaseCanonicalRevision)
            // Generic navigation/recovery cannot stand in for an explicit
            // reviewed choice that activates or starts discard from REQUIRED.
            if [.recoveryRequired, .conflicted].contains(previous.state),
               [.active, .discardPending].contains(value.state) { throw invalid() }
        case let .resolveConflict(resolution):
            try resolution.validate()
            guard resolution.expectedCheckpoint == previous,
                  resolution.successorCheckpoint == value,
                  mutation.expectedRevision == previous.draftRevision,
                  mutation.expectedBaseCanonicalRevision == previous.baseCanonicalRevision else { throw invalid() }
            // This preserves a typed historical command; target-specific
            // C36 disposition approval is a separate, still-required boundary.
        case let .applyDiscardTerminal(bundle):
            try bundle.validate()
            try value.validateSuccessor(of: previous, expectedDraftRevision: mutation.expectedRevision,
                                        expectedBaseRevision: mutation.expectedBaseCanonicalRevision)
            guard previous.state == .discardPending else { throw invalid() }
        default: throw invalid()
        }
    }

    private static func invalid() -> WorkspaceMutationFailureV1 { .receiptHistoryCorrupt }
}

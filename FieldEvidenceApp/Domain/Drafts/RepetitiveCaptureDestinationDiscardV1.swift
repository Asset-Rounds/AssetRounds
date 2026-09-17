import Foundation

/// Frozen confirmation values, not a lease or permission to write. No source
/// item, media file or Round belongs to this review's empty-content discard.
struct RepetitiveCaptureDestinationDiscardProposalV1: Equatable, Sendable {
    let expectedCheckpoint: FieldDraftCheckpointV1
    let plan: DraftDiscardPlanV1
    let terminalBundle: DraftDiscardTerminalBundleV1

    fileprivate init(expectedCheckpoint: FieldDraftCheckpointV1, plan: DraftDiscardPlanV1,
                     terminalBundle: DraftDiscardTerminalBundleV1) {
        self.expectedCheckpoint = expectedCheckpoint
        self.plan = plan
        self.terminalBundle = terminalBundle
    }

    var mutation: FieldDraftMutationV1 {
        get throws {
            try .init(workspaceID: expectedCheckpoint.workspaceID,
                expectedRevision: expectedCheckpoint.draftRevision,
                expectedBaseCanonicalRevision: expectedCheckpoint.baseCanonicalRevision,
                mutationID: terminalBundle.mutationID, postImage: .applyDiscardTerminal(terminalBundle))
        }
    }
}

/// Exact historical originals. This acknowledgement grants no current access,
/// operational continuation or authority over a retained source graph.
struct RepetitiveCaptureDestinationDiscardEvidenceV1: Equatable, Sendable {
    let resolution: ReviewedFieldDraftResolutionEvidenceV1
    let terminal: FieldDraftCommittedEvidenceV1
    let plan: DraftDiscardPlanV1
    let bundle: DraftDiscardTerminalBundleV1

    fileprivate init(resolution: ReviewedFieldDraftResolutionEvidenceV1,
                     terminal: FieldDraftCommittedEvidenceV1, plan: DraftDiscardPlanV1,
                     bundle: DraftDiscardTerminalBundleV1) {
        self.resolution = resolution; self.terminal = terminal
        self.plan = plan; self.bundle = bundle
    }
}

enum RepetitiveCaptureDestinationDiscardV1 {
    /// The caller freezes IDs and the proposed time once. A later call
    /// cannot treat this proposal as proof that a write or confirmation ran.
    static func propose(from lineage: RepetitiveCaptureReviewLineageV1,
                        receiptID: UUID, mutationID: MutationIDV1,
                        discardedAt: Date) throws -> RepetitiveCaptureDestinationDiscardProposalV1 {
        _ = try pendingResolution(in: lineage)
        let pending = lineage.selectedReview.checkpoint
        let plan = try discardPlan(for: pending)
        try validateFreshIDs(receiptID: receiptID, mutationID: mutationID, in: lineage)
        try MyDayLimitsV1.millisecondInstant(discardedAt)
        guard discardedAt >= pending.updatedAt,
              pending.draftRevision < UInt64(Int64.max) else { throw FieldDraftFailureV1.invalidValue }
        let receipt = try DraftDiscardReceiptV1(receiptID: receiptID, workspaceID: pending.workspaceID,
            draftID: pending.draftID, planSHA256: plan.planSHA256, disposedStageIDs: [],
            quarantinedReservationIDs: [], discardedAt: discardedAt, mutationID: mutationID)
        let terminal = try FieldDraftCheckpointV1(draftID: pending.draftID, workspaceID: pending.workspaceID,
            scope: pending.scope, purpose: pending.purpose, codec: pending.codec,
            baseCanonicalRevision: pending.baseCanonicalRevision, draftRevision: pending.draftRevision + 1,
            payloadData: pending.payloadData, stageIDs: [], resumeAnchor: pending.resumeAnchor,
            state: .discarded, lastDurableMutationID: mutationID, lastReceiptSHA256: receipt.receiptSHA256,
            updatedAt: discardedAt, mutationID: mutationID)
        let bundle = try DraftDiscardTerminalBundleV1(discardedCheckpoint: terminal, receipt: receipt)
        try validateContract(bundle, after: pending)
        return .init(expectedCheckpoint: pending, plan: plan, terminalBundle: bundle)
    }

    static func validate(_ mutation: FieldDraftMutationV1,
                         against lineage: RepetitiveCaptureReviewLineageV1) throws {
        try mutation.validate()
        _ = try pendingResolution(in: lineage)
        let pending = lineage.selectedReview.checkpoint
        guard case let .applyDiscardTerminal(bundle) = mutation.postImage,
              mutation.workspaceID == pending.workspaceID,
              mutation.expectedRevision == pending.draftRevision,
              mutation.expectedBaseCanonicalRevision == pending.baseCanonicalRevision else {
            throw FieldDraftFailureV1.invalidValue
        }
        try validateContract(bundle, after: pending)
        try validateFreshIDs(receiptID: bundle.receipt.receiptID, mutationID: bundle.mutationID, in: lineage)
    }

    /// This pure check is also used while reconstructing historical prefixes.
    /// It cannot establish the explicit disposition or zero-content census.
    static func validateContract(_ bundle: DraftDiscardTerminalBundleV1,
                                 after pending: FieldDraftCheckpointV1) throws {
        let plan = try discardPlan(for: pending)
        try bundle.validate()
        let terminal = bundle.discardedCheckpoint, receipt = bundle.receipt
        try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(terminal)
        try terminal.validateSuccessor(of: pending, expectedDraftRevision: pending.draftRevision,
                                       expectedBaseRevision: pending.baseCanonicalRevision)
        try MyDayLimitsV1.millisecondInstant(receipt.discardedAt)
        guard terminal.payloadData == pending.payloadData, terminal.resumeAnchor == pending.resumeAnchor,
              terminal.scope == pending.scope, terminal.codec == pending.codec,
              terminal.purpose == pending.purpose,
              terminal.updatedAt == receipt.discardedAt, terminal.updatedAt >= pending.updatedAt,
              receipt.planSHA256 == plan.planSHA256, receipt.disposedStageIDs.isEmpty,
              receipt.quarantinedReservationIDs.isEmpty,
              Set([pending.draftID, pending.mutationID.rawValue, receipt.receiptID,
                   receipt.mutationID.rawValue]).count == 4 else { throw FieldDraftFailureV1.invalidValue }
    }

    static func terminalEvidence(from lineage: RepetitiveCaptureReviewLineageV1) throws
        -> RepetitiveCaptureDestinationDiscardEvidenceV1 {
        let review = lineage.selectedReview
        guard review.checkpoint.state == .discarded, review.prefix.count >= 3,
              let terminalRecord = review.prefix.last,
              let pendingRecord = review.prefix.dropLast().last,
              case let .applyFieldDraft(pendingMutation) = pendingRecord.envelope.command,
              let pending = RepetitiveCaptureSourceGraphReviewV2.checkpointPostImage(pendingMutation.postImage),
              case let .applyFieldDraft(terminalMutation) = terminalRecord.envelope.command,
              case let .applyDiscardTerminal(bundle) = terminalMutation.postImage,
              bundle.discardedCheckpoint == review.checkpoint,
              terminalRecord.envelope.sourceKind == .localUser else { throw FieldDraftFailureV1.invalidValue }
        let resolution = try discardResolution(checkpoint: pending, record: pendingRecord)
        try validateContract(bundle, after: pending)
        try validateFreshIDs(receiptID: bundle.receipt.receiptID, mutationID: bundle.mutationID,
                             in: lineage, excluding: terminalRecord)
        let terminal = try FieldDraftCommittedEvidenceV1(envelope: terminalRecord.envelope,
                                                       receipt: terminalRecord.receipt)
        let plan = try discardPlan(for: pending)
        return .init(resolution: resolution, terminal: terminal, plan: plan, bundle: bundle)
    }

    static func pendingResolution(in lineage: RepetitiveCaptureReviewLineageV1) throws
        -> ReviewedFieldDraftResolutionEvidenceV1 {
        guard let record = lineage.selectedReview.prefix.last else { throw FieldDraftFailureV1.invalidValue }
        return try discardResolution(checkpoint: lineage.selectedReview.checkpoint, record: record)
    }

    private static func discardResolution(checkpoint: FieldDraftCheckpointV1,
                                           record: RepetitiveCaptureSourceHistoryRecordV2) throws
        -> ReviewedFieldDraftResolutionEvidenceV1 {
        try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(checkpoint)
        let evidence = try ReviewedFieldDraftResolutionEvidenceV1(original:
            .init(envelope: record.envelope, receipt: record.receipt))
        guard checkpoint.state == .discardPending, record.envelope.sourceKind == .localUser,
              evidence.resolution.plan == .discard,
              case let .repetitiveCapture(target) = evidence.resolution.reviewedTargetBasis,
              target.round == nil, evidence.resolution.successorCheckpoint == checkpoint else {
            throw FieldDraftFailureV1.invalidValue
        }
        return evidence
    }

    private static func discardPlan(for pending: FieldDraftCheckpointV1) throws -> DraftDiscardPlanV1 {
        try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(pending)
        guard pending.state == .discardPending, pending.draftRevision > 1 else {
            throw FieldDraftFailureV1.invalidValue
        }
        return try .init(planID: pending.draftID, workspaceID: pending.workspaceID, draftID: pending.draftID,
            expectedDraftRevision: pending.draftRevision, nonemptyPayload: true,
            stageIDs: [], reservationIDs: [], estimatedBytes: Int64(pending.payloadData.count))
    }

    private static func validateFreshIDs(receiptID: UUID, mutationID: MutationIDV1,
                                         in lineage: RepetitiveCaptureReviewLineageV1,
                                         excluding terminal: RepetitiveCaptureSourceHistoryRecordV2? = nil) throws {
        try FieldDraftValidationV1.id(receiptID); try FieldDraftValidationV1.id(mutationID.rawValue)
        let proposed = Set([receiptID, mutationID.rawValue])
        guard proposed.count == 2 else { throw FieldDraftFailureV1.invalidValue }
        for record in lineage.requiredHistory {
            if let terminal, record == terminal { continue }
            guard !proposed.contains(record.envelope.mutationID.rawValue) else { throw FieldDraftFailureV1.invalidValue }
            if case let .applyFieldDraft(value) = record.envelope.command,
               case let .applyDiscardTerminal(bundle) = value.postImage {
                guard !proposed.contains(bundle.receipt.receiptID) else { throw FieldDraftFailureV1.invalidValue }
            }
        }
        for review in lineage.reviews {
            guard !proposed.contains(review.checkpoint.draftID),
                  !review.payload.provenance.ultimateToDestinationPairs.contains(where: {
                      proposed.contains($0.sourceID) || proposed.contains($0.destinationID)
                  }) else { throw FieldDraftFailureV1.invalidValue }
        }
    }
}

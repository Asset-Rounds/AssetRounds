import Foundation

/// A caller's observation for an explicit choice. The review-only discard
/// case makes no Round-presence claim and needs only exact workspace CAS.
/// A decoded Round digest does not establish a current target.
struct ReviewedRepetitiveCaptureTargetBasisV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let tag: String
    let workspaceID: WorkspaceID
    let sessionID: UUID
    let expectedWorkspaceRevision: UInt64
    let round: RoundSessionReferenceV1?
    let existingIdentity: WorkspaceEntityIdentityV1?

    var targetRevision: UInt64 { round?.revision ?? 0 }

    init(workspaceID: WorkspaceID, sessionID: UUID, expectedWorkspaceRevision: UInt64,
         round: RoundSessionReferenceV1?) throws {
        schemaVersion = Self.schemaVersion
        tag = round == nil ? "REPETITIVE_CAPTURE_REVIEW_ONLY" : "REPETITIVE_CAPTURE_ROUND_TARGET"
        self.workspaceID = workspaceID
        self.sessionID = sessionID
        self.expectedWorkspaceRevision = expectedWorkspaceRevision
        self.round = round
        existingIdentity = try round.map { try .init(kind: .roundSession, id: $0.sessionID) }
        try validate()
    }

    func validate() throws {
        try FieldDraftValidationV1.workspace(workspaceID)
        try FieldDraftValidationV1.id(sessionID)
        guard schemaVersion == Self.schemaVersion,
              tag == (round == nil ? "REPETITIVE_CAPTURE_REVIEW_ONLY" : "REPETITIVE_CAPTURE_ROUND_TARGET"),
              expectedWorkspaceRevision > 0, expectedWorkspaceRevision < UInt64.max else {
            throw FieldDraftFailureV1.invalidValue
        }
        if let round {
            try round.validate()
            guard round.workspaceID == workspaceID, round.sessionID == sessionID,
                  existingIdentity == (try WorkspaceEntityIdentityV1(kind: .roundSession, id: sessionID)) else {
                throw FieldDraftFailureV1.wrongWorkspace
            }
        } else {
            guard existingIdentity == nil else { throw FieldDraftFailureV1.invalidValue }
        }
    }

    // existingIdentity is derived from the closed Round reference; it is not
    // a second caller-supplied identity or an additional serialized claim.
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, tag, workspaceID, sessionID, expectedWorkspaceRevision, round
    }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let round = try c.decodeIfPresent(RoundSessionReferenceV1.self, forKey: .round)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(String.self, forKey: .tag) ==
                (round == nil ? "REPETITIVE_CAPTURE_REVIEW_ONLY" : "REPETITIVE_CAPTURE_ROUND_TARGET") else {
            throw FieldDraftFailureV1.incompatibleVersion
        }
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID),
            sessionID: c.decode(UUID.self, forKey: .sessionID),
            expectedWorkspaceRevision: c.decode(UInt64.self, forKey: .expectedWorkspaceRevision),
            round: round)
    }
}

/// The My Day case delegates Codable to the original enum at the same encoder
/// level. It therefore keeps every legacy existing/absent command byte intact.
enum ReviewedDraftTargetBasisV1: Codable, Equatable, Sendable {
    case myDay(ReviewedMyDayTargetBasisV1)
    case repetitiveCapture(ReviewedRepetitiveCaptureTargetBasisV1)

    var workspaceID: WorkspaceID {
        switch self {
        case let .myDay(value): value.key.workspaceID
        case let .repetitiveCapture(value): value.workspaceID
        }
    }
    var targetRevision: UInt64 {
        switch self {
        case let .myDay(value): value.targetRevision
        case let .repetitiveCapture(value): value.targetRevision
        }
    }
    var existingIdentity: WorkspaceEntityIdentityV1? {
        switch self {
        case let .myDay(value): value.existingIdentity
        case let .repetitiveCapture(value): value.existingIdentity
        }
    }
    var expectedWorkspaceRevision: UInt64? {
        switch self {
        case let .myDay(value): value.expectedWorkspaceRevision
        case let .repetitiveCapture(value): value.expectedWorkspaceRevision
        }
    }
    var myDayBasis: ReviewedMyDayTargetBasisV1? {
        guard case let .myDay(value) = self else { return nil }
        return value
    }
    func validate() throws {
        switch self {
        case let .myDay(value): try value.validate()
        case let .repetitiveCapture(value): try value.validate()
        }
    }

    private enum CodingKeys: String, CodingKey { case repetitiveCapture }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.repetitiveCapture) {
            try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: ["repetitiveCapture"])
            self = .repetitiveCapture(try c.decode(ReviewedRepetitiveCaptureTargetBasisV1.self,
                                                 forKey: .repetitiveCapture))
        } else {
            self = .myDay(try ReviewedMyDayTargetBasisV1(from: decoder))
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case let .myDay(value): try value.encode(to: encoder)
        case let .repetitiveCapture(value):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(value, forKey: .repetitiveCapture)
        }
    }
}

enum RepetitiveCaptureDestinationResolutionV1 {
    /// Pure proposal construction. The caller's observations may be stale;
    /// only the existing writer can accept and receipt this choice.
    static func propose(plan: DraftConflictResolutionPlanV1,
                        from lineage: RepetitiveCaptureReviewLineageV1,
                        currentRoundHistory: [RoundSessionV1], expectedWorkspaceRevision: UInt64,
                        mutationID: MutationIDV1, reviewedAt: Date) throws -> ReviewedDraftConflictResolutionV1 {
        guard plan != .commitAsCopy else { throw FieldDraftFailureV1.invalidValue }
        let previous = lineage.selectedReview.checkpoint
        let sessionID = try mappedSessionID(in: lineage.selectedReview.payload)
        let round: RoundSessionV1?
        if plan == .discard { round = nil }
        else {
            round = try RoundSessionHistoryValidatorV1.validate(currentRoundHistory,
                workspaceID: previous.workspaceID, sessionID: sessionID)
        }
        let target = try ReviewedRepetitiveCaptureTargetBasisV1(workspaceID: previous.workspaceID,
            sessionID: sessionID, expectedWorkspaceRevision: expectedWorkspaceRevision, round: round?.reference)
        try validateNewMutationID(mutationID, in: lineage)
        guard previous.draftRevision < UInt64.max else { throw FieldDraftFailureV1.invalidValue }
        let successor = try FieldDraftCheckpointV1(draftID: previous.draftID, workspaceID: previous.workspaceID,
            scope: previous.scope, purpose: previous.purpose, codec: previous.codec,
            baseCanonicalRevision: plan == .reviewAndRebase ? target.targetRevision : previous.baseCanonicalRevision,
            draftRevision: previous.draftRevision + 1, payloadData: previous.payloadData, stageIDs: previous.stageIDs,
            resumeAnchor: previous.resumeAnchor, state: plan == .discard ? .discardPending : .active,
            lastDurableMutationID: previous.lastDurableMutationID, lastReceiptSHA256: previous.lastReceiptSHA256,
            updatedAt: reviewedAt, mutationID: mutationID)
        let resolution = try ReviewedDraftConflictResolutionV1(plan: plan, expectedCheckpoint: previous,
            repetitiveCaptureTargetBasis: target, successorCheckpoint: successor)
        try validate(resolution, against: lineage, currentRoundHistory: currentRoundHistory,
                     expectedWorkspaceRevision: expectedWorkspaceRevision)
        return resolution
    }

    /// Closed command semantics only. Current target and source authentication
    /// are deliberately separate from decoding a command.
    static func validateContract(plan: DraftConflictResolutionPlanV1,
                                 expected: FieldDraftCheckpointV1, successor: FieldDraftCheckpointV1,
                                 target: ReviewedRepetitiveCaptureTargetBasisV1) throws {
        try target.validate()
        try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(expected)
        try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(successor)
        let payload = try RepetitiveCaptureDestinationReviewCodecV1.decode(expected.payloadData)
        guard target.workspaceID == expected.workspaceID, target.sessionID == (try mappedSessionID(in: payload)),
              successor.payloadData == expected.payloadData,
              successor.lastDurableMutationID == expected.lastDurableMutationID,
              successor.lastReceiptSHA256 == expected.lastReceiptSHA256 else { throw FieldDraftFailureV1.invalidValue }
        switch plan {
        case .continueEditing:
            guard let round = target.round, successor.state == .active,
                  round.revision == expected.baseCanonicalRevision,
                  successor.baseCanonicalRevision == expected.baseCanonicalRevision else { throw FieldDraftFailureV1.invalidValue }
        case .reviewAndRebase:
            guard let round = target.round, successor.state == .active,
                  round.revision >= expected.baseCanonicalRevision,
                  successor.baseCanonicalRevision == round.revision else { throw FieldDraftFailureV1.invalidValue }
        case .discard:
            guard target.round == nil, successor.state == .discardPending,
                  successor.baseCanonicalRevision == expected.baseCanonicalRevision else { throw FieldDraftFailureV1.invalidValue }
        case .commitAsCopy:
            // The vocabulary is retained. No Round-copy semantics or effect
            // have been defined for this destination-review boundary.
            throw FieldDraftFailureV1.invalidValue
        }
    }

    static func validate(_ resolution: ReviewedDraftConflictResolutionV1,
                         against lineage: RepetitiveCaptureReviewLineageV1,
                         currentRoundHistory: [RoundSessionV1], expectedWorkspaceRevision: UInt64) throws {
        try resolution.validate()
        guard case let .repetitiveCapture(target) = resolution.reviewedTargetBasis,
              lineage.selectedReview.checkpoint == resolution.expectedCheckpoint,
              target.expectedWorkspaceRevision == expectedWorkspaceRevision
        else { throw FieldDraftFailureV1.invalidValue }
        try validateNewMutationID(resolution.successorCheckpoint.mutationID, in: lineage)
        // Discard cannot acquire a Round prerequisite. This basis makes no
        // presence/absence claim and cannot authorize a target or continuation.
        if resolution.plan == .discard { return }
        let current = try RoundSessionHistoryValidatorV1.validate(currentRoundHistory,
            workspaceID: target.workspaceID, sessionID: target.sessionID)
        guard try current?.reference == target.round else { throw FieldDraftFailureV1.staleDraftRevision }
        guard let current else { throw FieldDraftFailureV1.invalidValue }
        // ACTIVE plus fresh readiness is a later continuation prerequisite.
        // The review successor alone never grants operational permission.
        let expected = try restoredRoundPrefix(from: lineage)
        guard let restoredTip = expected.last,
              currentRoundHistory.count >= expected.count,
              Array(currentRoundHistory.prefix(expected.count)) == expected else {
            throw FieldDraftFailureV1.digestMismatch
        }
        switch resolution.plan {
        case .continueEditing:
            guard current == restoredTip else { throw FieldDraftFailureV1.staleDraftRevision }
        case .reviewAndRebase:
            guard current.revision > restoredTip.revision else { throw FieldDraftFailureV1.staleDraftRevision }
        case .discard, .commitAsCopy: throw FieldDraftFailureV1.invalidValue
        }
    }

    /// Derive the complete original Round prefix in the selected workspace.
    /// Canonical record IDs survive each hop; replacement mutation IDs are
    /// composed one actual hop at a time, including the receipt's generation.
    /// Workspace-only actor/content projection is then materialized once.
    static func restoredRoundPrefix(from lineage: RepetitiveCaptureReviewLineageV1) throws -> [RoundSessionV1] {
        let originalTip = lineage.retainedSource.graph.packageCurrentRound
        let originals = lineage.retainedSource.requiredHistory.compactMap { record -> RoundSessionV1? in
            guard case let .applyRoundSession(mutation) = record.envelope.command,
                  mutation.workspaceID == originalTip.workspaceID,
                  mutation.session.sessionID == originalTip.sessionID,
                  mutation.session.revision <= originalTip.revision else { return nil }
            return mutation.session
        }.sorted { $0.revision < $1.revision }
        guard try RoundSessionHistoryValidatorV1.validate(originals, workspaceID: originalTip.workspaceID,
            sessionID: originalTip.sessionID) == originalTip else { throw FieldDraftFailureV1.digestMismatch }
        var mutationIDs = originals.map(\.mutationID)
        var sourceWorkspaceID = originalTip.workspaceID
        for review in lineage.reviews {
            guard let creation = review.prefix.first,
                  creation.envelope.mutationID == review.initialCheckpoint.mutationID,
                  try mappedSessionID(in: review.payload) == originalTip.sessionID else {
                throw FieldDraftFailureV1.invalidValue
            }
            if review.payload.provenance.mode == .crossWorkspaceReplace {
                mutationIDs = try mutationIDs.map { sourceID in
                    try RestoreIdentityV1.destinationRoundSessionMutationID(for: sourceID,
                        sourceWorkspaceID: sourceWorkspaceID, destinationWorkspaceID: review.checkpoint.workspaceID,
                        generationID: creation.envelope.expectedRevision.generationID)
                }
            }
            sourceWorkspaceID = review.checkpoint.workspaceID
        }
        let targetWorkspaceID = lineage.selectedReview.checkpoint.workspaceID
        var result: [RoundSessionV1] = []
        for (index, original) in originals.enumerated() {
            var visits: [UUID: ActorSnapshotV1] = [:]
            for visit in original.items.compactMap(\.visit) {
                let value = try reboundActor(visit.recordedBy, workspaceID: targetWorkspaceID)
                if let previous = visits.updateValue(value, forKey: value.snapshotID), previous != value {
                    throw FieldDraftFailureV1.invalidValue
                }
            }
            let value = try original.rebindingWorkspaceID(targetWorkspaceID, rebasedPredecessor: result.last,
                recordedBy: reboundActor(original.recordedBy, workspaceID: targetWorkspaceID), visitActors: visits)
            result.append(try RoundSessionV1(workspaceID: targetWorkspaceID, sessionID: value.sessionID,
                predecessor: result.last, revision: value.revision, mutationID: mutationIDs[index], state: value.state,
                transition: value.transition, transitionItemID: value.transitionItemID, items: value.items,
                recordedBy: value.recordedBy, recordedAt: value.recordedAt))
        }
        _ = try RoundSessionHistoryValidatorV1.validate(result, workspaceID: targetWorkspaceID,
                                                       sessionID: originalTip.sessionID)
        return result
    }

    private static func mappedSessionID(in payload: RepetitiveCaptureDestinationReviewPayloadV1) throws -> UUID {
        let originalID = payload.source.value.roundSessionID
        let matches = payload.provenance.ultimateToDestinationPairs.filter {
            $0.kind == .roundSession && $0.sourceID == originalID
        }
        guard matches.count == 1, let pair = matches.first else { throw FieldDraftFailureV1.invalidValue }
        return pair.destinationID
    }

    private static func validateNewMutationID(_ mutationID: MutationIDV1,
                                              in lineage: RepetitiveCaptureReviewLineageV1) throws {
        try FieldDraftValidationV1.id(mutationID.rawValue)
        guard !lineage.requiredHistory.contains(where: { $0.envelope.mutationID == mutationID }),
              !lineage.reviews.contains(where: { review in
                review.checkpoint.draftID == mutationID.rawValue ||
                    review.payload.provenance.ultimateToDestinationPairs.contains(where: {
                        $0.sourceID == mutationID.rawValue || $0.destinationID == mutationID.rawValue
                    })
              }) else { throw FieldDraftFailureV1.invalidValue }
    }

    private static func reboundActor(_ value: ActorSnapshotV1, workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let actor = try LocalActorReferenceV1(actorReferenceID: value.actor.actorReferenceID,
            workspaceID: workspaceID, partyID: value.actor.partyID, displayName: value.actor.displayName)
        return try ActorSnapshotV1(snapshotID: value.snapshotID, workspaceID: workspaceID, actor: actor,
            responsibility: value.responsibility, displayNameAtTime: value.displayNameAtTime, capturedAt: value.capturedAt)
    }
}

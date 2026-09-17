import Foundation

/// Immutable command metadata. These references need the journal's complete
/// source and review proof; decoding them grants no readiness or write permit.
struct RepetitiveCaptureDestinationContinuationBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let review: RepetitiveCaptureSourceCheckpointReferenceV1
    let reviewEnvelopeSHA256: String
    let reviewReceiptIdentity: MutationReceiptIdentityV1
    let reviewReceiptSHA256: String
    let resolutionMutationID: MutationIDV1
    let resolutionEnvelopeSHA256: String
    let resolutionReceiptIdentity: MutationReceiptIdentityV1
    let resolutionReceiptSHA256: String
    let round: RoundSessionReferenceV1

    fileprivate init(lineage: RepetitiveCaptureReviewLineageV1,
                     resolution: ReviewedFieldDraftResolutionEvidenceV1) throws {
        let selected = lineage.selectedReview
        guard case let .repetitiveCapture(target) = resolution.resolution.reviewedTargetBasis,
              let round = target.round else { throw FieldDraftFailureV1.invalidValue }
        schemaVersion = Self.schemaVersion
        workspaceID = selected.checkpoint.workspaceID
        review = try .init(source: selected.checkpoint)
        reviewEnvelopeSHA256 = try selected.anchor.envelope.canonicalSHA256()
        reviewReceiptIdentity = selected.anchor.receipt.identity
        reviewReceiptSHA256 = try selected.anchor.receipt.canonicalSHA256()
        resolutionMutationID = resolution.original.mutation.mutationID
        resolutionEnvelopeSHA256 = resolution.original.envelopeSHA256
        resolutionReceiptIdentity = resolution.original.receipt.identity
        resolutionReceiptSHA256 = try resolution.original.receipt.canonicalSHA256()
        self.round = round
        try validate()
    }

    func validate() throws {
        try FieldDraftValidationV1.workspace(workspaceID)
        try review.validate()
        try reviewReceiptIdentity.validate()
        try resolutionReceiptIdentity.validate()
        try round.validate()
        try FieldDraftValidationV1.id(resolutionMutationID.rawValue)
        guard schemaVersion == Self.schemaVersion, round.workspaceID == workspaceID,
              reviewReceiptIdentity.workspaceID == workspaceID,
              resolutionReceiptIdentity.workspaceID == workspaceID,
              [reviewEnvelopeSHA256, reviewReceiptSHA256, resolutionEnvelopeSHA256,
               resolutionReceiptSHA256].allSatisfy(MutationEnvelopeV1.isSHA256) else {
            throw FieldDraftFailureV1.invalidValue
        }
    }

    var concurrencyIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            let source = try RepetitiveCaptureDestinationContinuationV1.ids(
                workspaceID: workspaceID, reviewDraftID: review.draftID)
            return try [WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: source.draftID),
                        WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: review.draftID),
                        WorkspaceEntityIdentityV1(kind: .roundSession, id: round.sessionID)]
                .sorted { $0.stableKey < $1.stableKey }
        }
    }

    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        let source = try RepetitiveCaptureDestinationContinuationV1.ids(
            workspaceID: workspaceID, reviewDraftID: review.draftID)
        if identity == (try .init(kind: .fieldDraftCheckpoint, id: source.draftID)) { return 0 }
        if identity == (try .init(kind: .fieldDraftCheckpoint, id: review.draftID)) { return review.draftRevision }
        if identity == (try .init(kind: .roundSession, id: round.sessionID)) { return round.revision }
        throw WorkspaceMutationContractFailureV1.invalidPlan
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, review, reviewEnvelopeSHA256, reviewReceiptIdentity
        case reviewReceiptSHA256, resolutionMutationID, resolutionEnvelopeSHA256
        case resolutionReceiptIdentity, resolutionReceiptSHA256, round
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        workspaceID = try c.decode(WorkspaceID.self, forKey: .workspaceID)
        review = try c.decode(RepetitiveCaptureSourceCheckpointReferenceV1.self, forKey: .review)
        reviewEnvelopeSHA256 = try c.decode(String.self, forKey: .reviewEnvelopeSHA256)
        reviewReceiptIdentity = try c.decode(MutationReceiptIdentityV1.self, forKey: .reviewReceiptIdentity)
        reviewReceiptSHA256 = try c.decode(String.self, forKey: .reviewReceiptSHA256)
        resolutionMutationID = try c.decode(MutationIDV1.self, forKey: .resolutionMutationID)
        resolutionEnvelopeSHA256 = try c.decode(String.self, forKey: .resolutionEnvelopeSHA256)
        resolutionReceiptIdentity = try c.decode(MutationReceiptIdentityV1.self, forKey: .resolutionReceiptIdentity)
        resolutionReceiptSHA256 = try c.decode(String.self, forKey: .resolutionReceiptSHA256)
        round = try c.decode(RoundSessionReferenceV1.self, forKey: .round)
        try validate()
    }
}

struct RepetitiveCaptureDestinationContinuationProposalV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let mutation: FieldDraftMutationV1
    fileprivate init(checkpoint: FieldDraftCheckpointV1, mutation: FieldDraftMutationV1) {
        self.checkpoint = checkpoint; self.mutation = mutation
    }
}

/// An acknowledgement of originals, including after later Round changes.
/// Entry and visible publication still need their existing live access owners.
struct RepetitiveCaptureDestinationContinuationEvidenceV1: Equatable, Sendable {
    let binding: RepetitiveCaptureDestinationContinuationBindingV1
    let resolution: ReviewedFieldDraftResolutionEvidenceV1
    let original: FieldDraftCommittedEvidenceV1
    let sourceCheckpoint: FieldDraftCheckpointV1
    fileprivate init(binding: RepetitiveCaptureDestinationContinuationBindingV1,
                     resolution: ReviewedFieldDraftResolutionEvidenceV1,
                     original: FieldDraftCommittedEvidenceV1, sourceCheckpoint: FieldDraftCheckpointV1) {
        self.binding = binding; self.resolution = resolution
        self.original = original; self.sourceCheckpoint = sourceCheckpoint
    }
}

enum RepetitiveCaptureDestinationContinuationV1 {
    struct IDs: Equatable, Sendable {
        let planID: UUID
        let draftID: UUID
        let mutationID: MutationIDV1
    }

    /// One identity set per review, including across a later re-review. A
    /// different prepared timestamp cannot allocate a second operational draft.
    static func ids(workspaceID: WorkspaceID, reviewDraftID: UUID) throws -> IDs {
        try FieldDraftValidationV1.workspace(workspaceID)
        try FieldDraftValidationV1.id(reviewDraftID)
        struct IdentityBody: Codable {
            let format: String
            let role: String
            let workspaceID: WorkspaceID
            let reviewDraftID: UUID
        }
        func id(_ role: String) throws -> UUID {
            let digest = try FieldDraftCanonicalCodecV1.sha256(IdentityBody(
                format: "assetrounds.c36.destination-continuation.identity.v1", role: role,
                workspaceID: workspaceID, reviewDraftID: reviewDraftID))
            var bytes: [UInt8] = []
            for offset in stride(from: 0, to: 32, by: 2) {
                guard let byte = UInt8(digest.dropFirst(offset).prefix(2), radix: 16) else {
                    throw FieldDraftFailureV1.digestMismatch
                }
                bytes.append(byte)
            }
            bytes[6] = (bytes[6] & 0x0f) | 0x50
            bytes[8] = (bytes[8] & 0x3f) | 0x80
            return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
                               bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        }
        return try .init(planID: id("plan"), draftID: id("checkpoint"),
                         mutationID: MutationIDV1(rawValue: id("mutation")))
    }

    static func propose(from lineage: RepetitiveCaptureReviewLineageV1,
                        currentRoundHistory: [RoundSessionV1], manifest: OfflineReadinessManifestV1,
                        preparedAt: Date) throws -> RepetitiveCaptureDestinationContinuationProposalV1 {
        let resolution = try activeResolution(in: lineage)
        let binding = try RepetitiveCaptureDestinationContinuationBindingV1(lineage: lineage, resolution: resolution)
        let current = try target(binding, in: currentRoundHistory, lineage: lineage, resolution: resolution)
        guard manifest.session == binding.round else { throw FieldDraftFailureV1.staleDraftRevision }
        let identity = try ids(workspaceID: binding.workspaceID, reviewDraftID: binding.review.draftID)
        let launch = try RepetitiveCaptureLaunchSourceV2(planID: identity.planID, round: current,
            readiness: current.items.map { try manifest.scanToWorkProof(assetID: $0.selection.assetID) })
        let checkpoint = try FieldDraftCheckpointV1(draftID: identity.draftID, workspaceID: binding.workspaceID,
            scope: RepetitiveCaptureDraftCodecV1.scope(planID: identity.planID, round: binding.round),
            purpose: .repetitiveCapture, codec: RepetitiveCaptureProgressDraftCodecV2.release(),
            baseCanonicalRevision: current.revision, draftRevision: 1,
            payloadData: RepetitiveCaptureProgressDraftCodecV2.encode(.source(launch)), stageIDs: [],
            resumeAnchor: anchor(for: launch), state: .active, updatedAt: preparedAt,
            mutationID: identity.mutationID)
        let mutation = try FieldDraftMutationV1(workspaceID: binding.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: current.revision, mutationID: identity.mutationID,
            postImage: .createCheckpoint(checkpoint), continuationBinding: binding)
        try validate(mutation, against: lineage, currentRoundHistory: currentRoundHistory)
        return .init(checkpoint: checkpoint, mutation: mutation)
    }

    static func validateCheckpoint(_ checkpoint: FieldDraftCheckpointV1,
                                   binding: RepetitiveCaptureDestinationContinuationBindingV1) throws {
        try binding.validate()
        let launch = try RepetitiveCaptureProgressDraftCodecV2.source(checkpoint)
        let identity = try ids(workspaceID: binding.workspaceID, reviewDraftID: binding.review.draftID)
        try MyDayLimitsV1.millisecondInstant(checkpoint.updatedAt)
        guard checkpoint.workspaceID == binding.workspaceID, checkpoint.draftID == identity.draftID,
              checkpoint.mutationID == identity.mutationID, launch.planID == identity.planID,
              try launch.round.reference == binding.round, launch.firstIncompleteItemID != nil,
              checkpoint.draftRevision == 1, checkpoint.state == .active, checkpoint.stageIDs.isEmpty,
              checkpoint.lastDurableMutationID == nil, checkpoint.lastReceiptSHA256 == nil,
              checkpoint.baseCanonicalRevision == binding.round.revision,
              checkpoint.scope == (try RepetitiveCaptureDraftCodecV1.scope(planID: identity.planID, round: binding.round)),
              checkpoint.resumeAnchor == (try anchor(for: launch)) else {
            throw FieldDraftFailureV1.invalidValue
        }
    }

    static func validate(_ mutation: FieldDraftMutationV1, against lineage: RepetitiveCaptureReviewLineageV1,
                         currentRoundHistory: [RoundSessionV1]) throws {
        try mutation.validate()
        guard let binding = mutation.continuationBinding,
              case let .createCheckpoint(checkpoint) = mutation.postImage else { throw FieldDraftFailureV1.invalidValue }
        let resolution = try activeResolution(in: lineage)
        guard binding == (try RepetitiveCaptureDestinationContinuationBindingV1(lineage: lineage, resolution: resolution)),
              checkpoint.updatedAt >= lineage.selectedReview.checkpoint.updatedAt else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let current = try target(binding, in: currentRoundHistory, lineage: lineage, resolution: resolution)
        let launch = try RepetitiveCaptureProgressDraftCodecV2.source(checkpoint)
        guard launch.round == current else { throw FieldDraftFailureV1.digestMismatch }
        try validateFreshIDs(binding, in: lineage)
    }

    static func evidence(original: FieldDraftCommittedEvidenceV1,
                         lineage: RepetitiveCaptureReviewLineageV1,
                         historicalRoundPrefix: [RoundSessionV1]) throws -> RepetitiveCaptureDestinationContinuationEvidenceV1 {
        guard let binding = original.mutation.continuationBinding,
              case let .createCheckpoint(checkpoint) = original.mutation.postImage,
              original.envelope.sourceKind == .localUser,
              original.envelope.causationMutationID == nil,
              original.envelope.expectedRevision.workspaceRevision >= lineage.selectedReview.anchor.receipt.resultingRevision.workspaceRevision,
              original.receipt.resultingRevision.workspaceRevision > lineage.selectedReview.anchor.receipt.resultingRevision.workspaceRevision else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        try validate(original.mutation, against: lineage, currentRoundHistory: historicalRoundPrefix)
        return try .init(binding: binding, resolution: activeResolution(in: lineage),
                         original: original, sourceCheckpoint: checkpoint)
    }

    private static func activeResolution(in lineage: RepetitiveCaptureReviewLineageV1) throws
        -> ReviewedFieldDraftResolutionEvidenceV1 {
        let selected = lineage.selectedReview
        guard selected.checkpoint.state == .active,
              let record = selected.prefix.reversed().first(where: {
                  guard case let .applyFieldDraft(mutation) = $0.envelope.command,
                        case .resolveConflict = mutation.postImage else { return false }
                  return true
              }) else { throw FieldDraftFailureV1.invalidValue }
        let resolution = try ReviewedFieldDraftResolutionEvidenceV1(original:
            .init(envelope: record.envelope, receipt: record.receipt))
        guard [.continueEditing, .reviewAndRebase].contains(resolution.resolution.plan),
              resolution.resolution.successorCheckpoint.state == .active,
              selected.checkpoint.baseCanonicalRevision == resolution.resolution.successorCheckpoint.baseCanonicalRevision,
              selected.checkpoint.payloadData == resolution.resolution.successorCheckpoint.payloadData else {
            throw FieldDraftFailureV1.invalidValue
        }
        return resolution
    }

    private static func target(_ binding: RepetitiveCaptureDestinationContinuationBindingV1,
                               in history: [RoundSessionV1], lineage: RepetitiveCaptureReviewLineageV1,
                               resolution: ReviewedFieldDraftResolutionEvidenceV1) throws -> RoundSessionV1 {
        guard let current = try RoundSessionHistoryValidatorV1.validate(history,
                workspaceID: binding.workspaceID, sessionID: binding.round.sessionID),
              try current.reference == binding.round, current.state == .active,
              current.items.contains(where: { !$0.disposition.isTerminal }) else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let restored = try RepetitiveCaptureDestinationResolutionV1.restoredRoundPrefix(from: lineage)
        guard let restoredTip = restored.last, history.count >= restored.count,
              Array(history.prefix(restored.count)) == restored else { throw FieldDraftFailureV1.digestMismatch }
        if resolution.resolution.plan == .continueEditing {
            guard current == restoredTip else { throw FieldDraftFailureV1.staleDraftRevision }
        }
        return current
    }

    private static func anchor(for launch: RepetitiveCaptureLaunchSourceV2) throws -> DraftResumeAnchorV1 {
        try .init(sectionID: "facts", selectedStableID: launch.round.items.first {
            $0.itemID == launch.firstIncompleteItemID
        }?.selection.assetID.uuidString.lowercased())
    }

    private static func validateFreshIDs(_ binding: RepetitiveCaptureDestinationContinuationBindingV1,
                                         in lineage: RepetitiveCaptureReviewLineageV1) throws {
        let identity = try ids(workspaceID: binding.workspaceID, reviewDraftID: binding.review.draftID)
        let fresh = Set([identity.planID, identity.draftID, identity.mutationID.rawValue])
        var unavailable = Set(lineage.requiredHistory.map { $0.envelope.mutationID.rawValue })
        for review in lineage.reviews {
            unavailable.insert(review.checkpoint.draftID)
            for pair in review.payload.provenance.ultimateToDestinationPairs {
                unavailable.insert(pair.sourceID); unavailable.insert(pair.destinationID)
            }
        }
        guard fresh.count == 3, fresh.isDisjoint(with: unavailable) else { throw FieldDraftFailureV1.invalidValue }
    }
}

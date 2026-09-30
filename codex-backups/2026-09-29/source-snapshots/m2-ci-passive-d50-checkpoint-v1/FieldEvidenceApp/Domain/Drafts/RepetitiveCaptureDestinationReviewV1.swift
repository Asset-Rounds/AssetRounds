import Foundation

/// These relations describe the destination of a historical graph. They do not
/// replay its mutations or make a mapped checkpoint operational.
enum RepetitiveCaptureReviewIdentityKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case checkpoint = "CHECKPOINT"
    case roundSession = "ROUND_SESSION"
    case roundItem = "ROUND_ITEM"
    case launchPlan = "LAUNCH_PLAN"
    case site = "SITE"
    case asset = "ASSET"
    case completion = "COMPLETION"
}

enum RepetitiveCaptureReviewModeV1: String, Codable, Equatable, Sendable {
    case crossWorkspaceReplace = "CROSS_WORKSPACE_REPLACE"
    case fork = "FORK"

    fileprivate var restoreMode: BackupRestoreMode {
        self == .fork ? .fork : .replaceExisting
    }
}

struct RepetitiveCaptureReviewIdentityPairV1: Codable, Equatable, Hashable, Sendable {
    let kind: RepetitiveCaptureReviewIdentityKindV1
    let sourceID: UUID
    let destinationID: UUID

    init(kind: RepetitiveCaptureReviewIdentityKindV1, sourceID: UUID, destinationID: UUID) throws {
        self.kind = kind
        self.sourceID = sourceID
        self.destinationID = destinationID
        try validate()
    }

    func validate() throws {
        try FieldDraftValidationV1.id(sourceID)
        try FieldDraftValidationV1.id(destinationID)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, sourceID, destinationID }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(kind: c.decode(RepetitiveCaptureReviewIdentityKindV1.self, forKey: .kind),
                      sourceID: c.decode(UUID.self, forKey: .sourceID),
                      destinationID: c.decode(UUID.self, forKey: .destinationID))
    }
}

/// One receipt link and one immediate relation, never a nested ancestor payload.
/// Decoding this value does not authenticate that receipt or its correspondence.
struct RepetitiveCaptureReviewPredecessorV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let reviewDraftID: UUID
    let reviewCheckpointSHA256: String
    let reviewMutationID: MutationIDV1
    let reviewEnvelopeSHA256: String
    let reviewReceiptIdentity: MutationReceiptIdentityV1
    let reviewReceiptSHA256: String
    let predecessorProvenanceSHA256: String
    let predecessorToDestinationPairs: [RepetitiveCaptureReviewIdentityPairV1]

    init(workspaceID: WorkspaceID, reviewDraftID: UUID, reviewCheckpointSHA256: String,
         reviewMutationID: MutationIDV1, reviewEnvelopeSHA256: String,
         reviewReceiptIdentity: MutationReceiptIdentityV1, reviewReceiptSHA256: String,
         predecessorProvenanceSHA256: String,
         predecessorToDestinationPairs: [RepetitiveCaptureReviewIdentityPairV1]) throws {
        self.workspaceID = workspaceID
        self.reviewDraftID = reviewDraftID
        self.reviewCheckpointSHA256 = reviewCheckpointSHA256
        self.reviewMutationID = reviewMutationID
        self.reviewEnvelopeSHA256 = reviewEnvelopeSHA256
        self.reviewReceiptIdentity = reviewReceiptIdentity
        self.reviewReceiptSHA256 = reviewReceiptSHA256
        self.predecessorProvenanceSHA256 = predecessorProvenanceSHA256
        self.predecessorToDestinationPairs = predecessorToDestinationPairs
        try validate()
    }

    func validate() throws {
        try FieldDraftValidationV1.workspace(workspaceID)
        try FieldDraftValidationV1.id(reviewDraftID)
        try FieldDraftValidationV1.id(reviewMutationID.rawValue)
        try reviewReceiptIdentity.validate()
        for digest in [reviewCheckpointSHA256, reviewEnvelopeSHA256, reviewReceiptSHA256,
                       predecessorProvenanceSHA256] { try FieldDraftValidationV1.digest(digest) }
        guard reviewReceiptIdentity.workspaceID == workspaceID,
              reviewDraftID != reviewMutationID.rawValue else { throw FieldDraftFailureV1.invalidValue }
        try RepetitiveCaptureReviewRelationsV1.validate(predecessorToDestinationPairs)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, reviewDraftID, reviewCheckpointSHA256, reviewMutationID
        case reviewEnvelopeSHA256, reviewReceiptIdentity, reviewReceiptSHA256
        case predecessorProvenanceSHA256, predecessorToDestinationPairs
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID),
            reviewDraftID: c.decode(UUID.self, forKey: .reviewDraftID),
            reviewCheckpointSHA256: c.decode(String.self, forKey: .reviewCheckpointSHA256),
            reviewMutationID: c.decode(MutationIDV1.self, forKey: .reviewMutationID),
            reviewEnvelopeSHA256: c.decode(String.self, forKey: .reviewEnvelopeSHA256),
            reviewReceiptIdentity: c.decode(MutationReceiptIdentityV1.self, forKey: .reviewReceiptIdentity),
            reviewReceiptSHA256: c.decode(String.self, forKey: .reviewReceiptSHA256),
            predecessorProvenanceSHA256: c.decode(String.self, forKey: .predecessorProvenanceSHA256),
            predecessorToDestinationPairs: c.decode([RepetitiveCaptureReviewIdentityPairV1].self,
                                                    forKey: .predecessorToDestinationPairs))
    }
}

struct RepetitiveCaptureReviewProvenanceV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    static let schemaVersion = 1
    let schemaVersion: Int
    let mode: RepetitiveCaptureReviewModeV1
    let destinationWorkspaceID: WorkspaceID
    let ultimateSourceReferenceSHA256: String
    let ultimateToDestinationPairs: [RepetitiveCaptureReviewIdentityPairV1]
    let immediatePredecessor: RepetitiveCaptureReviewPredecessorV1?
    let provenanceSHA256: String

    init(mode: RepetitiveCaptureReviewModeV1, destinationWorkspaceID: WorkspaceID,
         ultimateSourceReferenceSHA256: String,
         ultimateToDestinationPairs: [RepetitiveCaptureReviewIdentityPairV1],
         immediatePredecessor: RepetitiveCaptureReviewPredecessorV1? = nil) throws {
        schemaVersion = Self.schemaVersion
        self.mode = mode
        self.destinationWorkspaceID = destinationWorkspaceID
        self.ultimateSourceReferenceSHA256 = ultimateSourceReferenceSHA256
        self.ultimateToDestinationPairs = ultimateToDestinationPairs
        self.immediatePredecessor = immediatePredecessor
        provenanceSHA256 = try FieldDraftCanonicalCodecV1.sha256(Body(
            schemaVersion: Self.schemaVersion, mode: mode, destinationWorkspaceID: destinationWorkspaceID,
            ultimateSourceReferenceSHA256: ultimateSourceReferenceSHA256,
            ultimateToDestinationPairs: ultimateToDestinationPairs, immediatePredecessor: immediatePredecessor))
        try validate()
    }

    func validate() throws {
        try FieldDraftValidationV1.workspace(destinationWorkspaceID)
        try FieldDraftValidationV1.digest(ultimateSourceReferenceSHA256)
        try FieldDraftValidationV1.digest(provenanceSHA256)
        try RepetitiveCaptureReviewRelationsV1.validate(ultimateToDestinationPairs)
        if let predecessor = immediatePredecessor {
            try predecessor.validate()
            guard predecessor.workspaceID != destinationWorkspaceID,
                  RepetitiveCaptureReviewRelationsV1.destinations(predecessor.predecessorToDestinationPairs)
                    == RepetitiveCaptureReviewRelationsV1.destinations(ultimateToDestinationPairs) else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
        guard schemaVersion == Self.schemaVersion,
              provenanceSHA256 == (try FieldDraftCanonicalCodecV1.sha256(body)) else {
            throw FieldDraftFailureV1.digestMismatch
        }
    }

    private var body: Body {
        .init(schemaVersion: schemaVersion, mode: mode, destinationWorkspaceID: destinationWorkspaceID,
              ultimateSourceReferenceSHA256: ultimateSourceReferenceSHA256,
              ultimateToDestinationPairs: ultimateToDestinationPairs, immediatePredecessor: immediatePredecessor)
    }
    private struct Body: Codable {
        let schemaVersion: Int
        let mode: RepetitiveCaptureReviewModeV1
        let destinationWorkspaceID: WorkspaceID
        let ultimateSourceReferenceSHA256: String
        let ultimateToDestinationPairs: [RepetitiveCaptureReviewIdentityPairV1]
        let immediatePredecessor: RepetitiveCaptureReviewPredecessorV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, mode, destinationWorkspaceID, ultimateSourceReferenceSHA256
        case ultimateToDestinationPairs, immediatePredecessor, provenanceSHA256
    }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        mode = try c.decode(RepetitiveCaptureReviewModeV1.self, forKey: .mode)
        destinationWorkspaceID = try c.decode(WorkspaceID.self, forKey: .destinationWorkspaceID)
        ultimateSourceReferenceSHA256 = try c.decode(String.self, forKey: .ultimateSourceReferenceSHA256)
        ultimateToDestinationPairs = try c.decode([RepetitiveCaptureReviewIdentityPairV1].self,
                                                forKey: .ultimateToDestinationPairs)
        immediatePredecessor = try c.decodeIfPresent(RepetitiveCaptureReviewPredecessorV1.self,
                                                    forKey: .immediatePredecessor)
        provenanceSHA256 = try c.decode(String.self, forKey: .provenanceSHA256)
        try validate()
    }
}

/// Shape-valid historical review data. Only receipt-backed journal derivation
/// can later authenticate its provenance. It carries no current readiness.
struct RepetitiveCaptureDestinationReviewPayloadV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    static let schemaVersion = 1
    static let tag = "SOURCE_GRAPH_REVIEW"
    let schemaVersion: Int
    let tag: String
    let source: RepetitiveCaptureSourceGraphReferenceV2
    let provenance: RepetitiveCaptureReviewProvenanceV1

    init(source: RepetitiveCaptureSourceGraphReferenceV2, provenance: RepetitiveCaptureReviewProvenanceV1) throws {
        schemaVersion = Self.schemaVersion
        tag = Self.tag
        self.source = source
        self.provenance = provenance
        try validate()
    }

    func validate() throws {
        try source.validate()
        try provenance.validate()
        let pairs = provenance.ultimateToDestinationPairs
        let checkpoints = pairs.filter { $0.kind == .checkpoint }
        let rounds = pairs.filter { $0.kind == .roundSession }
        guard schemaVersion == Self.schemaVersion, tag == Self.tag,
              provenance.ultimateSourceReferenceSHA256 == source.referenceSHA256,
              Set(checkpoints.map(\.sourceID)) == Set(source.value.checkpoints.map(\.draftID)),
              rounds.count == 1, rounds.first?.sourceID == source.value.roundSessionID,
              pairs.filter({ $0.kind == .launchPlan }).count == 1 else { throw FieldDraftFailureV1.invalidValue }
        let itemCount = pairs.filter { $0.kind == .roundItem }.count
        let assetCount = pairs.filter { $0.kind == .asset }.count
        let siteCount = pairs.filter { $0.kind == .site }.count
        let completionCount = pairs.filter { $0.kind == .completion }.count
        guard itemCount > 0, itemCount <= ScanToWorkLimitsV1.maximumSelection,
              assetCount == itemCount, siteCount > 0, siteCount <= itemCount,
              completionCount <= itemCount else { throw FieldDraftFailureV1.invalidValue }
        if provenance.immediatePredecessor == nil {
            guard source.value.sourceWorkspaceID != provenance.destinationWorkspaceID else {
                throw FieldDraftFailureV1.wrongWorkspace
            }
            for pair in pairs {
                guard pair.destinationID == (try RepetitiveCaptureReviewRelationsV1.destination(
                    pair.sourceID, kind: pair.kind, mode: provenance.mode,
                    workspaceID: provenance.destinationWorkspaceID)) else { throw FieldDraftFailureV1.invalidValue }
            }
        }
    }

    /// Reproduce the complete first-hop relation from a sealed package review.
    /// A decoded pair list cannot select or shorten its own required coverage.
    func validateFirstSource(against reviewed: ReviewedRepetitiveCaptureSourceGraphsV2,
                             identity: RestoreIdentityV1) throws {
        let expected = try RepetitiveCaptureDestinationReviewV1.firstPayload(
            from: reviewed, sourceDraftID: source.value.sourceDraftID, identity: identity)
        guard self == expected else { throw FieldDraftFailureV1.digestMismatch }
    }

    /// Rebuild coverage from authenticated retained originals, never from the
    /// pair list's own claims. Original archive hashes remain historical data.
    func validateFirstSource(against retained: RepetitiveCaptureRetainedOriginalsV2) throws {
        let expected = try RepetitiveCaptureDestinationReviewV1.firstPayload(
            source: retained.reference, graph: retained.graph,
            mode: provenance.mode, workspace: provenance.destinationWorkspaceID)
        guard self == expected else { throw FieldDraftFailureV1.digestMismatch }
    }

    /// Pure correspondence comparison. The lineage reader separately owns
    /// authentication of the supplied predecessor checkpoint and originals.
    func validatePredecessor(against predecessor: RepetitiveCaptureDestinationReviewPayloadV1,
                             original: RepetitiveCaptureSourceHistoryRecordV2,
                             checkpoint: FieldDraftCheckpointV1) throws {
        let expected = try RepetitiveCaptureDestinationReviewV1.inheritedPayload(
            predecessor: predecessor, original: original, checkpoint: checkpoint,
            mode: provenance.mode, workspace: provenance.destinationWorkspaceID)
        guard self == expected else { throw FieldDraftFailureV1.digestMismatch }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, tag, source, provenance }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        tag = try c.decode(String.self, forKey: .tag)
        source = try c.decode(RepetitiveCaptureSourceGraphReferenceV2.self, forKey: .source)
        provenance = try c.decode(RepetitiveCaptureReviewProvenanceV1.self, forKey: .provenance)
        try validate()
    }
}

/// A prepared value, not permission to suppress rows or publish a mutation.
/// The restore owner must atomically bind it to its own fresh create receipt.
struct PreparedRepetitiveCaptureDestinationReviewV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let payload: RepetitiveCaptureDestinationReviewPayloadV1
    let sourceCheckpointIDs: [UUID]

    fileprivate init(checkpoint: FieldDraftCheckpointV1, payload: RepetitiveCaptureDestinationReviewPayloadV1) {
        self.checkpoint = checkpoint
        self.payload = payload
        sourceCheckpointIDs = payload.source.value.checkpoints.map(\.draftID)
    }
}

/// A proposal replacing a source review row, not the ultimate V2 source rows.
/// Its creation still requires the restore owner's atomic publication receipt.
struct PreparedRepetitiveCaptureInheritedReviewV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let payload: RepetitiveCaptureDestinationReviewPayloadV1
    let sourceReviewDraftID: UUID

    fileprivate init(checkpoint: FieldDraftCheckpointV1,
                     payload: RepetitiveCaptureDestinationReviewPayloadV1, sourceReviewDraftID: UUID) {
        self.checkpoint = checkpoint
        self.payload = payload
        self.sourceReviewDraftID = sourceReviewDraftID
    }
}

enum RepetitiveCaptureDestinationReviewV1 {
    static func prepareFirst(from reviewed: ReviewedRepetitiveCaptureSourceGraphsV2,
                             sourceDraftID: UUID, identity: RestoreIdentityV1,
                             reviewedAt: Date) throws -> PreparedRepetitiveCaptureDestinationReviewV1 {
        let payload = try firstPayload(from: reviewed, sourceDraftID: sourceDraftID, identity: identity)
        let checkpoint = try initialCheckpoint(payload: payload, generationID: identity.targetPointer.generationID,
            reviewedAt: reviewedAt, unavailable: Set(reviewed.requiredHistory.map { $0.envelope.mutationID.rawValue }))
        return .init(checkpoint: checkpoint, payload: payload)
    }

    static func prepareInherited(from lineage: RepetitiveCaptureReviewLineageV1,
                                 identity: RestoreIdentityV1, reviewedAt: Date) throws
        -> PreparedRepetitiveCaptureInheritedReviewV1 {
        let previous = lineage.selectedReview
        guard identity.source.workspaceID == previous.checkpoint.workspaceID.rawValue,
              identity.targetPointer.workspaceID != previous.checkpoint.workspaceID.rawValue,
              identity.recordIdentityDisposition == .preserve else { throw FieldDraftFailureV1.wrongWorkspace }
        let mode: RepetitiveCaptureReviewModeV1
        switch identity.mode {
        case .replaceExisting: mode = .crossWorkspaceReplace
        case .fork: mode = .fork
        case .clone, .emptyInstall: throw FieldDraftFailureV1.invalidValue
        }
        let payload = try inheritedPayload(predecessor: previous.payload, original: previous.anchor,
            checkpoint: previous.checkpoint, mode: mode,
            workspace: WorkspaceID(rawValue: identity.targetPointer.workspaceID))
        var unavailable = Set(lineage.requiredHistory.map { $0.envelope.mutationID.rawValue })
        for review in lineage.reviews {
            unavailable.insert(review.checkpoint.draftID)
            unavailable.formUnion(review.payload.provenance.ultimateToDestinationPairs.flatMap {
                [$0.sourceID, $0.destinationID]
            })
        }
        let checkpoint = try initialCheckpoint(payload: payload, generationID: identity.targetPointer.generationID,
            reviewedAt: reviewedAt, unavailable: unavailable)
        return .init(checkpoint: checkpoint, payload: payload, sourceReviewDraftID: previous.checkpoint.draftID)
    }

    private static func initialCheckpoint(payload: RepetitiveCaptureDestinationReviewPayloadV1,
                                          generationID: UUID, reviewedAt: Date,
                                          unavailable: Set<UUID>) throws -> FieldDraftCheckpointV1 {
        let ids = try RepetitiveCaptureDestinationReviewCodecV1.initialIDs(
            payload: payload, generationID: generationID)
        let blocked = unavailable.union(payload.provenance.ultimateToDestinationPairs.flatMap { [$0.sourceID, $0.destinationID] })
        guard !blocked.contains(ids.draftID), !blocked.contains(ids.mutationID.rawValue),
              ids.draftID != ids.mutationID.rawValue else { throw FieldDraftFailureV1.invalidValue }
        let checkpoint = try FieldDraftCheckpointV1(draftID: ids.draftID,
            workspaceID: payload.provenance.destinationWorkspaceID,
            scope: RepetitiveCaptureDestinationReviewCodecV1.scope(draftID: ids.draftID),
            purpose: .repetitiveCapture, codec: RepetitiveCaptureDestinationReviewCodecV1.release(),
            baseCanonicalRevision: payload.source.value.packageCurrentRound.revision,
            draftRevision: 1, payloadData: RepetitiveCaptureDestinationReviewCodecV1.encode(payload),
            stageIDs: [], resumeAnchor: DraftResumeAnchorV1(sectionID: "sourceReview"),
            state: .recoveryRequired, updatedAt: reviewedAt, mutationID: ids.mutationID)
        try RepetitiveCaptureDestinationReviewCodecV1.validateInitialCheckpoint(
            checkpoint, creationGenerationID: generationID)
        return checkpoint
    }

    fileprivate static func inheritedPayload(predecessor: RepetitiveCaptureDestinationReviewPayloadV1,
                                             original: RepetitiveCaptureSourceHistoryRecordV2,
                                             checkpoint: FieldDraftCheckpointV1,
                                             mode: RepetitiveCaptureReviewModeV1, workspace: WorkspaceID) throws
        -> RepetitiveCaptureDestinationReviewPayloadV1 {
        try predecessor.validate()
        try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(checkpoint)
        let committed = try FieldDraftCommittedEvidenceV1(envelope: original.envelope, receipt: original.receipt)
        guard workspace != checkpoint.workspaceID,
              checkpoint.payloadData == (try RepetitiveCaptureDestinationReviewCodecV1.encode(predecessor)),
              RepetitiveCaptureSourceGraphReviewV2.checkpointPostImage(committed.mutation.postImage) == checkpoint
        else { throw FieldDraftFailureV1.invalidValue }
        var immediate: [RepetitiveCaptureReviewIdentityPairV1] = []
        var composed: [RepetitiveCaptureReviewIdentityPairV1] = []
        for pair in predecessor.provenance.ultimateToDestinationPairs {
            // Derive this hop from authenticated predecessor endpoints. Never
            // transform the ultimate source endpoint again to simulate a chain.
            let destination = try RepetitiveCaptureReviewRelationsV1.destination(
                pair.destinationID, kind: pair.kind, mode: mode, workspaceID: workspace)
            immediate.append(try .init(kind: pair.kind, sourceID: pair.destinationID, destinationID: destination))
            composed.append(try .init(kind: pair.kind, sourceID: pair.sourceID, destinationID: destination))
        }
        immediate.sort(by: RepetitiveCaptureReviewRelationsV1.precedes)
        composed.sort(by: RepetitiveCaptureReviewRelationsV1.precedes)
        let link = try RepetitiveCaptureReviewPredecessorV1(workspaceID: checkpoint.workspaceID,
            reviewDraftID: checkpoint.draftID, reviewCheckpointSHA256: checkpoint.checkpointSHA256,
            reviewMutationID: original.envelope.mutationID,
            reviewEnvelopeSHA256: FieldDraftCanonicalCodecV1.sha256(original.original.envelopeData),
            reviewReceiptIdentity: original.receipt.identity,
            reviewReceiptSHA256: FieldDraftCanonicalCodecV1.sha256(original.original.receiptData),
            predecessorProvenanceSHA256: predecessor.provenance.provenanceSHA256,
            predecessorToDestinationPairs: immediate)
        return try .init(source: predecessor.source, provenance: .init(mode: mode,
            destinationWorkspaceID: workspace, ultimateSourceReferenceSHA256: predecessor.source.referenceSHA256,
            ultimateToDestinationPairs: composed, immediatePredecessor: link))
    }

    fileprivate static func firstPayload(from reviewed: ReviewedRepetitiveCaptureSourceGraphsV2,
                                         sourceDraftID: UUID, identity: RestoreIdentityV1) throws
        -> RepetitiveCaptureDestinationReviewPayloadV1 {
        guard identity.source.workspaceID == reviewed.sourceWorkspaceID.rawValue,
              identity.targetPointer.workspaceID != reviewed.sourceWorkspaceID.rawValue,
              identity.recordIdentityDisposition == .preserve else { throw FieldDraftFailureV1.wrongWorkspace }
        let mode: RepetitiveCaptureReviewModeV1
        switch identity.mode {
        case .replaceExisting: mode = .crossWorkspaceReplace
        case .fork: mode = .fork
        case .clone, .emptyInstall: throw FieldDraftFailureV1.invalidValue
        }
        let matches = reviewed.graphs.filter { $0.chain.sourceCheckpoint.draftID == sourceDraftID }
        guard matches.count == 1, let graph = matches.first else { throw FieldDraftFailureV1.invalidValue }
        let references = try RepetitiveCaptureSourceGraphReviewV2.references(from: reviewed)
        guard let source = references.first(where: { $0.value.sourceDraftID == sourceDraftID }),
              graph.checkpoints.map({ $0.original.draftID }) == source.value.checkpoints.map(\.draftID) else {
            throw FieldDraftFailureV1.invalidValue
        }
        return try firstPayload(source: source, graph: graph, mode: mode,
            workspace: WorkspaceID(rawValue: identity.targetPointer.workspaceID))
    }

    fileprivate static func firstPayload(source: RepetitiveCaptureSourceGraphReferenceV2,
                                         graph: ReviewedRepetitiveCaptureSourceGraphV2,
                                         mode: RepetitiveCaptureReviewModeV1,
                                         workspace: WorkspaceID) throws
        -> RepetitiveCaptureDestinationReviewPayloadV1 {
        guard workspace != source.value.sourceWorkspaceID,
              graph.chain.sourceCheckpoint.draftID == source.value.sourceDraftID,
              graph.checkpoints.map({ $0.original.draftID }) == source.value.checkpoints.map(\.draftID)
        else { throw FieldDraftFailureV1.wrongWorkspace }
        var required = Set<RepetitiveCaptureReviewRelationsV1.Key>()
        for frontier in source.value.checkpoints { required.insert(.init(kind: .checkpoint, id: frontier.draftID)) }
        required.insert(.init(kind: .roundSession, id: source.value.roundSessionID))
        required.insert(.init(kind: .launchPlan, id: graph.chain.launch.planID))
        for item in graph.packageCurrentRound.items {
            required.insert(.init(kind: .roundItem, id: item.itemID))
            required.insert(.init(kind: .asset, id: item.selection.assetID))
            required.insert(.init(kind: .site, id: item.selection.siteID))
            if let completion = item.completion { required.insert(.init(kind: .completion, id: completion.completionID)) }
        }
        let pairs = try required.map { key in
            try RepetitiveCaptureReviewIdentityPairV1(kind: key.kind, sourceID: key.id,
                destinationID: RepetitiveCaptureReviewRelationsV1.destination(
                    key.id, kind: key.kind, mode: mode, workspaceID: workspace))
        }.sorted(by: RepetitiveCaptureReviewRelationsV1.precedes)
        return try .init(source: source, provenance: .init(mode: mode, destinationWorkspaceID: workspace,
            ultimateSourceReferenceSHA256: source.referenceSHA256, ultimateToDestinationPairs: pairs))
    }
}

/// This definition is intentionally absent from shipping purpose registration.
/// A definition or decoded checkpoint grants no destination effect authority.
enum RepetitiveCaptureDestinationReviewCodecV1 {
    static let maximumPayloadBytes = FieldDraftLimitsV1.maximumPayloadBytes
    static let grammarDescriptor = "assetrounds.c36.destination-review.v1|canonical=FieldDraftCanonicalCodecV1.byteExact|closedIntroducedKeysAndTags|payload=schemaVersion,tag:SOURCE_GRAPH_REVIEW,source:sourceGraphReferenceV1,provenance|provenance=schemaVersion,mode:CROSS_WORKSPACE_REPLACE/FORK,destinationWorkspaceID,ultimateSourceReferenceSHA256,ultimateToDestinationPairs,immediatePredecessor?,provenanceSHA256|pair=kind:CHECKPOINT/ROUND_SESSION/ROUND_ITEM/LAUNCH_PLAN/SITE/ASSET/COMPLETION,sourceID,destinationID|pairs=kindThenSourceThenDestination.lowercaseUUID;nonzero;uniqueKindSourceAndKindDestination;identityPairsAllowed;maximum1203|predecessor=workspaceID,reviewDraftID,reviewCheckpointSHA256,reviewMutationID,reviewEnvelopeSHA256,reviewReceiptIdentity,reviewReceiptSHA256,predecessorProvenanceSHA256,predecessorToDestinationPairs|noNestedPayloadOrRawHistory;noHopLimit;receiptLinksNeedJournalReauthentication|firstCoverage=all401OrFewerCheckpointFrontiers,roundSession,launchPlan,currentRoundItemsAssetsSitesCompletions|firstMapping=existingRestoreCanonicalPreservationAndDraftForkNamespace|initialIDs=sha256CanonicalIdentityBody.formatRoleWorkspaceGenerationProvenance;uuidVersion5VariantRFC4122|initialCheckpoint=revision1,RECOVERY_REQUIRED,noStages,noLastReceipt,basePackageCurrentRound,sourceReviewAnchor|sameCodecLifecycleOnly;separateReceiptedContinuation|maximumPayloadBytes2097152|purpose=repetitiveCapture;target=applyFieldDraft;explicitDiscardOnly;workspacePrivate|notRegistered;noCurrentReadinessOrEffectAuthority"
    static let releaseSHA256 = "0d301e3c040ac66041b2556bb4eb1246bb8f7b9639974108e6297a0b0fd4fa65"

    static func release() throws -> DraftPayloadCodecReleaseV1 {
        guard maximumPayloadBytes == 2_097_152, ScanToWorkLimitsV1.maximumSelection == 200,
              RepetitiveCaptureSourceGraphReferenceV2.maximumFrontiers == 401,
              RepetitiveCaptureReviewRelationsV1.maximumPairs == 1_203,
              FieldDraftCanonicalCodecV1.sha256(Data(grammarDescriptor.utf8)) == releaseSHA256 else {
            throw FieldDraftFailureV1.digestMismatch
        }
        return try .init(codecID: "assetrounds.repetitive-capture.destination-review.v1",
                         codecVersion: 1, releaseSHA256: releaseSHA256)
    }
    static func definition() throws -> DraftPurposeDefinitionV1 {
        try .init(purpose: .repetitiveCapture, codec: release(), maximumPayloadBytes: maximumPayloadBytes,
                  maximumStageItems: 0, targetCommandKind: .applyFieldDraft, retention: .explicitDiscardOnly,
                  attachmentKinds: [], privacyClass: .workspacePrivate)
    }
    static func encode(_ value: RepetitiveCaptureDestinationReviewPayloadV1) throws -> Data {
        _ = try release()
        try value.validate()
        let data = try FieldDraftCanonicalCodecV1.encode(value)
        guard !data.isEmpty, data.count <= maximumPayloadBytes else { throw FieldDraftFailureV1.limitExceeded }
        return data
    }
    static func decode(_ data: Data) throws -> RepetitiveCaptureDestinationReviewPayloadV1 {
        _ = try release()
        guard !data.isEmpty, data.count <= maximumPayloadBytes else { throw FieldDraftFailureV1.limitExceeded }
        let value = try FieldDraftCanonicalCodecV1.decode(RepetitiveCaptureDestinationReviewPayloadV1.self, from: data)
        guard try encode(value) == data else { throw FieldDraftFailureV1.digestMismatch }
        return value
    }
    static func scope(draftID: UUID) throws -> DraftScopeKeyV1 {
        try FieldDraftValidationV1.id(draftID)
        return try .init(scopeKind: "repetitiveCapture.destinationReview.v1",
                         stableComponentIDs: [draftID.uuidString.lowercased()])
    }
    static func validateCheckpoint(_ checkpoint: FieldDraftCheckpointV1) throws {
        try checkpoint.validate()
        guard checkpoint.purpose == .repetitiveCapture, checkpoint.codec == (try release()),
              checkpoint.scope == (try scope(draftID: checkpoint.draftID)), checkpoint.stageIDs.isEmpty,
              [.recoveryRequired, .active, .conflicted, .discardPending, .discarded].contains(checkpoint.state) else {
            throw FieldDraftFailureV1.invalidValue
        }
        let payload = try decode(checkpoint.payloadData)
        guard payload.provenance.destinationWorkspaceID == checkpoint.workspaceID else {
            throw FieldDraftFailureV1.wrongWorkspace
        }
        if checkpoint.draftRevision == 1 {
            guard checkpoint.state == .recoveryRequired, checkpoint.lastDurableMutationID == nil,
                  checkpoint.lastReceiptSHA256 == nil,
                  checkpoint.baseCanonicalRevision == payload.source.value.packageCurrentRound.revision,
                  checkpoint.resumeAnchor == (try DraftResumeAnchorV1(sectionID: "sourceReview")) else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
    }
    static func validateInitialCheckpoint(_ checkpoint: FieldDraftCheckpointV1,
                                          creationGenerationID: UUID) throws {
        try validateCheckpoint(checkpoint)
        guard checkpoint.draftRevision == 1 else { throw FieldDraftFailureV1.invalidValue }
        let payload = try decode(checkpoint.payloadData)
        let ids = try initialIDs(payload: payload, generationID: creationGenerationID)
        guard checkpoint.draftID == ids.draftID, checkpoint.mutationID == ids.mutationID else {
            throw FieldDraftFailureV1.invalidValue
        }
    }
    /// Pure deterministic identity derivation; these IDs grant no source or receipt authority.
    static func initialIDs(payload: RepetitiveCaptureDestinationReviewPayloadV1,
                                       generationID: UUID) throws -> (draftID: UUID, mutationID: MutationIDV1) {
        try payload.validate()
        try FieldDraftValidationV1.id(generationID)
        struct IdentityBody: Codable {
            let format: String
            let role: String
            let workspaceID: WorkspaceID
            let generationID: UUID
            let provenanceSHA256: String
        }
        func id(_ role: String) throws -> UUID {
            let hash = try FieldDraftCanonicalCodecV1.sha256(IdentityBody(
                format: "assetrounds.c36.destination-review-identity.v1", role: role,
                workspaceID: payload.provenance.destinationWorkspaceID, generationID: generationID,
                provenanceSHA256: payload.provenance.provenanceSHA256))
            var bytes: [UInt8] = []
            for offset in stride(from: 0, to: 32, by: 2) {
                guard let value = UInt8(hash.dropFirst(offset).prefix(2), radix: 16) else {
                    throw FieldDraftFailureV1.digestMismatch
                }
                bytes.append(value)
            }
            bytes[6] = (bytes[6] & 0x0f) | 0x50
            bytes[8] = (bytes[8] & 0x3f) | 0x80
            return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
                               bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        }
        return try (id("checkpoint"), MutationIDV1(rawValue: id("mutation")))
    }
}

private enum RepetitiveCaptureReviewRelationsV1 {
    struct Key: Hashable { let kind: RepetitiveCaptureReviewIdentityKindV1; let id: UUID }
    static let maximumPairs = 2 + RepetitiveCaptureSourceGraphReferenceV2.maximumFrontiers
        + 4 * ScanToWorkLimitsV1.maximumSelection

    static func validate(_ pairs: [RepetitiveCaptureReviewIdentityPairV1]) throws {
        guard !pairs.isEmpty, pairs.count <= maximumPairs, pairs == pairs.sorted(by: precedes),
              Set(pairs.map { Key(kind: $0.kind, id: $0.sourceID) }).count == pairs.count,
              destinations(pairs).count == pairs.count else { throw FieldDraftFailureV1.invalidValue }
        try pairs.forEach { try $0.validate() }
    }
    static func destinations(_ pairs: [RepetitiveCaptureReviewIdentityPairV1]) -> Set<Key> {
        Set(pairs.map { Key(kind: $0.kind, id: $0.destinationID) })
    }
    static func precedes(_ lhs: RepetitiveCaptureReviewIdentityPairV1,
                         _ rhs: RepetitiveCaptureReviewIdentityPairV1) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.sourceID != rhs.sourceID { return lhs.sourceID.uuidString.lowercased() < rhs.sourceID.uuidString.lowercased() }
        return lhs.destinationID.uuidString.lowercased() < rhs.destinationID.uuidString.lowercased()
    }
    static func destination(_ id: UUID, kind: RepetitiveCaptureReviewIdentityKindV1,
                            mode: RepetitiveCaptureReviewModeV1, workspaceID: WorkspaceID) throws -> UUID {
        let result: UUID?
        if kind == .checkpoint {
            result = RestoreIdentityV1.destinationFieldDraftID(for: id, namespace: "draft",
                mode: mode.restoreMode, destinationWorkspaceID: workspaceID.rawValue)
        } else {
            result = RestoreIdentityV1.destinationRecordID(for: id)
        }
        guard let result else { throw FieldDraftFailureV1.invalidValue }
        return result
    }
}

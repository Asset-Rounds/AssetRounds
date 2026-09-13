import Foundation

/// An immutable snapshot of an existing active Round, with the actual proofs
/// returned by its readiness owner. This is not a scan/addition selection.
struct RepetitiveCaptureLaunchSourceV2: Codable, Equatable, Sendable {
    let planID: UUID
    let round: RoundSessionV1
    let readiness: [ScanToWorkOfflineReadinessProofV1]

    init(planID: UUID, round: RoundSessionV1,
         readiness: [ScanToWorkOfflineReadinessProofV1]) throws {
        self.planID = planID; self.round = round; self.readiness = readiness
        try validate()
    }

    func validate() throws {
        try round.validateIntrinsic()
        guard planID != Self.zero, round.state == .active,
              round.items.count <= ScanToWorkLimitsV1.maximumSelection, readiness.count == round.items.count,
              let first = readiness.first else { throw ScanToWorkFailureV1.authorityMismatch }
        let reference = try round.reference
        for (item, proof) in zip(round.items, readiness) {
            try proof.validateIntrinsic()
            guard proof.session == reference, proof.workspaceID == round.workspaceID,
                  proof.assetID == item.selection.assetID,
                  proof.manifestSHA256 == first.manifestSHA256,
                  proof.sourceSnapshotSHA256 == first.sourceSnapshotSHA256,
                  proof.status == first.status, proof.checkedAt == first.checkedAt,
                  proof.checkedAt.timeIntervalSince1970.isFinite else {
                throw ScanToWorkFailureV1.authorityMismatch
            }
        }
    }

    var firstIncompleteItemID: UUID? { round.items.first { !$0.disposition.isTerminal }?.itemID }
    private static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

enum RepetitiveCaptureProgressActionV2: String, Codable, Equatable, Sendable {
    case enter = "ENTRY"
    case complete = "COMPLETE_AND_NEXT"
    case `defer` = "DEFER_AND_NEXT"
    case keepOpenAndNext = "KEEP_OPEN_AND_NEXT"
}

/// The exact prepared action, persisted before its optional Round effect.
/// ENTRY on an already visited item and KEEP_OPEN have no Round mutation.
struct RepetitiveCaptureProgressStepV2: Codable, Equatable, Sendable {
    let source: RepetitiveCaptureSourceCheckpointReferenceV1
    let prior: RepetitiveCaptureSourceCheckpointReferenceV1?
    let priorRoundReceipt: RoundSessionMutationReceiptV1?
    let expectedRound: RoundSessionV1
    let itemID: UUID
    let action: RepetitiveCaptureProgressActionV2
    let roundMutation: RoundSessionMutationV1?
    let requirementFocus: RepetitiveCaptureRequirementFocusV1
    let resumeAnchor: DraftResumeAnchorV1
    let navigationItemID: UUID?

    init(source: RepetitiveCaptureSourceCheckpointReferenceV1,
         prior: RepetitiveCaptureSourceCheckpointReferenceV1?,
         priorRoundReceipt: RoundSessionMutationReceiptV1?, expectedRound: RoundSessionV1,
         itemID: UUID, action: RepetitiveCaptureProgressActionV2,
         roundMutation: RoundSessionMutationV1?, requirementFocus: RepetitiveCaptureRequirementFocusV1,
         resumeAnchor: DraftResumeAnchorV1) throws {
        self.source = source; self.prior = prior; self.priorRoundReceipt = priorRoundReceipt
        self.expectedRound = expectedRound; self.itemID = itemID; self.action = action
        self.roundMutation = roundMutation; self.requirementFocus = requirementFocus
        self.resumeAnchor = resumeAnchor
        navigationItemID = try Self.navigation(expected: expectedRound, itemID: itemID,
                                               action: action, mutation: roundMutation)
        try validate()
    }

    var resultingRound: RoundSessionV1 { roundMutation?.session ?? expectedRound }

    func validate() throws {
        try source.validate(); try prior?.validate(); try priorRoundReceipt?.validate()
        try expectedRound.validateIntrinsic(); try resumeAnchor.validate()
        guard expectedRound.state == .active,
              prior?.draftID != source.draftID,
              prior != nil || priorRoundReceipt == nil,
              navigationItemID == (try Self.navigation(expected: expectedRound, itemID: itemID,
                                                       action: action, mutation: roundMutation)),
              resumeAnchor.selectedStableID == resultingRound.items.first(where: {
                  $0.itemID == navigationItemID
              })?.selection.assetID.uuidString.lowercased() else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
    }

    /// Validate a node against the exact authenticated source and preceding
    /// node. Canonical receipt presence is checked separately by the lifecycle.
    func validate(sourceCheckpoint: FieldDraftCheckpointV1,
                  priorCheckpoint: FieldDraftCheckpointV1?) throws {
        try validate(); try source.validate(source: sourceCheckpoint)
        let launch = try RepetitiveCaptureProgressDraftCodecV2.source(sourceCheckpoint)
        let currentItem: UUID?
        let frontier: RoundSessionV1
        if let priorCheckpoint {
            guard let prior else { throw ScanToWorkFailureV1.authorityMismatch }
            try prior.validate(source: priorCheckpoint)
            guard case let .progress(previous) = try RepetitiveCaptureProgressDraftCodecV2.decode(priorCheckpoint.payloadData),
                  previous.source == source,
                  !(action == .enter && previous.action == .enter && previous.itemID == itemID) else {
                throw ScanToWorkFailureV1.authorityMismatch
            }
            if let mutation = previous.roundMutation {
                guard let receipt = priorRoundReceipt, receipt.mutation == mutation else {
                    throw ScanToWorkFailureV1.authorityMismatch
                }
                try receipt.validate()
            } else {
                guard priorRoundReceipt == nil else { throw ScanToWorkFailureV1.authorityMismatch }
            }
            frontier = previous.resultingRound; currentItem = previous.navigationItemID
        } else {
            guard prior == nil, priorRoundReceipt == nil else { throw ScanToWorkFailureV1.authorityMismatch }
            frontier = launch.round; currentItem = launch.firstIncompleteItemID
        }
        guard expectedRound == frontier, itemID == currentItem else { throw ScanToWorkFailureV1.stale }
    }

    private static func navigation(expected: RoundSessionV1, itemID: UUID,
                                   action: RepetitiveCaptureProgressActionV2,
                                   mutation: RoundSessionMutationV1?) throws -> UUID? {
        try expected.validateIntrinsic()
        guard expected.state == .active,
              let index = expected.items.firstIndex(where: { $0.itemID == itemID }),
              !expected.items[index].disposition.isTerminal else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let old = expected.items[index]
        let requiredTransition: RoundSessionTransitionV1?
        switch action {
        case .enter: requiredTransition = old.disposition == .pending ? .visitItem : nil
        case .complete:
            guard old.disposition == .visited else { throw ScanToWorkFailureV1.authorityMismatch }
            requiredTransition = .completeItem
        case .defer: requiredTransition = .deferItem
        case .keepOpenAndNext:
            guard old.disposition == .visited else { throw ScanToWorkFailureV1.authorityMismatch }
            requiredTransition = nil
        }
        let result: RoundSessionV1
        if let requiredTransition {
            guard let mutation, mutation.workspaceID == expected.workspaceID,
                  mutation.expectedRevision == expected.revision,
                  mutation.session.transition == requiredTransition,
                  mutation.session.transitionItemID == itemID else {
                throw ScanToWorkFailureV1.authorityMismatch
            }
            try mutation.validate(); try mutation.session.validateSuccessor(of: expected)
            result = mutation.session
        } else {
            guard mutation == nil else { throw ScanToWorkFailureV1.authorityMismatch }
            result = expected
        }
        if action == .enter { return itemID }
        return result.items.dropFirst(index + 1).first { !$0.disposition.isTerminal }?.itemID
    }
}

enum RepetitiveCaptureProgressDraftPayloadV2: Codable, Equatable, Sendable {
    case source(RepetitiveCaptureLaunchSourceV2)
    case progress(RepetitiveCaptureProgressStepV2)

    func validate() throws {
        switch self { case let .source(value): try value.validate()
        case let .progress(value): try value.validate() }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, tag, source, progress }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == 2 else { throw FieldDraftFailureV1.unknownCodec }
        switch try c.decode(String.self, forKey: .tag) {
        case "EXISTING_ACTIVE_ROUND":
            guard !c.contains(.progress) else { throw FieldDraftFailureV1.invalidValue }
            self = .source(try c.decode(RepetitiveCaptureLaunchSourceV2.self, forKey: .source))
        case "PROGRESS":
            guard !c.contains(.source) else { throw FieldDraftFailureV1.invalidValue }
            self = .progress(try c.decode(RepetitiveCaptureProgressStepV2.self, forKey: .progress))
        default: throw FieldDraftFailureV1.invalidValue
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate(); var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(2, forKey: .schemaVersion)
        switch self {
        case let .source(value): try c.encode("EXISTING_ACTIVE_ROUND", forKey: .tag); try c.encode(value, forKey: .source)
        case let .progress(value): try c.encode("PROGRESS", forKey: .tag); try c.encode(value, forKey: .progress)
        }
    }
}

enum RepetitiveCaptureProgressDraftCodecV2 {
    static let maximumPayloadBytes = FieldDraftLimitsV1.maximumPayloadBytes
    static let grammarDescriptor = "repetitive-capture-v2|EXISTING_ACTIVE_ROUND:planID,canonicalActiveRound,orderedActualReadinessProofs|PROGRESS:source,prior?,priorRoundReceipt?,expectedRound,itemID,action,roundMutation?,requirementFocus,resumeAnchor,navigationItemID|ENTRY:pendingVisitOrVisitedNoEffect|ADVANCE:complete,defer,visitedKeepOpenNoEffect|exactImmutableChainAndCanonicalReceipts|originalRoundOrderAndTerminalTruth|onePassMaximumNodes=2*itemCount|noRepeatedEntry|maximumItems=200|maximumPayloadBytes=2097152|maximumStageItems=0"
    static let releaseSHA256 = "9187aad927f80dd85a866d84feeabbe1fd295883afa4fff20445176008f75516"
    static func release() throws -> DraftPayloadCodecReleaseV1 {
        guard FieldDraftCanonicalCodecV1.sha256(Data(grammarDescriptor.utf8)) == releaseSHA256 else {
            throw FieldDraftFailureV1.digestMismatch
        }
        return try .init(codecID: "assetrounds.repetitive-capture.v2", codecVersion: 2, releaseSHA256: releaseSHA256)
    }
    static func definition() throws -> DraftPurposeDefinitionV1 {
        try .init(purpose: .repetitiveCapture, codec: release(), maximumPayloadBytes: maximumPayloadBytes,
                  maximumStageItems: 0, targetCommandKind: .applyRoundSession, retention: .explicitDiscardOnly,
                  attachmentKinds: [], privacyClass: .workspacePrivate)
    }
    static func encode(_ payload: RepetitiveCaptureProgressDraftPayloadV2) throws -> Data {
        _ = try release(); try payload.validate(); let bytes = try FieldDraftCanonicalCodecV1.encode(payload)
        guard !bytes.isEmpty, bytes.count <= maximumPayloadBytes else { throw FieldDraftFailureV1.limitExceeded }
        return bytes
    }
    static func decode(_ bytes: Data) throws -> RepetitiveCaptureProgressDraftPayloadV2 {
        _ = try release()
        guard !bytes.isEmpty, bytes.count <= maximumPayloadBytes else { throw FieldDraftFailureV1.limitExceeded }
        let value = try FieldDraftCanonicalCodecV1.decode(RepetitiveCaptureProgressDraftPayloadV2.self, from: bytes)
        guard try encode(value) == bytes else { throw FieldDraftFailureV1.digestMismatch }
        return value
    }
    static func validateCheckpoint(_ checkpoint: FieldDraftCheckpointV1) throws {
        try checkpoint.validate(authority: RepetitiveCaptureDraftPurposeAuthorityV1())
        guard checkpoint.purpose == .repetitiveCapture, checkpoint.codec == (try release()),
              checkpoint.draftRevision == 1, checkpoint.state == .active,
              checkpoint.stageIDs.isEmpty, checkpoint.lastDurableMutationID == nil,
              checkpoint.lastReceiptSHA256 == nil else { throw FieldDraftFailureV1.invalidValue }
        _ = try decode(checkpoint.payloadData)
    }
    static func source(_ checkpoint: FieldDraftCheckpointV1) throws -> RepetitiveCaptureLaunchSourceV2 {
        try validateCheckpoint(checkpoint)
        guard case let .source(launch) = try decode(checkpoint.payloadData),
              checkpoint.workspaceID == launch.round.workspaceID,
              checkpoint.resumeAnchor.selectedStableID == launch.round.items.first(where: {
                  $0.itemID == launch.firstIncompleteItemID
              })?.selection.assetID.uuidString.lowercased(),
              checkpoint.scope == (try RepetitiveCaptureDraftCodecV1.scope(planID: launch.planID, round: launch.round.reference)) else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        return launch
    }
}

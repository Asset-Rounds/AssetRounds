import Foundation

private let repetitiveCaptureDraftZeroUUIDV1 = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

struct RepetitiveCaptureSourceCheckpointReferenceV1: Codable, Equatable, Sendable {
    let draftID: UUID; let draftRevision: UInt64; let checkpointSHA256: String; let mutationID: MutationIDV1
    init(source: FieldDraftCheckpointV1) throws {
        try source.validate(); draftID = source.draftID; draftRevision = source.draftRevision
        checkpointSHA256 = source.checkpointSHA256; mutationID = source.mutationID; try validate()
    }
    func validate() throws {
        guard draftID != repetitiveCaptureDraftZeroUUIDV1, draftRevision > 0,
              MutationEnvelopeV1.isSHA256(checkpointSHA256) else { throw FieldDraftFailureV1.invalidValue }
    }
    func validate(source: FieldDraftCheckpointV1) throws {
        try validate(); try source.validate()
        guard draftID == source.draftID, draftRevision == source.draftRevision,
              checkpointSHA256 == source.checkpointSHA256, mutationID == source.mutationID else { throw ScanToWorkFailureV1.stale }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case draftID, draftRevision, checkpointSHA256, mutationID }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        draftID = try c.decode(UUID.self, forKey: .draftID); draftRevision = try c.decode(UInt64.self, forKey: .draftRevision)
        checkpointSHA256 = try c.decode(String.self, forKey: .checkpointSHA256); mutationID = try c.decode(MutationIDV1.self, forKey: .mutationID); try validate()
    }
}

enum RepetitiveCaptureDraftPayloadV1: Codable, Equatable, Sendable {
    case source(planID: UUID, round: RoundSessionReferenceV1, selection: BatchScanSelectionV1)
    case continuation(source: RepetitiveCaptureSourceCheckpointReferenceV1, request: RepetitiveCaptureCheckpointRequestV1)
    static let schemaVersion = 1
    func validate() throws {
        switch self {
        case let .source(planID, round, selection):
            guard planID != repetitiveCaptureDraftZeroUUIDV1 else { throw FieldDraftFailureV1.invalidValue }
            try round.validate(); try selection.validateIntrinsic()
            guard round.workspaceID == selection.workspaceID else { throw ScanToWorkFailureV1.authorityMismatch }
        case let .continuation(source, request):
            try source.validate(); try Self.validatedRequest(request)
            guard request.plan.draftID == source.draftID, request.plan.draftRevision == source.draftRevision,
                  request.plan.draftSHA256 == source.checkpointSHA256 else { throw ScanToWorkFailureV1.stale }
        }
    }
    fileprivate static func validatedRequest(_ request: RepetitiveCaptureCheckpointRequestV1) throws {
        let exact = try RepetitiveCaptureCheckpointRequestV1(plan: request.plan, assetID: request.assetID,
            disposition: request.disposition, requirementFocus: request.requirementFocus,
            resumeAnchor: request.resumeAnchor, roundMutation: request.roundMutation)
        guard exact == request else { throw ScanToWorkFailureV1.authorityMismatch }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, tag, planID, round, selection, source, request }
    private enum Tag: String, Codable { case source = "SOURCE", continuation = "CONTINUATION" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FieldDraftFailureV1.incompatibleVersion }
        let tag = try c.decode(Tag.self, forKey: .tag)
        let keys: Set<String>
        switch tag {
        case .source: keys = ["schemaVersion", "tag", "planID", "round", "selection"]
        case .continuation: keys = ["schemaVersion", "tag", "source", "request"]
        }
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: keys)
        switch tag {
        case .source: self = .source(planID: try c.decode(UUID.self, forKey: .planID), round: try c.decode(RoundSessionReferenceV1.self, forKey: .round), selection: try c.decode(BatchScanSelectionV1.self, forKey: .selection))
        case .continuation: self = .continuation(source: try c.decode(RepetitiveCaptureSourceCheckpointReferenceV1.self, forKey: .source), request: try c.decode(RepetitiveCaptureCheckpointRequestV1.self, forKey: .request))
        }
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        try validate(); var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(Self.schemaVersion, forKey: .schemaVersion)
        switch self {
        case let .source(planID, round, selection): try c.encode(Tag.source, forKey: .tag); try c.encode(planID, forKey: .planID); try c.encode(round, forKey: .round); try c.encode(selection, forKey: .selection)
        case let .continuation(source, request): try c.encode(Tag.continuation, forKey: .tag); try c.encode(source, forKey: .source); try c.encode(request, forKey: .request)
        }
    }
}

enum RepetitiveCaptureDraftCodecV1 {
    static let maximumPayloadBytes = 1_048_576; static let codecID = "assetrounds.repetitive-capture.v1"; static let codecVersion: UInt64 = 1
    static let grammarDescriptor = [
        "codecID=assetrounds.repetitive-capture.v1", "codecVersion=1", "payload.schemaVersion=1", "payload.tag=SOURCE|CONTINUATION",
        "payload.keys.SOURCE=schemaVersion,tag,planID,round,selection", "payload.keys.CONTINUATION=schemaVersion,tag,source,request",
        "source.keys=draftID,draftRevision,checkpointSHA256,mutationID", "source.payload=planID,exactRoundPredecessor,actualBatchScanSelection",
        "source.excludes=enclosingCheckpointDraftID,enclosingCheckpointRevision,enclosingCheckpointSHA256",
        "continuation=distinctCheckpoint,authenticatedSourceReference,exactRepetitiveCaptureCheckpointRequest",
        "canonical=WorkspaceMutationCanonicalV1.sortedKeys.byteExactReencode",
        "authority=purpose:REPETITIVE_CAPTURE,target:apply_round_session_v1,retention:EXPLICIT_DISCARD_ONLY,privacy:WORKSPACE_PRIVATE,attachments:none",
        "invariant=sourcePlanMaterializesOnlyFromExactImmutableSourceCheckpoint", "invariant=continuationRequestPlanEqualsSourceReference",
        "invariant=noAssetInferenceNoReadyProofManufactureNoSelfHashCycle", "limits.maximumPayloadBytes=1048576", "limits.maximumStageItems=0"
    ].joined(separator: "\n")
    static let releaseSHA256 = "d46b75b47de3fac01ddf9d047fa15b64f8d37d396385fea48463fc901c9f3612"
    static func release() throws -> DraftPayloadCodecReleaseV1 { guard FieldDraftCanonicalCodecV1.sha256(Data(grammarDescriptor.utf8)) == releaseSHA256 else { throw FieldDraftFailureV1.digestMismatch }; return try .init(codecID: codecID, codecVersion: codecVersion, releaseSHA256: releaseSHA256) }
    static func definition() throws -> DraftPurposeDefinitionV1 { try .init(purpose: .repetitiveCapture, codec: release(), maximumPayloadBytes: maximumPayloadBytes, maximumStageItems: 0, targetCommandKind: .applyRoundSession, retention: .explicitDiscardOnly, attachmentKinds: [], privacyClass: .workspacePrivate) }
    static func scope(planID: UUID, round: RoundSessionReferenceV1) throws -> DraftScopeKeyV1 { guard planID != repetitiveCaptureDraftZeroUUIDV1 else { throw FieldDraftFailureV1.invalidValue }; try round.validate(); return try .init(scopeKind: DraftPurposeV1.repetitiveCapture.rawValue, stableComponentIDs: [round.sessionID.uuidString.lowercased(), planID.uuidString.lowercased()]) }
    static func encode(_ payload: RepetitiveCaptureDraftPayloadV1) throws -> Data { _ = try release(); try payload.validate(); let data = try FieldDraftCanonicalCodecV1.encode(payload); guard !data.isEmpty, data.count <= maximumPayloadBytes else { throw FieldDraftFailureV1.limitExceeded }; return data }
    static func decode(_ data: Data) throws -> RepetitiveCaptureDraftPayloadV1 { _ = try release(); guard !data.isEmpty, data.count <= maximumPayloadBytes else { throw FieldDraftFailureV1.limitExceeded }; let payload = try FieldDraftCanonicalCodecV1.decode(RepetitiveCaptureDraftPayloadV1.self, from: data); try payload.validate(); guard try encode(payload) == data else { throw FieldDraftFailureV1.digestMismatch }; return payload }
    static func validateSourceCheckpoint(_ checkpoint: FieldDraftCheckpointV1) throws -> RepetitiveCaptureDraftPayloadV1 {
        let authority = try RepetitiveCaptureDraftPurposeAuthorityV1(); try checkpoint.validate(authority: authority)
        guard checkpoint.purpose == .repetitiveCapture, checkpoint.codec == (try release()), checkpoint.state == .active, checkpoint.stageIDs.isEmpty else { throw FieldDraftFailureV1.invalidValue }
        let payload = try decode(checkpoint.payloadData)
        guard case let .source(planID, round, selection) = payload, checkpoint.workspaceID == round.workspaceID,
              checkpoint.workspaceID == selection.workspaceID, checkpoint.scope == (try scope(planID: planID, round: round)) else { throw FieldDraftFailureV1.invalidValue }
        return payload
    }
    static func materializePlan(from sourceCheckpoint: FieldDraftCheckpointV1) throws -> RepetitiveCapturePlanV1 {
        let payload = try validateSourceCheckpoint(sourceCheckpoint); guard case let .source(planID, round, selection) = payload else { throw FieldDraftFailureV1.invalidValue }
        let plan = try RepetitiveCapturePlanV1(workspaceID: sourceCheckpoint.workspaceID, planID: planID, draftID: sourceCheckpoint.draftID, draftRevision: sourceCheckpoint.draftRevision, draftSHA256: sourceCheckpoint.checkpointSHA256, round: round, selection: selection)
        try C21RepetitiveCaptureDraftBoundaryV1.validate(plan: plan, checkpoint: sourceCheckpoint, registry: try RepetitiveCaptureDraftPurposeAuthorityV1()); return plan
    }
    static func validateContinuationCheckpoint(_ continuation: FieldDraftCheckpointV1, sourceCheckpoint: FieldDraftCheckpointV1) throws -> RepetitiveCaptureCheckpointRequestV1 {
        let authority = try RepetitiveCaptureDraftPurposeAuthorityV1(); try continuation.validate(authority: authority)
        guard continuation.purpose == .repetitiveCapture, continuation.codec == (try release()), continuation.state == .active, continuation.stageIDs.isEmpty, continuation.draftID != sourceCheckpoint.draftID else { throw FieldDraftFailureV1.invalidValue }
        let payload = try decode(continuation.payloadData); guard case let .continuation(source, request) = payload else { throw FieldDraftFailureV1.invalidValue }
        try source.validate(source: sourceCheckpoint); let plan = try materializePlan(from: sourceCheckpoint); try RepetitiveCaptureDraftPayloadV1.validatedRequest(request)
        guard request.plan == plan, continuation.workspaceID == sourceCheckpoint.workspaceID, continuation.resumeAnchor == request.resumeAnchor, continuation.scope == (try scope(planID: plan.planID, round: try requiredRound(plan))) else { throw ScanToWorkFailureV1.authorityMismatch }; return request
    }
    static func validateSelectedRoundItem(sourceCheckpoint: FieldDraftCheckpointV1, round: RoundSessionV1, selectedItem: RoundItemV1) throws {
        let plan = try materializePlan(from: sourceCheckpoint)
        guard let reference = plan.round, reference == (try round.reference), round.workspaceID == sourceCheckpoint.workspaceID,
              round.items.first(where: { $0.itemID == selectedItem.itemID }) == selectedItem,
              plan.selection.previews.contains(where: { preview in guard let asset = preview.asset else { return false }; return preview.outcome == .ready && asset.readiness.session == reference && asset.assetID == selectedItem.selection.assetID && asset.siteID == selectedItem.selection.siteID && asset.label == selectedItem.selection.labelAtSelection }) else { throw ScanToWorkFailureV1.authorityMismatch }
    }
    private static func requiredRound(_ plan: RepetitiveCapturePlanV1) throws -> RoundSessionReferenceV1 { guard let round = plan.round else { throw ScanToWorkFailureV1.authorityMismatch }; return round }
}

struct RepetitiveCaptureDraftPurposeAuthorityV1: DraftPurposeDefinitionResolvingV1, Sendable {
    private let definition: DraftPurposeDefinitionV1
    init() throws { definition = try RepetitiveCaptureDraftCodecV1.definition() }
    func require(_ purpose: DraftPurposeV1, codec: DraftPayloadCodecReleaseV1) throws -> DraftPurposeDefinitionV1 {
        guard purpose == .repetitiveCapture else { throw FieldDraftFailureV1.unknownPurpose }
        if codec == definition.codec { return definition }
        let progress = try RepetitiveCaptureProgressDraftCodecV2.definition()
        guard codec == progress.codec else { throw FieldDraftFailureV1.unknownCodec }
        return progress
    }
}

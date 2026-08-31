import Foundation

/// An ephemeral authority-checked projection. It is intentionally not Codable:
/// callers can only obtain one through the coordinator's live-authority checks.
struct IlluminatedSignPlaybookCheckpointProjectionV1: Equatable, Sendable {
    let checkpointSHA256: String
    let checkpointDraftRevision: UInt64
    let payload: IlluminatedSignPlaybookDraftPayloadV1
    let completeness: IlluminatedSignPlaybookCompletenessV1
    let projectionSHA256: String

    fileprivate init(checkpoint: FieldDraftCheckpointV1,
                     payload: IlluminatedSignPlaybookDraftPayloadV1,
                     completeness: IlluminatedSignPlaybookCompletenessV1) throws {
        checkpointSHA256 = checkpoint.checkpointSHA256
        checkpointDraftRevision = checkpoint.draftRevision
        self.payload = payload; self.completeness = completeness
        projectionSHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(Basis(
            checkpointSHA256: checkpoint.checkpointSHA256,
            checkpointDraftRevision: checkpoint.draftRevision,
            payload: payload, completeness: completeness
        ))
    }
    func validate() throws {
        guard projectionSHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(basis)),
              completeness.playbookID == payload.playbookID,
              completeness.payloadSHA256 == payload.payloadSHA256 else {
            throw IlluminatedSignPlaybookFailureV1.digestMismatch
        }
    }
    private var basis: Basis { .init(checkpointSHA256: checkpointSHA256,
        checkpointDraftRevision: checkpointDraftRevision, payload: payload,
        completeness: completeness) }
    private struct Basis: Codable { let checkpointSHA256: String; let checkpointDraftRevision: UInt64; let payload: IlluminatedSignPlaybookDraftPayloadV1; let completeness: IlluminatedSignPlaybookCompletenessV1 }
}

/// An ephemeral recovery result, never a second persisted or decodable authority.
struct IlluminatedSignPlaybookRecoveryV1: Equatable, Sendable {
    let checkpointDraftID: UUID
    let recoveredCheckpointSHA256: String
    let recoveredDraftRevision: UInt64
    let projection: IlluminatedSignPlaybookCheckpointProjectionV1
    let recoverySHA256: String

    init(checkpoint: FieldDraftCheckpointV1,
         projection: IlluminatedSignPlaybookCheckpointProjectionV1) throws {
        try projection.validate()
        checkpointDraftID = checkpoint.draftID
        recoveredCheckpointSHA256 = checkpoint.checkpointSHA256
        recoveredDraftRevision = checkpoint.draftRevision
        self.projection = projection
        recoverySHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(Basis(
            checkpointDraftID: checkpoint.draftID,
            recoveredCheckpointSHA256: checkpoint.checkpointSHA256,
            recoveredDraftRevision: checkpoint.draftRevision,
            projection: projection
        ))
    }
    func validate() throws {
        try projection.validate()
        guard recoveredCheckpointSHA256 == projection.checkpointSHA256,
              recoveredDraftRevision == projection.checkpointDraftRevision,
              recoverySHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(basis)) else {
            throw IlluminatedSignPlaybookFailureV1.digestMismatch
        }
    }
    private var basis: Basis { .init(checkpointDraftID: checkpointDraftID,
        recoveredCheckpointSHA256: recoveredCheckpointSHA256,
        recoveredDraftRevision: recoveredDraftRevision, projection: projection) }
    private struct Basis: Codable { let checkpointDraftID: UUID; let recoveredCheckpointSHA256: String; let recoveredDraftRevision: UInt64; let projection: IlluminatedSignPlaybookCheckpointProjectionV1 }
}

/// Pure orchestration over C05 evidence, C36 checkpoints and C37 pose events.
/// This type allocates no mutation identity and owns no persistence authority.
struct IlluminatedSignPlaybookCoordinatorV1: Sendable {
    let registry: IlluminatedSignPlaybookRegistryV1

    init(registry: IlluminatedSignPlaybookRegistryV1) throws {
        try registry.validate()
        self.registry = registry
    }

    func payload(workspaceID: WorkspaceID,
                 playbookID: IlluminatedSignPlaybookIDV1,
                 subject: EvidenceAssociationTargetV1,
                 stage: IlluminatedSignPlaybookStageV1,
                 checkedTime: IlluminatedSignCheckedTimeV1,
                 selectedVisibleCondition: IlluminatedSignSelectedVisibleConditionV1? = nil,
                 captures: [IlluminatedSignCaptureTraceV1] = [],
                 outcome: IlluminatedSignPlaybookOutcomeV1? = nil,
                 couldNotVerify: IlluminatedSignCouldNotVerifyV1? = nil,
                 poseTrace: IlluminatedSignPoseTraceV1? = nil) throws
        -> IlluminatedSignPlaybookDraftPayloadV1 {
        try IlluminatedSignPlaybookDraftPayloadV1(
            workspaceID: workspaceID, playbookID: playbookID, registry: registry,
            subject: subject,
            stage: stage, checkedTime: checkedTime,
            selectedVisibleCondition: selectedVisibleCondition,
            captures: captures, outcome: outcome, couldNotVerify: couldNotVerify,
            poseTrace: poseTrace
        )
    }

    func canonicalPayloadData(_ payload: IlluminatedSignPlaybookDraftPayloadV1) throws -> Data {
        try payload.validate(registry: registry)
        return try IlluminatedSignPlaybookCanonicalCodecV1.encode(payload)
    }

    func completeness(of payload: IlluminatedSignPlaybookDraftPayloadV1) throws
        -> IlluminatedSignPlaybookCompletenessV1 {
        try payload.validate(registry: registry)
        let manifest = try registry.manifest(for: payload.playbookID)
        let present = Set(payload.captures.map(\.slotID))
        let missing = manifest.captureRequirements.filter { $0.required && !present.contains($0.slotID) }
            .map(\.slotID)
        let identities = payload.captures.flatMap {
            [$0.item.evidenceID, $0.item.contentID, $0.item.associationBinding.associationEventID]
        }
        guard Set(payload.captures.map { $0.item.evidenceID }).count == payload.captures.count,
              Set(payload.captures.map { $0.item.contentID }).count == payload.captures.count,
              Set(payload.captures.map { $0.item.associationBinding.associationEventID }).count == payload.captures.count,
              identities.count <= IlluminatedSignPlaybookLimitsV1.maximumCaptureTraces * 3 else {
            throw IlluminatedSignPlaybookFailureV1.staleEvidence
        }
        let state: IlluminatedSignCompletenessStateV1
        if payload.outcome == .couldNotVerify, payload.couldNotVerify != nil {
            let poseMayBeOmitted = ["access_lost", "unsafe_to_continue",
                                    "required_view_obstructed", "capture_unavailable"]
                .contains(payload.couldNotVerify!.reasonKey)
            state = payload.poseTrace != nil || poseMayBeOmitted ? .couldNotVerify : .incomplete
        } else if missing.isEmpty, payload.outcome != nil, payload.poseTrace != nil {
            state = .complete
        } else {
            state = .incomplete
        }
        return IlluminatedSignPlaybookCompletenessV1(
            playbookID: payload.playbookID, state: state,
            missingRequiredSlots: missing, hasReviewedPose: payload.poseTrace != nil,
            payloadSHA256: payload.payloadSHA256
        )
    }

    func project(checkpoint: FieldDraftCheckpointV1,
                 predecessor: FieldDraftCheckpointV1? = nil,
                 associationEvents: [EvidenceAssociationV1],
                 evidenceSequence: EvidenceSequenceV1,
                 evidenceSequenceHistory: [EvidenceSequenceV1],
                 poseEventHistory: [AssetPoseEventV1]) throws
        -> IlluminatedSignPlaybookCheckpointProjectionV1 {
        try checkpoint.validate()
        guard checkpoint.purpose == .evidenceCuration,
              checkpoint.codec == registry.draftCodec,
              checkpoint.state == .active || checkpoint.state == .committing
                || checkpoint.state == .recoveryRequired || checkpoint.state == .conflicted else {
            throw IlluminatedSignPlaybookFailureV1.invalidCheckpoint
        }
        if let predecessor {
            try checkpoint.validateSuccessor(
                of: predecessor, expectedDraftRevision: predecessor.draftRevision,
                expectedBaseRevision: predecessor.baseCanonicalRevision
            )
        }
        let payload = try IlluminatedSignPlaybookCanonicalCodecV1.decodeDraftPayload(
            from: checkpoint.payloadData, registry: registry
        )
        try IlluminatedSignPlaybookDraftScopeV1.validate(
            checkpoint.scope, subject: payload.subject, playbookID: payload.playbookID
        )
        guard payload.workspaceID == checkpoint.workspaceID,
              payload.checkedTime.context.observedAtUTC <= checkpoint.updatedAt,
              evidenceSequence.target == payload.subject,
              checkpoint.payloadData == (try IlluminatedSignPlaybookCanonicalCodecV1.encode(payload)) else {
            throw IlluminatedSignPlaybookFailureV1.invalidCheckpoint
        }
        try validateCaptureAuthority(payload.captures, workspaceID: checkpoint.workspaceID,
                                     associationEvents: associationEvents,
                                     evidenceSequence: evidenceSequence,
                                     evidenceSequenceHistory: evidenceSequenceHistory)
        try validatePoseAuthority(payload.poseTrace, workspaceID: checkpoint.workspaceID,
                                  poseEventHistory: poseEventHistory)
        let completeness = try completeness(of: payload)
        return try .init(checkpoint: checkpoint, payload: payload, completeness: completeness)
    }

    func complete(checkpoint: FieldDraftCheckpointV1,
                  predecessor: FieldDraftCheckpointV1? = nil,
                  associationEvents: [EvidenceAssociationV1],
                  evidenceSequence: EvidenceSequenceV1,
                  evidenceSequenceHistory: [EvidenceSequenceV1],
                  poseEventHistory: [AssetPoseEventV1]) throws
        -> IlluminatedSignPlaybookCompletionV1 {
        let projection = try project(checkpoint: checkpoint, predecessor: predecessor,
                                     associationEvents: associationEvents,
                                     evidenceSequence: evidenceSequence,
                                     evidenceSequenceHistory: evidenceSequenceHistory,
                                     poseEventHistory: poseEventHistory)
        guard projection.completeness.state == .complete
                || projection.completeness.state == .couldNotVerify else {
            throw IlluminatedSignPlaybookFailureV1.missingCapture
        }
        return try IlluminatedSignPlaybookCompletionV1(
            checkpoint: checkpoint, payload: projection.payload,
            completeness: projection.completeness, evidenceSequence: evidenceSequence,
            registry: registry
        )
    }

    func recover(checkpoint: FieldDraftCheckpointV1,
                 predecessor: FieldDraftCheckpointV1? = nil,
                 associationEvents: [EvidenceAssociationV1],
                 evidenceSequence: EvidenceSequenceV1,
                 evidenceSequenceHistory: [EvidenceSequenceV1],
                 poseEventHistory: [AssetPoseEventV1]) throws
        -> IlluminatedSignPlaybookRecoveryV1 {
        guard checkpoint.state == .active || checkpoint.state == .recoveryRequired
                || checkpoint.state == .conflicted || checkpoint.state == .committing else {
            throw IlluminatedSignPlaybookFailureV1.recoveryConflict
        }
        let projection = try project(checkpoint: checkpoint, predecessor: predecessor,
                                     associationEvents: associationEvents,
                                     evidenceSequence: evidenceSequence,
                                     evidenceSequenceHistory: evidenceSequenceHistory,
                                     poseEventHistory: poseEventHistory)
        return try IlluminatedSignPlaybookRecoveryV1(checkpoint: checkpoint, projection: projection)
    }

    func reportSection(for completion: IlluminatedSignPlaybookCompletionV1,
                       checkpoint: FieldDraftCheckpointV1,
                       predecessor: FieldDraftCheckpointV1? = nil,
                       associationEvents: [EvidenceAssociationV1],
                       evidenceSequence: EvidenceSequenceV1,
                       evidenceSequenceHistory: [EvidenceSequenceV1],
                       poseEventHistory: [AssetPoseEventV1]) throws
        -> IlluminatedSignReportSectionV1 {
        let current = try complete(checkpoint: checkpoint, predecessor: predecessor,
                                   associationEvents: associationEvents,
                                   evidenceSequence: evidenceSequence,
                                   evidenceSequenceHistory: evidenceSequenceHistory,
                                   poseEventHistory: poseEventHistory)
        guard current == completion else { throw IlluminatedSignPlaybookFailureV1.recoveryConflict }
        let manifest = try registry.manifest(for: completion.fact.playbookID)
        try completion.validate(registry: registry)
        return try IlluminatedSignReportSectionV1(completion: completion, manifest: manifest,
                                                   registry: registry)
    }

    private func validateCaptureAuthority(_ captures: [IlluminatedSignCaptureTraceV1],
                                          workspaceID: WorkspaceID,
                                          associationEvents: [EvidenceAssociationV1],
                                          evidenceSequence: EvidenceSequenceV1,
                                          evidenceSequenceHistory: [EvidenceSequenceV1]) throws {
        guard associationEvents.count <= ContentContractLimitsV1.maximumAssociations else {
            throw IlluminatedSignPlaybookFailureV1.limitExceeded
        }
        let orderedAssociations = associationEvents.sorted {
            ($0.workspaceID, $0.evidenceID, $0.resultingEvidenceRevision, $0.associationEventID)
                < ($1.workspaceID, $1.evidenceID, $1.resultingEvidenceRevision, $1.associationEventID)
        }
        try EvidenceAssociationLedgerV1.validate(orderedAssociations)
        try evidenceSequence.validate()
        guard !evidenceSequenceHistory.isEmpty,
              evidenceSequenceHistory.count <= IlluminatedSignPlaybookLimitsV1.maximumHistoryEvents else {
            throw IlluminatedSignPlaybookFailureV1.limitExceeded
        }
        let orderedHistory = evidenceSequenceHistory.sorted { $0.revision < $1.revision }
        try orderedHistory.forEach { try $0.validate() }
        guard orderedHistory.last == evidenceSequence,
              orderedHistory.first?.revision == 1,
              orderedHistory.first?.predecessor == nil,
              Set(orderedHistory.map(\.revision)).count == orderedHistory.count,
              orderedHistory.allSatisfy({ $0.sequenceID == evidenceSequence.sequenceID
                    && $0.workspaceID == workspaceID && $0.target == evidenceSequence.target }) else {
            throw IlluminatedSignPlaybookFailureV1.staleEvidence
        }
        for index in 1..<orderedHistory.count {
            try orderedHistory[index].validateSuccessor(of: orderedHistory[index - 1])
        }
        guard evidenceSequence.workspaceID == workspaceID,
              captures.allSatisfy({ $0.item.target == evidenceSequence.target }) else {
            throw IlluminatedSignPlaybookFailureV1.staleEvidence
        }
        for trace in captures {
            let terminal = orderedAssociations
                .filter { $0.workspaceID == workspaceID.rawValue.uuidString.lowercased() && $0.evidenceID == trace.item.evidenceID }
                .max { $0.resultingEvidenceRevision < $1.resultingEvidenceRevision }
            let matches = orderedAssociations.filter {
                $0.associationEventID == trace.item.associationBinding.associationEventID
                    && $0.evidenceID == trace.item.evidenceID
                    && $0.resultingEvidenceRevision == trace.item.associationBinding.resultingEvidenceRevision
            }
            guard matches.count == 1, let event = matches.first, terminal == event,
                  event.action != .removed, event.contentID == trace.item.contentID,
                  event.target == trace.item.target,
                  evidenceSequence.orderedItems.contains(trace.item),
                  try event.associationSHA256 == trace.item.associationBinding.associationSHA256 else {
                throw IlluminatedSignPlaybookFailureV1.staleEvidence
            }
        }
    }

    private func validatePoseAuthority(_ trace: IlluminatedSignPoseTraceV1?,
                                       workspaceID: WorkspaceID,
                                       poseEventHistory: [AssetPoseEventV1]) throws {
        guard poseEventHistory.count <= IlluminatedSignPlaybookLimitsV1.maximumHistoryEvents else {
            throw IlluminatedSignPlaybookFailureV1.limitExceeded
        }
        guard let trace else {
            guard poseEventHistory.isEmpty else {
                throw IlluminatedSignPlaybookFailureV1.invalidPose
            }
            return
        }
        guard poseEventHistory.allSatisfy({
            $0.workspaceID == workspaceID && $0.assetID == trace.event.assetID
                && $0.axisDescriptor.axisID == trace.descriptor.axisID
        }) else {
            throw IlluminatedSignPlaybookFailureV1.invalidPose
        }
        let relevant = poseEventHistory.sorted { $0.revision < $1.revision }
        guard !relevant.isEmpty, relevant.last == trace.event,
              relevant.first?.revision == 1, relevant.first?.predecessor == nil,
              Set(relevant.map(\.revision)).count == relevant.count else {
            throw IlluminatedSignPlaybookFailureV1.invalidPose
        }
        try relevant.forEach { try $0.validateIntrinsic() }
        for index in 1..<relevant.count {
            try relevant[index].validateSuccessor(of: relevant[index - 1])
        }
    }
}

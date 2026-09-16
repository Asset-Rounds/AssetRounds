import Foundation

/// Exact journal composition for a same-workspace replacement. This is only a
/// value proof: canonical draft/media closure and the live restore authority
/// must be checked separately before it can be used by the restore owner.
struct CheckRunnerPhotoRestoreHistoryUnionV1: Equatable, Sendable {
    let source: MutationHistorySnapshotV1
    let current: MutationHistorySnapshotV1
    let merged: MutationHistorySnapshotV1

    private init(source: MutationHistorySnapshotV1,
                 current: MutationHistorySnapshotV1,
                 merged: MutationHistorySnapshotV1) {
        self.source = source
        self.current = current
        self.merged = merged
    }

    static func compose(source: MutationHistorySnapshotV1,
                        current: MutationHistorySnapshotV1,
                        sourceIdentity: WorkspaceReplicaIdentityV1,
                        currentIdentity: WorkspaceReplicaIdentityV1) throws -> Self {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard sourceIdentity.workspaceID == currentIdentity.workspaceID else { throw failure }
        try MutationJournalStoreV1.validateImportedSnapshot(source)
        try MutationJournalStoreV1.validateImportedSnapshot(current)
        var originals: [String: MutationHistoryReceiptRecordV1] = [:]
        var receiptIdentities: [String: String] = [:]
        var receiptKeys: [String: String] = [:]
        for record in source.receipts + current.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            let key = MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                                                  mutationID: envelope.mutationID)
            let receiptKey = receipt.identity.stableKey
            guard originals[key].map({ $0 == record }) ?? true,
                  receiptIdentities[receiptKey].map({ $0 == key }) ?? true else { throw failure }
            originals[key] = record
            receiptIdentities[receiptKey] = key
            receiptKeys[key] = receiptKey
        }
        var quarantines: [String: MutationHistoryQuarantineRecordV1] = [:]
        for row in source.quarantines + current.quarantines {
            let key = MutationWorkspaceKeyV1.value(workspaceID: row.workspaceID,
                mutationID: try MutationIDV1(rawValue: row.mutationID))
            guard quarantines[key].map({ $0 == row }) ?? true else { throw failure }
            quarantines[key] = row
        }
        // A quarantine references its accepted receipt in the incumbent journal.
        // Preserve that valid relationship; required photo receipts are checked
        // separately below and must never become quarantined.
        var revisions: [WorkspaceEntityIdentityV1: MutationHistoryEntityRevisionV1] = [:]
        for row in source.entityRevisions + current.entityRevisions {
            if let old = revisions[row.identity] {
                guard old.revision != row.revision || old == row else { throw failure }
                if old.revision > row.revision { continue }
            }
            revisions[row.identity] = row
        }
        let merged = MutationHistorySnapshotV1(
            workspaceRevision: max(source.workspaceRevision, current.workspaceRevision),
            lastLocalSequence: sourceIdentity == currentIdentity
                ? max(source.lastLocalSequence, current.lastLocalSequence)
                : current.lastLocalSequence,
            receipts: originals.keys.sorted { receiptKeys[$0]! < receiptKeys[$1]! }
                .map { originals[$0]! },
            quarantines: quarantines.keys.sorted().map { quarantines[$0]! },
            entityRevisions: revisions.values.sorted { $0.identity.stableKey < $1.identity.stableKey })
        try MutationJournalStoreV1.validateImportedSnapshot(merged)
        return .init(source: source, current: current, merged: merged)
    }

    func requireDestination(_ destination: MutationHistorySnapshotV1) throws {
        try MutationJournalStoreV1.validateImportedSnapshot(destination)
        guard destination == merged else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
    }

    func requireSourcePhotoHistory(_ history: CheckRunnerPhotoBackupHistoryV1) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var originals: [String: MutationHistoryReceiptRecordV1] = [:]
        for row in source.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            originals[MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID)] = row
        }
        let quarantined = Set(try merged.quarantines.map {
            MutationWorkspaceKeyV1.value(workspaceID: $0.workspaceID,
                mutationID: try MutationIDV1(rawValue: $0.mutationID))
        })
        for required in history.requiredHistory {
            let key = MutationWorkspaceKeyV1.value(workspaceID: required.envelope.workspaceID,
                mutationID: required.envelope.mutationID)
            guard originals[key] == required.original, !quarantined.contains(key) else { throw failure }
        }
    }
}

/// A pure, immutable census of one canonical Check Runner photo child. Every
/// value is reconstructed from original journal bytes and canonical records.
/// It owns no file handle, source access, destination identity, or effect.
struct CheckRunnerPhotoBackupHistoryChildV1: Equatable, Sendable {
    enum PhaseEvidence: Equatable, Sendable {
        case awaitingRaw(CheckRunnerPhotoRawStageEvidenceV1)
        case rawReady(CheckRunnerPhotoRawStageEvidenceV1)
        case continuation(CheckRunnerPhotoContinuationEvidenceV1)
    }

    let parentCheckpoint: FieldDraftCheckpointV1
    let currentCheckpoint: FieldDraftCheckpointV1
    let payload: CheckRunnerPhotoDraftPayloadV1
    let raw: CheckRunnerPhotoRawReadyV1?
    let pair: CheckRunnerPhotoPairReadyV1?
    let preparedReconstruction: CheckRunnerPhotoCommitReconstructionV1?
    let committingCheckpoint: FieldDraftCheckpointV1?
    let originals: [RepetitiveCaptureSourceHistoryRecordV2]
    let currentStage: AttachmentStagingItemV1?
    let sagas: [DraftCommitSagaV1]
    let reservations: [DraftContentReservationV1]
    let commitReceipts: [DraftCommitReceiptV1]
    let target: CheckRunnerPhotoCommittedEvidenceV1?
    let targetRecords: CheckRunnerPhotoBackupTargetRecordsV1?
    let terminal: CheckRunnerPhotoCommitEvidenceV1?
    let parentLink: CheckRunnerPhotoParentEvidenceV1?
    let currentTarget: CheckRunnerPhotoCurrentTargetEvidenceV1?
    let phaseEvidence: PhaseEvidence
    let sourceGraph: ReviewedRepetitiveCaptureSourceGraphV2
}

/// Canonical rows at an authenticated photo target's current frontier. For an
/// interrupted target commit the frontier must still be the original target;
/// terminal children may advance only through the explicit photo/finalization
/// successors accepted by `CheckRunnerPhotoCurrentTargetEvidenceV1`.
struct CheckRunnerPhotoBackupTargetRecordsV1: Equatable, Sendable {
    let workflow: V4BackupWorkflowRecordDTO
    let originalWorkflowPostImage: MutationPostImageV1
    let currentWorkflowPostImage: MutationPostImageV1
    let evidence: V4BackupEvidenceFileDTO
    let originalEvidencePostImage: MutationPostImageV1
    let currentEvidencePostImage: MutationPostImageV1
    let permittedSuccessors: [RepetitiveCaptureSourceHistoryRecordV2]
}

/// Complete source-history projection used before photo archive membership is
/// accepted. Pending states with no physical bytes remain valid observations.
struct CheckRunnerPhotoBackupHistoryV1: Equatable, Sendable {
    let source: V4BackupSourceV1
    let sourceWorkspaceID: WorkspaceID
    let sourceGenerationID: UUID?
    let children: [CheckRunnerPhotoBackupHistoryChildV1]
    let parentFinalizations: [CheckRunnerItemFinalizationEvidenceV1]
    let requiredHistory: [RepetitiveCaptureSourceHistoryRecordV2]

    /// Pure correspondence for an original Begin effect. Presence and quarantine
    /// come from the complete source journal; this comparison grants no live effect.
    static func requireFrozenBeginOriginal(_ original: CheckRunnerBeginCommittedEvidenceV1,
        attempt: CheckRunnerFrozenBeginAttemptV1, role: CheckRunnerBeginMutationRoleV1) throws {
        try attempt.validate()
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let command: WorkspaceCommandV1
        let mutationID: MutationIDV1
        let revisions: [WorkspaceEntityRevisionV1]
        let committedAt: Date
        switch role {
        case .record:
            command = .createCheckDraft(attempt.recordCommand)
            mutationID = attempt.recordMutationID
            revisions = attempt.recordExpectedEntityRevisions
            committedAt = attempt.recordCommittedAt
        case .timeZone:
            guard let zone = attempt.timeZone else { throw failure }
            command = .updateSiteTimeZone(zone.command)
            mutationID = zone.mutationID
            revisions = [try .init(identity: .init(kind: .site, id: zone.command.siteID),
                                   revision: zone.expectedSiteRevision)]
            committedAt = zone.committedAt
        }
        guard original.envelope.workspaceID == attempt.sourceWorkspaceID,
              original.envelope.mutationID == mutationID,
              original.envelope.commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(command)),
              original.receipt.committedAt == committedAt else { throw failure }
        // A genuine full-workspace CAS includes unrelated entities. Match every
        // frozen dependency exactly without dropping or rewriting the vector.
        for revision in revisions {
            let matches = original.receipt.expectedRevision.entityRevisions.filter {
                $0.identity == revision.identity
            }
            guard matches.count == 1, matches[0].revision == revision.revision else { throw failure }
        }
    }

    static func project(source: V4BackupSourceV1, records: V4BackupRecordsV1) throws -> Self {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let c36 = try RepetitiveCaptureSourceGraphReviewV2.reviewCanonicalSource(
            source: source, records: records)
        guard let rawWorkspaceID = source.workspaceID,
              c36.sourceWorkspaceID.rawValue == rawWorkspaceID,
              source.recordsSchemaVersion == records.recordsSchemaVersion else { throw failure }
        let workspaceID = c36.sourceWorkspaceID
        let rows = try Rows(records.fieldDrafts, workspaceID: workspaceID)
        let history = c36.history
        let membership = try photoMembership(rows: rows, history: history,
            workspaceID: workspaceID, graphs: c36.graphs)
        let currentPhotos = membership.photos

        var required = try parentHistoryKeys(membership.parentCache, history: history)
        c36.requiredHistory.forEach { required.insert(key($0)) }
        var results: [CheckRunnerPhotoBackupHistoryChildV1] = []
        var parentLinks: [UUID: CheckRunnerPhotoParentEvidenceV1] = [:]
        var currentTargets: [UUID: CheckRunnerPhotoCurrentTargetEvidenceV1] = [:]
        let orderedPhotos = try currentPhotos.values.sorted { lhs, rhs in
            let left = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(lhs)
            let right = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(rhs)
            let lk = "\(left.parentDraftID.uuidString)|\(captureRank(left.captureStep))|\(left.childDraftID.uuidString)"
            let rk = "\(right.parentDraftID.uuidString)|\(captureRank(right.captureStep))|\(right.childDraftID.uuidString)"
            return lk < rk
        }
        for checkpoint in orderedPhotos {
            results.append(try projectChild(checkpoint, rows: rows, records: records,
                history: history, workspaceID: workspaceID,
                parentCache: membership.parentCache, parentGraphs: membership.parentGraphs,
                required: &required, parentLinks: &parentLinks, currentTargets: &currentTargets))
        }
        guard results.count == currentPhotos.count else { throw failure }
        let requiredHistory = try required.map { try history.authenticated($0) }
            .sorted(by: RepetitiveCaptureSourceGraphReviewV2.recordLess)
        guard requiredHistory.allSatisfy({ !history.isQuarantined($0) }) else { throw failure }
        return .init(source: source, sourceWorkspaceID: workspaceID,
                     sourceGenerationID: source.sourceGenerationID,
                     children: results,
                     parentFinalizations: membership.parentCache.values.compactMap(\.finalization)
                        .sorted { $0.checkpoint.draftID.uuidString < $1.checkpoint.draftID.uuidString },
                     requiredHistory: requiredHistory)
    }
}

private extension CheckRunnerPhotoBackupHistoryV1 {
    struct Rows {
        var checkpoints: [UUID: FieldDraftCheckpointV1] = [:]
        var stages: [UUID: AttachmentStagingItemV1] = [:]
        var sagas: [UUID: DraftCommitSagaV1] = [:]
        var reservations: [UUID: DraftContentReservationV1] = [:]
        var commitReceipts: [UUID: DraftCommitReceiptV1] = [:]

        init(_ records: [V16BackupFieldDraftRecordV1], workspaceID: WorkspaceID) throws {
            let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
            for row in records {
                guard row.workspaceID == workspaceID.rawValue else { throw failure }
                switch row.kind {
                case .checkpoint:
                    let value = try FieldDraftCanonicalCodecV1.decode(
                        FieldDraftCheckpointV1.self, from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.draftID == row.id,
                          value.draftRevision == row.revision,
                          checkpoints.updateValue(value, forKey: value.draftID) == nil else { throw failure }
                case .stagingItem:
                    let value = try FieldDraftCanonicalCodecV1.decode(
                        AttachmentStagingItemV1.self, from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.stageID == row.id,
                          value.revision == row.revision,
                          stages.updateValue(value, forKey: value.stageID) == nil else { throw failure }
                case .commitSaga:
                    let value = try FieldDraftCanonicalCodecV1.decode(
                        DraftCommitSagaV1.self, from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.sagaID == row.id,
                          value.revision == row.revision,
                          sagas.updateValue(value, forKey: value.sagaID) == nil else { throw failure }
                case .contentReservation:
                    let value = try FieldDraftCanonicalCodecV1.decode(
                        DraftContentReservationV1.self, from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.reservationID == row.id,
                          value.revision == row.revision,
                          reservations.updateValue(value, forKey: value.reservationID) == nil else { throw failure }
                case .commitReceipt:
                    let value = try FieldDraftCanonicalCodecV1.decode(
                        DraftCommitReceiptV1.self, from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.receiptID == row.id,
                          value.revision == row.revision,
                          commitReceipts.updateValue(value, forKey: value.receiptID) == nil else { throw failure }
                case .discardReceipt:
                    let value = try FieldDraftCanonicalCodecV1.decode(
                        DraftDiscardReceiptV1.self, from: row.canonicalData)
                    try value.validate()
                    guard value.workspaceID == workspaceID, value.receiptID == row.id,
                          value.revision == row.revision else { throw failure }
                }
            }
        }
    }

    struct PhotoMembership {
        let photos: [UUID: FieldDraftCheckpointV1]
        let parentCache: [UUID: ParentHistory]
        let parentGraphs: [UUID: ReviewedRepetitiveCaptureSourceGraphV2]
    }

    /// PREPARED may have no effect, timezone only, or both effects before BOUND.
    /// Preserve that exact prefix and every parent original even without photos.
    @inline(never)
    static func parentHistoryKeys(_ parents: [UUID: ParentHistory],
                                  history: RepetitiveCaptureSourceGraphReviewV2.History) throws -> Set<String> {
        var required = Set<String>()
        for parent in parents.values {
            parent.originals.forEach { required.insert(key($0)) }
            if let target = parent.finalization?.target {
                let targetKey = RepetitiveCaptureSourceGraphReviewV2.key(
                    target.envelope.workspaceID, target.receipt.mutationID)
                _ = try history.authenticated(targetKey)
                required.insert(targetKey)
            }
            var attempts: [String: CheckRunnerFrozenBeginAttemptV1] = [:]
            var hasBoundBegin = false
            for checkpoint in parent.checkpoints {
                let begin = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint).field.begin
                if case .bound = begin { hasBoundBegin = true }
                guard let attempt = begin.attempt else { continue }
                let attemptKey = RepetitiveCaptureSourceGraphReviewV2.key(
                    attempt.sourceWorkspaceID, attempt.recordMutationID)
                if let prior = attempts[attemptKey] {
                    guard prior == attempt else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                    continue
                }
                attempts[attemptKey] = attempt
                let zone = try attempt.timeZone.flatMap {
                    try presentBeginOriginal(attempt: attempt, mutationID: $0.mutationID,
                                             role: .timeZone, history: history)
                }
                let workflow = try presentBeginOriginal(attempt: attempt,
                    mutationID: attempt.recordMutationID, role: .record, history: history)
                if let workflow, let expectedZone = attempt.timeZone {
                    guard let zone,
                          zone.envelope.mutationID == expectedZone.mutationID,
                          workflow.receipt.expectedRevision.workspaceRevision >=
                            zone.receipt.resultingRevision.workspaceRevision else {
                        throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                    }
                }
                if let zone { required.insert(key(zone)) }
                if let workflow { required.insert(key(workflow)) }
            }
            if hasBoundBegin {
                let begin = try beginEvidence(parent: parent, history: history)
                required.insert(key(begin.workflowRecord))
                _ = begin.timeZoneRecord.map { required.insert(key($0)) }
            }
        }
        return required
    }

    static func presentBeginOriginal(attempt: CheckRunnerFrozenBeginAttemptV1,
        mutationID: MutationIDV1, role: CheckRunnerBeginMutationRoleV1,
        history: RepetitiveCaptureSourceGraphReviewV2.History) throws
        -> RepetitiveCaptureSourceHistoryRecordV2? {
        let recordKey = RepetitiveCaptureSourceGraphReviewV2.key(attempt.sourceWorkspaceID, mutationID)
        guard !history.quarantinedKeys.contains(recordKey) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        guard history.records[recordKey] != nil else { return nil }
        let record = try history.authenticated(recordKey)
        let original = try CheckRunnerBeginCommittedEvidenceV1(envelope: record.envelope, receipt: record.receipt)
        try requireFrozenBeginOriginal(original, attempt: attempt, role: role)
        return record
    }

    @inline(never)
    static func photoMembership(rows: Rows,
        history: RepetitiveCaptureSourceGraphReviewV2.History,
        workspaceID: WorkspaceID,
        graphs: [ReviewedRepetitiveCaptureSourceGraphV2]) throws -> PhotoMembership {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let photoRelease = try CheckRunnerPhotoDraftCodecV1.release()
        let parentRelease = try CheckRunnerItemDraftCodecV1.release()

        let currentPhotos = rows.checkpoints.filter { $0.value.codec == photoRelease }
        let currentParents = rows.checkpoints.filter { $0.value.codec == parentRelease }
        var historicPhotoIDs = Set<UUID>()
        var historicParentIDs = Set<UUID>()
        for record in history.records.values where record.envelope.workspaceID == workspaceID {
            guard case let .applyFieldDraft(mutation) = record.envelope.command,
                  case let .createCheckpoint(checkpoint) = mutation.postImage else { continue }
            if checkpoint.codec == photoRelease {
                _ = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
                guard checkpoint.workspaceID == workspaceID,
                      historicPhotoIDs.insert(checkpoint.draftID).inserted else { throw failure }
            } else if checkpoint.codec == parentRelease {
                _ = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
                guard checkpoint.workspaceID == workspaceID,
                      historicParentIDs.insert(checkpoint.draftID).inserted else { throw failure }
            }
        }
        guard historicPhotoIDs == Set(currentPhotos.keys),
              historicParentIDs == Set(currentParents.keys) else { throw failure }
        for record in history.records.values where record.envelope.workspaceID != workspaceID {
            guard case let .applyFieldDraft(mutation) = record.envelope.command else { continue }
            if currentPhotos[RepetitiveCaptureSourceGraphReviewV2.draftID(mutation.postImage)] != nil {
                throw failure
            }
        }

        var parentCache: [UUID: ParentHistory] = [:]
        var parentGraphs: [UUID: ReviewedRepetitiveCaptureSourceGraphV2] = [:]
        var referencedPhotoIDs = Set<UUID>()
        for parent in currentParents.values {
            let reviewed = try parentHistory(
                current: parent, rows: rows, history: history, workspaceID: workspaceID)
            let graph = try sourceGraph(for: reviewed.currentPayload.source, in: graphs)
            try validateHistoricalEntry(reviewed.currentPayload.source, graph: graph)
            parentCache[parent.draftID] = reviewed
            parentGraphs[parent.draftID] = graph
            for checkpoint in reviewed.checkpoints {
                let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
                if let id = payload.field.wideContext?.childDraftID { referencedPhotoIDs.insert(id) }
                if let id = payload.field.closeDetail?.childDraftID { referencedPhotoIDs.insert(id) }
            }
        }
        guard referencedPhotoIDs == Set(currentPhotos.keys) else { throw failure }
        for child in currentPhotos.values {
            let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(child)
            guard parentCache[payload.parentDraftID] != nil else { throw failure }
        }
        return .init(photos: currentPhotos, parentCache: parentCache, parentGraphs: parentGraphs)
    }

    @inline(never)
    static func projectChild(_ checkpoint: FieldDraftCheckpointV1,
        rows: Rows,
        records: V4BackupRecordsV1,
        history: RepetitiveCaptureSourceGraphReviewV2.History,
        workspaceID: WorkspaceID,
        parentCache: [UUID: ParentHistory],
        parentGraphs: [UUID: ReviewedRepetitiveCaptureSourceGraphV2],
        required: inout Set<String>,
        parentLinks: inout [UUID: CheckRunnerPhotoParentEvidenceV1],
        currentTargets: inout [UUID: CheckRunnerPhotoCurrentTargetEvidenceV1]) throws
        -> CheckRunnerPhotoBackupHistoryChildV1 {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
        guard payload.childDraftID == checkpoint.draftID,
              let parent = parentCache[payload.parentDraftID],
              let graph = parentGraphs[payload.parentDraftID] else { throw failure }
        let begin = try beginEvidence(parent: parent, history: history)
        let childRecords = history.fieldDraftHistory(
            workspaceID: workspaceID, draftID: checkpoint.draftID)
        guard !childRecords.isEmpty else { throw failure }
        let childHistory = try childRecords.map { record -> FieldDraftCommittedEvidenceV1 in
            required.insert(key(record))
            return try FieldDraftCommittedEvidenceV1(
                envelope: record.envelope, receipt: record.receipt)
        }
        parent.originals.forEach { required.insert(key($0)) }
        required.insert(key(begin.workflowRecord))
        _ = begin.timeZoneRecord.map { required.insert(key($0)) }

        let stages = rows.stages.values.filter { $0.draftID == checkpoint.draftID }
            .sorted { $0.stageID.uuidString < $1.stageID.uuidString }
        let sagas = rows.sagas.values.filter { $0.draftID == checkpoint.draftID }
            .sorted { $0.revision < $1.revision }
        let reservations = rows.reservations.values.filter { $0.draftID == checkpoint.draftID }
            .sorted { $0.reservationID.uuidString < $1.reservationID.uuidString }
        let receipts = rows.commitReceipts.values.filter { $0.draftID == checkpoint.draftID }
            .sorted { $0.receiptID.uuidString < $1.receiptID.uuidString }

        let phase = try phaseFacts(payload, checkpoint: checkpoint, history: history,
                                   required: &required)
        let isCommitted = checkpoint.state == .committed
        let parentCheckpoint = try parent.frontier(for: checkpoint, committed: isCommitted)
        let parentEvidence = try parent.evidencePrefix(for: checkpoint, committed: isCommitted)
        let workflow = try exactlyOne(records.workflowRecords.filter { $0.id == payload.recordID })
        let workflowIdentity = try WorkspaceEntityIdentityV1(
            kind: .workflowRecord, id: payload.recordID)
        let priorImage = try workflowImageBeforePhoto(
            payload: payload, begin: begin.workflow,
            precedingWide: parentLinks[payload.parentDraftID])
        let targetImage = try phase.target.map {
            try exactlyOne($0.receipt.postImages.filter { try $0.identity == workflowIdentity })
        }
        let continuationWorkflowImage = targetImage ?? priorImage
        let evidenceImage = try phase.target.map { target in
            let identity = try WorkspaceEntityIdentityV1(
                kind: .evidenceFile, id: target.command.evidenceID)
            return try exactlyOne(target.receipt.postImages.filter { try $0.identity == identity })
        }

        let phaseEvidence: CheckRunnerPhotoBackupHistoryChildV1.PhaseEvidence
        let terminal: CheckRunnerPhotoCommitEvidenceV1?
        switch payload.phase {
        case .awaitingRawStage:
            guard stages.isEmpty, sagas.isEmpty, reservations.isEmpty, receipts.isEmpty,
                  phase.target == nil else { throw failure }
            let evidence = try CheckRunnerPhotoRawStageEvidenceV1(
                parentHistory: parentEvidence, parentCheckpoint: parentCheckpoint,
                workflow: begin.workflow, timeZone: begin.timeZone,
                childHistory: childHistory, childCheckpoint: checkpoint, currentStage: nil,
                currentWorkflowPostImage: priorImage,
                precedingWide: currentTargets[payload.parentDraftID])
            phaseEvidence = .awaitingRaw(evidence); terminal = nil
        case .rawReady:
            let stage = try exactlyOne(stages)
            guard sagas.isEmpty, reservations.isEmpty, receipts.isEmpty,
                  phase.target == nil else { throw failure }
            let evidence = try CheckRunnerPhotoRawStageEvidenceV1(
                parentHistory: parentEvidence, parentCheckpoint: parentCheckpoint,
                workflow: begin.workflow, timeZone: begin.timeZone,
                childHistory: childHistory, childCheckpoint: checkpoint, currentStage: stage,
                currentWorkflowPostImage: priorImage,
                precedingWide: currentTargets[payload.parentDraftID])
            phaseEvidence = .rawReady(evidence); terminal = nil
        case .pairReady(_), .preparedCommit(_, _):
            let stage = try exactlyOne(stages)
            let evidence = try CheckRunnerPhotoContinuationEvidenceV1(
                parentHistory: parentEvidence, parentCheckpoint: parentCheckpoint,
                workflow: begin.workflow, timeZone: begin.timeZone,
                history: childHistory, checkpoint: checkpoint, stages: [stage], sagas: sagas,
                reservations: reservations, receipts: receipts,
                precedingWide: parentLinks[payload.parentDraftID], target: phase.target,
                currentWorkflowPostImage: continuationWorkflowImage,
                currentEvidencePostImage: evidenceImage)
            phaseEvidence = .continuation(evidence); terminal = evidence.terminal
        }

        var targetRecords: CheckRunnerPhotoBackupTargetRecordsV1?
        var parentLink: CheckRunnerPhotoParentEvidenceV1?
        var currentTarget: CheckRunnerPhotoCurrentTargetEvidenceV1?
        if let target = phase.target {
            guard let originalWorkflowPostImage = targetImage,
                  let originalEvidencePostImage = evidenceImage else { throw failure }
            let evidence = try exactlyOne(records.evidenceFiles.filter {
                $0.id == target.command.evidenceID
            })
            let evidenceIdentity = try WorkspaceEntityIdentityV1(
                kind: .evidenceFile, id: evidence.id)
            let currentEvidencePostImage = try latestPostImage(
                identity: evidenceIdentity, workspaceID: workspaceID,
                history: history, records: records)
            let later = try laterWorkflowReceipts(
                after: target.receipt, identity: workflowIdentity, history: history)
            later.forEach { required.insert(key($0)) }
            let currentWorkflowPostImage = try latestPostImage(
                identity: workflowIdentity, workspaceID: workspaceID,
                history: history, records: records)
            try validateTargetRecords(target: target, begin: begin.workflow,
                workflow: workflow, originalWorkflowPostImage: originalWorkflowPostImage,
                currentWorkflowPostImage: currentWorkflowPostImage,
                evidence: evidence, originalEvidencePostImage: originalEvidencePostImage,
                currentEvidencePostImage: currentEvidencePostImage,
                later: later, terminal: terminal != nil)
            targetRecords = .init(workflow: workflow,
                originalWorkflowPostImage: originalWorkflowPostImage,
                currentWorkflowPostImage: currentWorkflowPostImage,
                evidence: evidence, originalEvidencePostImage: originalEvidencePostImage,
                currentEvidencePostImage: currentEvidencePostImage,
                permittedSuccessors: later)
        }
        if let terminal {
            let link = try CheckRunnerPhotoParentEvidenceV1(
                history: parentEvidence,
                checkpoint: parentCheckpoint, child: terminal,
                workflow: begin.workflow, timeZone: begin.timeZone)
            guard let targetRecords else { throw failure }
            let current = try CheckRunnerPhotoCurrentTargetEvidenceV1(
                parent: link, workflow: targetRecords.workflow,
                workflowPostImage: targetRecords.currentWorkflowPostImage,
                evidence: targetRecords.evidence,
                evidencePostImage: targetRecords.currentEvidencePostImage,
                laterReceipts: targetRecords.permittedSuccessors.map {
                    ($0.envelope, $0.receipt)
                })
            parentLink = link; currentTarget = current
            parentLinks[payload.parentDraftID] = link
            currentTargets[payload.parentDraftID] = current
        }

        let committingCheckpoint = phase.reconstruction?.draftCommit.checkpoint
            ?? terminal?.reconstruction.draftCommit.checkpoint
        return .init(parentCheckpoint: parentCheckpoint,
            currentCheckpoint: checkpoint, payload: payload,
            raw: phase.raw, pair: phase.pair,
            preparedReconstruction: phase.reconstruction ?? terminal?.reconstruction,
            committingCheckpoint: committingCheckpoint,
            originals: childRecords, currentStage: stages.first, sagas: sagas,
            reservations: reservations, commitReceipts: receipts, target: phase.target,
            targetRecords: targetRecords, terminal: terminal,
            parentLink: parentLink, currentTarget: currentTarget,
            phaseEvidence: phaseEvidence, sourceGraph: graph)
    }

    struct ParentHistory {
        let current: FieldDraftCheckpointV1
        let currentPayload: CheckRunnerItemDraftPayloadV1
        let originals: [RepetitiveCaptureSourceHistoryRecordV2]
        let checkpointEvidence: [FieldDraftCommittedEvidenceV1]
        let checkpoints: [FieldDraftCheckpointV1]
        let finalization: CheckRunnerItemFinalizationEvidenceV1?

        func frontier(for child: FieldDraftCheckpointV1, committed: Bool) throws
            -> FieldDraftCheckpointV1 {
            let childPayload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(child)
            let selected = Array(zip(checkpointEvidence, checkpoints)).last { _, checkpoint in
                guard checkpoint.state == .active,
                      let payload = try? CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint),
                      payload.phase == .editing else { return false }
                let slot = childPayload.captureStep == .wide
                    ? payload.field.wideContext : payload.field.closeDetail
                if committed {
                    guard case let .committed(childDraftID, _, _, _, _, _, _, _, _, _) = slot else {
                        return false
                    }
                    return childDraftID == childPayload.childDraftID
                }
                guard case let .pending(childDraftID, _, _) = slot else { return false }
                return childDraftID == childPayload.childDraftID
            }
            guard let selected else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
            return selected.1
        }

        func evidencePrefix(for child: FieldDraftCheckpointV1, committed: Bool)
            throws -> [FieldDraftCommittedEvidenceV1] {
            let selected = try frontier(for: child, committed: committed)
            return zip(checkpointEvidence, checkpoints).filter { $0.1.draftRevision <= selected.draftRevision }
                .map(\.0)
        }
    }

    struct BeginEvidence {
        let workflow: CheckRunnerBeginCommittedEvidenceV1
        let timeZone: CheckRunnerBeginCommittedEvidenceV1?
        let workflowRecord: RepetitiveCaptureSourceHistoryRecordV2
        let timeZoneRecord: RepetitiveCaptureSourceHistoryRecordV2?
    }

    struct PhaseFacts {
        let raw: CheckRunnerPhotoRawReadyV1?
        let pair: CheckRunnerPhotoPairReadyV1?
        let reconstruction: CheckRunnerPhotoCommitReconstructionV1?
        let target: CheckRunnerPhotoCommittedEvidenceV1?
    }

    static func parentHistory(current: FieldDraftCheckpointV1, rows: Rows,
        history: RepetitiveCaptureSourceGraphReviewV2.History, workspaceID: WorkspaceID) throws
        -> ParentHistory {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let originals = history.fieldDraftHistory(workspaceID: workspaceID, draftID: current.draftID)
        let evidence = try originals.map {
            try FieldDraftCommittedEvidenceV1(envelope: $0.envelope, receipt: $0.receipt)
        }
        let checkpointEntries = evidence.compactMap { value -> (FieldDraftCommittedEvidenceV1, FieldDraftCheckpointV1)? in
            RepetitiveCaptureSourceGraphReviewV2.checkpointPostImage(value.mutation.postImage)
                .map { (value, $0) }
        }.sorted { $0.1.draftRevision < $1.1.draftRevision }
        guard let first = checkpointEntries.first, let last = checkpointEntries.last,
              case .createCheckpoint = first.0.mutation.postImage,
              first.1.draftRevision == 1, last.1 == current,
              checkpointEntries.map(\.1.draftRevision) == Array(1...checkpointEntries.count).map(UInt64.init)
        else { throw failure }
        for (index, entry) in checkpointEntries.enumerated() {
            _ = try CheckRunnerItemDraftCodecV1.validateCheckpoint(entry.1)
            guard entry.0.mutation.mutationID == entry.1.mutationID,
                  entry.0.mutation.expectedRevision == entry.1.draftRevision - 1,
                  entry.0.mutation.expectedBaseCanonicalRevision == entry.1.baseCanonicalRevision else {
                throw failure
            }
            if index > 0 {
                try entry.1.validateSuccessor(of: checkpointEntries[index - 1].1,
                    expectedDraftRevision: checkpointEntries[index - 1].1.draftRevision,
                    expectedBaseRevision: checkpointEntries[index - 1].1.baseCanonicalRevision)
            }
        }
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(current)
        let sagas = rows.sagas.values.filter { $0.draftID == current.draftID }
        let reservations = rows.reservations.values.filter { $0.draftID == current.draftID }
        let stages = rows.stages.values.filter { $0.draftID == current.draftID }
        let receipts = rows.commitReceipts.values.filter { $0.draftID == current.draftID }
        let finalization: CheckRunnerItemFinalizationEvidenceV1?
        if let attempt = payload.finalizationAttempt {
            guard case let .bound(_, workflowReference, zoneReference) = payload.field.begin else { throw failure }
            let workflowRecord = try history.authenticated(
                workspaceID: workflowReference.workspaceID, mutationID: workflowReference.mutationID)
            let workflow = try CheckRunnerBeginCommittedEvidenceV1(
                envelope: workflowRecord.envelope, receipt: workflowRecord.receipt)
            try workflowReference.validate(evidence: workflow)
            let timeZone = try zoneReference.map { reference in
                let record = try history.authenticated(workspaceID: reference.workspaceID, mutationID: reference.mutationID)
                let value = try CheckRunnerBeginCommittedEvidenceV1(envelope: record.envelope, receipt: record.receipt)
                try reference.validate(evidence: value)
                return value
            }
            let targetKey = try RepetitiveCaptureSourceGraphReviewV2.key(
                workspaceID, .init(rawValue: attempt.identifiers.mutationID))
            guard !history.quarantinedKeys.contains(targetKey) else { throw failure }
            let target = try history.records[targetKey].map { record in
                try FinalizationCommittedEvidenceV1(envelope: record.envelope, receipt: record.receipt)
            }
            finalization = try .init(history: evidence, checkpoint: current, sagas: sagas,
                reservations: reservations, stages: stages, receipts: receipts,
                workflow: workflow, timeZone: timeZone, target: target)
        } else {
            guard checkpointEntries.count == originals.count,
                  sagas.isEmpty, reservations.isEmpty, stages.isEmpty, receipts.isEmpty else { throw failure }
            finalization = nil
        }
        return .init(current: current,
            currentPayload: payload,
            originals: originals, checkpointEvidence: checkpointEntries.map(\.0),
            checkpoints: checkpointEntries.map(\.1), finalization: finalization)
    }

    static func beginEvidence(parent: ParentHistory,
        history: RepetitiveCaptureSourceGraphReviewV2.History) throws -> BeginEvidence {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let bound = parent.checkpoints.compactMap {
            try? CheckRunnerItemDraftCodecV1.validateCheckpoint($0)
        }.compactMap { payload -> (CheckRunnerBeginReceiptReferenceV1, CheckRunnerBeginReceiptReferenceV1?)? in
            guard case let .bound(_, workflow, timeZone) = payload.field.begin else { return nil }
            return (workflow, timeZone)
        }
        guard let references = bound.last,
              bound.allSatisfy({ $0.0 == references.0 && $0.1 == references.1 }) else { throw failure }
        let workflowRecord = try history.authenticated(
            workspaceID: references.0.workspaceID, mutationID: references.0.mutationID)
        let workflow = try CheckRunnerBeginCommittedEvidenceV1(
            envelope: workflowRecord.envelope, receipt: workflowRecord.receipt)
        try references.0.validate(evidence: workflow)
        let timeZoneRecord = try references.1.map {
            try history.authenticated(workspaceID: $0.workspaceID, mutationID: $0.mutationID)
        }
        let timeZone = try timeZoneRecord.map {
            try CheckRunnerBeginCommittedEvidenceV1(envelope: $0.envelope, receipt: $0.receipt)
        }
        if let reference = references.1, let timeZone { try reference.validate(evidence: timeZone) }
        return .init(workflow: workflow, timeZone: timeZone,
                     workflowRecord: workflowRecord, timeZoneRecord: timeZoneRecord)
    }

    static func phaseFacts(_ payload: CheckRunnerPhotoDraftPayloadV1,
        checkpoint: FieldDraftCheckpointV1,
        history: RepetitiveCaptureSourceGraphReviewV2.History,
        required: inout Set<String>) throws -> PhaseFacts {
        let raw: CheckRunnerPhotoRawReadyV1?
        let pair: CheckRunnerPhotoPairReadyV1?
        let reconstruction: CheckRunnerPhotoCommitReconstructionV1?
        switch payload.phase {
        case .awaitingRawStage: raw = nil; pair = nil; reconstruction = nil
        case let .rawReady(value): raw = value; pair = nil; reconstruction = nil
        case let .pairReady(value): raw = value.raw; pair = value; reconstruction = nil
        case let .preparedCommit(value, _):
            raw = value.raw; pair = value
            let committing = try exactlyOne(history.fieldDraftHistory(
                workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID).compactMap { record -> FieldDraftCheckpointV1? in
                    guard case let .applyFieldDraft(mutation) = record.envelope.command,
                          let value = RepetitiveCaptureSourceGraphReviewV2.checkpointPostImage(
                            mutation.postImage), value.state == .committing else { return nil }
                    return value
                })
            reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: committing)
        }
        let target: CheckRunnerPhotoCommittedEvidenceV1?
        if let reconstruction {
            let mutationID = reconstruction.draftCommit.plan.mutationID
            if let record = history.records[RepetitiveCaptureSourceGraphReviewV2.key(
                checkpoint.workspaceID, mutationID)] {
                required.insert(key(record))
                target = try CheckRunnerPhotoCommittedEvidenceV1(
                    envelope: record.envelope, receipt: record.receipt)
            } else { target = nil }
        } else { target = nil }
        return .init(raw: raw, pair: pair, reconstruction: reconstruction, target: target)
    }

    static func sourceGraph(for source: CheckRunnerRoundItemSourceV1,
                            in graphs: [ReviewedRepetitiveCaptureSourceGraphV2]) throws
        -> ReviewedRepetitiveCaptureSourceGraphV2 {
        try exactlyOne(graphs.filter {
            (try? source.sourceCheckpoint.validate(source: $0.chain.sourceCheckpoint)) != nil
        })
    }

    static func validateHistoricalEntry(_ source: CheckRunnerRoundItemSourceV1,
                                        graph: ReviewedRepetitiveCaptureSourceGraphV2) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        try source.validate()
        try source.sourceCheckpoint.validate(source: graph.chain.sourceCheckpoint)
        let matches = graph.chain.nodes.filter {
            (try? source.entryProgressCheckpoint.validate(source: $0.checkpoint)) != nil
        }
        guard matches.count == 1, let entry = matches.first,
              entry.step.action == .enter,
              entry.step.itemID == source.originalItem.itemID,
              entry.step.navigationItemID == source.originalItem.itemID,
              !entry.isPendingRoundEffect else { throw failure }
        let round = entry.step.resultingRound
        guard try round.reference == source.roundAtEntry,
              graph.chain.launch.round.items.first(where: { $0.itemID == source.originalItem.itemID })
                == source.originalItem,
              round.items.first(where: { $0.itemID == source.itemAtEntry.itemID }) == source.itemAtEntry,
              source.itemAtEntry.selection.assetID == source.assetID,
              source.originalItem.requirement.packageRelease == source.packageRelease else { throw failure }
    }

    static func validateTargetRecords(target: CheckRunnerPhotoCommittedEvidenceV1,
        begin: CheckRunnerBeginCommittedEvidenceV1,
        workflow: V4BackupWorkflowRecordDTO,
        originalWorkflowPostImage: MutationPostImageV1,
        currentWorkflowPostImage: MutationPostImageV1,
        evidence: V4BackupEvidenceFileDTO,
        originalEvidencePostImage: MutationPostImageV1,
        currentEvidencePostImage: MutationPostImageV1,
        later: [RepetitiveCaptureSourceHistoryRecordV2], terminal: Bool) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let workflowIdentity = try WorkspaceEntityIdentityV1(
            kind: .workflowRecord, id: target.command.draftID)
        let evidenceIdentity = try WorkspaceEntityIdentityV1(
            kind: .evidenceFile, id: target.command.evidenceID)
        guard try originalWorkflowPostImage.identity == workflowIdentity,
              try originalEvidencePostImage.identity == evidenceIdentity,
              target.receipt.postImages.contains(originalWorkflowPostImage),
              target.receipt.postImages.contains(originalEvidencePostImage),
              evidence == evidenceDTO(target.command),
              currentEvidencePostImage == originalEvidencePostImage else { throw failure }
        if terminal { return }
        guard later.isEmpty, currentWorkflowPostImage == originalWorkflowPostImage,
              case let .createCheckDraft(command) = begin.command,
              command.recordID == target.command.draftID else { throw failure }
        try validateUnfinalizedTargetWorkflow(
            workflow, begin: command, target: target.command)
    }

    static func validateUnfinalizedTargetWorkflow(_ record: V4BackupWorkflowRecordDTO,
        begin command: CheckDraftMutationV1, target: CheckEvidenceMutationV1) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let actual = CheckDraftMutationV1(recordID: record.id, assetID: record.assetID,
            issueID: record.issueID, parentRecordID: record.parentRecordID, stage: record.stage,
            draftStepKey: command.draftStepKey, startedAt: record.startedAt,
            observedAtUTC: record.observedAtUTC, timeZoneID: record.timeZoneID,
            utcOffsetMinutes: record.utcOffsetMinutes, localDate: record.localDate,
            localTime: record.localTime,
            afterDarkAcknowledgementKey: record.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: record.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: record.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: record.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: record.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: record.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: record.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: record.safePositionAcknowledgementAccepted,
            packID: record.packID, packSchemaVersion: record.packSchemaVersion,
            packContentVersion: record.packContentVersion, pdfTemplateID: record.pdfTemplateID,
            pdfTemplateVersion: record.pdfTemplateVersion,
            observationBasis: command.observationBasis, temporalContext: command.temporalContext)
        let basis = try command.observationBasis
            ?? ObservationAndTimeLegacyMigrationV1.observationBasis(
                couldNotVerifyKey: nil, displaySnapshot: nil, registryVersion: nil)
        let temporal = try command.temporalContext
            ?? ObservationAndTimeLegacyMigrationV1.temporalContext(
                observedAtUTC: command.observedAtUTC, recordedAtUTC: command.startedAt,
                timeZoneID: command.timeZoneID,
                utcOffsetMinutes: command.utcOffsetMinutes,
                localDate: command.localDate, localTime: command.localTime)
        guard actual == command, let basis, let temporal,
              record.schemaVersion == 1,
              record.revisionKind == WorkflowRevisionKind.original.rawValue,
              record.recordRevisionRootID == command.recordID,
              record.revisesRecordID == nil, record.evidenceSourceRecordID == nil,
              record.state == WorkflowState.draft.rawValue,
              record.draftStepKey == target.nextDraftStepKey,
              record.packetID == nil, record.completedAt == nil,
              record.outcomeKey == nil, record.couldNotVerifyKey == nil,
              record.couldNotVerifyDisplaySnapshot == nil,
              record.couldNotVerifyRegistryVersion == nil,
              record.workPerformedLocalDate == nil, record.workDescription == nil,
              record.note == nil, record.finalizationMutationID == nil,
              record.observationBasisV1Data == (try ObservationAndTimeCodecV1.encode(basis)),
              record.temporalContextV1Data == (try ObservationAndTimeCodecV1.encode(temporal))
        else { throw failure }
    }

    static func evidenceDTO(_ command: CheckEvidenceMutationV1) -> V4BackupEvidenceFileDTO {
        .init(id: command.evidenceID, schemaVersion: 1, recordID: command.draftID,
            purposeKey: command.purposeKey, relativePath: command.relativePath,
            mimeType: command.mimeType, byteCount: command.byteCount, sha256: command.sha256,
            createdAt: command.createdAt,
            thumbnailRelativePath: command.thumbnailRelativePath,
            thumbnailByteCount: command.thumbnailByteCount,
            thumbnailSHA256: command.thumbnailSHA256)
    }

    static func workflowImageBeforePhoto(payload: CheckRunnerPhotoDraftPayloadV1,
        begin: CheckRunnerBeginCommittedEvidenceV1, precedingWide: CheckRunnerPhotoParentEvidenceV1?
    ) throws -> MutationPostImageV1 {
        let identity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: payload.recordID)
        switch payload.captureStep {
        case .wide:
            return try exactlyOne(begin.receipt.postImages.filter { try $0.identity == identity })
        case .close:
            guard let precedingWide else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
            return try exactlyOne(precedingWide.child.target.receipt.postImages.filter {
                try $0.identity == identity
            })
        default:
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
    }

    static func laterWorkflowReceipts(after original: MutationReceiptV1,
        identity: WorkspaceEntityIdentityV1,
        history: RepetitiveCaptureSourceGraphReviewV2.History) throws
        -> [RepetitiveCaptureSourceHistoryRecordV2] {
        try history.records.values.filter { record in
            guard record.envelope.workspaceID == original.identity.workspaceID,
                  record.receipt.resultingRevision.workspaceRevision
                    > original.resultingRevision.workspaceRevision else { return false }
            return try record.receipt.postImages.contains { try $0.identity == identity }
        }.sorted(by: RepetitiveCaptureSourceGraphReviewV2.recordLess)
    }

    static func latestPostImage(identity: WorkspaceEntityIdentityV1,
        workspaceID: WorkspaceID,
        history: RepetitiveCaptureSourceGraphReviewV2.History,
        records: V4BackupRecordsV1) throws -> MutationPostImageV1 {
        let images = try history.records.values.filter {
            $0.envelope.workspaceID == workspaceID
        }.flatMap { record in
            try record.receipt.postImages.filter { try $0.identity == identity }
        }.sorted { $0.revision < $1.revision }
        guard let last = images.last,
              images.map(\.revision) == Array(1...images.count).map(UInt64.init),
              records.mutationHistory?.entityRevisions.first(where: { $0.identity == identity })?.revision
                == last.revision else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        return last
    }

    static func key(_ record: RepetitiveCaptureSourceHistoryRecordV2) -> String {
        RepetitiveCaptureSourceGraphReviewV2.key(record.envelope)
    }

    static func captureRank(_ step: WorkflowDraftStep) -> Int {
        switch step { case .wide: 0; case .close: 1; default: 2 }
    }

    static func exactlyOne<T>(_ values: [T]) throws -> T {
        guard values.count == 1, let value = values.first else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return value
    }
}

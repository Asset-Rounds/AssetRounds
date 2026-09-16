import CryptoKit
import Foundation

struct RepetitiveCaptureSourceHistoryRecordV2: Equatable, Sendable {
    let original: MutationHistoryReceiptRecordV1
    let envelope: MutationEnvelopeV1
    let receipt: MutationReceiptV1
}

struct ReviewedRepetitiveCaptureSourceCheckpointV2: Equatable, Sendable {
    let original: FieldDraftCheckpointV1
    let current: FieldDraftCheckpointV1
    let lifecycle: [RepetitiveCaptureSourceHistoryRecordV2]
}

struct ReviewedRepetitiveCaptureSourceGraphV2: Equatable, Sendable {
    /// This chain contains original create postimages, including their historical
    /// readiness. It never supplies a destination readiness or mutation permit.
    let chain: ReviewedRepetitiveCaptureProgressChainV2
    let checkpoints: [ReviewedRepetitiveCaptureSourceCheckpointV2]
    let packageCurrentRound: RoundSessionV1
    let isUnchangedActiveSource: Bool
}

struct ReviewedRepetitiveCaptureSourceGraphsV2: Equatable, Sendable {
    let sourceWorkspaceID: WorkspaceID
    let sourcePersistentSchemaVersion: Int
    let sourceRecordsSchemaVersion: Int
    let manifestJSONSHA256: String
    let recordsJSONSHA256: String
    let graphs: [ReviewedRepetitiveCaptureSourceGraphV2]
    let requiredHistory: [RepetitiveCaptureSourceHistoryRecordV2]

    fileprivate init(sourceWorkspaceID: WorkspaceID, sourcePersistentSchemaVersion: Int,
                     sourceRecordsSchemaVersion: Int, manifestJSONSHA256: String,
                     recordsJSONSHA256: String, graphs: [ReviewedRepetitiveCaptureSourceGraphV2],
                     requiredHistory: [RepetitiveCaptureSourceHistoryRecordV2]) {
        self.sourceWorkspaceID = sourceWorkspaceID
        self.sourcePersistentSchemaVersion = sourcePersistentSchemaVersion
        self.sourceRecordsSchemaVersion = sourceRecordsSchemaVersion
        self.manifestJSONSHA256 = manifestJSONSHA256
        self.recordsJSONSHA256 = recordsJSONSHA256
        self.graphs = graphs
        self.requiredHistory = requiredHistory
    }
}

/// Complete canonical-value proof shared by source-graph and source-history
/// readers. It grants no archive-member, filesystem, writer, or effect authority.
struct ReviewedRepetitiveCaptureCanonicalSourceV2: Equatable, Sendable {
    let sourceWorkspaceID: WorkspaceID
    let graphs: [ReviewedRepetitiveCaptureSourceGraphV2]
    let requiredHistory: [RepetitiveCaptureSourceHistoryRecordV2]
    let history: RepetitiveCaptureSourceGraphReviewV2.History
}

/// Authenticates original C36 graphs inside a complete validated package. This
/// reader owns no store, filesystem operation, destination identity or writer.
enum RepetitiveCaptureSourceGraphReviewV2 {
    static func review(sourcePackage: ValidatedRepetitiveCaptureSourcePackageV2) throws
        -> ReviewedRepetitiveCaptureSourceGraphsV2 {
        let reviewed = try reviewCanonicalSource(
            source: sourcePackage.source, records: sourcePackage.records)
        return .init(sourceWorkspaceID: reviewed.sourceWorkspaceID,
                     sourcePersistentSchemaVersion: sourcePackage.source.persistentSchemaVersion,
                     sourceRecordsSchemaVersion: sourcePackage.source.recordsSchemaVersion,
                     manifestJSONSHA256: sourcePackage.manifestJSONSHA256,
                     recordsJSONSHA256: sourcePackage.recordsJSONSHA256,
                     graphs: reviewed.graphs, requiredHistory: reviewed.requiredHistory)
    }

    /// Pure value entry used before physical membership acceptance. The
    /// incumbent package entry above remains the only capability-bearing API.
    static func reviewCanonicalSource(source: V4BackupSourceV1, records: V4BackupRecordsV1) throws
        -> ReviewedRepetitiveCaptureCanonicalSourceV2 {
        guard let rawWorkspaceID = source.workspaceID,
              source.recordsSchemaVersion == records.recordsSchemaVersion,
              let snapshot = records.mutationHistory else { throw invalid() }
        let workspace = WorkspaceID(rawValue: rawWorkspaceID)
        try MutationJournalStoreV1.validateImportedSnapshot(
            snapshot, sourcePersistentSchemaVersion: source.persistentSchemaVersion)
        let history = try History(snapshot: snapshot)
        let release = try RepetitiveCaptureProgressDraftCodecV2.release()
        var currentByID: [UUID: FieldDraftCheckpointV1] = [:]
        var discardReceiptsByDraft: [UUID: [DraftDiscardReceiptV1]] = [:]
        for row in records.fieldDrafts where row.kind == .discardReceipt {
            let receipt = try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self,
                                                               from: row.canonicalData)
            guard row.workspaceID == rawWorkspaceID, receipt.workspaceID == workspace,
                  row.id == receipt.receiptID, row.revision == receipt.revision else { throw invalid() }
            discardReceiptsByDraft[receipt.draftID, default: []].append(receipt)
        }
        for row in records.fieldDrafts where row.kind == .checkpoint {
            let value = try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self,
                                                             from: row.canonicalData)
            guard value.workspaceID == workspace, row.workspaceID == rawWorkspaceID,
                  value.draftID == row.id, value.draftRevision == row.revision else { throw invalid() }
            guard value.codec == release else { continue }
            guard value.purpose == .repetitiveCapture,
                  currentByID.updateValue(value, forKey: value.draftID) == nil else { throw invalid() }
        }
        // C36 discard retains a terminal checkpoint; Erase removes both rows
        // and history. A same-workspace acknowledged create cannot disappear
        // from a full source package merely because records.json was rehashed.
        // Foreign imported history belongs to its own source workspace.
        var createdIDs = Set<UUID>()
        for record in history.records.values where record.envelope.workspaceID == workspace {
            guard case let .applyFieldDraft(mutation) = record.envelope.command,
                  case let .createCheckpoint(value) = mutation.postImage,
                  value.codec == release else { continue }
            try RepetitiveCaptureProgressDraftCodecV2.validateCheckpoint(value)
            guard value.workspaceID == workspace, currentByID[value.draftID] != nil,
                  createdIDs.insert(value.draftID).inserted else { throw invalid() }
        }
        guard createdIDs == Set(currentByID.keys) else { throw invalid() }

        var checkpoints: [UUID: ReviewedRepetitiveCaptureSourceCheckpointV2] = [:]
        var sources: [UUID: FieldDraftCheckpointV1] = [:]
        var membersBySource: [UUID: [UUID]] = [:]
        var requiredKeys = Set<String>()
        for current in currentByID.values {
            let reviewed = try checkpointHistory(current: current, history: history,
                discardReceipts: discardReceiptsByDraft[current.draftID, default: []])
            checkpoints[current.draftID] = reviewed
            for record in reviewed.lifecycle { requiredKeys.insert(key(record.envelope)) }
            switch try RepetitiveCaptureProgressDraftCodecV2.decode(reviewed.original.payloadData) {
            case .source:
                guard sources.updateValue(reviewed.original, forKey: current.draftID) == nil else {
                    throw invalid()
                }
                membersBySource[current.draftID, default: []].append(current.draftID)
            case let .progress(step):
                membersBySource[step.source.draftID, default: []].append(current.draftID)
            }
        }
        guard Set(membersBySource.keys) == Set(sources.keys) else { throw invalid() }

        var roundHistories: [UUID: [RoundSessionV1]] = [:]
        var roundRecords: [String: RepetitiveCaptureSourceHistoryRecordV2] = [:]
        var graphs: [ReviewedRepetitiveCaptureSourceGraphV2] = []
        var activeScopes = Set<DraftScopeKeyV1>()
        var covered = Set<UUID>()
        for sourceID in sources.keys.sorted(by: uuidLess) {
            guard let source = sources[sourceID], let memberIDs = membersBySource[sourceID] else {
                throw invalid()
            }
            let launch = try RepetitiveCaptureProgressDraftCodecV2.source(source)
            let sessionID = launch.round.sessionID
            let fullRounds: [RoundSessionV1]
            if let existing = roundHistories[sessionID] {
                fullRounds = existing
            } else {
                fullRounds = records.roundSessions.filter {
                    $0.workspaceID == workspace && $0.sessionID == sessionID
                }
                guard try RoundSessionHistoryValidatorV1.validate(fullRounds,
                    workspaceID: workspace, sessionID: sessionID) != nil else { throw invalid() }
                let journalRounds = history.roundsBySession[
                    .init(workspaceID: workspace, id: sessionID), default: []]
                var journalByRevision: [UInt64: RoundSessionV1] = [:]
                for round in journalRounds {
                    guard journalByRevision.updateValue(round, forKey: round.revision) == nil else {
                        throw invalid()
                    }
                }
                guard journalByRevision == Dictionary(uniqueKeysWithValues: fullRounds.map {
                    ($0.revision, $0)
                }) else { throw invalid() }
                var previousRevision: UInt64?
                // Every revision is authenticated, including pre-launch and
                // later history outside a disposed graph's captured frontier.
                for round in fullRounds {
                    let record = try roundRecord(round, history: history)
                    let revision = record.receipt.resultingRevision.workspaceRevision
                    guard previousRevision.map({ revision > $0 }) ?? true else { throw invalid() }
                    previousRevision = revision
                    let recordKey = key(record.envelope)
                    roundRecords[recordKey] = record
                    requiredKeys.insert(recordKey)
                }
                roundHistories[sessionID] = fullRounds
            }
            guard let packageCurrent = fullRounds.last else { throw invalid() }
            let members = try memberIDs.map { id -> ReviewedRepetitiveCaptureSourceCheckpointV2 in
                guard let value = checkpoints[id], covered.insert(id).inserted else { throw invalid() }
                return value
            }
            let unchangedActive = members.allSatisfy { $0.current == $0.original }
            if unchangedActive {
                guard activeScopes.insert(source.scope).inserted else { throw invalid() }
            }
            let originals = members.map(\.original)
            let effectiveFrontier = try frontier(source: source, originals: originals, history: history)
            guard fullRounds.contains(effectiveFrontier) else { throw invalid() }
            let selectedRounds: [RoundSessionV1]
            if unchangedActive {
                guard packageCurrent == effectiveFrontier else { throw invalid() }
                selectedRounds = fullRounds
            } else {
                selectedRounds = fullRounds.filter { $0.revision <= effectiveFrontier.revision }
            }
            let chain = try RepetitiveCaptureProgressChainReviewV2.review(
                workspaceID: workspace, sourceDraftID: sourceID,
                authenticatedProgressCheckpoint: { requestedWorkspace, id in
                    guard requestedWorkspace == workspace, memberIDs.contains(id),
                          let value = checkpoints[id], let original = value.lifecycle.first else {
                        throw invalid()
                    }
                    return (value.original, original.receipt)
                },
                progressRoundHistory: { requestedWorkspace, requestedSession in
                    guard requestedWorkspace == workspace, requestedSession == sessionID else {
                        throw invalid()
                    }
                    return selectedRounds
                },
                requireProgressLaunchReceipt: { round in
                    guard round == launch.round,
                          let record = roundRecords[key(workspace, round.mutationID)] else { throw invalid() }
                    return record.receipt
                },
                progressCheckpoints: { requestedWorkspace in
                    guard requestedWorkspace == workspace else { throw invalid() }
                    return originals
                },
                durableReceipt: { mutationID in
                    let recordKey = key(workspace, mutationID)
                    guard history.records[recordKey] != nil else { return nil }
                    guard let record = roundRecords[recordKey] else { throw invalid() }
                    return record.receipt
                })
            let orderedIDs = [sourceID] + chain.nodes.map { $0.checkpoint.draftID }
            guard orderedIDs.count == memberIDs.count,
                  Set(orderedIDs) == Set(memberIDs) else { throw invalid() }
            let ordered = try orderedIDs.map { id -> ReviewedRepetitiveCaptureSourceCheckpointV2 in
                guard let value = checkpoints[id] else { throw invalid() }
                return value
            }
            graphs.append(.init(chain: chain, checkpoints: ordered,
                                packageCurrentRound: packageCurrent,
                                isUnchangedActiveSource: unchangedActive))
        }
        guard covered == Set(currentByID.keys),
              requiredKeys.isDisjoint(with: history.quarantinedKeys) else { throw invalid() }
        let required = try requiredKeys.map { try history.authenticated($0) }.sorted(by: recordLess)
        return .init(sourceWorkspaceID: workspace, graphs: graphs,
                     requiredHistory: required, history: history)
    }

    struct WorkspaceObjectKey: Hashable, Sendable {
        let workspaceID: WorkspaceID
        let id: UUID
    }

    struct History: Equatable, Sendable {
        let records: [String: RepetitiveCaptureSourceHistoryRecordV2]
        let quarantinedKeys: Set<String>
        let checkpointsByDraft: [WorkspaceObjectKey: [RepetitiveCaptureSourceHistoryRecordV2]]
        let fieldDraftRecordsByDraft: [WorkspaceObjectKey: [RepetitiveCaptureSourceHistoryRecordV2]]
        let roundsBySession: [WorkspaceObjectKey: [RoundSessionV1]]

        init(snapshot: MutationHistorySnapshotV1) throws {
            var values: [String: RepetitiveCaptureSourceHistoryRecordV2] = [:]
            var checkpoints: [WorkspaceObjectKey: [RepetitiveCaptureSourceHistoryRecordV2]] = [:]
            var fieldDrafts: [WorkspaceObjectKey: [RepetitiveCaptureSourceHistoryRecordV2]] = [:]
            var rounds: [WorkspaceObjectKey: [RoundSessionV1]] = [:]
            for original in snapshot.receipts {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
                let receipt = try MutationReceiptV1.decodeCanonical(from: original.receiptData)
                let record = RepetitiveCaptureSourceHistoryRecordV2(
                    original: original, envelope: envelope, receipt: receipt)
                guard values.updateValue(record, forKey: RepetitiveCaptureSourceGraphReviewV2.key(envelope)) == nil
                else { throw RepetitiveCaptureSourceGraphReviewV2.invalid() }
                switch envelope.command {
                case let .applyFieldDraft(mutation):
                    let draftID = RepetitiveCaptureSourceGraphReviewV2.draftID(mutation.postImage)
                    fieldDrafts[.init(workspaceID: envelope.workspaceID, id: draftID),
                                default: []].append(record)
                    if let checkpoint = RepetitiveCaptureSourceGraphReviewV2.checkpointPostImage(mutation.postImage) {
                        checkpoints[.init(workspaceID: envelope.workspaceID, id: checkpoint.draftID),
                                    default: []].append(record)
                    }
                case let .applyRoundSession(mutation):
                    rounds[.init(workspaceID: envelope.workspaceID, id: mutation.session.sessionID),
                           default: []].append(mutation.session)
                default: break
                }
            }
            records = values
            checkpointsByDraft = checkpoints
            fieldDraftRecordsByDraft = fieldDrafts
            roundsBySession = rounds
            // Both quarantine identity domains use the same source mutation
            // closure. A valid unrelated quarantine does not taint this graph.
            quarantinedKeys = Set(try snapshot.quarantines.map {
                RepetitiveCaptureSourceGraphReviewV2.key(
                    $0.workspaceID, try MutationIDV1(rawValue: $0.mutationID))
            })
        }

        func authenticated(_ recordKey: String) throws -> RepetitiveCaptureSourceHistoryRecordV2 {
            guard let value = records[recordKey] else { throw RepetitiveCaptureSourceGraphReviewV2.invalid() }
            let envelope = value.envelope, receipt = value.receipt
            guard receipt.identity.workspaceID == envelope.workspaceID,
                  receipt.identity.replicaID == envelope.replicaID,
                  receipt.mutationID == envelope.mutationID,
                  receipt.envelopeSHA256 == (try envelope.canonicalSHA256()),
                  receipt.commandBodySHA256 == envelope.commandBodySHA256,
                  receipt.expectedRevision == envelope.expectedRevision,
                  receipt.contentDependencyIDs == envelope.contentDependencyIDs,
                  receipt.sourceKind == envelope.sourceKind,
                  receipt.causationMutationID == envelope.causationMutationID,
                  receipt.correlationID == envelope.correlationID else {
                throw RepetitiveCaptureSourceGraphReviewV2.invalid()
            }
            return value
        }

        func authenticated(workspaceID: WorkspaceID, mutationID: MutationIDV1) throws
            -> RepetitiveCaptureSourceHistoryRecordV2 {
            try authenticated(RepetitiveCaptureSourceGraphReviewV2.key(workspaceID, mutationID))
        }

        func fieldDraftHistory(workspaceID: WorkspaceID, draftID: UUID)
            -> [RepetitiveCaptureSourceHistoryRecordV2] {
            fieldDraftRecordsByDraft[.init(workspaceID: workspaceID, id: draftID), default: []]
                .sorted(by: RepetitiveCaptureSourceGraphReviewV2.recordLess)
        }

        func isQuarantined(_ record: RepetitiveCaptureSourceHistoryRecordV2) -> Bool {
            quarantinedKeys.contains(RepetitiveCaptureSourceGraphReviewV2.key(record.envelope))
        }
    }

    private static func checkpointHistory(current: FieldDraftCheckpointV1, history: History,
                                          discardReceipts: [DraftDiscardReceiptV1]) throws
        -> ReviewedRepetitiveCaptureSourceCheckpointV2 {
        let candidates = history.checkpointsByDraft[
            .init(workspaceID: current.workspaceID, id: current.draftID), default: []].sorted(by: recordLess)
        guard let first = candidates.first,
              case let .applyFieldDraft(firstMutation) = first.envelope.command,
              case let .createCheckpoint(original) = firstMutation.postImage else { throw invalid() }
        try RepetitiveCaptureProgressDraftCodecV2.validateCheckpoint(original)
        var previous: FieldDraftCheckpointV1?
        var previousReceiptRevision: UInt64?
        var lifecycle: [RepetitiveCaptureSourceHistoryRecordV2] = []
        for candidate in candidates {
            let record = try history.authenticated(key(candidate.envelope))
            let evidence = try FieldDraftCommittedEvidenceV1(envelope: record.envelope, receipt: record.receipt)
            let mutation = evidence.mutation
            guard let value = checkpointPostImage(mutation.postImage),
                  mutation.workspaceID == current.workspaceID, value.workspaceID == current.workspaceID,
                  value.draftID == current.draftID, value.mutationID == mutation.mutationID,
                  previousReceiptRevision.map({ record.receipt.resultingRevision.workspaceRevision > $0 }) ?? true
            else { throw invalid() }
            if let previous {
                try value.validateSuccessor(of: previous,
                    expectedDraftRevision: mutation.expectedRevision,
                    expectedBaseRevision: mutation.expectedBaseCanonicalRevision)
                try validateTransition(mutation.postImage, from: previous)
            } else {
                guard mutation.expectedRevision == 0,
                      mutation.expectedBaseCanonicalRevision == original.baseCanonicalRevision,
                      value == original else { throw invalid() }
            }
            previous = value
            previousReceiptRevision = record.receipt.resultingRevision.workspaceRevision
            lifecycle.append(record)
        }
        guard previous == current else { throw invalid() }
        if let last = lifecycle.last,
           case let .applyFieldDraft(mutation) = last.envelope.command,
           case let .applyDiscardTerminal(bundle) = mutation.postImage {
            guard discardReceipts == [bundle.receipt] else { throw invalid() }
        } else {
            guard current.state != .discarded, discardReceipts.isEmpty else { throw invalid() }
        }
        return .init(original: original, current: current, lifecycle: lifecycle)
    }

    private static func validateTransition(_ payload: FieldDraftMutationPayloadV1,
                                          from previous: FieldDraftCheckpointV1) throws {
        switch payload {
        case .reviseCheckpoint:
            // Generic revisions may legitimately change payload and navigation;
            // validateSuccessor owns their immutable identity/state boundary.
            return
        case let .resolveConflict(value):
            try value.validate()
            guard value.expectedCheckpoint == previous else { throw invalid() }
        case let .publishReadyStage(value):
            try value.validate()
            guard value.expectedCheckpoint == previous else { throw invalid() }
        case let .applyCommitTerminal(value, _):
            try value.validate()
            guard previous.state == .committing else { throw invalid() }
        case let .applyDiscardTerminal(value):
            try value.validate()
            guard previous.state == .discardPending else { throw invalid() }
        default:
            throw invalid()
        }
    }

    static func checkpointPostImage(_ payload: FieldDraftMutationPayloadV1) -> FieldDraftCheckpointV1? {
        switch payload {
        case let .createCheckpoint(value), let .reviseCheckpoint(value): return value
        case let .resolveConflict(value): return value.successorCheckpoint
        case let .publishReadyStage(value): return value.successorCheckpoint
        case let .applyCommitTerminal(value, _): return value.committedCheckpoint
        case let .applyDiscardTerminal(value): return value.discardedCheckpoint
        default: return nil
        }
    }

    static func draftID(_ payload: FieldDraftMutationPayloadV1) -> UUID {
        switch payload {
        case let .createCheckpoint(value), let .reviseCheckpoint(value): return value.draftID
        case let .appendStagingItem(value), let .reviseStagingItem(value): return value.draftID
        case let .appendCommitSaga(value), let .advanceCommitSaga(value): return value.draftID
        case let .appendContentReservation(value), let .reviseContentReservation(value): return value.draftID
        case let .applyCommitTerminal(value, _): return value.committedCheckpoint.draftID
        case let .applyDiscardTerminal(value): return value.discardedCheckpoint.draftID
        case let .resolveConflict(value): return value.successorCheckpoint.draftID
        case let .publishReadyStage(value): return value.successorCheckpoint.draftID
        }
    }

    private static func roundRecord(_ round: RoundSessionV1, history: History) throws
        -> RepetitiveCaptureSourceHistoryRecordV2 {
        guard round.revision > 0 else { throw invalid() }
        let record = try history.authenticated(key(round.workspaceID, round.mutationID))
        let expected = try RoundSessionMutationV1(workspaceID: round.workspaceID,
            expectedRevision: round.revision - 1, mutationID: round.mutationID, session: round)
        guard case let .applyRoundSession(actual) = record.envelope.command,
              actual == expected else { throw invalid() }
        _ = try RoundSessionMutationReceiptV1(mutation: actual, mutationReceipt: record.receipt)
        return record
    }

    private static func frontier(source: FieldDraftCheckpointV1,
                                 originals: [FieldDraftCheckpointV1], history: History) throws -> RoundSessionV1 {
        let progress = try originals.filter { $0.draftID != source.draftID }.map { checkpoint in
            guard case let .progress(step) = try RepetitiveCaptureProgressDraftCodecV2.decode(checkpoint.payloadData)
            else { throw invalid() }
            return (checkpoint, step)
        }
        guard !progress.isEmpty else { return try RepetitiveCaptureProgressDraftCodecV2.source(source).round }
        let predecessors = Set(progress.compactMap { $0.1.prior?.draftID })
        let leaves = progress.filter { !predecessors.contains($0.0.draftID) }
        guard leaves.count == 1, let step = leaves.first?.1 else { throw invalid() }
        if let mutation = step.roundMutation,
           history.records[key(source.workspaceID, mutation.mutationID)] != nil {
            _ = try roundRecord(mutation.session, history: history)
            return mutation.session
        }
        return step.expectedRound
    }

    static func key(_ envelope: MutationEnvelopeV1) -> String {
        key(envelope.workspaceID, envelope.mutationID)
    }
    static func key(_ workspace: WorkspaceID, _ mutation: MutationIDV1) -> String {
        MutationWorkspaceKeyV1.value(workspaceID: workspace, mutationID: mutation)
    }
    static func recordLess(_ lhs: RepetitiveCaptureSourceHistoryRecordV2,
                           _ rhs: RepetitiveCaptureSourceHistoryRecordV2) -> Bool {
        let left = lhs.receipt.resultingRevision.workspaceRevision
        let right = rhs.receipt.resultingRevision.workspaceRevision
        return left == right ? lhs.receipt.identity.stableKey < rhs.receipt.identity.stableKey : left < right
    }
    private static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }
    private static func invalid() -> WorkspaceMutationFailureV1 { .receiptHistoryCorrupt }
}

/// A bounded commitment to original source evidence. Decoding or validating its
/// shape grants no receipt, current readiness, destination identity or writer authority.
struct RepetitiveCaptureSourceGraphReferenceV2: Codable, Equatable, Sendable,
    FieldDraftValidatableV1 {
    static let format = "assetrounds.c36.source-graph-reference.v1"
    static let maximumFrontiers = 1 + 2 * ScanToWorkLimitsV1.maximumSelection

    struct HistoryCommitment: Codable, Equatable, Sendable {
        let recordCount: Int
        let recordsSHA256: String

        fileprivate func validate() throws {
            guard recordCount > 0,
                  recordCount <= MutationJournalStoreV1.maximumReceiptValidationCount else {
                throw FieldDraftFailureV1.limitExceeded
            }
            try FieldDraftValidationV1.digest(recordsSHA256)
        }
    }

    struct RecordAnchor: Codable, Equatable, Sendable {
        let mutationID: MutationIDV1
        let receiptIdentity: MutationReceiptIdentityV1
        let envelopeSHA256: String
        let receiptSHA256: String

        fileprivate init(_ record: RepetitiveCaptureSourceHistoryRecordV2) {
            mutationID = record.envelope.mutationID
            receiptIdentity = record.receipt.identity
            envelopeSHA256 = FieldDraftCanonicalCodecV1.sha256(record.original.envelopeData)
            receiptSHA256 = FieldDraftCanonicalCodecV1.sha256(record.original.receiptData)
        }

        fileprivate func validate(workspaceID: WorkspaceID) throws {
            try receiptIdentity.validate()
            try FieldDraftValidationV1.digest(envelopeSHA256)
            try FieldDraftValidationV1.digest(receiptSHA256)
            guard receiptIdentity.workspaceID == workspaceID else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
    }

    struct CheckpointTip: Codable, Equatable, Sendable {
        let draftRevision: UInt64
        let state: FieldDraftStateV1
        let checkpointSHA256: String
        let record: RecordAnchor

        fileprivate init(_ checkpoint: FieldDraftCheckpointV1,
                         record: RepetitiveCaptureSourceHistoryRecordV2) {
            draftRevision = checkpoint.draftRevision
            state = checkpoint.state
            checkpointSHA256 = checkpoint.checkpointSHA256
            self.record = .init(record)
        }
    }

    struct CheckpointFrontier: Codable, Equatable, Sendable {
        /// Zero is the source; remaining positions follow the exact progress chain.
        let position: Int
        let draftID: UUID
        let original: CheckpointTip
        let current: CheckpointTip
        let lifecycle: HistoryCommitment
    }

    struct RoundTip: Codable, Equatable, Sendable {
        let revision: UInt64
        let canonicalSHA256: String
        let record: RecordAnchor
    }

    struct Value: Codable, Equatable, Sendable {
        let format: String
        let sourceWorkspaceID: WorkspaceID
        let sourcePersistentSchemaVersion: Int
        let sourceRecordsSchemaVersion: Int
        let manifestJSONSHA256: String
        let recordsJSONSHA256: String
        let sourceDraftID: UUID
        let checkpoints: [CheckpointFrontier]
        let roundSessionID: UUID
        let historicalRound: RoundTip
        let packageCurrentRound: RoundTip
        let roundHistory: HistoryCommitment
        let requiredHistory: HistoryCommitment
        let isUnchangedActiveSource: Bool
    }

    let value: Value
    let referenceSHA256: String

    fileprivate init(value: Value) throws {
        self.value = value
        referenceSHA256 = try FieldDraftCanonicalCodecV1.sha256(value)
        try validate()
    }

    func validate() throws {
        try FieldDraftValidationV1.workspace(value.sourceWorkspaceID)
        try FieldDraftValidationV1.id(value.sourceDraftID)
        try FieldDraftValidationV1.id(value.roundSessionID)
        for digest in [value.manifestJSONSHA256, value.recordsJSONSHA256, referenceSHA256] {
            try FieldDraftValidationV1.digest(digest)
        }
        guard value.format == Self.format, value.sourcePersistentSchemaVersion > 0,
              value.sourceRecordsSchemaVersion > 0, !value.checkpoints.isEmpty,
              value.checkpoints.count <= Self.maximumFrontiers,
              value.checkpoints.first?.draftID == value.sourceDraftID,
              Set(value.checkpoints.map(\.draftID)).count == value.checkpoints.count else {
            throw FieldDraftFailureV1.invalidValue
        }
        var lifecycleCount = 0
        for (position, frontier) in value.checkpoints.enumerated() {
            try FieldDraftValidationV1.id(frontier.draftID)
            try frontier.lifecycle.validate()
            guard frontier.position == position, frontier.original.draftRevision == 1,
                  frontier.original.state == .active,
                  frontier.current.draftRevision >= frontier.original.draftRevision else {
                throw FieldDraftFailureV1.invalidValue
            }
            for tip in [frontier.original, frontier.current] {
                try FieldDraftValidationV1.digest(tip.checkpointSHA256)
                try tip.record.validate(workspaceID: value.sourceWorkspaceID)
            }
            lifecycleCount += frontier.lifecycle.recordCount
        }
        for tip in [value.historicalRound, value.packageCurrentRound] {
            try FieldDraftValidationV1.revision(tip.revision)
            try FieldDraftValidationV1.digest(tip.canonicalSHA256)
            try tip.record.validate(workspaceID: value.sourceWorkspaceID)
        }
        try value.roundHistory.validate()
        try value.requiredHistory.validate()
        guard value.historicalRound.revision <= value.packageCurrentRound.revision,
              value.requiredHistory.recordCount == lifecycleCount + value.roundHistory.recordCount,
              referenceSHA256 == (try FieldDraftCanonicalCodecV1.sha256(value)),
              try FieldDraftCanonicalCodecV1.encode(self).count <= FieldDraftLimitsV1.maximumPayloadBytes else {
            throw FieldDraftFailureV1.digestMismatch
        }
    }

    /// Equality with a fresh derivation proves the commitment belongs to this
    /// sealed package review. It does not authenticate a later destination row.
    func validate(against reviewed: ReviewedRepetitiveCaptureSourceGraphsV2) throws {
        try validate()
        let references = try RepetitiveCaptureSourceGraphReviewV2.references(from: reviewed)
        guard references.first(where: { $0.value.sourceDraftID == value.sourceDraftID }) == self else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
    }
}

extension RepetitiveCaptureSourceGraphReviewV2 {
    /// The aggregate's initializer is sealed to this file. No caller-supplied
    /// graph/history arrays can enter this source-reference construction boundary.
    static func references(from reviewed: ReviewedRepetitiveCaptureSourceGraphsV2) throws
        -> [RepetitiveCaptureSourceGraphReferenceV2] {
        typealias Reference = RepetitiveCaptureSourceGraphReferenceV2
        var roundsBySession: [UUID: [RepetitiveCaptureSourceHistoryRecordV2]] = [:]
        for record in reviewed.requiredHistory {
            if case let .applyRoundSession(mutation) = record.envelope.command {
                roundsBySession[mutation.session.sessionID, default: []].append(record)
            }
        }
        // Shared-session history is hashed once, even when several historical
        // graphs use it. Each graph's union commits to the same complete chunk.
        var roundEvidence: [UUID: SourceReferenceRoundEvidence] = [:]
        for (sessionID, records) in roundsBySession {
            let commitment = try sourceHistoryCommitment(records, role: "round")
            roundEvidence[sessionID] = .init(commitment: commitment,
                records: Dictionary(uniqueKeysWithValues: records.map { ($0.envelope.mutationID, $0) }))
        }
        return try reviewed.graphs.map { graph in
            let sessionID = graph.packageCurrentRound.sessionID
            guard let rounds = roundEvidence[sessionID] else { throw invalid() }
            let frontiers = try graph.checkpoints.enumerated().map { position, checkpoint in
                guard let first = checkpoint.lifecycle.first, let last = checkpoint.lifecycle.last else {
                    throw invalid()
                }
                return Reference.CheckpointFrontier(position: position,
                    draftID: checkpoint.original.draftID,
                    original: .init(checkpoint.original, record: first),
                    current: .init(checkpoint.current, record: last),
                    lifecycle: try sourceHistoryCommitment(checkpoint.lifecycle, role: "checkpoint"))
            }
            let unionChunks = frontiers.map {
                SourceReferenceHistoryChunk(role: "checkpoint", position: $0.position,
                    objectID: $0.draftID, commitment: $0.lifecycle)
            } + [.init(role: "round", position: frontiers.count,
                       objectID: sessionID, commitment: rounds.commitment)]
            let unionCount = unionChunks.reduce(0) { $0 + $1.commitment.recordCount }
            // Checkpoint lifecycle records and Round records have disjoint
            // command kinds; unique draft membership makes these chunks disjoint.
            let union = Reference.HistoryCommitment(recordCount: unionCount,
                recordsSHA256: try sourceCommitmentDigest(
                    role: "union", count: unionCount, frames: unionChunks))
            return try Reference(value: .init(format: Reference.format,
                sourceWorkspaceID: reviewed.sourceWorkspaceID,
                sourcePersistentSchemaVersion: reviewed.sourcePersistentSchemaVersion,
                sourceRecordsSchemaVersion: reviewed.sourceRecordsSchemaVersion,
                manifestJSONSHA256: reviewed.manifestJSONSHA256,
                recordsJSONSHA256: reviewed.recordsJSONSHA256,
                sourceDraftID: graph.chain.sourceCheckpoint.draftID, checkpoints: frontiers,
                roundSessionID: sessionID,
                historicalRound: try sourceReferenceRoundTip(graph.chain.currentRound, evidence: rounds),
                packageCurrentRound: try sourceReferenceRoundTip(graph.packageCurrentRound, evidence: rounds),
                roundHistory: rounds.commitment, requiredHistory: union,
                isUnchangedActiveSource: graph.isUnchangedActiveSource))
        }
    }

    private struct SourceReferenceRoundEvidence {
        let commitment: RepetitiveCaptureSourceGraphReferenceV2.HistoryCommitment
        let records: [MutationIDV1: RepetitiveCaptureSourceHistoryRecordV2]
    }

    private struct SourceReferenceHistoryChunk: Encodable {
        let role: String
        let position: Int
        let objectID: UUID
        let commitment: RepetitiveCaptureSourceGraphReferenceV2.HistoryCommitment
    }

    private static func sourceReferenceRoundTip(_ round: RoundSessionV1,
                                                evidence: SourceReferenceRoundEvidence) throws
        -> RepetitiveCaptureSourceGraphReferenceV2.RoundTip {
        guard let record = evidence.records[round.mutationID],
              case let .applyRoundSession(mutation) = record.envelope.command,
              mutation.session == round else { throw invalid() }
        return .init(revision: round.revision,
                     canonicalSHA256: try RoundSessionCanonicalCodecV1.sha256(round),
                     record: .init(record))
    }

    private static func sourceHistoryCommitment(_ records: [RepetitiveCaptureSourceHistoryRecordV2],
                                                role: String) throws
        -> RepetitiveCaptureSourceGraphReferenceV2.HistoryCommitment {
        guard !records.isEmpty,
              records.count <= MutationJournalStoreV1.maximumReceiptValidationCount else { throw invalid() }
        // One small record anchor is encoded at a time; raw history and its
        // potentially large postimages are never copied into the reference.
        let digest = try sourceCommitmentDigest(role: role, count: records.count,
            frames: records.lazy.map { RepetitiveCaptureSourceGraphReferenceV2.RecordAnchor($0) })
        return .init(recordCount: records.count, recordsSHA256: digest)
    }

    /// Frozen encoding: F(domain UTF8), U64BE(record count), then F(canonical
    /// frame) for each frame. F(bytes) is U64BE(byte count) followed by bytes.
    /// Lifecycle/Round frames use authenticated history order. Union frames use
    /// checkpoint chain order followed by the full Round-history commitment.
    private static func sourceCommitmentDigest<Frames: Sequence>(role: String, count: Int,
                                                                 frames: Frames) throws -> String
        where Frames.Element: Encodable {
        guard count > 0, count <= MutationJournalStoreV1.maximumReceiptValidationCount else {
            throw invalid()
        }
        var hasher = SHA256()
        sourceCommitmentFrame(Data("assetrounds.c36.source-history.\(role).v1".utf8), into: &hasher)
        sourceCommitmentInteger(UInt64(count), into: &hasher)
        for frame in frames {
            sourceCommitmentFrame(try FieldDraftCanonicalCodecV1.encode(frame), into: &hasher)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sourceCommitmentFrame(_ bytes: Data, into hasher: inout SHA256) {
        sourceCommitmentInteger(UInt64(bytes.count), into: &hasher)
        hasher.update(data: bytes)
    }

    private static func sourceCommitmentInteger(_ value: UInt64, into hasher: inout SHA256) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { hasher.update(data: Data($0)) }
    }
}

import Foundation

/// Authenticated, immutable original history used by C57 reference-owner replacement.
/// This boundary selects evidence only; it never rewrites, merges, or persists history.
enum ReferenceOwnerReplacementSourceV1 {
    enum Family: String, CaseIterable, Sendable {
        case workPacket
        case guidedSurvey
        case roundSession
        case schedule
        case fieldDraft
    }

    struct Source: Equatable, Sendable {
        let workspaceID: WorkspaceID
        let history: MutationHistorySnapshotV1
        let entries: [Entry]

        fileprivate init(
            workspaceID: WorkspaceID,
            history: MutationHistorySnapshotV1,
            entries: [Entry]
        ) {
            self.workspaceID = workspaceID
            self.history = history
            self.entries = entries
        }
    }

    struct Entry: Equatable, Sendable {
        let family: Family
        let record: MutationHistoryReceiptRecordV1
        let envelope: MutationEnvelopeV1
        let receipt: MutationReceiptV1

        fileprivate init(
            family: Family,
            record: MutationHistoryReceiptRecordV1,
            envelope: MutationEnvelopeV1,
            receipt: MutationReceiptV1
        ) {
            self.family = family
            self.record = record
            self.envelope = envelope
            self.receipt = receipt
        }
    }

    static func source(
        workspaceID: WorkspaceID,
        history: MutationHistorySnapshotV1
    ) throws -> Source {
        try MutationJournalStoreV1.validateImportedSnapshot(history)

        var entries: [Entry] = []
        var qualifiedMutationIDs = Set<UUID>()
        for record in history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            guard receipt.envelopeSHA256 == (try envelope.canonicalSHA256()),
                  receipt.identity.workspaceID == envelope.workspaceID,
                  receipt.mutationID == envelope.mutationID,
                  receipt.commandBodySHA256 == envelope.commandBodySHA256,
                  receipt.expectedRevision == envelope.expectedRevision else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            guard envelope.workspaceID == workspaceID,
                  let family = try authenticateRelevant(envelope: envelope, receipt: receipt) else {
                continue
            }
            guard qualifiedMutationIDs.insert(envelope.mutationID.rawValue).inserted else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            entries.append(Entry(
                family: family,
                record: record,
                envelope: envelope,
                receipt: receipt
            ))
        }

        let relevantIDs = qualifiedMutationIDs
        guard !history.quarantines.contains(where: {
            $0.workspaceID == workspaceID && relevantIDs.contains($0.mutationID)
        }) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }

        entries.sort {
            if $0.receipt.resultingRevision.workspaceRevision
                != $1.receipt.resultingRevision.workspaceRevision {
                return $0.receipt.resultingRevision.workspaceRevision
                    < $1.receipt.resultingRevision.workspaceRevision
            }
            return $0.receipt.identity.stableKey < $1.receipt.identity.stableKey
        }
        return Source(workspaceID: workspaceID, history: history, entries: entries)
    }
}

private extension ReferenceOwnerReplacementSourceV1 {
    static func authenticateRelevant(
        envelope: MutationEnvelopeV1,
        receipt: MutationReceiptV1
    ) throws -> Family? {
        switch envelope.command {
        case let .applyWorkPacket(mutation):
            guard mutation.workspaceID == envelope.workspaceID,
                  mutation.mutationID == envelope.mutationID else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            _ = try WorkPacketMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            return .workPacket
        case let .applySurveySession(mutation):
            guard mutation.workspaceID == envelope.workspaceID,
                  mutation.mutationID == envelope.mutationID else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            _ = try SurveySessionMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            return .guidedSurvey
        case let .applyRoundSession(mutation):
            guard mutation.workspaceID == envelope.workspaceID,
                  mutation.mutationID == envelope.mutationID else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            _ = try RoundSessionMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            return .roundSession
        case let .applySchedule(mutation):
            guard mutation.workspaceID == envelope.workspaceID,
                  mutation.mutationID == envelope.mutationID else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            _ = try ScheduleMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            return .schedule
        case let .applyFieldDraft(mutation):
            guard mutation.workspaceID == envelope.workspaceID,
                  mutation.mutationID == envelope.mutationID else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            _ = try FieldDraftMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            return .fieldDraft
        default:
            return nil
        }
    }
}

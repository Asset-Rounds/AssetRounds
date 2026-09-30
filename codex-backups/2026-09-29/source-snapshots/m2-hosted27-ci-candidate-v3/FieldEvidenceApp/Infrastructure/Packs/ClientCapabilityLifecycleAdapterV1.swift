import Foundation

enum ClientCapabilityLifecycleInterruptionV1: Error, Equatable, Sendable {
    case afterCanonicalCommitBeforeLocalReceipt
}

enum ClientCapabilityLifecycleDispositionV1: String, Codable, Sendable {
    case retainCanonicalHistory = "RETAIN_CANONICAL_HISTORY"
    case quarantineDivergentRetry = "QUARANTINE_DIVERGENT_RETRY"
}

/// Production bridge to the sole workspace writer. Recovery adopts an
/// existing receipt only after the typed C21 receipt validates the complete
/// mutation command, concurrency identity, revision and post-image digest.
@MainActor
final class WorkspaceClientCapabilityWriterV1: ClientCapabilityWritingV1 {
    typealias InterruptionHook = (ClientCapabilityLifecycleInterruptionV1) throws -> Void

    private let workspaceWriter: WorkspaceWriterV1
    private let journalStore: MutationJournalStoreV1
    private let interruptionHook: InterruptionHook?

    init(
        workspaceWriter: WorkspaceWriterV1,
        journalStore: MutationJournalStoreV1,
        interruptionHook: InterruptionHook? = nil
    ) {
        self.workspaceWriter = workspaceWriter
        self.journalStore = journalStore
        self.interruptionHook = interruptionHook
    }

    func acceptedWriteReceipt(for mutation: ClientCapabilityMutationV1) throws -> ClientCapabilityWriteReceiptV1? {
        guard let canonicalReceipt = try journalStore.receipt(mutationID: mutation.mutationID) else { return nil }
        return try validatedReceipt(for: mutation, canonicalReceipt: canonicalReceipt)
    }

    func applyClientCapability(_ mutation: ClientCapabilityMutationV1) throws -> ClientCapabilityWriteReceiptV1 {
        if let existing = try acceptedWriteReceipt(for: mutation) { return existing }
        let canonicalReceipt = try workspaceWriter.commitClientCapability(mutation)
        try interruptionHook?(.afterCanonicalCommitBeforeLocalReceipt)
        return try validatedReceipt(for: mutation, canonicalReceipt: canonicalReceipt)
    }

    private func validatedReceipt(
        for mutation: ClientCapabilityMutationV1,
        canonicalReceipt: MutationReceiptV1
    ) throws -> ClientCapabilityWriteReceiptV1 {
        _ = try ClientCapabilityMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: canonicalReceipt
        )
        return try ClientCapabilityWriteReceiptV1(
            mutationID: mutation.mutationID,
            postImageSHA256: postImageSHA256(of: mutation),
            canonicalMutationReceiptSHA256: canonicalReceipt.canonicalSHA256()
        )
    }

    private func postImageSHA256(of mutation: ClientCapabilityMutationV1) -> String {
        switch mutation {
        case let .profile(value): value.profileSHA256
        case let .policy(value, _): value.policySHA256
        case let .disposition(value, _): value.dispositionSHA256
        case let .admission(value, _, _, _, _): value.decisionSHA256
        }
    }
}

@MainActor
struct ClientCapabilityLifecycleAdapterV1 {
    private let coordinator: ClientCapabilityCoordinatorV1

    init(writer: any ClientCapabilityWritingV1) {
        coordinator = ClientCapabilityCoordinatorV1(writer: writer)
    }

    func coordinatorForLocalAdmission() -> ClientCapabilityCoordinatorV1 { coordinator }

    func disposition(existingReceiptMatchesMutation: Bool) -> ClientCapabilityLifecycleDispositionV1 {
        existingReceiptMatchesMutation ? .retainCanonicalHistory : .quarantineDivergentRetry
    }
}

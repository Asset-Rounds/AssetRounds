import Foundation

/// Bridges the survey coordinator to the sole workspace writer. Lifecycle
/// events remain inside the canonical mutation envelope and are never rows.
@MainActor
final class SurveyDefinitionLifecycleAdapterV1: SurveyDefinitionWritingV1 {
    private let writer: WorkspaceWriterV1
    private let journalStore: MutationJournalStoreV1

    init(writer: WorkspaceWriterV1, journalStore: MutationJournalStoreV1) {
        self.writer = writer
        self.journalStore = journalStore
    }

    func acceptedSurveyDefinitionMutation(_ mutationID: MutationIDV1) async throws -> SurveyDefinitionMutationReceiptV1? {
        guard let receipt = try journalStore.receipt(mutationID: mutationID),
              let mutation = try journalStore.surveyDefinitionMutation(mutationID: mutationID) else {
            return nil
        }
        return try SurveyDefinitionMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
    }

    func applySurveyDefinition(_ mutation: SurveyDefinitionMutationV1) async throws -> SurveyDefinitionMutationReceiptV1 {
        if let accepted = try await acceptedSurveyDefinitionMutation(mutation.mutationID) {
            try accepted.validate(mutation: mutation)
            return accepted
        }
        let receipt = try writer.commitSurveyDefinition(mutation)
        return try SurveyDefinitionMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
    }
}

import Foundation

enum SurveySessionScheduleLifecycleBoundaryV1 { static let occurrenceHistoryMayRewritePublication = false }

/// C26 lifecycle bridge. The journal is the idempotency authority and the
/// existing workspace writer remains the sole mutation transaction boundary.
@MainActor final class SurveySessionLifecycleAdapterV1: SurveySessionWritingV1 {
    private let writer: WorkspaceWriterV1
    private let journalStore: MutationJournalStoreV1

    init(writer: WorkspaceWriterV1, journalStore: MutationJournalStoreV1) {
        self.writer = writer
        self.journalStore = journalStore
    }

    func acceptedSurveySessionMutation(
        _ mutation: SurveySessionMutationV1
    ) throws -> SurveySessionMutationReceiptV1? {
        try journalStore.validateSurveySessionReferences(mutation)
        return try journalStore.acceptedSurveySessionMutation(mutation)
    }

    func applySurveySession(
        _ mutation: SurveySessionMutationV1
    ) throws -> SurveySessionMutationReceiptV1 {
        try mutation.validate()
        try journalStore.validateSurveySessionReferences(mutation)
        if let accepted = try acceptedSurveySessionMutation(mutation) {
            return accepted
        }
        let receipt = try writer.commitSurveySession(mutation)
        return try SurveySessionMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: receipt
        )
    }
}

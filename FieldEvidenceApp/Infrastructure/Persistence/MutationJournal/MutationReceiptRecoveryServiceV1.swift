import Foundation

@MainActor
final class MutationReceiptRecoveryServiceV1 {
    private let store: MutationJournalStoreV1

    init(store: MutationJournalStoreV1) {
        self.store = store
    }

    func recoverBeforeWriterActivation() throws {
        try store.validateAll()
    }
}

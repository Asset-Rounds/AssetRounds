import Foundation

@MainActor
final class MutationReceiptRecoveryServiceV1 {
    private let store: MutationJournalStoreV1

    init(store: MutationJournalStoreV1) {
        self.store = store
    }

    /// The store's StaleWriterFenceV1 revalidates its GenerationLeaseTokenV1
    /// under the shared generation mutation lock before recovery can inspect
    /// canonical journal state for writer activation.
    func recoverBeforeWriterActivation() throws {
        try store.withAuthorizedRecovery {
            try store.validateAll()
        }
    }
}

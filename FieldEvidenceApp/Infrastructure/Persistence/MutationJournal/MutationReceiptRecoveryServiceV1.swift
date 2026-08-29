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

    /// Field-draft saga recovery shares the canonical journal repair boundary;
    /// it must not become a second receipt or mutation authority.
    func recoverFieldDraftEffectsBeforeWriterActivation() throws {
        try recoverBeforeWriterActivation()
    }

    /// Immutable recoverability receipts use the same effect-before-receipt
    /// repair boundary as every other canonical workspace mutation. Derived
    /// verification staging is deliberately outside this durable recovery.
    func recoverRecoverabilityVerificationReceiptsBeforeWriterActivation() throws {
        try recoverBeforeWriterActivation()
    }

    /// C23 release imports and subject bindings recover from the same canonical
    /// effect-before-receipt boundary. Offline readiness remains derived and is
    /// never reconstructed as durable state here.
    func recoverFieldReferenceEffectsBeforeWriterActivation() throws {
        try recoverBeforeWriterActivation()
    }
    func recoverAccessibleDocumentAssessmentEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    func recoverSurveyDefinitionEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    /// C26's five post-image families and their generic receipt are repaired
    /// together; no projection or provisional staging is promoted to truth.
    func recoverSurveySessionEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    /// C27 locator and binding-receipt effects are recovered exclusively from
    /// the canonical mutation journal; derived resolution previews are rebuilt.
    func recoverAssetLocatorEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    func recoverScheduleEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
}

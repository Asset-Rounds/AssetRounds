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
        guard C50IncumbentFileExchangeRecoveryBoundaryV1.validate() else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
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
    /// Calendar releases and override events are recovered with the original
    /// `.applySchedule` effect/receipt pair. A recovered stream is revalidated
    /// against its persisted frontier; preview and due/reminder state remain
    /// disposable projections.
    func recoverScheduleEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    /// C29 repairs the four plan histories and their generic receipt together;
    /// spatial frames stay embedded and rebase previews are rebuilt.
    func recoverPlanEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    func recoverPlacementPoseEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    func recoverEvidenceContextEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    /// C31 recovery revalidates persisted topology and claim admission
    /// authorities through MutationJournalStoreV1 before activating a writer.
    func recoverLightingEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    /// C33 repairs clip/anchor effects and their canonical receipt together.
    /// Original/derivative content cleanup is retried only from the accepted
    /// retention receipt; recovery never invents a second content authority.
    func recoverTemporalEvidenceEffectsBeforeWriterActivation()throws{try recoverBeforeWriterActivation()}
    /// C46 repairs contact and durable handoff-intent effects with their
    /// canonical receipt before a writer becomes available. Platform results
    /// are never promoted into recovery state.
    func recoverOperationalContactEffectsBeforeWriterActivation()throws{
        try recoverBeforeWriterActivation()
    }
    /// C48 repairs only the existing C14 rows and canonical mutation receipt.
    /// Exact portable bytes are finalized by PortableExchangeSessionStoreV2
    /// after this proof succeeds; session-only history never enters this path.
    func recoverPortableReviewEffectsBeforeWriterActivation()throws{
        try recoverBeforeWriterActivation()
    }
    /// C49 revalidates the one canonical entry postimage (including embedded
    /// direct cost) through the existing journal recovery authority.
    func recoverWorkResourceEffectsBeforeWriterActivation()throws{
        try recoverBeforeWriterActivation()
    }
}

enum LightingMutationReceiptRecoveryPolicyV1 { static func validateRecovered(operation:LightingWriteOperationV1,receipt:MutationReceiptV1)throws{_ = try LightingMutationReceiptV1(operation:operation,mutationReceipt:receipt)} }
enum TemporalEvidenceMutationReceiptRecoveryPolicyV1 {
    static func validateRecovered(
        mutation: TemporalEvidenceMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        try C33TemporalEvidenceJournalBoundaryV1.validate(
            mutation: mutation,
            receipt: receipt
        )
    }
}

enum OperationalContactMutationReceiptRecoveryPolicyV1 {
    static func validateRecovered(
        mutation: OperationalContactMutationV1,
        receipt: MutationReceiptV1
    ) throws {
        _ = try OperationalContactMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: receipt
        )
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Persistence_MutationJournal_MutationReceiptRecoveryServiceV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C45AcceptedLabelRecoveryBoundaryV1 { static let commandKind:WorkspaceCommandKindV1 = .applyAssetLabel;static let effectBeforeReceiptRecoveryIsIdempotent=true }

enum C46OperationalContactBoundary_20{static let persistentFamilies=OperationalContactPersistenceEnrollmentV1.persistentFamilies;static let platformOutcomesPersistent=false}
enum C47ActivityContractRecoveryBoundaryV2 { static let commandKind:WorkspaceCommandKindV1 = .applyActivityContract;static let effectBeforeReceiptRecoveryIsIdempotent=true;static let completedSnapshotBytesAreNeverReencoded=true }
enum C48PortableReviewRecoveryBoundaryV1 { static let commandKind:WorkspaceCommandKindV1 = .applyPortableReview;static let canonicalEffectUsesExistingC14Rows=true;static let sessionEvidenceFinalizesOnlyAfterExactReceipt=true;static let historyOnlyNeverEntersWorkspaceJournal=true }
enum C49WorkResourceRecoveryBoundaryV1 { static let commandKind:WorkspaceCommandKindV1 = .applyWorkResource;static let effectBeforeReceiptRecoveryUsesCanonicalPostimage=true;static let divergentSameMutationIsQuarantined=true;static let noSecondCostLedger=true }
enum C51ScheduleOverrideRecoveryBoundaryV1 { static let commandKind:WorkspaceCommandKindV1 = .applySchedule;static let effectBeforeReceiptRecoveryUsesCanonicalPostimages=true;static let divergentSameMutationIsQuarantined=true;static let overrideFrontierIsRevalidatedFromPersistedRows=true;static let createsParallelWriter=false }

enum C50IncumbentFileExchangeRecoveryBoundaryV1 {
    static let profileSelectionSessionSourceQuarantineDisposition = "NONPERSISTENT"
    static let recoveryDisposition = "NOT_APPLICABLE"
    static let adapterStateIsNotRecovered = true
    static let sourceScratchAndQuarantineAreNotRecovered = true
    static let canonicalImportedEffectsUseExistingRecovery = true
    static let noAdapterMutationOrReceipt = true

    static func validate() -> Bool {
        profileSelectionSessionSourceQuarantineDisposition == "NONPERSISTENT"
            && recoveryDisposition == "NOT_APPLICABLE"
            && adapterStateIsNotRecovered
            && sourceScratchAndQuarantineAreNotRecovered
            && canonicalImportedEffectsUseExistingRecovery
            && noAdapterMutationOrReceipt
            && C50IncumbentFileExchangePersistenceBoundaryV1.validate()
    }
}

import Foundation

/// Provider-free orchestration for the canonical reference consumer. Its
/// output is disposable derived state, never a delivery queue or mutation.
struct IntegrationConformanceConsumerV1: Sendable {
    enum InterruptionPointV1: Equatable, Sendable {
        case none
        case afterEffectBeforeCheckpoint
    }

    private let projection: IntegrationEventProjectionV1
    private let consumer: IntegrationEventConformanceConsumerV1
    private let registry: IntegrationContractRegistryV1
    private let limits: IntegrationEventLimitsV1
    private let store: any IntegrationProjectionOperationalStoreV1
    private let interruptionPoint: @Sendable () -> InterruptionPointV1

    init(
        registry: IntegrationContractRegistryV1,
        limits: IntegrationEventLimitsV1 = try! IntegrationEventLimitsV1(),
        consumerID: String = "assetrounds.local.conformance",
        consumerVersion: Int = 1,
        store: any IntegrationProjectionOperationalStoreV1,
        interruptionPoint: @escaping @Sendable () -> InterruptionPointV1 = { .none }
    ) throws {
        try registry.validate(limits: limits)
        self.registry = registry
        self.limits = limits
        projection = try IntegrationEventProjectionV1(registry: registry, limits: limits)
        consumer = try IntegrationEventConformanceConsumerV1(
            consumerID: consumerID, consumerVersion: consumerVersion
        )
        self.store = store
        self.interruptionPoint = interruptionPoint
    }

    /// Replays from the last verified checkpoint. The disposable local effect
    /// ledger is updated idempotently before checkpoint publication, so a
    /// process stop at that boundary retries the same event IDs without a
    /// duplicate logical effect.
    func advance(
        workspaceID: WorkspaceID,
        acceptedReceipts: [MutationReceiptV1]
    ) async throws -> IntegrationEventConsumerResultV1 {
        guard acceptedReceipts.count <= ChangeJournalLimitsV1.productionMaximumEntitiesPerCheckpoint else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        try projection.validatePackagePromotionReplay(acceptedReceipts)
        try projection.validateMeasurementIntegrityReplay(acceptedReceipts)
        try projection.validatePrivacyTransformReplay(acceptedReceipts)
        try projection.validateClientCapabilityReplay(acceptedReceipts)
        try projection.validateFieldReferenceReplay(acceptedReceipts)
        try projection.validateAccessibleDocumentAssessmentReplay(acceptedReceipts)
        try projection.validateSurveyDefinitionReplay(acceptedReceipts)
        try projection.validateSurveySessionReplay(acceptedReceipts)
        try projection.validateAssetLocatorReplay(acceptedReceipts)
        try projection.validateScheduleReplay(acceptedReceipts)
        try projection.validatePlanReplay(acceptedReceipts)
        try projection.validatePlacementPoseReplay(acceptedReceipts)
        try projection.validateEvidenceContextReplay(acceptedReceipts)
        try projection.validateLightingReplay(acceptedReceipts)
        try projection.validateTemporalEvidenceReplay(acceptedReceipts)
        let prior = try await store.checkpoint(
            consumerID: consumer.consumerID, workspaceID: workspaceID
        )
        let events = try projection.events(
            after: prior, workspaceID: workspaceID,
            acceptedReceipts: acceptedReceipts
        )
        guard events.count <= limits.maximumEventsPerReplay else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        let result = try consumer.consume(
            workspaceID: workspaceID, registry: registry,
            events: events, priorCheckpoint: prior
        )
        try await store.recordDerivedConsumerEffects(
            events: events,
            consumerID: consumer.consumerID,
            workspaceID: workspaceID
        )
        if interruptionPoint() == .afterEffectBeforeCheckpoint {
            throw IntegrationEventFailureV1.staleCheckpoint
        }
        try await store.replaceDerivedProjection(
            events: events, checkpoint: result.checkpoint,
            consumerID: consumer.consumerID, workspaceID: workspaceID
        )
        let readBack = try await store.checkpoint(
            consumerID: consumer.consumerID, workspaceID: workspaceID
        )
        guard readBack == result.checkpoint else {
            throw IntegrationEventFailureV1.invalidDigest
        }
        return result
    }

    /// A bounded, disposable rebuild. A crash after the drop is safe because
    /// the next attempt starts from the immutable receipt history again.
    func rebuild(
        workspaceID: WorkspaceID,
        acceptedReceipts: [MutationReceiptV1]
    ) async throws -> IntegrationEventConsumerResultV1 {
        guard acceptedReceipts.count <= ChangeJournalLimitsV1.productionMaximumEntitiesPerCheckpoint else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        try projection.validatePackagePromotionReplay(acceptedReceipts)
        try projection.validateMeasurementIntegrityReplay(acceptedReceipts)
        try projection.validatePrivacyTransformReplay(acceptedReceipts)
        try projection.validateClientCapabilityReplay(acceptedReceipts)
        try projection.validateFieldReferenceReplay(acceptedReceipts)
        try projection.validateAccessibleDocumentAssessmentReplay(acceptedReceipts)
        try projection.validateSurveyDefinitionReplay(acceptedReceipts)
        try projection.validateSurveySessionReplay(acceptedReceipts)
        try projection.validateAssetLocatorReplay(acceptedReceipts)
        try projection.validateScheduleReplay(acceptedReceipts)
        try projection.validatePlanReplay(acceptedReceipts)
        try projection.validatePlacementPoseReplay(acceptedReceipts)
        try projection.validateEvidenceContextReplay(acceptedReceipts)
        try projection.validateLightingReplay(acceptedReceipts)
        try projection.validateTemporalEvidenceReplay(acceptedReceipts)
        try await store.dropDerivedProjection(
            consumerID: consumer.consumerID, workspaceID: workspaceID
        )
        return try await advance(
            workspaceID: workspaceID, acceptedReceipts: acceptedReceipts
        )
    }

    func drop(workspaceID: WorkspaceID) async throws {
        try await store.dropDerivedProjection(
            consumerID: consumer.consumerID, workspaceID: workspaceID
        )
    }
}

enum LightingIntegrationConformancePolicyV1 { static let durableKinds:Set<WorkspaceEntityKindV1>=[.lightingSystem,.lightingObservation,.lightingIssue,.lightingMeasurementPlan,.lightingClaimState];static func accepts(_ event:IntegrationEventV1)->Bool{durableKinds.contains(event.subject.kind)} }

enum C31LightingConformanceBoundaryV1 {
    static let canonicalLightingKindsRemainClosed = true
    static let reportAndSearchConsumersAreDerivedOnly = true
    static let noPartialLightingActivation = true
    static func accepts(_ event: IntegrationEventV1) -> Bool {
        LightingIntegrationConformancePolicyV1.accepts(event)
    }
}


enum C33TemporalEvidenceConformanceBoundaryV1 {
    static let durableKinds = C33TemporalEvidenceIntegrationEventBoundaryV1.projectedKinds
    static let derivedConsumerNeverReceivesOriginalBytes = true

    static func accepts(_ event: IntegrationEventV1) -> Bool {
        durableKinds.contains(event.subject.kind)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Replication_IntegrationConformanceConsumerV1 {
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

enum C45AcceptedLabelIntegrationConsumerBoundaryV1 { static let cannotActivateHistoricCloneSnapshot=true;static let cannotInferHandoffPossession=true }

enum C46OperationalContactBoundary_51{static let commandKind:WorkspaceCommandKindV1 = .applyOperationalContact;static let platformOutcomesProjected=false}
enum C47ActivityContractIntegrationConsumerBoundaryV2 { static let commandKind:WorkspaceCommandKindV1 = .applyActivityContract;static let historicRestoreCannotInferNewCompletionClaims=true;static let receiptIsolation=true }

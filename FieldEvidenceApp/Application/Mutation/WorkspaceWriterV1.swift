import Foundation

@MainActor
protocol WorkspaceWriterAdapterPortV1: AnyObject {
    var requiresInitialPlacementForFirstSign: Bool { get }
    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1
    func queryExisting(
        identities: [WorkspaceEntityIdentityV1]
    ) throws -> (
        identities: [WorkspaceEntityIdentityV1],
        packageBindings: [WorkspacePackageBindingV1]
    )
    func persistedActivityContractEffectMatches(
        _ mutation: ActivityContractMutationV2
    ) throws -> Bool
    func persistedServiceRequestEffectMatches(
        _ mutation: ServiceRequestMutationV1
    ) throws -> Bool
    func persistedServiceReliabilityEffectMatches(
        _ bundle: ServiceReliabilityAtomicBundleV1
    ) throws -> Bool
    func persistedEvidenceMetadataEffectMatches(
        _ mutation: EvidenceMetadataMutationV1
    ) throws -> Bool
    func evidenceAssociationHistory(
        workspaceID: WorkspaceID,
        evidenceID: String
    ) throws -> [EvidenceAssociationV1]
    func evidenceSequenceHistory(
        workspaceID: WorkspaceID,
        sequenceID: UUID
    ) throws -> [EvidenceSequenceV1]
    func persistedMyDayEffectMatches(_ mutation: MyDayMutationV1) throws -> Bool
    func persistedRoundSessionEffectMatches(_ mutation: RoundSessionMutationV1) throws -> Bool
    func roundSessionHistory(workspaceID: WorkspaceID, sessionID: UUID) throws -> [RoundSessionV1]
    func currentMyDayPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1?
    func validateReinspectionExceptionCommand(
        _ command: ReinspectionExceptionMutationCommandV1,
        currentRevision: WorkspaceRevisionV1
    ) throws
    func reinspectionExceptionQuery(
        _ request: ReinspectionExceptionQueryV1,
        providers: [any ExceptionQueueCanonicalSourceProvidingV1]
    ) throws -> ReinspectionExceptionQueryResultV1
    func validateEntityIdentityResolutionCommand(
        _ command: EntityIdentityResolutionMutationCommandV1,
        currentRevision: WorkspaceRevisionV1
    ) throws
    func entityIdentityResolutionReceipt(
        for command: EntityIdentityResolutionMutationCommandV1
    ) throws -> EntityIdentityResolutionMutationReceiptV1?
    func entityIdentityResolutionQuery(
        _ request: EntityIdentityResolutionQueryV1
    ) throws -> EntityIdentityResolutionQueryResultV1
    func persistedWorkspaceExperienceEffectMatches(
        _ command: WorkspaceExperienceMutationCommandV1
    ) throws -> Bool
    func persistedLightingDayInventoryEffectMatches(
        _ operation: LightingDayInventoryWriteOperationV1
    ) throws -> Bool
    func persistedLightingNightWorkflowEffectMatches(
        _ operation: LightingNightWorkflowWriteOperationV1
    ) throws -> Bool
    func persistAppliedActivityContractEffect(
        _ mutation: ActivityContractMutationV2
    ) throws
    func rollback()
}

enum C50IncumbentSoleWriterDelegationBoundaryV1 {
    static let adapterOwnsWorkspaceWriter = false
    static let previewWritesWorkspace = false
    static let commitMustUseExistingWorkspaceWriter = true
    static let effectBeforeReceiptRecoveryQueriesExistingMutationID = true
}

extension WorkspaceWriterAdapterPortV1 {
    var requiresInitialPlacementForFirstSign: Bool { false }
}

extension WorkspaceWriterAdapterPortV1 {
    func queryExisting(
        identities: [WorkspaceEntityIdentityV1]
    ) throws -> (
        identities: [WorkspaceEntityIdentityV1],
        packageBindings: [WorkspacePackageBindingV1]
    ) {
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }

    func persistedServiceRequestEffectMatches(
        _ mutation: ServiceRequestMutationV1
    ) throws -> Bool {
        false
    }
    func persistedServiceReliabilityEffectMatches(_ bundle:ServiceReliabilityAtomicBundleV1)throws->Bool{false}
    func persistedEvidenceMetadataEffectMatches(
        _ mutation: EvidenceMetadataMutationV1
    ) throws -> Bool { false }
    func evidenceAssociationHistory(
        workspaceID: WorkspaceID,
        evidenceID: String
    ) throws -> [EvidenceAssociationV1] {
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }
    func evidenceSequenceHistory(
        workspaceID: WorkspaceID,
        sequenceID: UUID
    ) throws -> [EvidenceSequenceV1] {
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }
    func persistedMyDayEffectMatches(_ mutation: MyDayMutationV1) throws -> Bool { false }
    func persistedRoundSessionEffectMatches(_ mutation: RoundSessionMutationV1) throws -> Bool { false }
    func roundSessionHistory(workspaceID: WorkspaceID, sessionID: UUID) throws -> [RoundSessionV1] { throw WorkspaceMutationFailureV1.unsupportedCommand }
    func currentMyDayPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1? {
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }
    func validateReinspectionExceptionCommand(
        _ command: ReinspectionExceptionMutationCommandV1,
        currentRevision: WorkspaceRevisionV1
    ) throws { throw WorkspaceMutationFailureV1.unsupportedCommand }
    func reinspectionExceptionQuery(_ request: ReinspectionExceptionQueryV1, providers: [any ExceptionQueueCanonicalSourceProvidingV1]) throws -> ReinspectionExceptionQueryResultV1 { throw WorkspaceMutationFailureV1.unsupportedCommand }
    func validateEntityIdentityResolutionCommand(_ command: EntityIdentityResolutionMutationCommandV1, currentRevision: WorkspaceRevisionV1) throws { throw WorkspaceMutationFailureV1.unsupportedCommand }
    func entityIdentityResolutionReceipt(for command: EntityIdentityResolutionMutationCommandV1) throws -> EntityIdentityResolutionMutationReceiptV1? { nil }
    func entityIdentityResolutionQuery(_ request: EntityIdentityResolutionQueryV1) throws -> EntityIdentityResolutionQueryResultV1 { throw WorkspaceMutationFailureV1.unsupportedCommand }
    func persistedWorkspaceExperienceEffectMatches(_ command: WorkspaceExperienceMutationCommandV1) throws -> Bool { false }
    func persistedLightingDayInventoryEffectMatches(_ operation: LightingDayInventoryWriteOperationV1) throws -> Bool { false }
    func persistedLightingNightWorkflowEffectMatches(_ operation: LightingNightWorkflowWriteOperationV1) throws -> Bool { false }

    func persistedActivityContractEffectMatches(
        _ mutation: ActivityContractMutationV2
    ) throws -> Bool {
        false
    }

    func persistAppliedActivityContractEffect(
        _ mutation: ActivityContractMutationV2
    ) throws {
        throw WorkspaceMutationFailureV1.persistenceFailed
    }

    func rollback() {}
}

@MainActor
final class WorkspaceWriterV1: WorkspaceQueryClientV1, MeasurementIntegrityWorkspaceWriterV1 {
    static let defaultMaximumRememberedMutationCount = 10_000

    private struct RememberedMutation {
        let digest: String
        let outcome: WorkspaceMutationOutcomeV1
    }

    private let identity: WorkspaceReplicaIdentityV1
    private let generationID: UUID
    private let writerInstanceID: UUID
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let fileAuthority: any ApplicationFileAuthorityV1
    private let adapter: any WorkspaceWriterAdapterPortV1
    private let journalStore: MutationJournalStoreV1?
    private let storageAdmission: (any WorkspaceStorageAdmissionPortV1)?
    private let searchIndexInvalidation: ((SearchSourceRevisionV1) throws -> Void)?
    private let maximumRememberedMutationCount: Int

    private var workspaceRevision: UInt64
    private var entityRevisions: [WorkspaceEntityIdentityV1: UInt64]
    private var remembered: [MutationIDV1: RememberedMutation] = [:]
    private var quarantined: Set<MutationIDV1> = []
    private var isExecuting = false
    private var isActive = true

    init(
        identity: WorkspaceReplicaIdentityV1,
        generationID: UUID,
        initialRevision: WorkspaceRevisionV1,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        adapter: any WorkspaceWriterAdapterPortV1,
        journalStore: MutationJournalStoreV1? = nil,
        storageAdmission: (any WorkspaceStorageAdmissionPortV1)? = nil,
        searchIndexInvalidation: ((SearchSourceRevisionV1) throws -> Void)? = nil,
        maximumRememberedMutationCount: Int = WorkspaceWriterV1.defaultMaximumRememberedMutationCount
    ) throws {
        guard initialRevision.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard initialRevision.generationID == generationID else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        guard maximumRememberedMutationCount > 0 else {
            throw WorkspaceMutationFailureV1.idempotencyCapacityReached
        }
        self.identity = identity
        self.generationID = generationID
        let instanceID = idSource.makeID()
        guard instanceID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        writerInstanceID = instanceID
        self.workspaceRevision = initialRevision.revision
        self.entityRevisions = Dictionary(
            uniqueKeysWithValues: initialRevision.entityRevisions.map { ($0.identity, $0.revision) }
        )
        self.clock = clock
        self.idSource = idSource
        self.fileAuthority = fileAuthority
        self.adapter = adapter
        self.journalStore = journalStore
        self.storageAdmission = storageAdmission
        self.searchIndexInvalidation = searchIndexInvalidation
        self.maximumRememberedMutationCount = maximumRememberedMutationCount
    }

    func makeMutationID() throws -> MutationIDV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        return try MutationIDV1(rawValue: idSource.makeID())
    }

    func currentRevision() throws -> WorkspaceRevisionV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        if let journalStore {
            return try journalStore.currentRevision(writerInstanceID: writerInstanceID)
        }
        return try WorkspaceRevisionV1(
            workspaceID: identity.workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            revision: workspaceRevision,
            entityRevisions: entityRevisions.map {
                WorkspaceEntityRevisionV1(identity: $0.key, revision: $0.value)
            }
        )
    }

    func sourceMutationHistorySnapshot() throws -> MutationHistorySnapshotV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.exportSnapshot()
    }

    /// Read-only C17 source for the provider-neutral integration projection.
    /// The journal remains the sole accepted-receipt authority; this method
    /// does not allocate IDs, write a checkpoint, or mutate workspace truth.
    func acceptedReceiptsForProjection() throws -> [MutationReceiptV1] {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.acceptedReceiptsForProjection()
    }

    func executeImported(_ change: JournalChangeV1) throws -> WorkspaceMutationOutcomeV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        try change.validate()
        try change.portableReversalPlan?.validate()

        let sourceInputSHA256 = try change.canonicalSHA256()
        let isSemanticReversal = change.envelope.sourceKind == .semanticReversal
        guard isSemanticReversal == (change.semanticReversalReceipt != nil),
              change.receipt.sourceKind == change.envelope.sourceKind,
              change.receipt.commandBodySHA256 == change.envelope.commandBodySHA256,
              change.receipt.expectedRevision == change.envelope.expectedRevision,
              change.receipt.causationMutationID == change.envelope.causationMutationID,
              change.receipt.correlationID == change.envelope.correlationID,
              change.receipt.contentDependencyIDs == change.envelope.contentDependencyIDs,
              change.reversalBasis?.targetMutationID == change.envelope.mutationID
                || change.reversalBasis == nil,
              change.reversalBasis?.targetReceiptIdentity == change.receipt.identity
                || change.reversalBasis == nil,
              change.envelope.correlationID.map({ $0 != Self.zeroUUID }) ?? true,
              change.receipt.reversesMutationID
                == change.semanticReversalReceipt?.reversesMutationID else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }

        let sourceCorrelationID: UUID
        if change.envelope.sourceKind == .importedHistory {
            guard let carried = change.envelope.correlationID else {
                throw WorkspaceMutationFailureV1.invalidReceipt
            }
            sourceCorrelationID = carried
        } else if isSemanticReversal,
                  let carried = change.envelope.correlationID {
            sourceCorrelationID = carried
        } else {
            sourceCorrelationID = try Self.correlationID(
                sourceInputSHA256: sourceInputSHA256
            )
        }

        let effectiveSourceKind: MutationSourceKindV1 = isSemanticReversal
            ? .semanticReversal
            : .importedHistory
        if let prior = try journalStore.receipt(
            mutationID: change.envelope.mutationID
        ), prior.sourceKind == effectiveSourceKind,
           prior.correlationID == sourceCorrelationID {
            guard try importedReplayMatches(
                change,
                prior: prior,
                effectiveSourceKind: effectiveSourceKind,
                journalStore: journalStore
            ) else {
                try quarantineChangedImportedReplay(
                    change,
                    prior: prior,
                    sourceInputSHA256: sourceInputSHA256,
                    journalStore: journalStore
                )
            }
            let request = try importedRequest(
                mutationID: change.envelope.mutationID,
                command: change.envelope.command,
                expectedRevision: prior.expectedRevision
            )
            return try notifyingSearchIndex(outcome(
                from: prior,
                request: request,
                digest: prior.envelopeSHA256,
                occurredAt: prior.committedAt
            ))
        }

        let request = try importedRequest(
            mutationID: change.envelope.mutationID,
            command: change.envelope.command
        )
        if isSemanticReversal {
            guard change.reversalBasis == nil,
                  change.portableReversalPlan == nil,
                  let sourceExecution = change.envelope.semanticReversalExecution,
                  let sourceReceipt = change.semanticReversalReceipt,
                  sourceReceipt.reversesMutationID == sourceExecution.targetMutationID,
                  sourceReceipt.targetReceiptIdentity == sourceExecution.targetReceiptIdentity,
                  sourceReceipt.reversalBasisSHA256 == sourceExecution.reversalBasisSHA256,
                  sourceReceipt.planDigest == sourceExecution.planDigest,
                  sourceReceipt.compensatingMutationIDs == sourceExecution.compensatingMutationIDs,
                  sourceReceipt.resultingRevision == change.receipt.resultingRevision,
                  sourceExecution.compensatingMutationIDs == [change.envelope.mutationID],
                  let target = try journalStore.receipt(
                    mutationID: sourceExecution.targetMutationID
                  ),
                  let basis = try journalStore.reversalBasis(
                    mutationID: sourceExecution.targetMutationID
                  ),
                  basis.targetReceiptIdentity == target.identity,
                  basis.compensatingCommandKinds == [request.command.kind] else {
                throw WorkspaceMutationFailureV1.invalidReversal
            }
            let execution = try SemanticReversalExecutionV1(
                targetMutationID: sourceExecution.targetMutationID,
                targetReceiptIdentity: target.identity,
                reversalBasisSHA256: basis.canonicalSHA256(),
                planDigest: basis.planDigest,
                compensatingMutationIDs: sourceExecution.compensatingMutationIDs
            )
            let replayIdentitySHA256 = try SemanticReversalReplayIdentityV1(
                request: request,
                identity: identity,
                targetMutationID: execution.targetMutationID,
                planDigest: execution.planDigest,
                compensatingMutationIDs: execution.compensatingMutationIDs
            ).canonicalSHA256()
            let locationOccurredAt = try change.envelope.command.canonicalLocationAffectedIdentities() == nil
                ? nil
                : change.receipt.committedAt
            return try executeInternal(
                request,
                reversalPlan: nil,
                semanticReversalExecution: execution,
                semanticReversalReplayIdentitySHA256: replayIdentitySHA256,
                sourceKind: .semanticReversal,
                contentDependencyIDs: change.envelope.contentDependencyIDs,
                correlationID: sourceCorrelationID,
                occurredAtOverride: locationOccurredAt
            )
        }

        guard change.envelope.semanticReversalExecution == nil,
              change.envelope.causationMutationID == nil else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        let locationOccurredAt = try change.envelope.command.canonicalLocationAffectedIdentities() == nil
            ? nil
            : change.receipt.committedAt
        return try executeInternal(
            request,
            reversalPlan: nil,
            semanticReversalExecution: nil,
            semanticReversalReplayIdentitySHA256: nil,
            sourceKind: .importedHistory,
            contentDependencyIDs: change.envelope.contentDependencyIDs,
            correlationID: sourceCorrelationID,
            portableReversalPlan: change.portableReversalPlan,
            occurredAtOverride: locationOccurredAt
        )
    }

    func query(
        _ request: WorkspacePackageLifecycleQueryRequestV1
    ) throws -> WorkspacePackageLifecycleQueryResultV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard request.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard request.generationID == generationID else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        let observed = try adapter.queryExisting(identities: request.identities)
        return try WorkspacePackageLifecycleQueryResultV1(
            request: request,
            revision: currentRevision(),
            existingIdentities: observed.identities,
            packageBindings: observed.packageBindings
        )
    }

    /// This operation is synchronous by design: no canonical transaction can
    /// suspend and admit another command on the main actor.
    func execute(_ command: WorkspaceCommandV1) throws -> WorkspaceMutationOutcomeV1 {
        try execute(command, mutationID: makeMutationID())
    }

    func commitMeasurementIntegrity(
        _ bundle: MeasurementIntegrityAtomicBundleV1
    ) async throws -> MeasurementIntegrityWriteReceiptV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard !isExecuting else { throw WorkspaceMutationFailureV1.persistenceFailed }
        let mutation = try MeasurementIntegrityMutationV1(bundle: bundle)
        guard mutation.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }

        // Reading the current revision also validates the durable writer lease.
        // Even a receipt-only retry must not bypass generation invalidation.
        let current = try currentRevision()

        // A committed command retains its original expected revisions. Replay
        // must validate the durable command identity before comparing those
        // revisions with the now-advanced live workspace.
        if let receipt = try journalStore.receipt(mutationID: bundle.mutationID) {
            _ = try MeasurementIntegrityMutationReceiptV1(
                mutation: mutation, mutationReceipt: receipt
            )
            return try MeasurementIntegrityWriteReceiptV1(
                workspaceID: bundle.workspaceID,
                mutationID: bundle.mutationID,
                bundleSHA256: bundle.bundleSHA256,
                journalReceiptSHA256: receipt.canonicalSHA256()
            )
        }

        let concurrency = try mutation.concurrencyIdentities
        let byIdentity = Dictionary(uniqueKeysWithValues: current.entityRevisions.map {
            ($0.identity, $0.revision)
        })
        guard try concurrency.allSatisfy({
            byIdentity[$0, default: 0] == (try mutation.expectedRevision(for: $0))
        }) else { throw WorkspaceMutationFailureV1.staleWorkspaceRevision }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: concurrency.map {
                WorkspaceEntityRevisionV1(identity: $0, revision: byIdentity[$0, default: 0])
            }
        )
        _ = try execute(WorkspaceMutationRequestV1(
            mutationID: bundle.mutationID,
            expectedRevision: expected,
            command: .applyMeasurementIntegrity(mutation)
        ))
        guard let receipt = try journalStore.receipt(mutationID: bundle.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try MeasurementIntegrityMutationReceiptV1(
            mutation: mutation, mutationReceipt: receipt
        )
        return try MeasurementIntegrityWriteReceiptV1(
            workspaceID: bundle.workspaceID,
            mutationID: bundle.mutationID,
            bundleSHA256: bundle.bundleSHA256,
            journalReceiptSHA256: receipt.canonicalSHA256()
        )
    }
    func commitPrivacyTransform(_ mutation:PrivacyTransformMutationV1)throws->MutationReceiptV1{try mutation.validate();let current=try currentRevision();let concurrency=try mutation.concurrencyIdentities;let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:try concurrency.map{WorkspaceEntityRevisionV1(identity:$0,revision:try mutation.expectedRevision(for:$0))});_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applyPrivacyTransform(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try PrivacyTransformMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
    func commitEvidenceMetadata(
        _ mutation: EvidenceMetadataMutationV1
    ) throws -> EvidenceMetadataMutationReceiptV1 {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.acceptedEvidenceMetadataMutation(mutation) {
            guard try adapter.persistedEvidenceMetadataEffectMatches(mutation) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return existing
        }
        let current = try currentRevision()
        let targets = try mutation.concurrencyIdentities
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map {
            ($0.identity, $0.revision)
        })
        guard current.workspaceID == mutation.workspaceID,
              try targets.allSatisfy({
                  known[$0, default: 0] == (try mutation.expectedRevision(for: $0))
              }) else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: try targets.map {
                .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
            }
        )
        let request = try WorkspaceMutationRequestV1(
            mutationID: mutation.mutationID,
            expectedRevision: expected,
            command: .applyEvidenceMetadata(mutation)
        )
        if try adapter.persistedEvidenceMetadataEffectMatches(mutation) {
            let associationHistory = try adapter.evidenceAssociationHistory(
                workspaceID: mutation.workspaceID,
                evidenceID: mutation.associationEvent.evidenceID
            )
            let sequenceHistory = try adapter.evidenceSequenceHistory(
                workspaceID: mutation.workspaceID,
                sequenceID: mutation.sequenceSuccessor.sequenceID
            )
            guard associationHistory.last == mutation.associationEvent,
                  sequenceHistory.last == mutation.sequenceSuccessor else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let envelope = try MutationEnvelopeV1(
                request: request,
                identity: identity,
                sourceKind: .localUser
            )
            let receipt = try journalStore.commit(
                envelope: envelope,
                writerInstanceID: writerInstanceID,
                affectedEntities: mutation.affectedIdentities,
                committedAt: clock.now()
            )
            return try EvidenceMetadataMutationReceiptV1(
                mutation: mutation,
                mutationReceipt: receipt
            )
        }
        _ = try execute(request)
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return try EvidenceMetadataMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: receipt
        )
    }

    /// C10 is submitted through the one canonical writer/journal transaction.
    /// Evidence, rule, and waiver history are immutable; a replay returns the
    /// existing typed receipt only after its command digest is revalidated.
    func commitEvidenceQuality(
        _ command: EvidenceQualityMutationCommandV1
    ) throws -> EvidenceQualityMutationReceiptV1 {
        try command.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let receipt = try journalStore.evidenceQualityReceipt(command) { return receipt }
        let current = try currentRevision()
        let target = try command.affectedIdentityForCanonicalWriter()
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        let expected = Dictionary(uniqueKeysWithValues: command.expectedRevision.entityRevisions.map { ($0.identity, $0.revision) })
        guard current.workspaceID == command.expectedRevision.workspaceID,
              current.generationID == command.expectedRevision.generationID,
              current.writerInstanceID == command.expectedRevision.writerInstanceID,
              current.revision == command.expectedRevision.workspaceRevision,
              let targetRevision = expected[target], known[target, default: 0] == targetRevision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        _ = try execute(.init(mutationID: command.mutationID,
                              expectedRevision: command.expectedRevision,
                              command: .applyEvidenceQuality(command)))
        guard let receipt = try journalStore.evidenceQualityReceipt(command) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return receipt
    }

    func evidenceQualityReceipt(
        for command: EvidenceQualityMutationCommandV1
    ) throws -> EvidenceQualityMutationReceiptV1? {
        try command.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.evidenceQualityReceipt(command)
    }

    /// C11 uses this same writer/journal transaction for every inbox item,
    /// explicit promotion, and versioned snippet postimage. Repeating a
    /// MutationID returns the already durable typed receipt only after the
    /// complete command digest has been revalidated.
    func commitFastSurveyInbox(
        _ command: FastSurveyInboxMutationCommandV1
    ) throws -> FastSurveyInboxMutationReceiptV1 {
        try command.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let receipt = try journalStore.fastSurveyInboxReceipt(command) { return receipt }
        let current = try currentRevision()
        try command.validate(currentRevision: current)
        _ = try execute(.init(
            mutationID: command.mutationID,
            expectedRevision: command.expectedRevision,
            command: .applyFastSurveyInbox(command)
        ))
        guard let receipt = try journalStore.fastSurveyInboxReceipt(command) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        try receipt.validate(command: command)
        return receipt
    }

    func fastSurveyInboxReceipt(
        for command: FastSurveyInboxMutationCommandV1
    ) throws -> FastSurveyInboxMutationReceiptV1? {
        try command.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.fastSurveyInboxReceipt(command)
    }

    /// C12 uses the incumbent writer/journal transaction for canonical plan,
    /// attestation, and acknowledgement history only. The exception queue is
    /// a query-time projection and is never accepted as a mutation effect.
    func commitReinspectionException(
        _ command: ReinspectionExceptionMutationCommandV1
    ) throws -> ReinspectionExceptionMutationReceiptV1 {
        try command.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let receipt = try journalStore.reinspectionExceptionReceipt(command) { return receipt }
        let current = try currentRevision()
        try adapter.validateReinspectionExceptionCommand(command, currentRevision: current)
        _ = try execute(.init(
            mutationID: command.mutationID,
            expectedRevision: command.expectedRevision,
            command: .applyReinspectionException(command)
        ))
        guard let receipt = try journalStore.reinspectionExceptionReceipt(command) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        try receipt.validate(command: command)
        return receipt
    }

    func reinspectionExceptionReceipt(
        for command: ReinspectionExceptionMutationCommandV1
    ) throws -> ReinspectionExceptionMutationReceiptV1? {
        try command.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.reinspectionExceptionReceipt(command)
    }

    /// C13 writes only an explicit reviewed alias/consolidation command.  The
    /// adapter resolves every source and inventory item before the generic
    /// journal transaction stages its one effect row and typed receipt.
    func commitEntityIdentityResolution(
        _ command: EntityIdentityResolutionMutationCommandV1
    ) throws -> EntityIdentityResolutionMutationReceiptV1 {
        try command.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let receipt = try journalStore.entityIdentityResolutionReceipt(command) {
            try receipt.validate(command: command)
            return receipt
        }
        let current = try currentRevision()
        try Self.validateEntityIdentityResolutionLineage(command, currentRevision: current)
        try adapter.validateEntityIdentityResolutionCommand(command, currentRevision: current)
        _ = try execute(.init(
            mutationID: command.mutationID,
            expectedRevision: command.expectedRevision,
            command: .applyEntityIdentityResolution(command)
        ))
        guard let receipt = try journalStore.entityIdentityResolutionReceipt(command) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        try receipt.validate(command: command)
        return receipt
    }

    func entityIdentityResolutionReceipt(
        for command: EntityIdentityResolutionMutationCommandV1
    ) throws -> EntityIdentityResolutionMutationReceiptV1? {
        try command.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.entityIdentityResolutionReceipt(command)
    }

    /// C13 identity queries are immutable-history reads.  They deliberately
    /// do not invoke the canonical mutation resolver or the mutation journal.
    func entityIdentityResolutionQuery(
        _ request: EntityIdentityResolutionQueryV1
    ) throws -> EntityIdentityResolutionQueryResultV1 {
        try request.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard request.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        let result = try adapter.entityIdentityResolutionQuery(request)
        try result.validate(for: request)
        return result
    }

    func commitWorkspaceExperience(
        _ command: WorkspaceExperienceMutationCommandV1
    ) throws -> WorkspaceExperienceMutationReceiptV1 {
        try command.validateForCanonicalWriter()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let prior = try journalStore.workspaceExperienceReceipt(command) {
            try prior.validate(command: command)
            guard try adapter.persistedWorkspaceExperienceEffectMatches(command) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return prior
        }
        _ = try execute(.init(
            mutationID: command.mutationID,
            expectedRevision: command.expectedRevision,
            command: .applyWorkspaceExperience(command)
        ))
        guard let receipt = try journalStore.workspaceExperienceReceipt(command) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        try receipt.validate(command: command)
        guard try adapter.persistedWorkspaceExperienceEffectMatches(command) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return receipt
    }

    func workspaceExperienceReceipt(
        for command: WorkspaceExperienceMutationCommandV1
    ) throws -> WorkspaceExperienceMutationReceiptV1? {
        try command.validateForCanonicalWriter()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard command.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.workspaceExperienceReceipt(command)
    }

    func reinspectionExceptionQuery(
        _ request: ReinspectionExceptionQueryV1,
        providers: [any ExceptionQueueCanonicalSourceProvidingV1]
    ) throws -> ReinspectionExceptionQueryResultV1 {
        try request.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard request.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        // The adapter owns both incumbent canonical resolvers and returns only
        // a result already validated with `validateResolved(for:...)`.
        return try adapter.reinspectionExceptionQuery(request, providers: providers)
    }

    func evidenceMetadataReceipt(
        for mutation: EvidenceMetadataMutationV1
    ) throws -> EvidenceMetadataMutationReceiptV1? {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        guard let receipt = try journalStore.acceptedEvidenceMetadataMutation(mutation) else {
            return nil
        }
        guard try adapter.persistedEvidenceMetadataEffectMatches(mutation) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return receipt
    }

    func evidenceAssociationHistory(
        workspaceID: WorkspaceID,
        evidenceID: String
    ) throws -> [EvidenceAssociationV1] {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        return try adapter.evidenceAssociationHistory(
            workspaceID: workspaceID,
            evidenceID: evidenceID
        )
    }

    func evidenceSequenceHistory(
        workspaceID: WorkspaceID,
        sequenceID: UUID
    ) throws -> [EvidenceSequenceV1] {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        return try adapter.evidenceSequenceHistory(
            workspaceID: workspaceID,
            sequenceID: sequenceID
        )
    }
    func commitClientCapability(_ mutation:ClientCapabilityMutationV1)throws->MutationReceiptV1{try mutation.validate();let current=try currentRevision(),concurrency=try mutation.concurrencyIdentity;let known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard known[concurrency,default:0]==mutation.expectedRevision else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:[.init(identity:concurrency,revision:mutation.expectedRevision)]);_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applyClientCapability(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try ClientCapabilityMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
    func commitFieldReference(_ mutation:FieldReferenceMutationV1)throws->MutationReceiptV1{try mutation.validate();let current=try currentRevision(),concurrency=try mutation.concurrencyIdentity;let known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard known[concurrency,default:0]==mutation.expectedRevision else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:[.init(identity:concurrency,revision:mutation.expectedRevision)]);_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applyFieldReference(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try FieldReferenceMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
    func commitShopReportProfile(
        _ mutation: ShopReportProfileMutationV1
    ) throws -> ShopReportProfileMutationReceiptV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard !isExecuting else { throw WorkspaceMutationFailureV1.persistenceFailed }
        try mutation.validate()
        guard mutation.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        // Validate the current writer lease even when returning an old receipt.
        let current = try currentRevision()
        if let receipt = try journalStore.receipt(mutationID: mutation.mutationID) {
            return try ShopReportProfileMutationReceiptV1(
                mutation: mutation, mutationReceipt: receipt
            )
        }

        // Only new commands compare their expected revision with live state.
        let concurrency = try mutation.concurrencyIdentity
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map {
            ($0.identity, $0.revision)
        })
        guard known[concurrency, default: 0] == mutation.expectedRevision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [.init(identity: concurrency, revision: mutation.expectedRevision)]
        )
        _ = try execute(.init(
            mutationID: mutation.mutationID,
            expectedRevision: expected,
            command: .applyShopReportProfile(mutation)
        ))
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return try ShopReportProfileMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
    }
    func commitRoundSession(_ mutation: RoundSessionMutationV1) throws -> RoundSessionMutationReceiptV1 {
        try mutation.validate(); guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard mutation.workspaceID == identity.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        let command = WorkspaceCommandV1.applyRoundSession(mutation), digest = try WorkspaceMutationCanonicalV1.sha256(command)
        // A durable receipt does not bypass the current generation's writer lease.
        let current = try currentRevision()
        if let receipt = try journalStore.receipt(mutationID: mutation.mutationID) {
            guard receipt.identity.workspaceID == mutation.workspaceID, receipt.commandBodySHA256 == digest,
                  try adapter.persistedRoundSessionEffectMatches(mutation) else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
            return try .init(mutation: mutation, mutationReceipt: receipt)
        }
        let target = try mutation.concurrencyIdentity
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        guard known[target, default: 0] == mutation.expectedRevision else { throw WorkspaceMutationFailureV1.staleWorkspaceRevision }
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID, generationID: current.generationID, writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision, entityRevisions: [.init(identity: target, revision: mutation.expectedRevision)])
        _ = try execute(.init(mutationID: mutation.mutationID, expectedRevision: expected, command: command))
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID), try adapter.persistedRoundSessionEffectMatches(mutation) else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        return try .init(mutation: mutation, mutationReceipt: receipt)
    }
    func commitAccessibleDocumentAssessment(_ mutation:AccessibleDocumentMutationV1,validatedAgainst tree:AccessibleDocumentSemanticTreeV1)throws->MutationReceiptV1{try mutation.validate();try mutation.receipt.validate(tree:tree);let current=try currentRevision(),concurrency=try mutation.concurrencyIdentity;let known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard known[concurrency,default:0]==mutation.expectedRevision else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:[.init(identity:concurrency,revision:mutation.expectedRevision)]);_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applyAccessibleDocumentAssessment(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try AccessibleDocumentMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
    func commitSurveyDefinition(_ mutation:SurveyDefinitionMutationV1)throws->MutationReceiptV1{try mutation.validate();let current=try currentRevision(),targets=try mutation.concurrencyIdentities;let known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard try targets.allSatisfy({known[$0,default:0]==(try mutation.expectedRevision(for:$0))})else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:try targets.map{.init(identity:$0,revision:try mutation.expectedRevision(for:$0))});_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applySurveyDefinition(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try SurveyDefinitionMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
    func commitSurveySession(_ mutation:SurveySessionMutationV1)throws->MutationReceiptV1{try mutation.validate();let current=try currentRevision(),targets=try mutation.concurrencyIdentities;let known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard try targets.allSatisfy({known[$0,default:0]==(try mutation.expectedRevision(for:$0))})else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:try targets.map{.init(identity:$0,revision:try mutation.expectedRevision(for:$0))});_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applySurveySession(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try SurveySessionMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
    func commitAssetLocator(_ mutation:AssetLocatorMutationV1)throws->MutationReceiptV1{try mutation.validate();let current=try currentRevision(),targets=try mutation.concurrencyIdentities,known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard try targets.allSatisfy({known[$0,default:0]==(try mutation.expectedRevision(for:$0))})else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:try targets.map{.init(identity:$0,revision:try mutation.expectedRevision(for:$0))});_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applyAssetLocator(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try AssetLocatorMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
    func manualShortCodeIsAvailable(_ code:ManualShortCodeV1,workspaceID:WorkspaceID)throws->Bool{guard isActive else{throw WorkspaceMutationFailureV1.writerInvalidated};guard workspaceID==identity.workspaceID else{throw WorkspaceMutationFailureV1.wrongWorkspace};guard let journalStore else{throw WorkspaceMutationFailureV1.persistenceFailed};let key=try code.externalKey();return try !journalStore.assetLocatorLookupKeyWasEverUsed(key.lookupKey)}
    func commitSchedule(_ mutation:ScheduleMutationV1)throws->MutationReceiptV1{try mutation.validate();try Self.validateC51ScheduleMutation(mutation);let current=try currentRevision(),targets=try mutation.concurrencyIdentities,known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard try targets.allSatisfy({known[$0,default:0]==(try mutation.expectedRevision(for:$0))})else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:try targets.map{.init(identity:$0,revision:try mutation.expectedRevision(for:$0))});_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applySchedule(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try ScheduleMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
    func commitPlan(_ mutation:PlanMutationV1,validatedAgainst preview:RebasePreviewV1)throws->MutationReceiptV1{try mutation.validate();switch mutation.payload{case let .applyRebase(newRevision,predecessorRevision,placements,predecessorPlacements,receipt,predecessorReceipt,poseEffects):let basis=try PlanRebaseCommandBasisV1(workspaceID:mutation.workspaceID,mutationID:mutation.mutationID,preview:preview,newRevision:newRevision,predecessorRevision:predecessorRevision,placements:placements,predecessorPlacements:predecessorPlacements,receiptID:receipt.receiptID,predecessorReceipt:predecessorReceipt,reviewedBy:receipt.reviewedBy,recordedAt:receipt.recordedAt,poseEffects:poseEffects);try receipt.validate(preview:preview,commandBasis:basis,predecessor:predecessorReceipt);case let .recordRebaseRejection(receipt,predecessor):if let predecessor{try receipt.validateSuccessor(of:predecessor,preview:preview)}else{try receipt.validate(preview:preview);guard receipt.revision==1,receipt.supersedesReceiptSHA256==nil else{throw WorkspaceMutationFailureV1.invalidCommand}};default:throw WorkspaceMutationFailureV1.invalidCommand};let current=try currentRevision(),targets=try mutation.concurrencyIdentities,known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard try targets.allSatisfy({known[$0,default:0]==(try mutation.expectedRevision(for:$0))})else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:try targets.map{.init(identity:$0,revision:try mutation.expectedRevision(for:$0))});_ = try execute(.init(mutationID:mutation.mutationID,expectedRevision:expected,command:.applyPlan(mutation)));guard let receipt=try journalStore?.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try PlanMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}

    func execute(
        _ command: WorkspaceCommandV1,
        mutationID: MutationIDV1
    ) throws -> WorkspaceMutationOutcomeV1 {
        let current = try currentRevision()
        let targets = try Self.expectedRevisionIdentities(for: command)
        let known = Dictionary(
            uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) }
        )
        let scoped = try WorkspaceRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            revision: current.revision,
            entityRevisions: targets.map {
                WorkspaceEntityRevisionV1(identity: $0, revision: known[$0, default: 0])
            }
        )
        return try execute(WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: scoped),
            command: command
        ))
    }

    func execute(_ request: WorkspaceMutationRequestV1) throws -> WorkspaceMutationOutcomeV1 {
        try executeInternal(request, reversalPlan: nil, semanticReversalExecution: nil, semanticReversalReplayIdentitySHA256: nil)
    }

    func execute(
        _ request: WorkspaceMutationRequestV1,
        reversalPlan: SemanticReversalPlanV1
    ) throws -> WorkspaceMutationOutcomeV1 {
        try executeInternal(request, reversalPlan: reversalPlan, semanticReversalExecution: nil, semanticReversalReplayIdentitySHA256: nil)
    }

    func executeSemanticReversal(
        _ request: WorkspaceMutationRequestV1,
        targetMutationID: MutationIDV1,
        plan: SemanticReversalPlanV1,
        compensatingMutationIDs: [MutationIDV1]
    ) throws -> WorkspaceMutationOutcomeV1 {
        let replayIdentity = try SemanticReversalReplayIdentityV1(
            request: request,
            identity: identity,
            targetMutationID: targetMutationID,
            planDigest: plan.planDigest,
            compensatingMutationIDs: compensatingMutationIDs
        )
        let replayIdentitySHA256 = try replayIdentity.canonicalSHA256()
        let replayObservedAt = clock.now()
        if let journalStore,
           let prior = try journalStore.resolveSemanticReversalReplay(
             request: request,
             replayIdentitySHA256: replayIdentitySHA256,
             detectedAt: replayObservedAt
           ) {
            return try notifyingSearchIndex(outcome(
                from: prior,
                request: request,
                digest: prior.envelopeSHA256,
                occurredAt: replayObservedAt
            ))
        }
        guard let journalStore,
              plan.mutationID == targetMutationID,
              plan.compensatingCommands.count == 1,
              plan.compensatingCommands.first == request.command,
              compensatingMutationIDs == [request.mutationID],
              let target = try journalStore.receipt(mutationID: targetMutationID),
              let basis = try journalStore.reversalBasis(mutationID: targetMutationID),
              basis.planDigest == plan.planDigest,
              basis.compensatingCommandKinds == plan.compensatingCommands.map(\.kind) else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        let execution = try SemanticReversalExecutionV1(
            targetMutationID: targetMutationID,
            targetReceiptIdentity: target.identity,
            reversalBasisSHA256: basis.canonicalSHA256(),
            planDigest: plan.planDigest,
            compensatingMutationIDs: compensatingMutationIDs
        )
        return try executeInternal(
            request,
            reversalPlan: nil,
            semanticReversalExecution: execution,
            semanticReversalReplayIdentitySHA256: replayIdentitySHA256
        )
    }

    private func executeInternal(
        _ request: WorkspaceMutationRequestV1,
        reversalPlan: SemanticReversalPlanV1?,
        semanticReversalExecution: SemanticReversalExecutionV1?,
        semanticReversalReplayIdentitySHA256: String?,
        sourceKind: MutationSourceKindV1? = nil,
        contentDependencyIDs: [String] = [],
        correlationID: UUID? = nil,
        portableReversalPlan: PortableReversalPlanV1? = nil,
        occurredAtOverride: Date? = nil
    ) throws -> WorkspaceMutationOutcomeV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard !isExecuting else { throw WorkspaceMutationFailureV1.persistenceFailed }
        guard reversalPlan == nil || portableReversalPlan == nil else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        switch request.command {
        case .createFirstSign(let value):
            let placementFields = [
                value.initialPlacementMutationID != nil,
                value.initialPlacementEventID != nil,
                value.initialPhysicalEpisodeID != nil,
            ]
            guard placementFields.allSatisfy({ $0 }) || placementFields.allSatisfy({ !$0 }),
                  !(adapter.requiresInitialPlacementForFirstSign
                    && sourceKind != .importedHistory
                    && !placementFields.allSatisfy({ $0 })),
                  value.initialPlacementMutationID.map({ $0 == request.mutationID }) ?? true else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyLocationHierarchyChange(let value):
            let beforeByID = Dictionary(uniqueKeysWithValues: value.plan.beforeNodes.map { ($0.id, $0) })
            let changedAfterNodes = value.plan.afterNodes.filter { beforeByID[$0.id] != $0 }
            guard value.plan.workspaceID == identity.workspaceID,
                  (sourceKind == .importedHistory || occurredAtOverride != nil || value.plan.expectedRevision == request.expectedRevision),
                  changedAfterNodes.allSatisfy({ $0.provenance.mutationID == request.mutationID }),
                  value.placementChanges.allSatisfy({ $0.mutationID == request.mutationID }) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyAssetPlacementChange(let plan):
            try plan.validate()
            guard plan.mutationID == request.mutationID,
                  (sourceKind == .importedHistory || occurredAtOverride != nil || plan.basis.expectedRevision == request.expectedRevision),
                  plan.basis.workspaceID == identity.workspaceID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyAssetCompositionChange(let plan):
            guard plan.mutationID == request.mutationID,
                  (sourceKind == .importedHistory || occurredAtOverride != nil || plan.expectedRevision == request.expectedRevision),
                  plan.workspaceID == identity.workspaceID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applySavedSmartView(let value):
            try value.validate()
            guard value.workspaceID == identity.workspaceID.rawValue,
                  value.mutationID == request.mutationID.rawValue else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyRequirementAssurance(let value):
            try value.validate()
            guard value.snapshot.workspaceID == identity.workspaceID.rawValue,
                  value.mutationID == request.mutationID.rawValue else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyPartyAccountability(let value):
            try value.validate()
            guard value.workspaceID == identity.workspaceID,
                  value.mutationID.map({ $0 == request.mutationID }) ?? true else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyPartyContactSiteRoleImport(let value):
            do {
                try value.validate()
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.expectedRevision == request.expectedRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 {
                throw failure
            } catch {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyAssetSemantics(let value):
            do {
                try value.validate()
                if case let .upsertPart(part) = value, part.archived { throw WorkspaceMutationFailureV1.invalidCommand }
                let target = try value.affectedIdentity
                let expectedEntityRevision = request.expectedRevision.entityRevisions
                    .first(where: { $0.identity == target })?.revision
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      sourceKind == .importedHistory
                          || occurredAtOverride != nil
                          || expectedEntityRevision == value.expectedAssetRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 {
                throw failure
            } catch {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyAuthorityCriterion(let value):
            do {
                try value.validate()
                let target = try value.concurrencyIdentity
                let expectedEntityRevision = request.expectedRevision.entityRevisions
                    .first(where: { $0.identity == target })?.revision
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      sourceKind == .importedHistory || occurredAtOverride != nil
                        || expectedEntityRevision == value.expectedRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
            catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyFunctionalRelationship(let value):
            do {
                try value.validate()
                let target = try value.concurrencyIdentity
                let expectedEntityRevision = request.expectedRevision.entityRevisions
                    .first(where: { $0.identity == target })?.revision
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      sourceKind == .importedHistory || occurredAtOverride != nil
                        || expectedEntityRevision == value.expectedRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
            catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyEvidenceAssurance(let value):
            do{try value.validate();let target=try value.concurrencyIdentity;let expected=request.expectedRevision.entityRevisions.first(where:{$0.identity==target})?.revision;guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || expected==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyInspectionReview(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities;let expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || targets.allSatisfy{expected[$0] != nil} else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyWorkPacket(let value):
            do{try value.validate();let target=try value.concurrencyIdentity;let expected=request.expectedRevision.entityRevisions.first(where:{$0.identity==target})?.revision;guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || expected==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyFieldDraft(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities;let expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy{expected[$0] == (try value.expectedRevision(for:$0))}) else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyPackagePromotion(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities;let expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy{expected[$0] == (try value.expectedRevision(for:$0))}) else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyMeasurementIntegrity(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities;let expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy{expected[$0] == (try value.expectedRevision(for:$0))}) else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyPrivacyTransform(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities;let expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy{expected[$0] == (try value.expectedRevision(for:$0))}) else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyEvidenceMetadata(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities;let expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy{expected[$0] == (try value.expectedRevision(for:$0))}) else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyClientCapability(let value):
            do{try value.validate();let target=try value.concurrencyIdentity;let expected=request.expectedRevision.entityRevisions.first(where:{$0.identity==target})?.revision;guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || expected==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyFieldReference(let value):
            do{try value.validate();let target=try value.concurrencyIdentity;let expected=request.expectedRevision.entityRevisions.first(where:{$0.identity==target})?.revision;guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || expected==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyAccessibleDocumentAssessment(let value):
            do{try value.validate();let target=try value.concurrencyIdentity;let expected=request.expectedRevision.entityRevisions.first(where:{$0.identity==target})?.revision;guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || expected==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applySurveyDefinition(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities;let expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy({expected[$0]==(try value.expectedRevision(for:$0))})) else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applySurveySession(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities;let expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy({expected[$0]==(try value.expectedRevision(for:$0))})) else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyAssetLocator(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities,expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy({expected[$0]==(try value.expectedRevision(for:$0))}))else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applySchedule(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities,expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy({expected[$0]==(try value.expectedRevision(for:$0))}))else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyPlan(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities,expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy({expected[$0]==(try value.expectedRevision(for:$0))}))else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyPlacementPose(let value):
            do{try value.validate();let targets=try value.concurrencyIdentities,expected=Dictionary(uniqueKeysWithValues:request.expectedRevision.entityRevisions.map{($0.identity,$0.revision)});guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy({expected[$0]==(try value.expectedRevision(for:$0))}))else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyEvidenceContext(let value):
            do{try value.validate();guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || request.expectedRevision.entityRevisions.first(where:{$0.identity==(try value.concurrencyIdentity)})?.revision==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyLighting(let value):
            do{try value.validate();guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || request.expectedRevision.entityRevisions.first(where:{$0.identity==(try value.concurrencyIdentity)})?.revision==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyLightingDayInventory(let value):
            do { try value.validate(); guard value.workspaceID == identity.workspaceID, value.mutationID == request.mutationID, sourceKind == .importedHistory || occurredAtOverride != nil || request.expectedRevision.entityRevisions.first(where: { $0.identity == (try value.concurrencyIdentity) })?.revision == value.expectedRevision else { throw WorkspaceMutationFailureV1.invalidCommand } } catch let failure as WorkspaceMutationFailureV1 { throw failure } catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyLightingNightWorkflow(let value):
            do { try value.validate(); guard value.workspaceID == identity.workspaceID, value.mutationID == request.mutationID, sourceKind == .importedHistory || occurredAtOverride != nil || request.expectedRevision.entityRevisions.first(where: { $0.identity == (try value.concurrencyIdentity) })?.revision == value.expectedRevision else { throw WorkspaceMutationFailureV1.invalidCommand } } catch let failure as WorkspaceMutationFailureV1 { throw failure } catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyAssistanceAcceptance(let acceptance):
            do {
                try acceptance.validate()
                guard acceptance.proposal.target.workspaceID == identity.workspaceID,
                      acceptance.mutationID == request.mutationID,
                      acceptance.expectedRevision == request.expectedRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 {
                throw failure
            } catch {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .applyTemporalEvidence(let value):
            do{try value.validate();guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,value.expectedRevision==request.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyAssetLabel(let value):
            do{try value.validate();guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,value.expectedRevision==request.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyOperationalContact(let value):
            do{try value.validate();guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,value.expectedRevision==request.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyActivityContract(let value):
            do{try value.validateForCanonicalMutation();guard C47ActivityContractPersistenceBoundaryV2.acceptsCanonicalRow(kind:value.successorEnvelope.kind),value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,value.expectedRevision==request.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyPortableReview(let value):
            do {
                try value.validate()
                let targets = try value.concurrencyIdentities
                let expected = Dictionary(uniqueKeysWithValues: request.expectedRevision.entityRevisions.map { ($0.identity, $0.revision) })
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.plan.basisWorkspaceRevision == request.expectedRevision.workspaceRevision,
                      sourceKind == .importedHistory || occurredAtOverride != nil || (try targets.allSatisfy {
                          expected[$0] == (try value.expectedRevision(for: $0))
                      }) else { throw WorkspaceMutationFailureV1.invalidCommand }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyWorkResource(let value):
            do {
                try value.validate()
                let concurrency = try value.concurrencyIdentity
                let expected = request.expectedRevision.entityRevisions.first(where: { $0.identity == concurrency })?.revision
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      expected == value.postImage.expectedRevision else { throw WorkspaceMutationFailureV1.invalidCommand }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyPartsStock(let value):
            do {
                try value.validate()
                let targets = try value.concurrencyIdentities
                let expected = Dictionary(uniqueKeysWithValues: request.expectedRevision.entityRevisions.map { ($0.identity, $0.revision) })
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      Set(targets).count == targets.count,
                      try targets.allSatisfy({ expected[$0] == (try value.expectedRevision(for: $0)) }) else { throw WorkspaceMutationFailureV1.invalidCommand }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyMyDay(let value):
            do {
                try value.validate()
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.expectedRevision == request.expectedRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyServiceRequest(let value):
            do {
                try value.validateForCanonicalWriter()
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.expectedRevision == request.expectedRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyServiceReliability(let value):
            do{try value.validateForCanonicalWriter();guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,value.expectedRevision==request.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}
            catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyShopReportProfile(let value):
            do{try value.validate();let target=try value.concurrencyIdentity,expected=request.expectedRevision.entityRevisions.first(where:{$0.identity==target})?.revision;guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || expected==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}
            catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyRoundSession(let value):
            do{try value.validate();let target=try value.concurrencyIdentity,expected=request.expectedRevision.entityRevisions.first(where:{$0.identity==target})?.revision;guard value.workspaceID==identity.workspaceID,value.mutationID==request.mutationID,sourceKind == .importedHistory || occurredAtOverride != nil || expected==value.expectedRevision else{throw WorkspaceMutationFailureV1.invalidCommand}}
            catch let failure as WorkspaceMutationFailureV1{throw failure}catch{throw WorkspaceMutationFailureV1.invalidCommand}
        case .applyImportBulk(let value):
            do { try value.validate(); let target = try value.concurrencyIdentity; let expected = request.expectedRevision.entityRevisions.first(where: { $0.identity == target })?.revision; guard value.workspaceID == identity.workspaceID, value.mutationID == request.mutationID, sourceKind == .importedHistory || occurredAtOverride != nil || expected == value.expectedRevision else { throw WorkspaceMutationFailureV1.invalidCommand } }
            catch let failure as WorkspaceMutationFailureV1 { throw failure } catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyEvidenceQuality(let value):
            do {
                try value.validate()
                let target = try value.affectedIdentityForCanonicalWriter()
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.expectedRevision == request.expectedRevision,
                      request.expectedRevision.entityRevisions.contains(where: { $0.identity == target }) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyFastSurveyInbox(let value):
            do {
                try value.validate()
                let targets = try value.affectedIdentitiesForCanonicalWriter()
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.expectedRevision == request.expectedRevision,
                      Set(request.expectedRevision.entityRevisions.map(\.identity)).isSuperset(of: targets) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyReinspectionException(let value):
            do {
                try value.validate()
                let targets = try value.affectedIdentitiesForCanonicalWriter()
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.expectedRevision == request.expectedRevision,
                      Set(request.expectedRevision.entityRevisions.map(\.identity)).isSuperset(of: targets) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyEntityIdentityResolution(let value):
            do {
                try value.validateForCanonicalWriter()
                let target = try Self.entityIdentityResolutionConcurrencyIdentity(value)
                let expected = request.expectedRevision.entityRevisions.filter { $0.identity == target }
                let (nextRevision, overflow) = expected.count == 1
                    ? expected[0].revision.addingReportingOverflow(1)
                    : (UInt64.zero, true)
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.expectedRevision == request.expectedRevision,
                      !overflow,
                      nextRevision == (try Self.entityIdentityResolutionLineageRevision(value)) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        case .applyWorkspaceExperience(let value):
            do {
                try value.validateForCanonicalWriter()
                guard value.workspaceID == identity.workspaceID,
                      value.mutationID == request.mutationID,
                      value.expectedRevision == request.expectedRevision else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
              catch { throw WorkspaceMutationFailureV1.invalidCommand }
        default:
            break
        }
        let envelope: MutationEnvelopeV1
        let digest: String
        do {
            envelope = try MutationEnvelopeV1(
                request: request,
                identity: identity,
                sourceKind: sourceKind
                    ?? (semanticReversalExecution == nil ? .localUser : .semanticReversal),
                contentDependencyIDs: contentDependencyIDs,
                causationMutationID: semanticReversalExecution?.targetMutationID,
                correlationID: correlationID,
                reversalPlanDigest: reversalPlan?.planDigest
                    ?? portableReversalPlan?.planDigest,
                semanticReversalReplayIdentitySHA256: semanticReversalReplayIdentitySHA256,
                semanticReversalExecution: semanticReversalExecution
            )
            digest = try envelope.canonicalSHA256()
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }

        let occurredAt = occurredAtOverride ?? clock.now()
        if let journalStore,
           let prior = try journalStore.resolveReplay(envelope: envelope, detectedAt: occurredAt) {
            return try notifyingSearchIndex(outcome(
                from: prior,
                request: request,
                digest: digest,
                occurredAt: occurredAt
            ))
        }

        guard !quarantined.contains(request.mutationID) else {
            throw WorkspaceMutationFailureV1.mutationIDQuarantined
        }
        if let prior = remembered[request.mutationID] {
            guard prior.digest == digest else {
                quarantined.insert(request.mutationID)
                throw WorkspaceMutationFailureV1.mutationIDQuarantined
            }
            return try notifyingSearchIndex(prior.outcome)
        }
        guard remembered.count < maximumRememberedMutationCount else {
            throw WorkspaceMutationFailureV1.idempotencyCapacityReached
        }

        let targets = try Self.targetIdentities(for: request.command)
        let expectedRevisionTargets = try Self.expectedRevisionIdentities(for: request.command)
        try require(request.expectedRevision, targets: expectedRevisionTargets)
        let liveRevision = try currentRevision()
        let liveByIdentity = Dictionary(uniqueKeysWithValues: liveRevision.entityRevisions.map { ($0.identity, $0.revision) })
        guard liveRevision.revision < UInt64(Int64.max),
              expectedRevisionTargets.allSatisfy({ liveByIdentity[$0, default: 0] < UInt64(Int64.max) }) else {
            throw WorkspaceMutationFailureV1.revisionOverflow
        }

        let before = try currentRevision()
        let temporaryRelativePath: String
        do {
            temporaryRelativePath = try fileAuthority.temporaryRelativePath(
                mutationID: request.mutationID,
                component: request.command.kind.rawValue
            )
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard !temporaryRelativePath.isEmpty,
              !temporaryRelativePath.hasPrefix("/"),
              !temporaryRelativePath.contains("..") else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: targets,
            temporaryRelativePath: temporaryRelativePath
        )

        let storageReservation: OwnedStorageReservationV1?
        do {
            storageReservation = try storageAdmission?.reserve(
                attemptID: OwnedStorageAttemptIDV1(
                    workspaceID: identity.workspaceID,
                    generationID: generationID,
                    mutationID: request.mutationID
                ),
                requiredBytes: WorkspaceStorageEstimateV1.requiredBytes(
                    for: request.command
                )
            )
        } catch {
            throw WorkspaceMutationFailureV1.storageAdmissionFailed
        }
        defer {
            if let storageReservation {
                storageAdmission?.release(reservation: storageReservation)
            }
        }

        isExecuting = true
        defer { isExecuting = false }
        do {
            let applied = try adapter.apply(
                request.command,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
            guard applied == effect else {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
            if case let .applyActivityContract(mutation) = request.command {
                guard journalStore != nil else {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                try adapter.persistAppliedActivityContractEffect(mutation)
            }
            if let journalStore {
                try journalStore.reach(.afterEffectBeforeReceipt)
                let basis: ReversalBasisV1?
                if let reversalPlan {
                    guard reversalPlan.mutationID == request.mutationID,
                          reversalPlan.commandKind == request.command.kind,
                          reversalPlan.expectedRevision == request.expectedRevision else {
                        throw WorkspaceMutationFailureV1.invalidReversal
                    }
                    basis = try ReversalBasisV1(
                        targetMutationID: request.mutationID,
                        targetReceiptIdentity: MutationReceiptIdentityV1(
                            workspaceID: identity.workspaceID,
                            replicaID: identity.replicaID,
                            localSequence: try journalStore.nextLocalSequence()
                        ),
                        plan: reversalPlan
                    )
                } else if let portableReversalPlan {
                    let targetReceiptIdentity = MutationReceiptIdentityV1(
                        workspaceID: identity.workspaceID,
                        replicaID: identity.replicaID,
                        localSequence: try journalStore.nextLocalSequence()
                    )
                    let rebound = try PortableReversalPlanV1(
                        targetMutationID: request.mutationID,
                        targetReceiptIdentity: targetReceiptIdentity,
                        expectedRevision: MutationPortableExpectedRevisionV1(
                            request.expectedRevision
                        ),
                        planDigest: portableReversalPlan.planDigest,
                        compensatingCommands: portableReversalPlan.compensatingCommands
                    )
                    basis = try ReversalBasisV1(
                        portablePlan: rebound,
                        targetReceiptIdentity: targetReceiptIdentity
                    )
                } else {
                    basis = nil
                }
                let receipt = try journalStore.commit(
                    envelope: envelope,
                    writerInstanceID: writerInstanceID,
                    affectedEntities: applied.affectedEntities,
                    committedAt: occurredAt,
                    reversalBasis: basis,
                    semanticReversalExecution: semanticReversalExecution
                )
                let after = try revision(from: receipt.resultingRevision)
                return try notifyingSearchIndex(WorkspaceMutationOutcomeV1(
                    mutationID: request.mutationID,
                    commandDigest: digest,
                    occurredAt: occurredAt,
                    before: before,
                    after: after,
                    effect: applied
                ))
            }
        } catch let failure as MutationJournalFailureV1 {
            adapter.rollback()
            throw failure
        } catch let error as WorkspaceMutationFailureV1 {
            adapter.rollback()
            throw error
        } catch {
            adapter.rollback()
            throw WorkspaceMutationFailureV1.persistenceFailed
        }

        workspaceRevision += 1
        if case let .applyAssetPlacementChange(plan) = request.command {
            entityRevisions[try .init(kind: .asset, id: plan.basis.assetID), default: 0] += 1
            entityRevisions[try .init(kind: .assetPlacementEvent, id: plan.newEventID)] = 1
            for event in plan.poseEvents {
                entityRevisions[try .init(kind: .assetPoseEvent, id: event.eventID)] = event.revision
            }
        } else if case let .applyAuthorityCriterion(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity] = mutation.postImage.revision
        } else if case let .applyFunctionalRelationship(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity] = mutation.postImage.revision
        } else if case let .applyEvidenceAssurance(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity] = mutation.postImage.revision
        } else if case let .applyInspectionReview(mutation) = request.command {
            for image in try mutation.postImage.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyWorkPacket(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity]=mutation.postImage.revision
        } else if case let .applyFieldDraft(mutation) = request.command {
            for image in try mutation.postImage.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyPackagePromotion(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyMeasurementIntegrity(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyPrivacyTransform(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyEvidenceMetadata(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyClientCapability(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity]=mutation.revision
        } else if case let .applyFieldReference(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity]=mutation.revision
        } else if case let .applyAccessibleDocumentAssessment(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity]=mutation.revision
        } else if case let .applySurveyDefinition(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applySurveySession(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyAssetLocator(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applySchedule(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyPlan(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyPlacementPose(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyEvidenceContext(operation) = request.command {
            entityRevisions[try operation.affectedIdentity]=operation.revision
        } else if case let .applyLighting(operation) = request.command {
            entityRevisions[try operation.affectedIdentity]=operation.revision
        } else if case let .applyLightingDayInventory(operation) = request.command {
            entityRevisions[try operation.affectedIdentity] = operation.workflow.revision
        } else if case let .applyLightingNightWorkflow(operation) = request.command {
            entityRevisions[try operation.affectedIdentity] = operation.workflow.revision
        } else if case let .applyAssistanceAcceptance(acceptance) = request.command {
            switch acceptance.targetMutation {
            case .surveySession(let mutation):
                for image in try mutation.mutationPostImages {
                    entityRevisions[try image.identity] = image.revision
                }
            }
        } else if case let .applyTemporalEvidence(mutation) = request.command {
            for image in try mutation.mutationPostImages{entityRevisions[try image.identity]=image.revision}
        } else if case let .applyAssetLabel(mutation) = request.command {
            let image = try mutation.mutationPostImage
            entityRevisions[try image.identity] = image.revision
        } else if case let .applyOperationalContact(mutation) = request.command {
            for image in try mutation.mutationPostImages {
                entityRevisions[try image.identity] = image.revision
            }
        } else if case let .applyPartyContactSiteRoleImport(mutation) = request.command {
            for image in try mutation.mutationPostImages {
                entityRevisions[try image.identity] = image.revision
            }
        } else if case let .applyActivityContract(mutation) = request.command {
            for image in try mutation.mutationPostImages {
                entityRevisions[try image.identity] = image.revision
            }
        } else if case let .applyPortableReview(mutation) = request.command {
            for image in try mutation.mutationPostImages {
                entityRevisions[try image.identity] = image.revision
            }
        } else if case let .applyWorkResource(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity] = mutation.postImage.revision
        } else if case let .applyPartsStock(mutation) = request.command {
            for image in try mutation.mutationPostImages {
                if case let .partsStock(id, kind, concurrency, revision, _) = image {
                    let physical = try WorkspaceEntityIdentityV1(kind: kind, id: id)
                    entityRevisions[physical] = revision
                    entityRevisions[concurrency] = revision
                } else {
                    entityRevisions[try image.identity] = image.revision
                    entityRevisions[try image.concurrencyIdentity] = image.revision
                }
            }
        } else if case let .applyMyDay(mutation) = request.command {
            for image in try mutation.mutationPostImages {
                entityRevisions[try image.identity] = image.revision
            }
        } else if case let .applyServiceRequest(mutation) = request.command {
            for image in try mutation.mutationPostImages {
                entityRevisions[try image.identity] = image.revision
            }
        } else if case let .applyServiceReliability(bundle) = request.command {
            for image in try bundle.mutationPostImages { entityRevisions[try image.identity]=image.revision }
        } else if case let .applyShopReportProfile(mutation) = request.command {
            let image = try mutation.mutationPostImage
            entityRevisions[try image.identity] = image.revision
        } else if case let .applyRoundSession(mutation) = request.command {
            let image = try mutation.mutationPostImage
            entityRevisions[try image.identity] = image.revision
        } else if case let .applyImportBulk(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentity] = mutation.expectedRevision + 1
        } else if case let .applyEvidenceQuality(mutation) = request.command {
            let target = try mutation.affectedIdentityForCanonicalWriter()
            let expected = request.expectedRevision.entityRevisions.first(where: { $0.identity == target })?.revision ?? 0
            entityRevisions[target] = expected + 1
        } else if case let .applyFastSurveyInbox(mutation) = request.command {
            for target in try mutation.affectedIdentitiesForCanonicalWriter() {
                let expected = request.expectedRevision.entityRevisions.first(where: { $0.identity == target })?.revision ?? 0
                entityRevisions[target] = expected + 1
            }
        } else if case let .applyReinspectionException(mutation) = request.command {
            for target in try mutation.affectedIdentitiesForCanonicalWriter() {
                let expected = request.expectedRevision.entityRevisions.first(where: { $0.identity == target })?.revision ?? 0
                entityRevisions[target] = expected + 1
            }
        } else if case let .applyEntityIdentityResolution(mutation) = request.command {
            let target = try Self.entityIdentityResolutionConcurrencyIdentity(mutation)
            entityRevisions[target] = try Self.entityIdentityResolutionLineageRevision(mutation)
        } else if case let .applyWorkspaceExperience(mutation) = request.command {
            entityRevisions[try mutation.affectedIdentityForCanonicalWriter()] = mutation.provenance.revision
        } else {
            for target in targets { entityRevisions[target, default: 0] += 1 }
        }
        if case let .applyLocationHierarchyChange(value) = request.command {
            for placement in value.placementChanges {
                for event in placement.poseEvents {
                    entityRevisions[try .init(kind: .assetPoseEvent, id: event.eventID)] = event.revision
                }
            }
        }
        let after = try currentRevision()
        let outcome = WorkspaceMutationOutcomeV1(
            mutationID: request.mutationID,
            commandDigest: digest,
            occurredAt: occurredAt,
            before: before,
            after: after,
            effect: effect
        )
        remembered[request.mutationID] = RememberedMutation(digest: digest, outcome: outcome)
        return try notifyingSearchIndex(outcome)
    }

    private func notifyingSearchIndex(
        _ outcome: WorkspaceMutationOutcomeV1
    ) throws -> WorkspaceMutationOutcomeV1 {
        let source = try SearchSourceRevisionV1(
            workspaceID: identity.workspaceID.rawValue,
            generationID: generationID,
            commitRevision: outcome.after.revision
        )
        try searchIndexInvalidation?(source)
        return outcome
    }

    func durableReceipt(mutationID: MutationIDV1) throws -> MutationReceiptV1? {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { return nil }
        return try journalStore.receipt(mutationID: mutationID)
    }

    func invalidate() {
        isActive = false
        remembered.removeAll(keepingCapacity: false)
        quarantined.removeAll(keepingCapacity: false)
    }

    private func require(
        _ expected: WorkspaceExpectedRevisionV1,
        targets: [WorkspaceEntityIdentityV1]
    ) throws {
        guard expected.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard expected.generationID == generationID else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        guard expected.writerInstanceID == writerInstanceID else {
            throw WorkspaceMutationFailureV1.wrongWriterInstance
        }
        let current = try currentRevision()
        guard expected.workspaceRevision == current.revision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let expectedByID = Dictionary(
            uniqueKeysWithValues: expected.entityRevisions.map { ($0.identity, $0.revision) }
        )
        guard targets.allSatisfy({ expectedByID[$0] != nil }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let currentByID = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        for identity in targets where expectedByID[identity, default: 0] != currentByID[identity, default: 0] {
            throw WorkspaceMutationFailureV1.staleEntityRevision(identity)
        }
    }

    private func importedRequest(
        mutationID: MutationIDV1,
        command: WorkspaceCommandV1,
        expectedRevision: MutationPortableExpectedRevisionV1? = nil
    ) throws -> WorkspaceMutationRequestV1 {
        let expected: WorkspaceExpectedRevisionV1
        if let expectedRevision {
            expected = try WorkspaceExpectedRevisionV1(
                workspaceID: identity.workspaceID,
                generationID: generationID,
                writerInstanceID: writerInstanceID,
                workspaceRevision: expectedRevision.workspaceRevision,
                entityRevisions: expectedRevision.entityRevisions
            )
        } else {
            let current = try currentRevision()
            let targets = try Self.expectedRevisionIdentities(for: command)
            let known = Dictionary(
                uniqueKeysWithValues: current.entityRevisions.map {
                    ($0.identity, $0.revision)
                }
            )
            expected = try WorkspaceExpectedRevisionV1(
                workspaceID: identity.workspaceID,
                generationID: generationID,
                writerInstanceID: writerInstanceID,
                workspaceRevision: current.revision,
                entityRevisions: targets.map {
                    WorkspaceEntityRevisionV1(
                        identity: $0,
                        revision: known[$0, default: 0]
                    )
                }
            )
        }
        return WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: expected,
            command: command
        )
    }

    private func importedReplayMatches(
        _ change: JournalChangeV1,
        prior: MutationReceiptV1,
        effectiveSourceKind: MutationSourceKindV1,
        journalStore: MutationJournalStoreV1
    ) throws -> Bool {
        let priorPostImageIdentities = try prior.postImages.map { try $0.identity }
        let incomingPostImageIdentities = try change.receipt.postImages.map {
            try $0.identity
        }
        guard prior.sourceKind == effectiveSourceKind,
              prior.mutationID == change.envelope.mutationID,
              prior.commandBodySHA256 == change.envelope.commandBodySHA256,
              prior.contentDependencyIDs == change.envelope.contentDependencyIDs,
              prior.causationMutationID == change.envelope.causationMutationID,
              priorPostImageIdentities == incomingPostImageIdentities,
              prior.reversesMutationID
                == change.semanticReversalReceipt?.reversesMutationID else {
            return false
        }
        if effectiveSourceKind == .semanticReversal {
            guard let sourceExecution = change.envelope.semanticReversalExecution,
                  let sourceReceipt = change.semanticReversalReceipt,
                  let targetReceipt = try journalStore.receipt(
                    mutationID: sourceExecution.targetMutationID
                  ),
                  let targetBasis = try journalStore.reversalBasis(
                    mutationID: sourceExecution.targetMutationID
                  ),
                  prior.reversesMutationID == sourceExecution.targetMutationID,
                  sourceReceipt.reversesMutationID == sourceExecution.targetMutationID,
                  sourceReceipt.targetReceiptIdentity
                    == sourceExecution.targetReceiptIdentity,
                  sourceReceipt.reversalBasisSHA256
                    == sourceExecution.reversalBasisSHA256,
                  sourceReceipt.compensatingMutationIDs
                    == [change.envelope.mutationID],
                  targetBasis.targetReceiptIdentity == targetReceipt.identity,
                  sourceExecution.targetReceiptIdentity == change.semanticReversalReceipt?.targetReceiptIdentity else {
                return false
            }
            return sourceReceipt.planDigest == targetBasis.planDigest
                && sourceExecution.planDigest == sourceReceipt.planDigest
                && sourceExecution.compensatingMutationIDs
                    == sourceReceipt.compensatingMutationIDs
                && targetBasis.compensatingCommandKinds == [change.envelope.command.kind]
        }

        let acceptedBasis = try journalStore.reversalBasis(
            mutationID: change.envelope.mutationID
        )
        guard (acceptedBasis == nil) == (change.portableReversalPlan == nil) else {
            return false
        }
        guard let portable = change.portableReversalPlan else { return true }
        return acceptedBasis?.planDigest == portable.planDigest
            && acceptedBasis?.compensatingCommandKinds
                == portable.compensatingCommands.map(\.kind)
    }

    /// Forces the existing durable replay-conflict path for a source change
    /// that reused an accepted mutation ID and provenance correlation while
    /// changing invariant receipt or body data. No adapter effect is applied.
    private func quarantineChangedImportedReplay(
        _ change: JournalChangeV1,
        prior: MutationReceiptV1,
        sourceInputSHA256: String,
        journalStore: MutationJournalStoreV1
    ) throws -> Never {
        let request = try importedRequest(
            mutationID: change.envelope.mutationID,
            command: change.envelope.command,
            expectedRevision: prior.expectedRevision
        )
        let correlationID = try Self.conflictingCorrelationID(
            sourceInputSHA256: sourceInputSHA256,
            accepted: prior.correlationID
        )
        let probe = try MutationEnvelopeV1(
            request: request,
            identity: identity,
            sourceKind: .importedHistory,
            contentDependencyIDs: change.envelope.contentDependencyIDs,
            correlationID: correlationID,
            reversalPlanDigest: change.portableReversalPlan?.planDigest
        )
        _ = try journalStore.resolveReplay(
            envelope: probe,
            detectedAt: clock.now()
        )
        throw WorkspaceMutationFailureV1.mutationIDQuarantined
    }

    private static func correlationID(sourceInputSHA256: String) throws -> UUID {
        guard MutationEnvelopeV1.isSHA256(sourceInputSHA256) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        var bytes = stride(from: 0, to: 32, by: 2).compactMap { offset in
            UInt8(
                sourceInputSHA256[
                    sourceInputSHA256.index(
                        sourceInputSHA256.startIndex,
                        offsetBy: offset
                    )..<sourceInputSHA256.index(
                        sourceInputSHA256.startIndex,
                        offsetBy: offset + 2
                    )
                ],
                radix: 16
            )
        }
        guard bytes.count == 16 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func conflictingCorrelationID(
        sourceInputSHA256: String,
        accepted: UUID?
    ) throws -> UUID {
        let derived = try correlationID(sourceInputSHA256: sourceInputSHA256)
        guard derived == accepted else { return derived }
        let alternate = UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)
        )
        guard alternate == accepted else { return alternate }
        return UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 2)
        )
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    private func outcome(
        from receipt: MutationReceiptV1,
        request: WorkspaceMutationRequestV1,
        digest: String,
        occurredAt: Date
    ) throws -> WorkspaceMutationOutcomeV1 {
        let temporaryRelativePath = try fileAuthority.temporaryRelativePath(
            mutationID: request.mutationID,
            component: request.command.kind.rawValue
        )
        let entities = try receipt.postImages.map { try $0.identity }
        return WorkspaceMutationOutcomeV1(
            mutationID: receipt.mutationID,
            commandDigest: digest,
            occurredAt: receipt.committedAt,
            before: try revision(from: receipt.expectedRevision),
            after: try revision(from: receipt.resultingRevision),
            effect: try WorkspaceMutationEffectV1(
                affectedEntities: entities,
                temporaryRelativePath: temporaryRelativePath
            )
        )
    }

    private func revision(from value: MutationPortableExpectedRevisionV1) throws -> WorkspaceRevisionV1 {
        try WorkspaceRevisionV1(
            workspaceID: value.workspaceID,
            generationID: value.generationID,
            writerInstanceID: writerInstanceID,
            revision: value.workspaceRevision,
            entityRevisions: value.entityRevisions
        )
    }

    private static func targetIdentities(
        for command: WorkspaceCommandV1
    ) throws -> [WorkspaceEntityIdentityV1] {
        let values: [WorkspaceEntityIdentityV1]
        switch command {
        case let .createFirstSign(value):
            var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
            if let site = value.newSite {
                identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
            }
            if let placementEventID = value.initialPlacementEventID {
                identities.append(try WorkspaceEntityIdentityV1(
                    kind: .assetPlacementEvent,
                    id: placementEventID
                ))
            }
            values = identities
        case let .createCheckDraft(value):
            values = [try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID)]
        case let .acceptCheckEvidence(value):
            values = try [
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.draftID),
                WorkspaceEntityIdentityV1(kind: .evidenceFile, id: value.evidenceID),
            ]
        case let .updateSiteTimeZone(value):
            values = [try WorkspaceEntityIdentityV1(kind: .site, id: value.siteID)]
        case let .deleteAsset(value):
            try requireOperationID(value.deletionID)
            try requireDigest(value.planDigest)
            values = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        case let .deleteSite(value):
            try requireOperationID(value.deletionID)
            try requireDigest(value.planDigest)
            values = [try WorkspaceEntityIdentityV1(kind: .site, id: value.siteID)]
        case let .eraseWorkspace(value):
            try requireOperationID(value.eraseID)
            try requireOperationID(value.targetGenerationID)
            try requireDigest(value.oldPointerDigest)
            try requireDigest(value.emptyLedgerDigest)
            values = []
        case let .finalizeCheck(value):
            try requireOperationID(value.finalizationMutationID)
            try requireDigest(value.semanticDigest)
            guard value.contentDigests.count <= 256,
                  Set(value.contentDigests).count == value.contentDigests.count else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            try value.contentDigests.forEach { try requireDigest($0) }
            var identities = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID),
                WorkspaceEntityIdentityV1(kind: .packet, id: value.packetID),
                WorkspaceEntityIdentityV1(kind: .report, id: value.reportID),
            ]
            if let issueID = value.issueID {
                identities.append(try WorkspaceEntityIdentityV1(kind: .issue, id: issueID))
            }
            values = identities
        case let .finalizeCorrection(value):
            try requireOperationID(value.finalizationMutationID)
            try requireDigest(value.semanticDigest)
            values = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.correctionRecordID),
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.revisesRecordID),
                WorkspaceEntityIdentityV1(kind: .packet, id: value.packetID),
                WorkspaceEntityIdentityV1(kind: .report, id: value.reportID),
                WorkspaceEntityIdentityV1(kind: .report, id: value.replacesReportID),
            ]
        case let .recordWork(value):
            try requireOperationID(value.workMutationID)
            try requireDigest(value.semanticDigest)
            guard value.evidenceIDs.count <= 256,
                  Set(value.evidenceIDs).count == value.evidenceIDs.count else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            var identities = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
                WorkspaceEntityIdentityV1(kind: .issue, id: value.issueID),
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID),
            ]
            identities.append(contentsOf: try value.evidenceIDs.map {
                try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: $0)
            })
            values = identities
        case let .restoreWorkspace(value):
            try requireOperationID(value.restoreID)
            try requireOperationID(value.targetGenerationID)
            try requireDigest(value.sourceArchiveDigest)
            guard BackupRestoreMode(rawValue: value.mode) != nil else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            values = []
        case let .archiveEntities(value):
            guard value.identities.count <= 256,
                  !value.reason.isEmpty,
                  value.reason.count <= 4_096 else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            values = value.identities
        case let .applyLocationHierarchyChange(value):
            try value.plan.validate()
            let plan = value.plan
            guard plan.beforeNodes.allSatisfy({ $0.workspaceID == plan.workspaceID }),
                  plan.afterNodes.allSatisfy({ $0.workspaceID == plan.workspaceID }) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let nodeIDs = Set(plan.beforeNodes.map(\.id)).union(plan.afterNodes.map(\.id))
            let poseEventCount = value.placementChanges.reduce(0) { $0 + $1.poseEvents.count }
            guard nodeIDs.count + value.placementChanges.count * 2 + poseEventCount
                    <= MutationReceiptV1.maximumPostImageCount else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            var identities = try nodeIDs.map {
                try WorkspaceEntityIdentityV1(kind: .locationNode, id: $0)
            }
            for placement in value.placementChanges {
                identities.append(try .init(kind: .asset, id: placement.basis.assetID))
                identities.append(try .init(kind: .assetPlacementEvent, id: placement.newEventID))
                identities.append(contentsOf: try placement.poseEvents.map {
                    try .init(kind: .assetPoseEvent, id: $0.eventID)
                })
            }
            values = identities
        case let .applyAssetPlacementChange(plan):
            try plan.validate()
            guard plan.mutationID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                  plan.basis.currentPlacement?.id != plan.newEventID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            values = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: plan.basis.assetID),
                WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: plan.newEventID),
            ] + plan.poseEvents.map { try WorkspaceEntityIdentityV1(kind: .assetPoseEvent, id: $0.eventID) }
        case let .applyAssetCompositionChange(plan):
            try plan.validate()
            values = try [
                WorkspaceEntityIdentityV1(kind: .assetCompositionEdge, id: plan.event.edge.id),
                WorkspaceEntityIdentityV1(kind: .assetCompositionEvent, id: plan.event.id),
            ]
        case let .applySavedSmartView(value):
            try value.validate()
            values = [try WorkspaceEntityIdentityV1(kind: .savedSmartView, id: value.id)]
        case let .applyRequirementAssurance(value):
            try value.validate()
            values = [try WorkspaceEntityIdentityV1(
                kind: .workflowRecord,
                id: value.snapshot.workflowRecordID
            )]
        case let .applyPartyAccountability(value):
            try value.validate()
            values = [try value.affectedIdentity]
        case let .applyPartyContactSiteRoleImport(value):
            try value.validate()
            values = try value.affectedIdentities
        case let .applyAssetSemantics(value):
            try value.validate()
            values = [try value.affectedIdentity]
        case let .applyAuthorityCriterion(value):
            try value.validate()
            values = [try value.affectedIdentity]
        case let .applyFunctionalRelationship(value):
            try value.validate()
            values = [try value.affectedIdentity]
        case let .applyEvidenceAssurance(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyInspectionReview(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyWorkPacket(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyFieldDraft(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyPackagePromotion(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyMeasurementIntegrity(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyPrivacyTransform(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyEvidenceMetadata(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyClientCapability(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyFieldReference(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyAccessibleDocumentAssessment(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applySurveyDefinition(value):
            try value.validate();values=try value.affectedIdentities
        case let .applySurveySession(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyAssetLocator(value):
            try value.validate();values=try value.affectedIdentities
        case let .applySchedule(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyPlan(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyPlacementPose(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyEvidenceContext(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyLighting(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyLightingDayInventory(value):
            try value.validate(); values = [try value.affectedIdentity]
        case let .applyLightingNightWorkflow(value):
            try value.validate(); values = [try value.affectedIdentity]
        case let .applyAssistanceAcceptance(value):
            try value.validate();values=try value.targetMutation.affectedIdentities
        case let .applyTemporalEvidence(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyAssetLabel(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyOperationalContact(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyActivityContract(value):
            try value.validateForCanonicalMutation();values=try value.affectedIdentities
        case let .applyPortableReview(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyWorkResource(value):
            try value.validate();values=try value.affectedIdentities
        case let .applyPartsStock(value):
            try value.validate(); values = try value.affectedIdentities
        case let .applyMyDay(value):
            try value.validate(); values = try value.affectedIdentities
        case let .applyServiceRequest(value):
            try value.validateForCanonicalWriter();values=try value.affectedIdentities
        case let .applyServiceReliability(value):
            try value.validateForCanonicalWriter();values=try value.affectedIdentities
        case let .applyShopReportProfile(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyRoundSession(value):
            try value.validate();values=[try value.affectedIdentity]
        case let .applyImportBulk(value):
            try value.validate(); values = [try value.affectedIdentity]
        case let .applyEvidenceQuality(value):
            try value.validate(); values = [try value.affectedIdentityForCanonicalWriter()]
        case let .applyFastSurveyInbox(value):
            try value.validate(); values = try value.affectedIdentitiesForCanonicalWriter()
        case let .applyReinspectionException(value):
            try value.validate(); values = try value.affectedIdentitiesForCanonicalWriter()
        case let .applyEntityIdentityResolution(value):
            try value.validateForCanonicalWriter(); values = [try Self.entityIdentityResolutionConcurrencyIdentity(value)]
        case let .applyWorkspaceExperience(value):
            try value.validateForCanonicalWriter(); values = [try value.affectedIdentityForCanonicalWriter()]
        }
        guard Set(values).count == values.count else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return values
    }

    private static func expectedRevisionIdentities(
        for command: WorkspaceCommandV1
    ) throws -> [WorkspaceEntityIdentityV1] {
        if case let .applyLocationHierarchyChange(value) = command {
            var identities = try targetIdentities(for: command).filter { $0.kind != .assetPoseEvent }
            for placement in value.placementChanges {
                identities.append(contentsOf: try placement.poseEventPredecessors.map {
                    try .init(kind: .assetPoseEvent, id: $0.eventID)
                })
            }
            return identities
        }
        if case let .applyAssetPlacementChange(plan) = command {
            try plan.validate()
            return try ([WorkspaceEntityIdentityV1(kind: .asset, id: plan.basis.assetID),
                         WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: plan.newEventID)]
                + plan.poseEventPredecessors.map { try WorkspaceEntityIdentityV1(kind: .assetPoseEvent, id: $0.eventID) })
        }
        if case let .applyAuthorityCriterion(value) = command {
            try value.validate()
            return [try value.concurrencyIdentity]
        }
        if case let .applyFunctionalRelationship(value) = command {
            try value.validate()
            return [try value.concurrencyIdentity]
        }
        if case let .applyEvidenceAssurance(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyInspectionReview(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyWorkPacket(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyFieldDraft(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyPackagePromotion(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyMeasurementIntegrity(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyPrivacyTransform(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyEvidenceMetadata(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyClientCapability(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyFieldReference(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyAccessibleDocumentAssessment(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applySurveyDefinition(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applySurveySession(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyAssetLocator(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applySchedule(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyPlan(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyPlacementPose(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyEvidenceContext(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyLighting(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyLightingDayInventory(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyLightingNightWorkflow(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyAssistanceAcceptance(value)=command{try value.validate();return try value.targetMutation.concurrencyIdentities}
        if case let .applyTemporalEvidence(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyAssetLabel(value)=command{try value.validate();return[try value.affectedIdentity]}
        if case let .applyOperationalContact(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyPartyContactSiteRoleImport(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyActivityContract(value)=command{try value.validateForCanonicalMutation();return try value.concurrencyIdentities}
        if case let .applyPortableReview(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyWorkResource(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyPartsStock(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyMyDay(value)=command{try value.validate();return try value.concurrencyIdentities}
        if case let .applyServiceRequest(value)=command{try value.validateForCanonicalWriter();return try value.concurrencyIdentities}
        if case let .applyServiceReliability(value)=command{try value.validateForCanonicalWriter();return try value.concurrencyIdentities}
        if case let .applyShopReportProfile(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyRoundSession(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyImportBulk(value)=command{try value.validate();return[try value.concurrencyIdentity]}
        if case let .applyEvidenceQuality(value)=command{try value.validate();return[try value.affectedIdentityForCanonicalWriter()]}
        if case let .applyFastSurveyInbox(value)=command{try value.validate();return try value.affectedIdentitiesForCanonicalWriter()}
        if case let .applyReinspectionException(value)=command{try value.validate();return try value.affectedIdentitiesForCanonicalWriter()}
        if case let .applyEntityIdentityResolution(value)=command{try value.validateForCanonicalWriter();return [try entityIdentityResolutionConcurrencyIdentity(value)]}
        if case let .applyWorkspaceExperience(value)=command{try value.validateForCanonicalWriter();return [try value.affectedIdentityForCanonicalWriter()]}
        return try targetIdentities(for: command)
    }

    /// C13 revisions serialize logical identity chains, never the append-only
    /// event/receipt identifiers.  The latter remain immutable payload facts.
    private static func entityIdentityResolutionConcurrencyIdentity(
        _ command: EntityIdentityResolutionMutationCommandV1
    ) throws -> WorkspaceEntityIdentityV1 {
        try command.validateForCanonicalWriter()
        switch command.payload {
        case let .alias(value, _):
            return try .init(kind: .entityAliasLink, id: value.alias.identity.id)
        case let .consolidation(value, _):
            return try .init(kind: .entityConsolidationReceipt, id: value.source.identity.id)
        }
    }

    private static func entityIdentityResolutionLineageRevision(
        _ command: EntityIdentityResolutionMutationCommandV1
    ) throws -> UInt64 {
        try command.validateForCanonicalWriter()
        switch command.payload {
        case let .alias(value, _): return value.revision
        case let .consolidation(value, _): return value.revision
        }
    }

    private static func validateEntityIdentityResolutionLineage(
        _ command: EntityIdentityResolutionMutationCommandV1,
        currentRevision: WorkspaceRevisionV1
    ) throws {
        let target = try entityIdentityResolutionConcurrencyIdentity(command)
        let expectedRows = command.expectedRevision.entityRevisions.filter { $0.identity == target }
        let currentRows = currentRevision.entityRevisions.filter { $0.identity == target }
        guard expectedRows.count == 1, currentRows.count <= 1,
              currentRevision.workspaceID == command.expectedRevision.workspaceID,
              currentRevision.generationID == command.expectedRevision.generationID,
              currentRevision.writerInstanceID == command.expectedRevision.writerInstanceID,
              currentRevision.revision == command.expectedRevision.workspaceRevision,
              expectedRows[0].revision == (currentRows.first?.revision ?? 0) else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let (nextRevision, overflow) = expectedRows[0].revision.addingReportingOverflow(1)
        guard !overflow, nextRevision == (try entityIdentityResolutionLineageRevision(command)) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private static func validateC51ScheduleMutation(_ mutation: ScheduleMutationV1) throws {
        let postImages = try mutation.mutationPostImages
        switch mutation.payload {
        case .appendExceptionCalendarRelease:
            guard postImages.count == 1,
                  try postImages[0].identity.kind == .exceptionCalendarRelease else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        case .appendOverrideEvent:
            guard postImages.count == 1,
                  try postImages[0].identity.kind == .scheduleOverrideEvent else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        default:
            return
        }
    }

    private static func requireOperationID(_ value: UUID) throws {
        _ = try MutationIDV1(rawValue: value)
    }

    private static func requireDigest(_ value: String) throws {
        guard value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

}

extension WorkspaceWriterV1: PlanRebaseWorkspaceWritingV1 {
    func commitPlan(_ mutation: PlanMutationV1) throws -> MutationReceiptV1 {
        try mutation.validate()
        switch mutation.payload {
        case .appendDocument, .appendRevision, .appendPlacement:
            break
        case .applyRebase, .recordRebaseRejection:
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return try commitValidatedPlan(mutation)
    }

    private func commitValidatedPlan(_ mutation: PlanMutationV1) throws -> MutationReceiptV1 {
        let current = try currentRevision()
        let targets = try mutation.concurrencyIdentities
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        guard try targets.allSatisfy({ known[$0, default: 0] == (try mutation.expectedRevision(for: $0)) }) else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: try targets.map {
                .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
            }
        )
        _ = try execute(.init(mutationID: mutation.mutationID, expectedRevision: expected,
                              command: .applyPlan(mutation)))
        guard let receipt = try journalStore?.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try PlanMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
        return receipt
    }
}

extension WorkspaceWriterV1 {
    func commitPlacementPose(_ mutation: PlacementPoseMutationV1) throws -> MutationReceiptV1 {
        try mutation.validate()
        let current = try currentRevision()
        let targets = try mutation.concurrencyIdentities
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        guard try targets.allSatisfy({ known[$0, default: 0] == (try mutation.expectedRevision(for: $0)) }) else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID,
            generationID: current.generationID, writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision, entityRevisions: try targets.map {
                .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
            })
        _ = try execute(.init(mutationID: mutation.mutationID, expectedRevision: expected,
                              command: .applyPlacementPose(mutation)))
        guard let receipt = try journalStore?.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try PlacementPoseMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
        return receipt
    }
}

// MARK: - C55 parts-stock sole writer

extension WorkspaceWriterV1: PartsStockCanonicalWriterPortV1 {
    func commitPartsStock(_ mutation: PartsStockMutationV1) throws -> PartsStockMutationReceiptV1 {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.receipt(mutationID: mutation.mutationID) {
            let commandDigest = try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyPartsStock(mutation))
            guard existing.identity.workspaceID == mutation.workspaceID,
                  existing.commandBodySHA256 == commandDigest else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return try PartsStockMutationReceiptV1(
                workspaceID: mutation.workspaceID,
                mutationID: mutation.mutationID,
                mutationSHA256: try PartsStockCanonicalCodecV1.sha256(mutation),
                committedAt: existing.committedAt
            )
        }
        let current = try currentRevision()
        let targets = try mutation.concurrencyIdentities
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        guard mutation.workspaceID == current.workspaceID,
              try targets.allSatisfy({ known[$0, default: 0] == (try mutation.expectedRevision(for: $0)) }) else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: try targets.map { .init(identity: $0, revision: try mutation.expectedRevision(for: $0)) }
        )
        _ = try execute(.init(mutationID: mutation.mutationID, expectedRevision: expected, command: .applyPartsStock(mutation)))
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        return try PartsStockMutationReceiptV1(workspaceID: mutation.workspaceID, mutationID: mutation.mutationID, mutationSHA256: try PartsStockCanonicalCodecV1.sha256(mutation), committedAt: receipt.committedAt)
    }
}

// MARK: - C57 My Day sole writer

extension WorkspaceWriterV1 {
    func commitMyDay(_ mutation: MyDayMutationV1) throws -> MyDayMutationReceiptV1 {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        let command = WorkspaceCommandV1.applyMyDay(mutation)
        let commandDigest = try WorkspaceMutationCanonicalV1.sha256(command)
        if let existing = try journalStore.receipt(mutationID: mutation.mutationID) {
            guard existing.identity.workspaceID == mutation.workspaceID,
                  existing.commandBodySHA256 == commandDigest,
                  try adapter.persistedMyDayEffectMatches(mutation) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let prior = try MyDayMutationReceiptV1(
                command: mutation.command,
                resultingPlan: mutation.resultingPlan,
                carryoverReceipt: mutation.carryoverReceipt,
                disposition: .committed,
                committedAt: existing.committedAt
            )
            return try MyDayCommandReplayResolutionV1.resolve(
                command: mutation.command,
                priorReceipt: prior
            ).receipt
        }
        let current = try currentRevision()
        let targets = try mutation.concurrencyIdentities
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        guard current.workspaceID == mutation.workspaceID,
              mutation.expectedRevision.workspaceID == current.workspaceID,
              mutation.expectedRevision.generationID == current.generationID,
              mutation.expectedRevision.writerInstanceID == current.writerInstanceID,
              mutation.expectedRevision.workspaceRevision == current.revision,
              try targets.allSatisfy({ known[$0, default: 0] == (try mutation.expectedRevision(for: $0)) }) else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        _ = try execute(.init(
            mutationID: mutation.mutationID,
            expectedRevision: mutation.expectedRevision,
            command: command
        ))
        guard let persisted = try journalStore.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try MyDayWorkspaceMutationReceiptV1(mutation: mutation, mutationReceipt: persisted)
        return try MyDayMutationReceiptV1(
            command: mutation.command,
            resultingPlan: mutation.resultingPlan,
            carryoverReceipt: mutation.carryoverReceipt,
            disposition: .committed,
            committedAt: persisted.committedAt
        )
    }
}

// MARK: - C57 My Day application writer bridge

extension WorkspaceWriterV1: MyDayWritingV1 {
    func currentPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1? {
        try key.validate()
        guard key.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        return try adapter.currentMyDayPlan(for: key)
    }

    func result(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) throws -> MyDayCommandResultV1? {
        guard workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard let journalStore,
              let mutation = try journalStore.myDayMutation(mutationID: mutationID),
              let journalReceipt = try journalStore.receipt(mutationID: mutationID) else {
            return nil
        }
        _ = try MyDayWorkspaceMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: journalReceipt
        )
        let receipt = try MyDayMutationReceiptV1(
            command: mutation.command,
            resultingPlan: mutation.resultingPlan,
            carryoverReceipt: mutation.carryoverReceipt,
            disposition: .committed,
            committedAt: journalReceipt.committedAt
        )
        let value = MyDayCommandResultV1(plan: mutation.resultingPlan, receipt: receipt)
        try value.validate()
        try receipt.validate(command: mutation.command)
        return value
    }

    func commit(_ command: MyDayCommandV1) throws -> MyDayCommandResultV1 {
        try command.validate()
        guard command.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        let current = try currentRevision()
        let targetPlan: MyDayPlanV1
        var identities: [WorkspaceEntityIdentityV1] = []
        switch command {
        case let .save(successor, _):
            targetPlan = successor
            identities.append(try .init(kind: .myDayPlan, id: successor.planID))
        case let .carryover(_, source, target, _):
            targetPlan = target
            identities.append(try .init(kind: .myDayPlan, id: source.planID))
            identities.append(try .init(kind: .myDayPlan, id: target.planID))
            identities.append(try .init(kind: .myDayCarryoverReceipt, id: command.mutationID.rawValue))
        }
        let targets = Array(Set(identities)).sorted { $0.stableKey < $1.stableKey }
        let revisions = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: targets.map {
                .init(identity: $0, revision: revisions[$0, default: 0])
            }
        )
        let mutation = try MyDayMutationV1(command: command, expectedRevision: expected)
        let receipt = try commitMyDay(mutation)
        let value = MyDayCommandResultV1(plan: targetPlan, receipt: receipt)
        try value.validate()
        return value
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_Mutation_WorkspaceWriterV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}

extension WorkspaceWriterV1:EvidenceContextCanonicalWorkspaceWritingV1{
    func commitEvidenceContext(_ operation:EvidenceContextWriteOperationV1)throws->MutationReceiptV1{try operation.validate();let current=try currentRevision(),target=try operation.concurrencyIdentity,known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard known[target,default:0]==operation.expectedRevision else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:[.init(identity:target,revision:operation.expectedRevision)]);_ = try execute(.init(mutationID:operation.mutationID,expectedRevision:expected,command:.applyEvidenceContext(operation)));guard let receipt=try journalStore?.receipt(mutationID:operation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try EvidenceContextMutationReceiptV1(operation:operation,mutationReceipt:receipt);return receipt}
}

extension WorkspaceWriterV1:LightingCanonicalWorkspaceWritingV1{
    func commitLighting(_ operation:LightingWriteOperationV1)throws->MutationReceiptV1{try operation.validate();let current=try currentRevision(),target=try operation.concurrencyIdentity,known=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard known[target,default:0]==operation.expectedRevision else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:[.init(identity:target,revision:operation.expectedRevision)]);_ = try execute(.init(mutationID:operation.mutationID,expectedRevision:expected,command:.applyLighting(operation)));guard let receipt=try journalStore?.receipt(mutationID:operation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try LightingMutationReceiptV1(operation:operation,mutationReceipt:receipt);return receipt}
}

extension WorkspaceWriterV1: LightingDayInventoryCanonicalWorkspaceWritingV1 {
    func commitLightingDayInventory(_ operation: LightingDayInventoryWriteOperationV1) throws -> MutationReceiptV1 {
        try operation.validate()
        let current = try currentRevision()
        let target = try operation.concurrencyIdentity
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        guard known[target, default: 0] == operation.expectedRevision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.lightingDayInventoryReceipt(for: operation) {
            _ = try LightingDayInventoryMutationReceiptV1(operation: operation, mutationReceipt: existing)
            guard try adapter.persistedLightingDayInventoryEffectMatches(operation) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return existing
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [.init(identity: target, revision: operation.expectedRevision)]
        )
        _ = try execute(.init(
            mutationID: operation.mutationID,
            expectedRevision: expected,
            command: .applyLightingDayInventory(operation)
        ))
        guard let receipt = try journalStore.lightingDayInventoryReceipt(for: operation) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try LightingDayInventoryMutationReceiptV1(operation: operation, mutationReceipt: receipt)
        guard try adapter.persistedLightingDayInventoryEffectMatches(operation) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return receipt
    }
}

extension WorkspaceWriterV1: LightingNightWorkflowCanonicalWorkspaceWritingV1 {
    func commitLightingNightWorkflow(_ operation: LightingNightWorkflowWriteOperationV1) throws -> MutationReceiptV1 {
        try operation.validate()
        let current = try currentRevision()
        let target = try operation.concurrencyIdentity
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        guard known[target, default: 0] == operation.expectedRevision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.lightingNightWorkflowReceipt(for: operation) {
            _ = try LightingNightWorkflowMutationReceiptV1(operation: operation, mutationReceipt: existing)
            guard try adapter.persistedLightingNightWorkflowEffectMatches(operation) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return existing
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: [.init(identity: target, revision: operation.expectedRevision)]
        )
        _ = try execute(.init(mutationID: operation.mutationID, expectedRevision: expected,
                              command: .applyLightingNightWorkflow(operation)))
        guard let receipt = try journalStore.lightingNightWorkflowReceipt(for: operation) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try LightingNightWorkflowMutationReceiptV1(operation: operation, mutationReceipt: receipt)
        guard try adapter.persistedLightingNightWorkflowEffectMatches(operation) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return receipt
    }
}


// MARK: - C32 expected-revision acceptance preflight

extension WorkspaceWriterV1: AssistanceCanonicalWorkspaceWritingV1 {
    /// Proves the consumer-supplied request is still at the exact target
    /// revision before its typed command delegate calls the sole writer. It
    /// does not invent a generic WorkspaceCommandV1 for an arbitrary field.
    func validateAssistanceAcceptanceRequest(
        _ request: AssistanceAcceptanceRequestV1
    ) throws {
        try request.validate()
        let current = try currentRevision()
        let expected = request.expectedRevision
        let targetRows = expected.entityRevisions.filter {
            $0.identity == request.proposal.target.entity
        }
        let currentRows = current.entityRevisions.filter {
            $0.identity == request.proposal.target.entity
        }
        guard current.workspaceID == expected.workspaceID,
              current.generationID == expected.generationID,
              current.writerInstanceID == expected.writerInstanceID,
              current.revision == expected.workspaceRevision,
              targetRows.count == 1,
              currentRows.count == 1,
              targetRows[0].revision == request.proposal.target.revision,
              currentRows[0].revision == request.proposal.target.revision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
    }

    func commitAssistanceAcceptance(
        _ request: AssistanceAcceptanceRequestV1
    ) throws -> AssistanceAcceptanceReceiptV1 {
        try request.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }

        if let existing = try journalStore.assistanceAcceptanceReceipt(
            mutationID: request.mutationID
        ) {
            try existing.validate(request: request)
            return existing
        }

        try validateAssistanceAcceptanceRequest(request)
        _ = try execute(request.canonicalWorkspaceMutationRequest())
        guard let committed = try journalStore.assistanceAcceptanceReceipt(
            mutationID: request.mutationID
        ) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        try committed.validate(request: request)
        return committed
    }

    func acceptedAssistanceReceipt(
        mutationID: MutationIDV1
    ) throws -> AssistanceAcceptanceReceiptV1? {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.assistanceAcceptanceReceipt(mutationID: mutationID)
    }
}

// MARK: - C33 bounded temporal-evidence canonical writer

extension WorkspaceWriterV1:TemporalEvidenceCanonicalWorkspaceWritingV1{
    func commitTemporalEvidence(_ mutation:TemporalEvidenceMutationV1)throws->TemporalEvidenceMutationReceiptV1{try mutation.validate();guard isActive else{throw WorkspaceMutationFailureV1.writerInvalidated};guard let journalStore else{throw WorkspaceMutationFailureV1.persistenceFailed};if let existing=try journalStore.receipt(mutationID:mutation.mutationID){return try .init(mutation:mutation,mutationReceipt:existing)};let current=try currentRevision();guard mutation.expectedRevision.workspaceID==current.workspaceID,mutation.expectedRevision.generationID==current.generationID,mutation.expectedRevision.writerInstanceID==current.writerInstanceID,mutation.expectedRevision.workspaceRevision==current.revision else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};_ = try execute(mutation.canonicalWorkspaceMutationRequest());guard let receipt=try journalStore.receipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return try .init(mutation:mutation,mutationReceipt:receipt)}
    func temporalEvidenceReceipt(mutationID:MutationIDV1)throws->MutationReceiptV1?{guard isActive else{throw WorkspaceMutationFailureV1.writerInvalidated};guard let journalStore else{throw WorkspaceMutationFailureV1.persistenceFailed};return try journalStore.receipt(mutationID:mutationID)}
}

// MARK: - C48 portable-review accept-and-apply sole writer

extension WorkspaceWriterV1 {
    func commitPortableReview(
        _ mutation: PortableReviewMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) throws -> PortableReviewMutationReceiptV1 {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.receipt(mutationID: mutation.mutationID) {
            return try PortableReviewMutationReceiptV1(mutation: mutation, mutationReceipt: existing)
        }
        let current = try currentRevision()
        guard expectedRevision.workspaceID == current.workspaceID,
              expectedRevision.generationID == current.generationID,
              expectedRevision.writerInstanceID == current.writerInstanceID,
              expectedRevision.workspaceRevision == current.revision,
              expectedRevision.workspaceRevision == mutation.plan.basisWorkspaceRevision,
              Set(expectedRevision.entityRevisions.map(\.identity)) == Set(try mutation.concurrencyIdentities),
              try mutation.concurrencyIdentities.allSatisfy({ identity in
                  expectedRevision.entityRevisions.first(where: { $0.identity == identity })?.revision
                      == (try mutation.expectedRevision(for: identity))
              }) else { throw WorkspaceMutationFailureV1.staleWorkspaceRevision }
        _ = try execute(try WorkspaceMutationRequestV1(
            mutationID: mutation.mutationID,
            expectedRevision: expectedRevision,
            command: .applyPortableReview(mutation)
        ))
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return try PortableReviewMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
    }

    func portableReviewReceipt(
        mutationID: MutationIDV1
    ) throws -> PortableReviewMutationReceiptV1? {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.portableReviewReceipt(mutationID: mutationID)
    }
}

// MARK: - C49 append-only work-resource sole writer

extension WorkspaceWriterV1 {
    func commitWorkResource(
        _ mutation: WorkResourceMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) throws -> WorkResourceMutationReceiptV1 {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.receipt(mutationID: mutation.mutationID) {
            return try .init(mutation: mutation, mutationReceipt: existing)
        }
        let current = try currentRevision()
        let concurrency = try mutation.concurrencyIdentity
        guard expectedRevision.workspaceID == current.workspaceID,
              expectedRevision.generationID == current.generationID,
              expectedRevision.writerInstanceID == current.writerInstanceID,
              expectedRevision.workspaceRevision == current.revision,
              expectedRevision.entityRevisions.count == 1,
              expectedRevision.entityRevisions.first?.identity == concurrency,
              expectedRevision.entityRevisions.first?.revision == mutation.postImage.expectedRevision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        _ = try execute(try WorkspaceMutationRequestV1(
            mutationID: mutation.mutationID,
            expectedRevision: expectedRevision,
            command: .applyWorkResource(mutation)
        ))
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return try .init(mutation: mutation, mutationReceipt: receipt)
    }
}

// MARK: - C52 append-only service-request sole writer

extension WorkspaceWriterV1 {
    func commitServiceRequest(
        _ mutation: ServiceRequestMutationV1
    ) throws -> ServiceRequestMutationReceiptV1 {
        try mutation.validateForCanonicalWriter()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.receipt(mutationID: mutation.mutationID) {
            return try .init(mutation: mutation, mutationReceipt: existing)
        }
        let current = try currentRevision()
        guard mutation.expectedRevision.workspaceID == current.workspaceID,
              mutation.expectedRevision.generationID == current.generationID,
              mutation.expectedRevision.writerInstanceID == current.writerInstanceID,
              mutation.expectedRevision.workspaceRevision == current.revision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let request = try WorkspaceMutationRequestV1(
            mutationID: mutation.mutationID,
            expectedRevision: mutation.expectedRevision,
            command: .applyServiceRequest(mutation)
        )
        if try adapter.persistedServiceRequestEffectMatches(mutation) {
            let envelope = try MutationEnvelopeV1(request: request, identity: identity, sourceKind: .localUser)
            let receipt = try journalStore.commit(
                envelope: envelope,
                writerInstanceID: writerInstanceID,
                affectedEntities: try mutation.affectedIdentities,
                committedAt: clock.now()
            )
            return try .init(mutation: mutation, mutationReceipt: receipt)
        }
        _ = try execute(request)
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return try .init(mutation: mutation, mutationReceipt: receipt)
    }

    func durableServiceRequestReceipt(
        mutation: ServiceRequestMutationV1
    ) throws -> ServiceRequestMutationReceiptV1? {
        try mutation.validateForCanonicalWriter()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard try currentRevision().workspaceID == mutation.workspaceID else { throw WorkspaceMutationFailureV1.wrongWorkspace }
        guard let journalStore, let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else { return nil }
        return try .init(mutation: mutation, mutationReceipt: receipt)
    }
}

// MARK: - C53 append-only asset-service reliability sole writer
extension WorkspaceWriterV1 {
    func commitServiceReliability(
        _ bundle: ServiceReliabilityAtomicBundleV1
    ) throws -> ServiceReliabilityMutationReceiptV1 {
        try bundle.validateForCanonicalWriter()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.receipt(mutationID: bundle.mutationID) {
            return try .init(bundle: bundle, mutationReceipt: existing)
        }
        let current = try currentRevision()
        guard bundle.expectedRevision.workspaceID == current.workspaceID,
              bundle.expectedRevision.generationID == current.generationID,
              bundle.expectedRevision.writerInstanceID == current.writerInstanceID,
              bundle.expectedRevision.workspaceRevision == current.revision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let request = try bundle.canonicalWorkspaceMutationRequest()
        if try adapter.persistedServiceReliabilityEffectMatches(bundle) {
            let envelope = try MutationEnvelopeV1(
                request: request,
                identity: identity,
                sourceKind: .localUser
            )
            let receipt = try journalStore.commit(
                envelope: envelope,
                writerInstanceID: writerInstanceID,
                affectedEntities: try bundle.affectedIdentities,
                committedAt: clock.now()
            )
            return try .init(bundle: bundle, mutationReceipt: receipt)
        }
        _ = try execute(request)
        guard let receipt = try journalStore.receipt(mutationID: bundle.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return try .init(bundle: bundle, mutationReceipt: receipt)
    }

    func durableServiceReliabilityReceipt(
        bundle: ServiceReliabilityAtomicBundleV1
    ) throws -> ServiceReliabilityMutationReceiptV1? {
        try bundle.validateForCanonicalWriter()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard try currentRevision().workspaceID == bundle.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard let journalStore,
              let receipt = try journalStore.receipt(mutationID: bundle.mutationID) else {
            return nil
        }
        return try .init(bundle: bundle, mutationReceipt: receipt)
    }
}

// MARK: - C45 accepted-label sole writer

extension WorkspaceWriterV1: AssetLabelCanonicalWorkspaceWritingV1 {
    func acceptedReceipt(
        for mutation: AssetLabelMutationV1
    ) async throws -> AssetLabelAcceptanceReceiptV1? {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.assetLabelAcceptanceReceipt(mutationID: mutation.mutationID)
    }

    func commitAssetLabel(
        _ mutation: AssetLabelMutationV1
    ) async throws -> AssetLabelAcceptanceReceiptV1 {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.assetLabelAcceptanceReceipt(mutationID: mutation.mutationID) {
            try existing.validate(snapshot: mutation.snapshot)
            return existing
        }
        _ = try execute(mutation.canonicalWorkspaceMutationRequest())
        guard let committed = try journalStore.assetLabelAcceptanceReceipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        try committed.validate(snapshot: mutation.snapshot)
        return committed
    }
}

// MARK: - C46 operational-contact sole writer

extension WorkspaceWriterV1: OperationalContactMutationCommittingV1 {
    func commitOperationalContact(
        _ mutation: OperationalContactMutationV1
    ) async throws -> OperationalContactMutationReceiptV1 {
        try mutation.validate()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.operationalContactReceipt(mutationID: mutation.mutationID) {
            guard existing.mutationSHA256 == (try OperationalContactCanonicalCodecV1.sha256(mutation)) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return existing
        }
        let current = try currentRevision()
        guard mutation.expectedRevision.workspaceID == current.workspaceID,
              mutation.expectedRevision.generationID == current.generationID,
              mutation.expectedRevision.writerInstanceID == current.writerInstanceID,
              mutation.expectedRevision.workspaceRevision == current.revision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        _ = try execute(mutation.canonicalWorkspaceMutationRequest())
        guard let receipt = try journalStore.operationalContactReceipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return receipt
    }

    func durableOperationalContactReceipt(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> OperationalContactMutationReceiptV1? {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        let current = try currentRevision()
        guard current.workspaceID == workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard let journalStore else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        return try journalStore.operationalContactReceipt(mutationID: mutationID)
    }
}

// MARK: - C47 activity-contract sole writer

extension WorkspaceWriterV1: ActivityContractCanonicalWorkspaceWritingV2 {
    func commitActivityContract(_ mutation: ActivityContractMutationV2) async throws -> MutationReceiptV1 {
        try mutation.validateForCanonicalMutation()
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        if let existing = try journalStore.receipt(mutationID: mutation.mutationID) {
            _ = try ActivityContractMutationReceiptV2(mutation: mutation, mutationReceipt: existing)
            return existing
        }
        let current = try currentRevision()
        guard mutation.expectedRevision.workspaceID == current.workspaceID,
              mutation.expectedRevision.generationID == current.generationID,
              mutation.expectedRevision.writerInstanceID == current.writerInstanceID,
              mutation.expectedRevision.workspaceRevision == current.revision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let request = try mutation.canonicalWorkspaceMutationRequest()
        if let recovered = try reconcileActivityContractEffectBeforeReceipt(
            mutation: mutation,
            request: request,
            journalStore: journalStore
        ) {
            return recovered
        }
        _ = try execute(request)
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        _ = try ActivityContractMutationReceiptV2(mutation: mutation, mutationReceipt: receipt)
        return receipt
    }

    /// C47's effect is persisted before the journal receipt boundary.  A
    /// restarted writer must therefore adopt only an effect whose canonical
    /// post-images exactly recreate the requested receipt; it must never
    /// execute the duplicate activity rows or retain process-local replay
    /// state.
    private func reconcileActivityContractEffectBeforeReceipt(
        mutation: ActivityContractMutationV2,
        request: WorkspaceMutationRequestV1,
        journalStore: MutationJournalStoreV1
    ) throws -> MutationReceiptV1? {
        guard try adapter.persistedActivityContractEffectMatches(mutation) else {
            return nil
        }
        let envelope = try MutationEnvelopeV1(
            request: request,
            identity: identity,
            sourceKind: .localUser
        )
        let receipt = try journalStore.commit(
            envelope: envelope,
            writerInstanceID: writerInstanceID,
            affectedEntities: try mutation.affectedIdentities,
            committedAt: clock.now()
        )
        _ = try ActivityContractMutationReceiptV2(
            mutation: mutation,
            mutationReceipt: receipt
        )
        return receipt
    }

    func durableActivityContractReceipt(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> MutationReceiptV1? {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard try currentRevision().workspaceID == workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard let journalStore else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return try journalStore.receipt(mutationID: mutationID)
    }
}

enum C34SceneNavigationWorkspaceWriterBoundaryV1 {
    static let resolutionWriteCount = 0
    static let restorationWriteCount = 0
    static let registersRouteWriter = false

    static func validate() -> Bool {
        resolutionWriteCount == 0 && restorationWriteCount == 0
            && !registersRouteWriter && C34SceneNavigationCanonicalExclusionV1.validate()
    }
}
// C52_BOUNDARY_ANCHOR: canonical-service-request-writer

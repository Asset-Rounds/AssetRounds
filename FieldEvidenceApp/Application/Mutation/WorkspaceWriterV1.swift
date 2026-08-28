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
    func rollback()
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

    func commitMeasurementIntegrity(_ bundle:MeasurementIntegrityAtomicBundleV1) async throws->MeasurementIntegrityWriteReceiptV1{let mutation=try MeasurementIntegrityMutationV1(bundle:bundle);let current=try currentRevision();let concurrency=try mutation.concurrencyIdentities;let byIdentity=Dictionary(uniqueKeysWithValues:current.entityRevisions.map{($0.identity,$0.revision)});guard try concurrency.allSatisfy({byIdentity[$0,default:0] == (try mutation.expectedRevision(for:$0))})else{throw WorkspaceMutationFailureV1.staleWorkspaceRevision};let expected=try WorkspaceExpectedRevisionV1(workspaceID:current.workspaceID,generationID:current.generationID,writerInstanceID:current.writerInstanceID,workspaceRevision:current.revision,entityRevisions:concurrency.map{WorkspaceEntityRevisionV1(identity:$0,revision:byIdentity[$0,default:0])});_ = try execute(WorkspaceMutationRequestV1(mutationID:bundle.mutationID,expectedRevision:expected,command:.applyMeasurementIntegrity(mutation)));guard let receipt=try journalStore?.receipt(mutationID:bundle.mutationID)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};_ = try MeasurementIntegrityMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return try MeasurementIntegrityWriteReceiptV1(workspaceID:bundle.workspaceID,mutationID:bundle.mutationID,bundleSHA256:bundle.bundleSHA256,journalReceiptSHA256:receipt.canonicalSHA256())}

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
        case .applyAssetSemantics(let value):
            do {
                try value.validate()
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
        if case let .applyAuthorityCriterion(mutation) = request.command {
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
        } else {
            for target in targets { entityRevisions[target, default: 0] += 1 }
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
            guard nodeIDs.count + value.placementChanges.count * 2 <= MutationReceiptV1.maximumPostImageCount else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            var identities = try nodeIDs.map {
                try WorkspaceEntityIdentityV1(kind: .locationNode, id: $0)
            }
            for placement in value.placementChanges {
                identities.append(try .init(kind: .asset, id: placement.basis.assetID))
                identities.append(try .init(kind: .assetPlacementEvent, id: placement.newEventID))
            }
            values = identities
        case let .applyAssetPlacementChange(plan):
            guard plan.mutationID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                  plan.basis.currentPlacement?.id != plan.newEventID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            values = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: plan.basis.assetID),
                WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: plan.newEventID),
            ]
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
        }
        guard Set(values).count == values.count else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return values
    }

    private static func expectedRevisionIdentities(
        for command: WorkspaceCommandV1
    ) throws -> [WorkspaceEntityIdentityV1] {
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
        return try targetIdentities(for: command)
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

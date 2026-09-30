import Foundation
import SwiftData

@MainActor final class FieldDraftLifecycleAdapterV1:FieldDraftWritingV1{
    private let writer:WorkspaceWriterV1
    private let journal:MutationJournalStoreV1
    private let context:ModelContext
    init(writer:WorkspaceWriterV1,journal:MutationJournalStoreV1,modelContext:ModelContext){self.writer=writer;self.journal=journal;context=modelContext}
    func currentCheckpoint(workspaceID:WorkspaceID,draftID:UUID)throws->FieldDraftCheckpointV1?{let id=draftID;let rows=try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>(predicate:#Predicate{$0.draftID==id}));guard rows.count<=1 else{throw FieldDraftFailureV1.invalidValue};guard let row=rows.first else{return nil};let value=try row.value();guard value.workspaceID==workspaceID else{throw FieldDraftFailureV1.wrongWorkspace};return value}
    func compareAndSwap(checkpoint value:FieldDraftCheckpointV1,expectedDraftRevision:UInt64,expectedBaseRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedDraftRevision,expectedBaseCanonicalRevision:expectedBaseRevision,mutationID:value.mutationID,postImage:expectedDraftRevision==0 ? .createCheckpoint(value):.reviseCheckpoint(value)))}
    func publish(readyStage bundle: FieldDraftStagePublicationBundleV1) throws -> MutationReceiptV1 {
        try execute(.init(workspaceID: bundle.workspaceID,
                          expectedRevision: bundle.expectedCheckpoint.draftRevision,
                          expectedBaseCanonicalRevision: bundle.expectedCheckpoint.baseCanonicalRevision,
                          mutationID: bundle.mutationID, postImage: .publishReadyStage(bundle)))
    }

    /// Initial publication-edge proof. Later stage/checkpoint successors are
    /// authenticated through their full history, not this exact-tip predicate.
    func readyStagePublicationEvidence(for bundle: FieldDraftStagePublicationBundleV1) throws
        -> FieldDraftCommittedEvidenceV1? {
        try bundle.validate()
        try writer.validateFieldDraftReadContext(context)
        let current = try writer.currentRevision()
        guard current.workspaceID == bundle.workspaceID else { throw FieldDraftFailureV1.wrongWorkspace }
        let evidence = try writer.fieldDraftEvidence(mutationID: bundle.mutationID)
        let checkpoint = try currentCheckpoint(workspaceID: bundle.workspaceID,
                                               draftID: bundle.expectedCheckpoint.draftID)
        let stageID = bundle.readyItem.stageID
        let rows = try context.fetch(FetchDescriptor<AttachmentStagingItemRow>(
            predicate: #Predicate { $0.stageID == stageID }
        ))
        guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        let stage = try rows.first?.value()
        guard let evidence else {
            guard checkpoint == bundle.expectedCheckpoint, stage == nil else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return nil
        }
        let mutation = try FieldDraftMutationV1(workspaceID: bundle.workspaceID,
            expectedRevision: bundle.expectedCheckpoint.draftRevision,
            expectedBaseCanonicalRevision: bundle.expectedCheckpoint.baseCanonicalRevision,
            mutationID: bundle.mutationID, postImage: .publishReadyStage(bundle))
        guard evidence.mutation == mutation,
              checkpoint == bundle.successorCheckpoint, stage == bundle.readyItem else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return evidence
    }

    func append(stagingItem value:AttachmentStagingItemV1,expectedRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedRevision,expectedBaseCanonicalRevision:0,mutationID:value.mutationID,postImage:expectedRevision==0 ? .appendStagingItem(value):.reviseStagingItem(value)))}
    func append(saga value:DraftCommitSagaV1,expectedRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedRevision,expectedBaseCanonicalRevision:value.plan.baseCanonicalRevision,mutationID:value.mutationID,postImage:expectedRevision==0 ? .appendCommitSaga(value):.advanceCommitSaga(value)))}
    func append(reservation value:DraftContentReservationV1,expectedRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedRevision,expectedBaseCanonicalRevision:0,mutationID:value.mutationID,postImage:expectedRevision==0 ? .appendContentReservation(value):.reviseContentReservation(value)))}
    func apply(commitTerminalBundle value:DraftCommitTerminalBundleV1,expectedDraftRevision:UInt64,expectedSagaRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedDraftRevision,expectedBaseCanonicalRevision:value.committedCheckpoint.baseCanonicalRevision,mutationID:value.mutationID,postImage:.applyCommitTerminal(value,expectedSagaRevision:expectedSagaRevision)))}
    func apply(discardTerminalBundle value:DraftDiscardTerminalBundleV1,expectedDraftRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedDraftRevision,expectedBaseCanonicalRevision:value.discardedCheckpoint.baseCanonicalRevision,mutationID:value.mutationID,postImage:.applyDiscardTerminal(value)))}
    /// The journal validates physical tips and retained history together. No
    /// historical successor is reconstructed from the current checkpoint.
    func reviewedFieldDraftResolutionEvidence(
        mutationID: MutationIDV1
    ) throws -> ReviewedFieldDraftResolutionEvidenceV1? {
        try writer.reviewedFieldDraftResolutionEvidence(mutationID: mutationID)
    }

    private func execute(_ mutation:FieldDraftMutationV1)throws->MutationReceiptV1{try writer.commitFieldDraft(mutation)}
}

extension FieldDraftLifecycleAdapterV1 {
    func repetitiveCaptureDestinationContinuation(workspaceID: WorkspaceID, reviewDraftID: UUID) throws
        -> RepetitiveCaptureDestinationContinuationEvidenceV1? {
        try writer.validateFieldDraftReadContext(context)
        return try writer.repetitiveCaptureDestinationContinuationEvidence(
            workspaceID: workspaceID, reviewDraftID: reviewDraftID)
    }

    func persistRepetitiveCaptureDestinationContinuation(
        _ proposal: RepetitiveCaptureDestinationContinuationProposalV1
    ) throws -> RepetitiveCaptureDestinationContinuationEvidenceV1 {
        guard let binding = proposal.mutation.continuationBinding else { throw FieldDraftFailureV1.invalidValue }
        if let original = try repetitiveCaptureDestinationContinuation(
            workspaceID: binding.workspaceID, reviewDraftID: binding.review.draftID) {
            guard original.original.mutation == proposal.mutation,
                  original.sourceCheckpoint == proposal.checkpoint else { throw ScanToWorkFailureV1.stale }
            return original
        }
        _ = try writer.commitFieldDraft(proposal.mutation)
        guard let original = try repetitiveCaptureDestinationContinuation(
            workspaceID: binding.workspaceID, reviewDraftID: binding.review.draftID),
              original.original.mutation == proposal.mutation,
              original.sourceCheckpoint == proposal.checkpoint else { throw ScanToWorkFailureV1.authorityMismatch }
        return original
    }

    /// Caller supplies the original live scene/readiness capability. This seam
    /// additionally requires actual canonical Round history and its receipt.
    func persistRepetitiveCaptureProgressSource(_ checkpoint: FieldDraftCheckpointV1) throws
        -> ReviewedRepetitiveCaptureProgressChainV2 {
        let launch = try RepetitiveCaptureProgressDraftCodecV2.source(checkpoint)
        _ = try writer.currentRevision()
        if let existing = try currentCheckpoint(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID) {
            guard existing == checkpoint else { throw ScanToWorkFailureV1.stale }
            return try reviewedRepetitiveCaptureProgress(workspaceID: checkpoint.workspaceID,
                                                       sourceDraftID: checkpoint.draftID)
        }
        let history = try progressRoundHistory(workspaceID: checkpoint.workspaceID, sessionID: launch.round.sessionID)
        guard history.last == launch.round else { throw ScanToWorkFailureV1.stale }
        _ = try requireProgressLaunchReceipt(launch.round)
        // Prove the scope has no competing source before the first write.
        guard try progressCheckpoints(workspaceID: checkpoint.workspaceID).allSatisfy({
            $0.scope != checkpoint.scope
        }) else { throw ScanToWorkFailureV1.duplicate }
        _ = try compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: 0,
                               expectedBaseRevision: checkpoint.baseCanonicalRevision)
        return try reviewedRepetitiveCaptureProgress(workspaceID: checkpoint.workspaceID,
                                                   sourceDraftID: checkpoint.draftID)
    }

    func persistRepetitiveCaptureProgressStep(_ checkpoint: FieldDraftCheckpointV1) throws
        -> ReviewedRepetitiveCaptureProgressChainV2 {
        try RepetitiveCaptureProgressDraftCodecV2.validateCheckpoint(checkpoint)
        guard case let .progress(step) = try RepetitiveCaptureProgressDraftCodecV2.decode(checkpoint.payloadData) else {
            throw FieldDraftFailureV1.invalidValue
        }
        let chain = try reviewedRepetitiveCaptureProgress(workspaceID: checkpoint.workspaceID,
                                                         sourceDraftID: step.source.draftID)
        if let existing = chain.nodes.first(where: { $0.checkpoint.draftID == checkpoint.draftID }) {
            guard existing.checkpoint == checkpoint, chain.nodes.last == existing else { throw ScanToWorkFailureV1.stale }
            return chain
        }
        guard chain.nodes.last?.isPendingRoundEffect != true,
              chain.nodes.count < chain.launch.round.items.count * 2,
              chain.currentRound == step.expectedRound,
              checkpoint.draftID != chain.sourceCheckpoint.draftID,
              checkpoint.scope == chain.sourceCheckpoint.scope,
              checkpoint.resumeAnchor == step.resumeAnchor else { throw ScanToWorkFailureV1.stale }
        try step.validate(sourceCheckpoint: chain.sourceCheckpoint, priorCheckpoint: chain.nodes.last?.checkpoint)
        guard step.priorRoundReceipt == chain.nodes.last?.roundReceipt else { throw ScanToWorkFailureV1.authorityMismatch }
        var mutationIDs = Set([chain.sourceCheckpoint.mutationID, chain.launch.round.mutationID])
        for node in chain.nodes {
            mutationIDs.insert(node.checkpoint.mutationID)
            if let mutation = node.step.roundMutation { mutationIDs.insert(mutation.mutationID) }
        }
        guard mutationIDs.insert(checkpoint.mutationID).inserted else { throw ScanToWorkFailureV1.duplicate }
        if let mutation = step.roundMutation {
            guard mutationIDs.insert(mutation.mutationID).inserted,
                  try writer.durableReceipt(mutationID: mutation.mutationID) == nil else {
                throw ScanToWorkFailureV1.duplicate
            }
        }
        _ = try compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: 0,
                               expectedBaseRevision: checkpoint.baseCanonicalRevision)
        return try reviewedRepetitiveCaptureProgress(workspaceID: checkpoint.workspaceID,
                                                   sourceDraftID: step.source.draftID)
    }

    /// Read only. Authenticate through this live writer, then apply the shared
    /// complete-chain rules used by source restore validation.
    func reviewedRepetitiveCaptureProgress(workspaceID: WorkspaceID, sourceDraftID: UUID) throws
        -> ReviewedRepetitiveCaptureProgressChainV2 {
        if let chain = try writer.reviewedRepetitiveCaptureProgressInReadScope(
            workspaceID: workspaceID, sourceDraftID: sourceDraftID, modelContext: context) {
            return chain
        }
        return try RepetitiveCaptureProgressChainReviewV2.review(
            workspaceID: workspaceID, sourceDraftID: sourceDraftID,
            authenticatedProgressCheckpoint: { workspace, draft in
                try self.authenticatedProgressCheckpoint(workspaceID: workspace, draftID: draft)
            },
            progressRoundHistory: { workspace, session in
                try self.progressRoundHistory(workspaceID: workspace, sessionID: session)
            },
            requireProgressLaunchReceipt: { try self.requireProgressLaunchReceipt($0) },
            progressCheckpoints: { try self.progressCheckpoints(workspaceID: $0) },
            durableReceipt: { try self.writer.durableReceipt(mutationID: $0) })
    }

    /// Read only. Every active authenticated capture source launched for one
    /// Round session, in stable draft order; resuming callers require exactly one.
    func repetitiveCaptureSources(workspaceID: WorkspaceID, sessionID: UUID) throws
        -> [ReviewedRepetitiveCaptureProgressChainV2] {
        try progressCheckpoints(workspaceID: workspaceID)
            .filter { $0.state == .active }
            .sorted { $0.draftID.uuidString < $1.draftID.uuidString }
            .compactMap { checkpoint in
                guard case let .source(launch) = try RepetitiveCaptureProgressDraftCodecV2.decode(checkpoint.payloadData),
                      launch.round.sessionID == sessionID else { return nil }
                return try reviewedRepetitiveCaptureProgress(workspaceID: workspaceID, sourceDraftID: checkpoint.draftID)
            }
    }

    private func authenticatedProgressCheckpoint(workspaceID: WorkspaceID, draftID: UUID) throws
        -> (FieldDraftCheckpointV1, MutationReceiptV1) {
        _ = try writer.currentRevision()
        guard let checkpoint = try currentCheckpoint(workspaceID: workspaceID, draftID: draftID) else { throw ScanToWorkFailureV1.stale }
        try RepetitiveCaptureProgressDraftCodecV2.validateCheckpoint(checkpoint)
        guard let evidence = try writer.fieldDraftEvidence(mutationID: checkpoint.mutationID),
              evidence.mutation.workspaceID == workspaceID, evidence.mutation.expectedRevision == 0,
              evidence.mutation.expectedBaseCanonicalRevision == checkpoint.baseCanonicalRevision,
              case let .createCheckpoint(original) = evidence.mutation.postImage, original == checkpoint else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        return (checkpoint, evidence.receipt)
    }

    private func progressCheckpoints(workspaceID: WorkspaceID) throws -> [FieldDraftCheckpointV1] {
        let rawWorkspaceID = workspaceID.rawValue
        let rows = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>(predicate: #Predicate { $0.workspaceID == rawWorkspaceID }))
        let release = try RepetitiveCaptureProgressDraftCodecV2.release()
        return try rows.map { try $0.value() }.filter { $0.purpose == .repetitiveCapture && $0.codec == release }
    }

    private func progressRoundHistory(workspaceID: WorkspaceID, sessionID: UUID) throws -> [RoundSessionV1] {
        _ = try writer.currentRevision()
        let history = try WorkspaceWriterAdapterV1(modelContext: context).roundSessionHistory(workspaceID: workspaceID, sessionID: sessionID)
        _ = try RoundSessionHistoryValidatorV1.validate(history, workspaceID: workspaceID, sessionID: sessionID)
        return history
    }

    private func requireProgressLaunchReceipt(_ round: RoundSessionV1) throws -> MutationReceiptV1 {
        guard round.revision > 0,
              let receipt = try writer.durableReceipt(mutationID: round.mutationID) else { throw ScanToWorkFailureV1.authorityMismatch }
        let mutation = try RoundSessionMutationV1(workspaceID: round.workspaceID, expectedRevision: round.revision - 1,
                                                mutationID: round.mutationID, session: round)
        _ = try RoundSessionMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
        return receipt
    }
}

extension FieldDraftLifecycleAdapterV1: VoiceReviewedFieldDraftReceiptReadingV1 {}
extension FieldDraftLifecycleAdapterV1: OCRReviewedFieldDraftReceiptReadingV1 {
    func reviewedOCRFieldReceipt(mutationID: MutationIDV1) throws -> MutationReceiptV1? {
        try journal.receipt(mutationID: mutationID)
    }
}

enum C23OCRFieldDraftLifecycleBoundaryV1 {
    static let addedRowCount = OCRProposalPersistenceBoundaryV1.addedDurableRowCount
    static let proposalOrReviewIsBackedUp = false
    static let scratchCleanupUsesAssistanceLifecycle = true
    static let effectBeforeReceiptRecoveryUsesMutationJournal = true
}

enum C24AssistedCaptureDraftLifecycleBoundaryV1 {
    static let addedDurableRows=DictationLocationPersistenceBoundaryV1.addedDurableRowCount
    static let proposalReviewAndPermissionStateIsPersistent=false
    static let receiptRecoveryUsesMutationJournal=true
    static let audioScratchUsesDictationAudioScratchLifecycle=true
}

extension FieldDraftLifecycleAdapterV1 {
    /// Resolves the C21 capture plan against the physical checkpoint row, so
    /// a stale plan cannot be reused after a durable draft revision changes.
    func validateRepetitiveCapturePlan(
        _ plan: RepetitiveCapturePlanV1
    ) throws -> FieldDraftCheckpointV1 {
        try plan.validateIntrinsic()
        guard let checkpoint = try currentCheckpoint(
            workspaceID: plan.workspaceID,
            draftID: plan.draftID
        ) else {
            throw ScanToWorkFailureV1.stale
        }
        try C21RepetitiveCaptureDraftBoundaryV1.validate(plan: plan, checkpoint: checkpoint)
        return checkpoint
    }

    func validateRepetitiveCaptureConfigurationCopy(
        _ copy: RepetitiveCaptureConfigurationCopyV1,
        source: RepetitiveCapturePlanV1
    ) throws {
        let checkpoint = try validateRepetitiveCapturePlan(source)
        try C21RepetitiveCaptureDraftBoundaryV1.validateConfigurationCopy(
            copy,
            source: source,
            sourceCheckpoint: checkpoint
        )
    }

    /// C56 reuses the existing C36 journal read-back; no parallel receipt
    /// cache or writer is introduced for reviewed field checkpoints.
    func reviewedVoiceFieldReceipt(
        mutationID: MutationIDV1
    ) throws -> MutationReceiptV1? {
        try journal.receipt(mutationID: mutationID)
    }

    func validatePackageUpgradeSource(_ checkpoint: FieldDraftCheckpointV1) throws {
        try PackageEvolutionDraftBoundaryV1.validateSource(checkpoint)
        guard let durable = try currentCheckpoint(
            workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID
        ), durable.checkpointSHA256 == checkpoint.checkpointSHA256 else {
            throw PackageEvolutionFailureV1.staleSource
        }
    }

    /// Read-back seam for C21-aware package upgrades.  Capability decisions
    /// are checked against the durable source before the coordinator performs
    /// its compare-and-swap; no optimistic draft write is permitted.
    func validatePackageUpgradeAdmission(
        plan: DraftUpgradePlanV1,
        source: FieldDraftCheckpointV1,
        diff: PackageSemanticDiffV1,
        admittedBy capability: ClientCapabilityLifecycleClosureV1
    ) throws {
        try validatePackageUpgradeSource(source)
        try PackageEvolutionDraftPersistenceBoundaryV1.validateUpgradeInputs(
            plan: plan,
            source: source,
            diff: diff,
            admittedBy: capability
        )
    }

    /// C23 read-back seam. The field-reference tuple is checked against the
    /// durable checkpoint before any caller uses it for resume or commit; no
    /// binding row is created here and no draft bytes are copied.
    func validateFieldReferenceBinding(
        checkpoint: FieldDraftCheckpointV1,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws -> FieldDraftReferenceProjectionV1 {
        guard let durable = try currentCheckpoint(
            workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID
        ), durable.checkpointSHA256 == checkpoint.checkpointSHA256 else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        return try durable.c23ReferenceProjection(
            binding: binding,
            release: release,
            readiness: readiness
        )
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Drafts_FieldDraftLifecycleAdapterV1_swift {
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
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Drafts_FieldDraftLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift", role: .draft)
}

enum C31LightingConsumerBoundary_Infrastructure_Drafts_FieldDraftLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/field-draft-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Drafts_FieldDraftLifecycleAdapterV1 {
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Drafts_FieldDraftLifecycleAdapterV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row163 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Drafts_FieldDraftLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

enum C34SceneRestorationFieldDraftLifecycleBoundaryV1 {
    static let writesCheckpoint = false
    static let changesDraftState = false
    static let opensByStableAnchorOnly = true
    static func validate(anchor: DraftResumeAnchorV1) -> Bool { !writesCheckpoint && !changesDraftState && opensByStableAnchorOnly && C34DraftResumeNavigationBoundaryV1.validate(anchor: anchor) }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Drafts_FieldDraftLifecycleAdapterV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

/// Values are issued only after the original journal command and exact active
/// physical checkpoint agree. They confer no scene or Round-write authority.
struct ReviewedRepetitiveCaptureSourceV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let plan: RepetitiveCapturePlanV1
    let receipt: MutationReceiptV1
    fileprivate init(checkpoint: FieldDraftCheckpointV1, plan: RepetitiveCapturePlanV1, receipt: MutationReceiptV1) {
        self.checkpoint = checkpoint; self.plan = plan; self.receipt = receipt
    }
}

struct ReviewedRepetitiveCaptureContinuationV1: Equatable, Sendable {
    let source: ReviewedRepetitiveCaptureSourceV1
    let checkpoint: FieldDraftCheckpointV1
    let request: RepetitiveCaptureCheckpointRequestV1
    let receipt: MutationReceiptV1
    fileprivate init(source: ReviewedRepetitiveCaptureSourceV1, checkpoint: FieldDraftCheckpointV1,
                     request: RepetitiveCaptureCheckpointRequestV1, receipt: MutationReceiptV1) {
        self.source = source; self.checkpoint = checkpoint; self.request = request; self.receipt = receipt
    }
}

extension FieldDraftLifecycleAdapterV1 {
    /// The caller retains live scene and canonical Round admission. This lower
    /// seam persists only the immutable C36 source, never a Round transition.
    func persistRepetitiveCaptureSource(_ checkpoint: FieldDraftCheckpointV1,
                                       round: RoundSessionV1, selectedItem: RoundItemV1) throws -> ReviewedRepetitiveCaptureSourceV1 {
        try requireImmutableRepetitiveCaptureCheckpoint(checkpoint)
        try RepetitiveCaptureDraftCodecV1.validateSelectedRoundItem(
            sourceCheckpoint: checkpoint, round: round, selectedItem: selectedItem)
        guard checkpoint.mutationID != round.mutationID else { throw ScanToWorkFailureV1.authorityMismatch }
        _ = try compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: 0,
                               expectedBaseRevision: checkpoint.baseCanonicalRevision)
        let result = try reviewedRepetitiveCaptureSource(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID)
        guard result.checkpoint == checkpoint else { throw ScanToWorkFailureV1.stale }
        return result
    }

    func reviewedRepetitiveCaptureSource(workspaceID: WorkspaceID, draftID: UUID) throws -> ReviewedRepetitiveCaptureSourceV1 {
        let (checkpoint, receipt) = try authenticatedRepetitiveCaptureCheckpoint(workspaceID: workspaceID, draftID: draftID)
        let plan = try RepetitiveCaptureDraftCodecV1.materializePlan(from: checkpoint)
        return .init(checkpoint: checkpoint, plan: plan, receipt: receipt)
    }

    func persistRepetitiveCaptureContinuation(_ checkpoint: FieldDraftCheckpointV1) throws -> ReviewedRepetitiveCaptureContinuationV1 {
        try requireImmutableRepetitiveCaptureCheckpoint(checkpoint)
        let (source, request) = try repetitiveCaptureContinuationInputs(checkpoint)
        _ = try compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: 0,
                               expectedBaseRevision: checkpoint.baseCanonicalRevision)
        let result = try reviewedRepetitiveCaptureContinuation(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID)
        guard result.checkpoint == checkpoint, result.source == source, result.request == request else {
            throw ScanToWorkFailureV1.stale
        }
        return result
    }

    /// A fresh adapter can reconstruct the exact original command after a lost
    /// acknowledgement. This performs no write, restart or navigation.
    func reviewedRepetitiveCaptureContinuation(workspaceID: WorkspaceID, draftID: UUID) throws -> ReviewedRepetitiveCaptureContinuationV1 {
        let (checkpoint, receipt) = try authenticatedRepetitiveCaptureCheckpoint(workspaceID: workspaceID, draftID: draftID)
        let (source, request) = try repetitiveCaptureContinuationInputs(checkpoint)
        return .init(source: source, checkpoint: checkpoint, request: request, receipt: receipt)
    }

    private func repetitiveCaptureContinuationInputs(_ checkpoint: FieldDraftCheckpointV1) throws
        -> (ReviewedRepetitiveCaptureSourceV1, RepetitiveCaptureCheckpointRequestV1) {
        guard case let .continuation(reference, _) = try RepetitiveCaptureDraftCodecV1.decode(checkpoint.payloadData) else {
            throw FieldDraftFailureV1.invalidValue
        }
        let source = try reviewedRepetitiveCaptureSource(workspaceID: checkpoint.workspaceID, draftID: reference.draftID)
        try reference.validate(source: source.checkpoint)
        let request = try RepetitiveCaptureDraftCodecV1.validateContinuationCheckpoint(checkpoint, sourceCheckpoint: source.checkpoint)
        guard checkpoint.mutationID != source.checkpoint.mutationID,
              checkpoint.mutationID != request.roundMutation.mutationID,
              source.checkpoint.mutationID != request.roundMutation.mutationID else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        return (source, request)
    }

    private func requireImmutableRepetitiveCaptureCheckpoint(_ checkpoint: FieldDraftCheckpointV1) throws {
        try checkpoint.validate(authority: RepetitiveCaptureDraftPurposeAuthorityV1())
        guard checkpoint.draftRevision == 1, checkpoint.state == .active, checkpoint.stageIDs.isEmpty,
              checkpoint.lastDurableMutationID == nil, checkpoint.lastReceiptSHA256 == nil else {
            throw ScanToWorkFailureV1.stale
        }
    }

    private func authenticatedRepetitiveCaptureCheckpoint(workspaceID: WorkspaceID, draftID: UUID) throws
        -> (FieldDraftCheckpointV1, MutationReceiptV1) {
        // Check the writer as well as the journal: an invalidated adapter must
        // never regain authority merely because its old lease still exists.
        _ = try writer.currentRevision()
        guard let checkpoint = try currentCheckpoint(workspaceID: workspaceID, draftID: draftID) else {
            throw ScanToWorkFailureV1.stale
        }
        try requireImmutableRepetitiveCaptureCheckpoint(checkpoint)
        guard let evidence = try writer.fieldDraftEvidence(mutationID: checkpoint.mutationID),
              evidence.mutation.workspaceID == workspaceID, evidence.mutation.expectedRevision == 0,
              evidence.mutation.expectedBaseCanonicalRevision == checkpoint.baseCanonicalRevision,
              case let .createCheckpoint(original) = evidence.mutation.postImage, original == checkpoint else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        return (checkpoint, evidence.receipt)
    }
}

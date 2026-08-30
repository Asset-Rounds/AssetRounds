import Foundation

/// Sole-store adapter contract. Implementations route every append/CAS through
/// the existing workspace writer and return its durable receipt.
@MainActor protocol FieldDraftWritingV1: AnyObject {
    func currentCheckpoint(workspaceID:WorkspaceID,draftID:UUID)throws->FieldDraftCheckpointV1?
    func compareAndSwap(checkpoint:FieldDraftCheckpointV1,expectedDraftRevision:UInt64,expectedBaseRevision:UInt64)throws->MutationReceiptV1
    func append(stagingItem:AttachmentStagingItemV1,expectedRevision:UInt64)throws->MutationReceiptV1
    func append(saga:DraftCommitSagaV1,expectedRevision:UInt64)throws->MutationReceiptV1
    func append(reservation:DraftContentReservationV1,expectedRevision:UInt64)throws->MutationReceiptV1
    func apply(commitTerminalBundle:DraftCommitTerminalBundleV1,expectedDraftRevision:UInt64,expectedSagaRevision:UInt64)throws->MutationReceiptV1
    func apply(discardTerminalBundle:DraftDiscardTerminalBundleV1,expectedDraftRevision:UInt64)throws->MutationReceiptV1
}

/// Existing content authority only; this coordinator never writes bytes itself.
protocol DraftContentPromotionPortV1: Sendable {
    func promote(plan:DraftCommitPlanV1,items:[AttachmentStagingItemV1],reservationMutationIDs:[UUID:MutationIDV1])async throws->[DraftContentReservationV1]
    func quarantine(reservations:[DraftContentReservationV1],for plan:DraftDiscardPlanV1)async throws
}

/// Existing WorkspaceWriter target effect/read-back authority.
@MainActor protocol DraftCanonicalCommitPortV1: AnyObject {
    func commit(plan:DraftCommitPlanV1,reservations:[DraftContentReservationV1])throws->MutationReceiptV1
    func readBackMatches(plan:DraftCommitPlanV1,receipt:MutationReceiptV1)throws->Bool
}

@MainActor final class FieldDraftCoordinatorV1 {
    private let registry:DraftPurposeRegistryV1
    private let writer:any FieldDraftWritingV1
    private let content:any DraftContentPromotionPortV1
    private let target:any DraftCanonicalCommitPortV1
    init(registry:DraftPurposeRegistryV1,writer:any FieldDraftWritingV1,content:any DraftContentPromotionPortV1,target:any DraftCanonicalCommitPortV1){self.registry=registry;self.writer=writer;self.content=content;self.target=target}

    func checkpoint(_ value:FieldDraftCheckpointV1,expectedDraftRevision:UInt64,expectedBaseRevision:UInt64)throws->MutationReceiptV1{
        try value.validate(registry:registry)
        if let prior=try writer.currentCheckpoint(workspaceID:value.workspaceID,draftID:value.draftID){try value.validateSuccessor(of:prior,expectedDraftRevision:expectedDraftRevision,expectedBaseRevision:expectedBaseRevision)}else{guard expectedDraftRevision==0,value.draftRevision==1,value.baseCanonicalRevision==expectedBaseRevision else{throw FieldDraftFailureV1.staleDraftRevision}}
        return try writer.compareAndSwap(checkpoint:value,expectedDraftRevision:expectedDraftRevision,expectedBaseRevision:expectedBaseRevision)
    }

    func append(_ item:AttachmentStagingItemV1,checkpoint:FieldDraftCheckpointV1,expectedRevision:UInt64)throws->MutationReceiptV1{try item.validate();try checkpoint.validate(registry:registry);guard item.workspaceID==checkpoint.workspaceID,item.draftID==checkpoint.draftID,checkpoint.stageIDs.contains(item.stageID)else{throw FieldDraftFailureV1.wrongWorkspace};return try writer.append(stagingItem:item,expectedRevision:expectedRevision)}

    func applyPackageUpgrade(
        plan: DraftUpgradePlanV1,
        source: FieldDraftCheckpointV1,
        diff: PackageSemanticDiffV1,
        mutationID: MutationIDV1,
        updatedAt: Date
    ) throws -> MutationReceiptV1 {
        try source.validate(registry: registry)
        try plan.validate(source: source, diff: diff)
        return try applyPackageUpgradeSuccessor(
            plan: plan, source: source, mutationID: mutationID, updatedAt: updatedAt
        )
    }

    /// Applies a package upgrade only after the immutable C21 capability
    /// closure has admitted the safe migration operation.  The capability
    /// values remain nonpersistent preview inputs; this method still uses the
    /// existing compare-and-swap checkpoint writer for the sole durable effect.
    func applyPackageUpgrade(
        plan: DraftUpgradePlanV1,
        source: FieldDraftCheckpointV1,
        diff: PackageSemanticDiffV1,
        admittedBy capability: ClientCapabilityLifecycleClosureV1,
        mutationID: MutationIDV1,
        updatedAt: Date
    ) throws -> MutationReceiptV1 {
        try PackageEvolutionDraftPersistenceBoundaryV1.validateUpgradeInputs(
            plan: plan,
            source: source,
            diff: diff,
            admittedBy: capability
        )
        try source.validate(registry: registry)
        return try applyPackageUpgradeSuccessor(
            plan: plan, source: source, mutationID: mutationID, updatedAt: updatedAt
        )
    }

    private func applyPackageUpgradeSuccessor(
        plan: DraftUpgradePlanV1,
        source: FieldDraftCheckpointV1,
        mutationID: MutationIDV1,
        updatedAt: Date
    ) throws -> MutationReceiptV1 {
        guard source.draftRevision < UInt64.max else {
            throw PackageEvolutionFailureV1.staleSource
        }
        let successor = try FieldDraftCheckpointV1(
            draftID: source.draftID, workspaceID: source.workspaceID,
            scope: source.scope, purpose: source.purpose, codec: source.codec,
            baseCanonicalRevision: source.baseCanonicalRevision,
            draftRevision: source.draftRevision + 1,
            payloadData: plan.targetPayloadData, stageIDs: source.stageIDs,
            resumeAnchor: source.resumeAnchor, state: .active,
            lastDurableMutationID: source.lastDurableMutationID,
            lastReceiptSHA256: source.lastReceiptSHA256,
            updatedAt: updatedAt, mutationID: mutationID
        )
        return try checkpoint(
            successor, expectedDraftRevision: source.draftRevision,
            expectedBaseRevision: source.baseCanonicalRevision
        )
    }

    func commit(plan:DraftCommitPlanV1,checkpoint:FieldDraftCheckpointV1,items:[AttachmentStagingItemV1],prepared:DraftCommitSagaV1,contentPromoted:DraftCommitSagaV1,targetCommitted:DraftCommitSagaV1,retirePending:DraftCommitSagaV1,retired:DraftCommitSagaV1,commitReceiptID:UUID,terminalCheckpointUpdatedAt:Date,rowMutationIDs:DraftCommitRowMutationIDsV1)async throws->DraftCommitReceiptV1{
        try plan.validate();try checkpoint.validate(registry:registry);try items.forEach{$0.validate()};try prepared.validate();try contentPromoted.validateSuccessor(of:prepared);try targetCommitted.validateSuccessor(of:contentPromoted);try retirePending.validateSuccessor(of:targetCommitted);try retired.validateSuccessor(of:retirePending)
        try rowMutationIDs.validate(stageIDs:items.map(\.stageID),targetMutationID:plan.mutationID,sagaMutationIDs:[prepared.mutationID,contentPromoted.mutationID,targetCommitted.mutationID,retirePending.mutationID])
        guard checkpoint.state == .committing,plan.workspaceID==checkpoint.workspaceID,plan.draftID==checkpoint.draftID,plan.draftRevision==checkpoint.draftRevision,plan.baseCanonicalRevision==checkpoint.baseCanonicalRevision,plan.payloadSHA256==checkpoint.payloadSHA256,prepared.plan==plan,prepared.state == .prepared,contentPromoted.state == .contentPromotedUnbound,targetCommitted.state == .targetCommitted,retirePending.state == .draftRetirePending,retired.state == .draftRetired,retired.mutationID==rowMutationIDs.terminalBundleMutationID,Set(items.map(\.stageID)).count==items.count,Set(items.map(\.stageSHA256)).count==items.count,items.allSatisfy({$0.workspaceID==plan.workspaceID&&$0.draftID==plan.draftID&&$0.state == .readyLocal}),Set(items.map(\.stageSHA256)).sorted()==plan.stageDigests else{throw FieldDraftFailureV1.conflictRequired}
        _ = try writer.append(saga:prepared,expectedRevision:0)
        let reservations=try await content.promote(plan:plan,items:items,reservationMutationIDs:rowMutationIDs.reservationByStageID)
        guard reservations.count==items.count,Set(reservations.map(\.stageID)).count==reservations.count,Set(reservations.map(\.stageID))==Set(items.map(\.stageID)),reservations.allSatisfy({$0.workspaceID==plan.workspaceID&&$0.draftID==plan.draftID&&$0.commitPlanSHA256==plan.planSHA256&&$0.mutationID==rowMutationIDs.reservationByStageID[$0.stageID]})else{throw FieldDraftFailureV1.missingContent}
        for reservation in reservations{_ = try writer.append(reservation:reservation,expectedRevision:0)}
        _ = try writer.append(saga:contentPromoted,expectedRevision:prepared.revision)
        let targetReceipt=try target.commit(plan:plan,reservations:reservations)
        guard try target.readBackMatches(plan:plan,receipt:targetReceipt)else{throw FieldDraftFailureV1.missingReceipt}
        _ = try writer.append(saga:targetCommitted,expectedRevision:contentPromoted.revision)
        _ = try writer.append(saga:retirePending,expectedRevision:targetCommitted.revision)
        let mapping=Dictionary(uniqueKeysWithValues:reservations.map{($0.stageID.uuidString,$0.locator.contentID)})
        let chain=[prepared,contentPromoted,targetCommitted,retirePending,retired].map(\.sagaSHA256)
        let receipt=try DraftCommitReceiptV1(receiptID:commitReceiptID,workspaceID:plan.workspaceID,draftID:plan.draftID,sagaID:retired.sagaID,commitPlanSHA256:plan.planSHA256,sagaEventSHA256Chain:chain,targetMutationID:plan.mutationID,targetReceiptSHA256:targetReceipt.resultSHA256,consumedStageToContentID:mapping,committedAt:targetReceipt.committedAt,mutationID:rowMutationIDs.terminalBundleMutationID)
        let revision=checkpoint.draftRevision.addingReportingOverflow(1);guard !revision.overflow else{throw FieldDraftFailureV1.staleDraftRevision}
        let terminalCheckpoint=try FieldDraftCheckpointV1(draftID:checkpoint.draftID,workspaceID:checkpoint.workspaceID,scope:checkpoint.scope,purpose:checkpoint.purpose,codec:checkpoint.codec,baseCanonicalRevision:checkpoint.baseCanonicalRevision,draftRevision:revision.partialValue,payloadData:checkpoint.payloadData,stageIDs:checkpoint.stageIDs,resumeAnchor:checkpoint.resumeAnchor,state:.committed,lastDurableMutationID:rowMutationIDs.terminalBundleMutationID,lastReceiptSHA256:receipt.receiptSHA256,updatedAt:terminalCheckpointUpdatedAt,mutationID:rowMutationIDs.terminalBundleMutationID)
        try terminalCheckpoint.validateSuccessor(of:checkpoint,expectedDraftRevision:checkpoint.draftRevision,expectedBaseRevision:checkpoint.baseCanonicalRevision)
        let bundle=try DraftCommitTerminalBundleV1(retiredSaga:retired,committedCheckpoint:terminalCheckpoint,receipt:receipt)
        _ = try writer.apply(commitTerminalBundle:bundle,expectedDraftRevision:checkpoint.draftRevision,expectedSagaRevision:retirePending.revision)
        return receipt
    }

    func discard(plan:DraftDiscardPlanV1,checkpoint:FieldDraftCheckpointV1,reservations:[DraftContentReservationV1],disposedStageIDs:[UUID],discardReceiptID:UUID,at instant:Date,mutationID:MutationIDV1)async throws->DraftDiscardReceiptV1{
        try plan.validate();try checkpoint.validate(registry:registry);try reservations.forEach{$0.validate()};guard checkpoint.state == .discardPending,checkpoint.workspaceID==plan.workspaceID,checkpoint.draftID==plan.draftID,checkpoint.draftRevision==plan.expectedDraftRevision,Set(disposedStageIDs).count==disposedStageIDs.count,Set(reservations.map(\.reservationID)).count==reservations.count,Set(disposedStageIDs).isSubset(of:Set(plan.stageIDs)),Set(reservations.map(\.reservationID)).isSubset(of:Set(plan.reservationIDs)),reservations.allSatisfy({$0.workspaceID==plan.workspaceID&&$0.draftID==plan.draftID})else{throw FieldDraftFailureV1.invalidValue}
        try await content.quarantine(reservations:reservations,for:plan)
        let receipt=try DraftDiscardReceiptV1(receiptID:discardReceiptID,workspaceID:plan.workspaceID,draftID:plan.draftID,planSHA256:plan.planSHA256,disposedStageIDs:disposedStageIDs,quarantinedReservationIDs:reservations.map(\.reservationID),discardedAt:instant,mutationID:mutationID)
        let revision=checkpoint.draftRevision.addingReportingOverflow(1);guard !revision.overflow else{throw FieldDraftFailureV1.staleDraftRevision}
        let terminalCheckpoint=try FieldDraftCheckpointV1(draftID:checkpoint.draftID,workspaceID:checkpoint.workspaceID,scope:checkpoint.scope,purpose:checkpoint.purpose,codec:checkpoint.codec,baseCanonicalRevision:checkpoint.baseCanonicalRevision,draftRevision:revision.partialValue,payloadData:checkpoint.payloadData,stageIDs:checkpoint.stageIDs,resumeAnchor:checkpoint.resumeAnchor,state:.discarded,lastDurableMutationID:mutationID,lastReceiptSHA256:receipt.receiptSHA256,updatedAt:instant,mutationID:mutationID)
        try terminalCheckpoint.validateSuccessor(of:checkpoint,expectedDraftRevision:checkpoint.draftRevision,expectedBaseRevision:checkpoint.baseCanonicalRevision)
        let bundle=try DraftDiscardTerminalBundleV1(discardedCheckpoint:terminalCheckpoint,receipt:receipt)
        _ = try writer.apply(discardTerminalBundle:bundle,expectedDraftRevision:checkpoint.draftRevision)
        return receipt
    }
}

extension FieldDraftCoordinatorV1 {
    /// C23-aware checkpoint entry point. The reference tuple is checked before
    /// the existing checkpoint CAS and is never copied into the draft row.
    @MainActor
    func checkpoint(
        _ value: FieldDraftCheckpointV1,
        expectedDraftRevision: UInt64,
        expectedBaseRevision: UInt64,
        fieldReferenceBinding: FieldReferenceBindingV1,
        fieldReferenceRelease: FieldReferenceReleaseV1,
        fieldReferenceReadiness: FieldReferenceOfflineReadinessV1
    ) throws -> MutationReceiptV1 {
        _ = try value.c23ReferenceProjection(
            binding: fieldReferenceBinding,
            release: fieldReferenceRelease,
            readiness: fieldReferenceReadiness
        )
        return try checkpoint(
            value,
            expectedDraftRevision: expectedDraftRevision,
            expectedBaseRevision: expectedBaseRevision
        )
    }

    /// Read-only validation used by commit/recovery coordinators immediately
    /// before they operate on a draft. Finalized checkpoints cannot accept a
    /// replacement binding; callers must use an explicit C23 successor while
    /// the session is still active.
    @MainActor
    func validateFieldReference(
        checkpoint: FieldDraftCheckpointV1,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws -> FieldDraftReferenceProjectionV1 {
        guard let durable = try writer.currentCheckpoint(
            workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID
        ), durable.checkpointSHA256 == checkpoint.checkpointSHA256 else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        return try durable.c23ReferenceProjection(
            binding: binding, release: release, readiness: readiness
        )
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_Drafts_FieldDraftCoordinatorV1_swift {
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
enum C30ConsumerBoundaryV1_Application_Drafts_FieldDraftCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift", role: .draft)
}

enum C31LightingConsumerBoundary_Application_Drafts_FieldDraftCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/field-draft-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}
// MARK: - C32 assistance field draft boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_Drafts_FieldDraftCoordinatorV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let manualDraftTextRemainsIndependent = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceBoundary_Application_Drafts_FieldDraftCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row162 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_Drafts_FieldDraftCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

enum C34RouteAdoptionBoundary_FieldDraftCoordinatorV1 {
    static let draftAnchorType = DraftResumeAnchorV1.self
    static let routeAnchorType = FieldPositionAnchorV1.self
    static let routeCarriesSemanticIDsOnly = true
}

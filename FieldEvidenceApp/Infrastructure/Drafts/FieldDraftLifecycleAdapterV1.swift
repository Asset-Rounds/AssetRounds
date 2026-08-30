import Foundation
import SwiftData

@MainActor final class FieldDraftLifecycleAdapterV1:FieldDraftWritingV1{
    private let writer:WorkspaceWriterV1
    private let journal:MutationJournalStoreV1
    private let context:ModelContext
    init(writer:WorkspaceWriterV1,journal:MutationJournalStoreV1,modelContext:ModelContext){self.writer=writer;self.journal=journal;context=modelContext}
    func currentCheckpoint(workspaceID:WorkspaceID,draftID:UUID)throws->FieldDraftCheckpointV1?{let id=draftID;let rows=try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>(predicate:#Predicate{$0.draftID==id}));guard rows.count<=1 else{throw FieldDraftFailureV1.invalidValue};guard let row=rows.first else{return nil};let value=try row.value();guard value.workspaceID==workspaceID else{throw FieldDraftFailureV1.wrongWorkspace};return value}
    func compareAndSwap(checkpoint value:FieldDraftCheckpointV1,expectedDraftRevision:UInt64,expectedBaseRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedDraftRevision,expectedBaseCanonicalRevision:expectedBaseRevision,mutationID:value.mutationID,postImage:expectedDraftRevision==0 ? .createCheckpoint(value):.reviseCheckpoint(value)))}
    func append(stagingItem value:AttachmentStagingItemV1,expectedRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedRevision,expectedBaseCanonicalRevision:0,mutationID:value.mutationID,postImage:expectedRevision==0 ? .appendStagingItem(value):.reviseStagingItem(value)))}
    func append(saga value:DraftCommitSagaV1,expectedRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedRevision,expectedBaseCanonicalRevision:value.plan.baseCanonicalRevision,mutationID:value.mutationID,postImage:expectedRevision==0 ? .appendCommitSaga(value):.advanceCommitSaga(value)))}
    func append(reservation value:DraftContentReservationV1,expectedRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedRevision,expectedBaseCanonicalRevision:0,mutationID:value.mutationID,postImage:expectedRevision==0 ? .appendContentReservation(value):.reviseContentReservation(value)))}
    func apply(commitTerminalBundle value:DraftCommitTerminalBundleV1,expectedDraftRevision:UInt64,expectedSagaRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedDraftRevision,expectedBaseCanonicalRevision:value.committedCheckpoint.baseCanonicalRevision,mutationID:value.mutationID,postImage:.applyCommitTerminal(value,expectedSagaRevision:expectedSagaRevision)))}
    func apply(discardTerminalBundle value:DraftDiscardTerminalBundleV1,expectedDraftRevision:UInt64)throws->MutationReceiptV1{try execute(.init(workspaceID:value.workspaceID,expectedRevision:expectedDraftRevision,expectedBaseCanonicalRevision:value.discardedCheckpoint.baseCanonicalRevision,mutationID:value.mutationID,postImage:.applyDiscardTerminal(value)))}
    private func execute(_ mutation:FieldDraftMutationV1)throws->MutationReceiptV1{_ = try writer.execute(.applyFieldDraft(mutation),mutationID:mutation.mutationID);guard let receipt=try journal.receipt(mutationID:mutation.mutationID)else{throw FieldDraftFailureV1.missingReceipt};_ = try FieldDraftMutationReceiptV1(mutation:mutation,mutationReceipt:receipt);return receipt}
}

extension FieldDraftLifecycleAdapterV1 {
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

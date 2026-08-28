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
}

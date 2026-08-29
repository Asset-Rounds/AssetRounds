import Foundation
enum EvidenceContextFieldDraftBoundaryV1{static let draftContextPreviewsAreDisposable=true;static let acceptedContextUsesSoleWorkspaceWriter=true}
enum PlacementPoseFieldDraftPersistenceBoundaryV1{static let draftPoseProposalsRemainDisposable=true;static let acceptedPoseWritesUseTheWorkspaceWriter=true}
import SwiftData

private func fieldDraftStoredRevision(_ value: UInt64) throws -> Int64 {
    guard value > 0, value <= UInt64(Int64.max) else { throw FieldDraftFailureV1.invalidValue }
    return Int64(value)
}
private func fieldDraftDomainRevision(_ value: Int64) throws -> UInt64 {
    guard value > 0 else { throw FieldDraftFailureV1.invalidValue }
    return UInt64(value)
}

@Model final class FieldDraftCheckpointRow {
    @Attribute(.unique) private(set) var draftID: UUID
    private(set) var workspaceID: UUID; private(set) var revision: Int64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String
    private(set) var canonicalData: Data
    init(_ value: FieldDraftCheckpointV1) throws { try value.validate(); draftID=value.draftID; workspaceID=value.workspaceID.rawValue; revision=try fieldDraftStoredRevision(value.draftRevision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.checkpointSHA256; canonicalData=try FieldDraftCanonicalCodecV1.encode(value) }
    func value() throws -> FieldDraftCheckpointV1 { let value=try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self,from:canonicalData); guard value.draftID==draftID,value.workspaceID.rawValue==workspaceID,value.draftRevision==(try fieldDraftDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.checkpointSHA256==canonicalSHA256 else{throw FieldDraftFailureV1.digestMismatch};return value }
    func replace(with value:FieldDraftCheckpointV1,expectedRevision:UInt64)throws{let prior=try self.value();try value.validateSuccessor(of:prior,expectedDraftRevision:expectedRevision,expectedBaseRevision:prior.baseCanonicalRevision);workspaceID=value.workspaceID.rawValue;revision=try fieldDraftStoredRevision(value.draftRevision);mutationID=value.mutationID.rawValue;canonicalSHA256=value.checkpointSHA256;canonicalData=try FieldDraftCanonicalCodecV1.encode(value)}
}

@Model final class AttachmentStagingItemRow {
    @Attribute(.unique) private(set) var stageID:UUID
    private(set) var draftID:UUID;private(set) var workspaceID:UUID;private(set) var revision:Int64
    private(set) var mutationID:UUID;private(set) var canonicalSHA256:String;private(set) var canonicalData:Data
    init(_ value:AttachmentStagingItemV1)throws{try value.validate();stageID=value.stageID;draftID=value.draftID;workspaceID=value.workspaceID.rawValue;revision=try fieldDraftStoredRevision(value.revision);mutationID=value.mutationID.rawValue;canonicalSHA256=value.stageSHA256;canonicalData=try FieldDraftCanonicalCodecV1.encode(value)}
    func value()throws->AttachmentStagingItemV1{let value=try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self,from:canonicalData);guard value.stageID==stageID,value.draftID==draftID,value.workspaceID.rawValue==workspaceID,value.revision==(try fieldDraftDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.stageSHA256==canonicalSHA256 else{throw FieldDraftFailureV1.digestMismatch};return value}
    func replace(with value:AttachmentStagingItemV1,expectedRevision:UInt64)throws{let prior=try self.value();guard prior.revision==expectedRevision else{throw FieldDraftFailureV1.staleDraftRevision};try value.validateSuccessor(of:prior);draftID=value.draftID;workspaceID=value.workspaceID.rawValue;revision=try fieldDraftStoredRevision(value.revision);mutationID=value.mutationID.rawValue;canonicalSHA256=value.stageSHA256;canonicalData=try FieldDraftCanonicalCodecV1.encode(value)}
}

@Model final class DraftCommitSagaRow {
    @Attribute(.unique) private(set) var sagaID:UUID
    private(set) var draftID:UUID;private(set) var workspaceID:UUID;private(set) var predecessorSagaID:UUID?
    private(set) var revision:Int64;private(set) var mutationID:UUID;private(set) var canonicalSHA256:String;private(set) var canonicalData:Data
    init(_ value:DraftCommitSagaV1)throws{try value.validate();sagaID=value.sagaID;draftID=value.draftID;workspaceID=value.workspaceID.rawValue;predecessorSagaID=value.predecessorSagaID;revision=try fieldDraftStoredRevision(value.revision);mutationID=value.mutationID.rawValue;canonicalSHA256=value.sagaSHA256;canonicalData=try FieldDraftCanonicalCodecV1.encode(value)}
    func value()throws->DraftCommitSagaV1{let value=try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self,from:canonicalData);guard value.sagaID==sagaID,value.draftID==draftID,value.workspaceID.rawValue==workspaceID,value.predecessorSagaID==predecessorSagaID,value.revision==(try fieldDraftDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.sagaSHA256==canonicalSHA256 else{throw FieldDraftFailureV1.digestMismatch};return value}
}

@Model final class DraftContentReservationRow {
    @Attribute(.unique) private(set) var reservationID:UUID
    private(set) var draftID:UUID;private(set) var stageID:UUID;private(set) var workspaceID:UUID
    private(set) var revision:Int64;private(set) var mutationID:UUID;private(set) var canonicalSHA256:String;private(set) var canonicalData:Data
    init(_ value:DraftContentReservationV1)throws{try value.validate();reservationID=value.reservationID;draftID=value.draftID;stageID=value.stageID;workspaceID=value.workspaceID.rawValue;revision=try fieldDraftStoredRevision(value.revision);mutationID=value.mutationID.rawValue;canonicalSHA256=value.reservationSHA256;canonicalData=try FieldDraftCanonicalCodecV1.encode(value)}
    func value()throws->DraftContentReservationV1{let value=try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self,from:canonicalData);guard value.reservationID==reservationID,value.draftID==draftID,value.stageID==stageID,value.workspaceID.rawValue==workspaceID,value.revision==(try fieldDraftDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.reservationSHA256==canonicalSHA256 else{throw FieldDraftFailureV1.digestMismatch};return value}
    func replace(with value:DraftContentReservationV1,expectedRevision:UInt64)throws{let prior=try self.value();guard prior.revision==expectedRevision else{throw FieldDraftFailureV1.staleDraftRevision};try value.validateSuccessor(of:prior);draftID=value.draftID;stageID=value.stageID;workspaceID=value.workspaceID.rawValue;revision=try fieldDraftStoredRevision(value.revision);mutationID=value.mutationID.rawValue;canonicalSHA256=value.reservationSHA256;canonicalData=try FieldDraftCanonicalCodecV1.encode(value)}
}

@Model final class DraftCommitReceiptRow {
    @Attribute(.unique) private(set) var receiptID:UUID
    private(set) var draftID:UUID;private(set) var sagaID:UUID;private(set) var workspaceID:UUID
    private(set) var revision:Int64;private(set) var mutationID:UUID;private(set) var canonicalSHA256:String;private(set) var canonicalData:Data
    init(_ value:DraftCommitReceiptV1)throws{try value.validate();receiptID=value.receiptID;draftID=value.draftID;sagaID=value.sagaID;workspaceID=value.workspaceID.rawValue;revision=try fieldDraftStoredRevision(value.revision);mutationID=value.mutationID.rawValue;canonicalSHA256=value.receiptSHA256;canonicalData=try FieldDraftCanonicalCodecV1.encode(value)}
    func value()throws->DraftCommitReceiptV1{let value=try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self,from:canonicalData);guard value.receiptID==receiptID,value.draftID==draftID,value.sagaID==sagaID,value.workspaceID.rawValue==workspaceID,value.revision==(try fieldDraftDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.receiptSHA256==canonicalSHA256 else{throw FieldDraftFailureV1.digestMismatch};return value}
}

@Model final class DraftDiscardReceiptRow {
    @Attribute(.unique) private(set) var receiptID:UUID
    private(set) var draftID:UUID;private(set) var workspaceID:UUID;private(set) var revision:Int64
    private(set) var mutationID:UUID;private(set) var canonicalSHA256:String;private(set) var canonicalData:Data
    init(_ value:DraftDiscardReceiptV1)throws{try value.validate();receiptID=value.receiptID;draftID=value.draftID;workspaceID=value.workspaceID.rawValue;revision=try fieldDraftStoredRevision(value.revision);mutationID=value.mutationID.rawValue;canonicalSHA256=value.receiptSHA256;canonicalData=try FieldDraftCanonicalCodecV1.encode(value)}
    func value()throws->DraftDiscardReceiptV1{let value=try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self,from:canonicalData);guard value.receiptID==receiptID,value.draftID==draftID,value.workspaceID.rawValue==workspaceID,value.revision==(try fieldDraftDomainRevision(revision)),value.mutationID.rawValue==mutationID,value.receiptSHA256==canonicalSHA256 else{throw FieldDraftFailureV1.digestMismatch};return value}
}

/// Schema inventory marker: DraftUpgradePlanV1 previews deliberately add no
/// C36 column or model. Only the resulting checkpoint successor is durable.
enum PackageEvolutionDraftPersistenceBoundaryV1 {
    static let addsPersistentModel = false
    static let storedResultType = "FieldDraftCheckpointRow"

    /// C21 capability/profile/policy/disposition/decision values are
    /// authoritative inputs to a draft-upgrade preview, not draft columns.
    /// The four capability rows live in their own package-lifecycle model
    /// file; this boundary deliberately keeps the C36 draft schema unchanged.
    static let capabilityInputsPersistent = false
    static let capabilityInputStore = "ClientCapabilityPersistenceModelsV1"
    static let capabilityDecisionOperation = PackageLifecycleOperationV1.upgradeDraft

    static func validateUpgradeInputs(
        plan: DraftUpgradePlanV1,
        source: FieldDraftCheckpointV1,
        diff: PackageSemanticDiffV1,
        admittedBy capability: ClientCapabilityLifecycleClosureV1
    ) throws {
        try PackageEvolutionDraftBoundaryV1.validateUpgradePreview(
            plan: plan,
            source: source,
            diff: diff,
            admittedBy: capability
        )
    }
}

/// C23 deliberately keeps reference bindings out of the draft row family.
/// This boundary makes that decision inspectable while requiring every draft
/// read to prove the exact release/binding/readiness tuple.
enum FieldDraftReferencePersistenceBoundaryV1 {
    static let persistentBindingFamilies = FieldReferencePackLifecycleV1.persistentFamilies
    static let draftReferenceProjectionPersistence = "DERIVED_ONLY"
    static let acceptsUnboundDraftBytes = false

    static func validate(
        checkpoint: FieldDraftCheckpointV1,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws -> FieldDraftReferenceProjectionV1 {
        try checkpoint.c23ReferenceProjection(
            binding: binding, release: release, readiness: readiness
        )
    }
}

extension FieldDraftCheckpointRow {
    func c23ReferenceProjection(
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws -> FieldDraftReferenceProjectionV1 {
        let checkpoint = try value()
        return try FieldDraftReferencePersistenceBoundaryV1.validate(
            checkpoint: checkpoint,
            binding: binding,
            release: release,
            readiness: readiness
        )
    }
}

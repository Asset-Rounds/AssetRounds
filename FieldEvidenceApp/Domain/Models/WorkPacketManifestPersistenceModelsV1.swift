import Foundation
enum EvidenceContextWorkPacketBoundaryV1{static let manifestsMayReferenceEvidenceRevisionButDoNotEmbedContextRows=true}
enum PlacementPoseWorkPacketPersistenceBoundaryV1{static let packetsReferencePoseResultsWithoutOwningTips=true}
import SwiftData

enum PlanWorkPacketBoundaryV1 { static let planRebaseDoesNotCreateWorkPackets = true; static let planRevisionHistoryIsImmutable = true }
private func workPacketStoredRevision(_ v:UInt64)throws->Int64{guard v>0,v<=UInt64(Int64.max)else{throw WorkPacketFailureV1.invalidValue};return Int64(v)}
private func workPacketDomainRevision(_ v:Int64)throws->UInt64{guard v>0 else{throw WorkPacketFailureV1.invalidValue};return UInt64(v)}
@Model final class WorkPacketManifestRow{@Attribute(.unique)private(set)var manifestID:UUID;private(set)var packetID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ v:WorkPacketManifestV1)throws{try v.validate();let d=try WorkPacketCanonicalCodecV1.encode(v);manifestID=v.manifestID;packetID=v.packetID;workspaceID=v.workspaceID.rawValue;revision=try workPacketStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.manifestSHA256;canonicalData=d}func value()throws->WorkPacketManifestV1{let v=try WorkPacketCanonicalCodecV1.decode(WorkPacketManifestV1.self,from:canonicalData);guard v.manifestID==manifestID,v.packetID==packetID,v.workspaceID.rawValue==workspaceID,v.revision==(try workPacketDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.manifestSHA256==canonicalSHA256 else{throw WorkPacketFailureV1.digestMismatch};return v}}
@Model final class WorkItemClaimRow{@Attribute(.unique)private(set)var claimID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ v:WorkItemClaimV1)throws{try v.validate();claimID=v.claimID;workspaceID=v.workspaceID.rawValue;revision=try workPacketStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.claimSHA256;canonicalData=try WorkPacketCanonicalCodecV1.encode(v)}func value()throws->WorkItemClaimV1{let v=try WorkPacketCanonicalCodecV1.decode(WorkItemClaimV1.self,from:canonicalData);guard v.claimID==claimID,v.workspaceID.rawValue==workspaceID,v.revision==(try workPacketDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.claimSHA256==canonicalSHA256 else{throw WorkPacketFailureV1.digestMismatch};return v}}
@Model final class WorkLeaseRow{@Attribute(.unique)private(set)var leaseID:UUID;private(set)var claimID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ v:WorkLeaseV1)throws{try v.validate();leaseID=v.leaseID;claimID=v.claimID;workspaceID=v.workspaceID.rawValue;revision=try workPacketStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.leaseSHA256;canonicalData=try WorkPacketCanonicalCodecV1.encode(v)}func value()throws->WorkLeaseV1{let v=try WorkPacketCanonicalCodecV1.decode(WorkLeaseV1.self,from:canonicalData);guard v.leaseID==leaseID,v.claimID==claimID,v.workspaceID.rawValue==workspaceID,v.revision==(try workPacketDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.leaseSHA256==canonicalSHA256 else{throw WorkPacketFailureV1.digestMismatch};return v}}
@Model final class WorkReleaseRow{@Attribute(.unique)private(set)var releaseID:UUID;private(set)var claimID:UUID;private(set)var leaseID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ v:WorkReleaseV1)throws{try v.validate();releaseID=v.releaseID;claimID=v.claimID;leaseID=v.leaseID;workspaceID=v.workspaceID.rawValue;revision=try workPacketStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.releaseSHA256;canonicalData=try WorkPacketCanonicalCodecV1.encode(v)}func value()throws->WorkReleaseV1{let v=try WorkPacketCanonicalCodecV1.decode(WorkReleaseV1.self,from:canonicalData);guard v.releaseID==releaseID,v.claimID==claimID,v.leaseID==leaseID,v.workspaceID.rawValue==workspaceID,v.revision==(try workPacketDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.releaseSHA256==canonicalSHA256 else{throw WorkPacketFailureV1.digestMismatch};return v}}
@Model final class WorkHandoffRow{@Attribute(.unique)private(set)var handoffID:UUID;private(set)var releaseID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ v:WorkHandoffV1)throws{try v.validate();handoffID=v.handoffID;releaseID=v.releaseID;workspaceID=v.workspaceID.rawValue;revision=try workPacketStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.handoffSHA256;canonicalData=try WorkPacketCanonicalCodecV1.encode(v)}func value()throws->WorkHandoffV1{let v=try WorkPacketCanonicalCodecV1.decode(WorkHandoffV1.self,from:canonicalData);guard v.handoffID==handoffID,v.releaseID==releaseID,v.workspaceID.rawValue==workspaceID,v.revision==(try workPacketDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.handoffSHA256==canonicalSHA256 else{throw WorkPacketFailureV1.digestMismatch};return v}}

/// C23 reference bindings are separate canonical rows. Work-packet rows only
/// expose a read-only proof boundary and never duplicate the binding store.
enum WorkPacketReferencePersistenceBoundaryV1 {
    static let bindingFamily = "FieldReferenceBindingV1"
    static let releaseFamily = "FieldReferenceReleaseV1"
    static let projectionPersistence = "DERIVED_ONLY"
    static let writer = "SOLE_CANONICAL_WORKSPACE_WRITER"

    static func validate(
        manifest: WorkPacketManifestV1,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        try manifest.c23ValidateReferenceBinding(
            binding,
            release: release,
            readiness: readiness,
            subjectState: subjectState
        )
    }
}

extension WorkPacketManifestRow {
    /// A persisted manifest may be consumed only with an independently read
    /// C23 binding whose packet subject and exact release/manifest digests
    /// match this row's decoded manifest.
    func c23ValidateReferenceBinding(
        _ binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        let manifest = try value()
        return try WorkPacketReferencePersistenceBoundaryV1.validate(
            manifest: manifest,
            binding: binding,
            release: release,
            readiness: readiness,
            subjectState: subjectState
        )
    }
}


extension WorkPacketManifestRow {
    /// Resolves the exact pre-created work packet referenced by an atomic C28
    /// START event. The schedule event stores only this immutable reference.
    func value(matching reference: WorkPacketManifestReferenceV1) throws -> WorkPacketManifestV1 {
        let manifest = try value()
        guard try WorkPacketManifestReferenceV1(manifest) == reference else {
            throw WorkPacketFailureV1.digestMismatch
        }
        return manifest
    }
}

enum LightingWorkPacketReuseV1 { static let workPacketRowsRemainExistingAuthority = true; static let lightingAddsNoPacketRow = true }

enum C31LightingWorkPacketPersistenceBoundaryV1 {
    static let persistedManifestBytesAreNotDuplicated = true
    static let projectionStoresDigestAndReferenceOnly = true
    static let missingPackageDataFailsClosed = true
}
// MARK: - C32 assistance work packet persistence boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_WorkPacketManifestPersistenceModelsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalNotPersistedInWorkPacketRows = true

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

enum C33TemporalEvidenceBoundary_Domain_Models_WorkPacketManifestPersistenceModelsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

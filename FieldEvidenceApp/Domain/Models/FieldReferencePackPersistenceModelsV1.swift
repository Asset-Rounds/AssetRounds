import Foundation
enum EvidenceContextFieldReferenceBoundaryV1{static let referencePackContentDoesNotOwnObservedLightingOrSolarContext=true}
enum PlacementPoseFieldReferencePersistenceBoundaryV1{static let fieldReferenceRowsOwnNoPoseAxesOrTips=true}
import SwiftData

enum PlanFieldReferencePersistenceBindingV1 { static let planRevisionRequiresExactRelease = true; static let originalContentAuthorityIsPreserved = true }

enum FieldReferencePackPersistenceFailureV1: Error { case corruptRow }

@Model final class FieldReferenceReleaseRow {
    @Attribute(.unique) var releaseID: UUID
    var workspaceID: UUID
    var referencePackID: String
    var revision: UInt64
    var mutationID: UUID
    var manifestSHA256: String
    var releaseSHA256: String
    var canonicalData: Data

    init(_ value: FieldReferenceReleaseV1) throws {
        try value.validate()
        releaseID=value.releaseID;workspaceID=value.workspaceID.rawValue;referencePackID=value.referencePackID
        revision=value.revision;mutationID=value.mutationID.rawValue;manifestSHA256=value.manifestSHA256
        releaseSHA256=value.releaseSHA256;canonicalData=try FieldReferencePackCanonicalCodecV1.encode(value)
    }

    func value() throws -> FieldReferenceReleaseV1 {
        let value=try FieldReferencePackCanonicalCodecV1.decode(FieldReferenceReleaseV1.self,from:canonicalData)
        try value.validate()
        guard value.releaseID==releaseID,value.workspaceID.rawValue==workspaceID,value.referencePackID==referencePackID,
              value.revision==revision,value.mutationID.rawValue==mutationID,value.manifestSHA256==manifestSHA256,
              value.releaseSHA256==releaseSHA256 else{throw FieldReferencePackPersistenceFailureV1.corruptRow}
        return value
    }
}

@Model final class FieldReferenceBindingRow {
    @Attribute(.unique) var bindingID: UUID
    var workspaceID: UUID
    var subjectID: UUID
    var releaseID: UUID
    var revision: UInt64
    var mutationID: UUID
    var bindingSHA256: String
    var canonicalData: Data

    init(_ value: FieldReferenceBindingV1, release: FieldReferenceReleaseV1) throws {
        try value.validate(release:release)
        bindingID=value.bindingID;workspaceID=value.workspaceID.rawValue;subjectID=value.subjectID;releaseID=value.releaseID
        revision=value.revision;mutationID=value.mutationID.rawValue;bindingSHA256=value.bindingSHA256
        canonicalData=try FieldReferencePackCanonicalCodecV1.encode(value)
    }

    func value(release: FieldReferenceReleaseV1) throws -> FieldReferenceBindingV1 {
        let value=try FieldReferencePackCanonicalCodecV1.decode(FieldReferenceBindingV1.self,from:canonicalData)
        try value.validate(release:release)
        guard value.bindingID==bindingID,value.workspaceID.rawValue==workspaceID,value.subjectID==subjectID,
              value.releaseID==releaseID,value.revision==revision,value.mutationID.rawValue==mutationID,
              value.bindingSHA256==bindingSHA256 else{throw FieldReferencePackPersistenceFailureV1.corruptRow}
        return value
    }
}

enum LightingFieldReferenceReuseV1 { static let criterionLocatorsRemainExactReferences = true; static let licensedTextIsNotPersistedByLighting = true }

enum C31LightingReferencePackPersistenceBoundaryV1 {
    static let packBindingIsExistingPersistenceAuthority = true
    static let lightingStoresNoReferencePackCopy = true
    static let projectionCarriesOnlyDigestAndIDs = true
}
// MARK: - C32 assistance reference pack persistence boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_FieldReferencePackPersistenceModelsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalNotPersistedInReferencePackRows = true

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

enum C33TemporalEvidenceBoundary_Domain_Models_FieldReferencePackPersistenceModelsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

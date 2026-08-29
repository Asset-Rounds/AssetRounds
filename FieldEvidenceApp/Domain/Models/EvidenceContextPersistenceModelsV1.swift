import Foundation
import SwiftData

enum EvidenceContextPersistenceFailureV1:Error{case corruptRow}

@Model final class EvidenceContextRow{
    @Attribute(.unique)var contextID:UUID
    var workspaceID:UUID;var evidenceID:String;var evidenceSHA256:String;var evidenceRevision:UInt64
    var assetID:UUID;var assetRevision:UInt64;var predecessorContextSHA256:String?
    var revision:UInt64;var mutationID:UUID;var contextSHA256:String;var canonicalData:Data
    init(_ value:EvidenceContextV1)throws{try value.validateIntrinsic();contextID=value.contextID;workspaceID=value.workspaceID.rawValue;evidenceID=value.evidenceID;evidenceSHA256=value.evidenceSHA256;evidenceRevision=value.evidenceRevision;assetID=value.assetID;assetRevision=value.assetRevision;predecessorContextSHA256=value.predecessorContextSHA256;revision=value.revision;mutationID=value.mutationID.rawValue;contextSHA256=value.contextSHA256;canonicalData=try EvidenceContextCanonicalCodecV1.encode(value);guard try EvidenceContextCanonicalCodecV1.decode(EvidenceContextV1.self,from:canonicalData)==value else{throw EvidenceContextPersistenceFailureV1.corruptRow}}
    func value()throws->EvidenceContextV1{let value=try EvidenceContextCanonicalCodecV1.decode(EvidenceContextV1.self,from:canonicalData);try value.validateIntrinsic();guard value.contextID==contextID,value.workspaceID.rawValue==workspaceID,value.evidenceID==evidenceID,value.evidenceSHA256==evidenceSHA256,value.evidenceRevision==evidenceRevision,value.assetID==assetID,value.assetRevision==assetRevision,value.predecessorContextSHA256==predecessorContextSHA256,value.revision==revision,value.mutationID.rawValue==mutationID,value.contextSHA256==contextSHA256 else{throw EvidenceContextPersistenceFailureV1.corruptRow};return value}
}

@Model final class PairedObservationLinkRow{
    @Attribute(.unique)var linkID:UUID
    var workspaceID:UUID;var firstEvidenceID:String;var firstEvidenceSHA256:String;var firstEvidenceRevision:UInt64;var secondEvidenceID:String;var secondEvidenceSHA256:String;var secondEvidenceRevision:UInt64;var assetID:UUID;var firstAssetRevision:UInt64;var secondAssetRevision:UInt64
    var predecessorLinkSHA256:String?;var revision:UInt64;var mutationID:UUID
    var linkSHA256:String;var canonicalData:Data
    init(_ value:PairedObservationLinkV1)throws{try value.validateIntrinsic();linkID=value.linkID;workspaceID=value.workspaceID.rawValue;firstEvidenceID=value.first.evidenceID;firstEvidenceSHA256=value.first.evidenceSHA256;firstEvidenceRevision=value.first.evidenceRevision;secondEvidenceID=value.second.evidenceID;secondEvidenceSHA256=value.second.evidenceSHA256;secondEvidenceRevision=value.second.evidenceRevision;assetID=value.first.assetID;firstAssetRevision=value.first.assetRevision;secondAssetRevision=value.second.assetRevision;predecessorLinkSHA256=value.predecessorLinkSHA256;revision=value.revision;mutationID=value.mutationID.rawValue;linkSHA256=value.linkSHA256;canonicalData=try EvidenceContextCanonicalCodecV1.encode(value);guard try EvidenceContextCanonicalCodecV1.decode(PairedObservationLinkV1.self,from:canonicalData)==value else{throw EvidenceContextPersistenceFailureV1.corruptRow}}
    func value()throws->PairedObservationLinkV1{let value=try EvidenceContextCanonicalCodecV1.decode(PairedObservationLinkV1.self,from:canonicalData);try value.validateIntrinsic();guard value.linkID==linkID,value.workspaceID.rawValue==workspaceID,value.first.evidenceID==firstEvidenceID,value.first.evidenceSHA256==firstEvidenceSHA256,value.first.evidenceRevision==firstEvidenceRevision,value.second.evidenceID==secondEvidenceID,value.second.evidenceSHA256==secondEvidenceSHA256,value.second.evidenceRevision==secondEvidenceRevision,value.first.assetID==assetID,value.first.assetRevision==firstAssetRevision,value.second.assetID==assetID,value.second.assetRevision==secondAssetRevision,value.predecessorLinkSHA256==predecessorLinkSHA256,value.revision==revision,value.mutationID.rawValue==mutationID,value.linkSHA256==linkSHA256 else{throw EvidenceContextPersistenceFailureV1.corruptRow};return value}
}

enum EvidenceContextPersistenceEnrollmentV1{static let persistentSchemaVersion=30;static let recordsSchemaVersion=29;static let durableModelCount=2;static let totalModelCount=104}
enum LightingEvidenceContextReuseV1 { static let observationEmbedsExactEvidenceContext = true; static let lightingAddsNoEvidenceContextRow = true }

enum C31LightingEvidenceContextPersistenceBoundaryV1 {
    static let evidenceContextRowRemainsExistingAuthority = true
    static let lightingStoresOnlyContextReferenceAndDigest = true
    static let privateContextPayloadIsExcludedFromSearch = true
}
// MARK: - C32 assistance evidence context persistence boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_EvidenceContextPersistenceModelsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalNotPersistedInEvidenceRows = true

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

enum C33TemporalEvidenceBoundary_Domain_Models_EvidenceContextPersistenceModelsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row171 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

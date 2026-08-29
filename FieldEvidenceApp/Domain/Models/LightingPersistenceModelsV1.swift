import Foundation
import SwiftData

enum LightingPersistenceFailureV1: Error { case corruptRow }

@Model final class LightingSystemRow {
    @Attribute(.unique) var recordID: UUID
    var systemID: UUID; var workspaceID: UUID; var siteID: UUID; var supersedesRecordID: UUID?
    var revision: UInt64; var mutationID: UUID; var systemSHA256: String; var canonicalData: Data
    init(_ value: LightingSystemV1) throws { try value.validateIntrinsic(); recordID=value.recordID;systemID=value.systemID;workspaceID=value.workspaceID.rawValue;siteID=value.siteID;supersedesRecordID=value.supersedesRecordID;revision=value.revision;mutationID=value.mutationID.rawValue;systemSHA256=value.systemSHA256;canonicalData=try LightingCanonicalCodecV1.encode(value) }
    func value() throws -> LightingSystemV1 { let v=try LightingCanonicalCodecV1.decode(LightingSystemV1.self,from:canonicalData);try v.validateIntrinsic();guard v.recordID==recordID,v.systemID==systemID,v.workspaceID.rawValue==workspaceID,v.siteID==siteID,v.supersedesRecordID==supersedesRecordID,v.revision==revision,v.mutationID.rawValue==mutationID,v.systemSHA256==systemSHA256 else{throw LightingPersistenceFailureV1.corruptRow};return v }
}

@Model final class LightingObservationRow {
    @Attribute(.unique) var recordID: UUID
    var observationID: UUID; var workspaceID: UUID; var systemID: UUID; var supersedesRecordID: UUID?
    var revision: UInt64; var mutationID: UUID; var observationSHA256: String; var canonicalData: Data
    init(_ value: LightingObservationV1) throws { try value.validateIntrinsic();recordID=value.recordID;observationID=value.observationID;workspaceID=value.workspaceID.rawValue;systemID=value.systemID;supersedesRecordID=value.supersedesRecordID;revision=value.revision;mutationID=value.mutationID.rawValue;observationSHA256=value.observationSHA256;canonicalData=try LightingCanonicalCodecV1.encode(value) }
    func value() throws -> LightingObservationV1 { let v=try LightingCanonicalCodecV1.decode(LightingObservationV1.self,from:canonicalData);try v.validateIntrinsic();guard v.recordID==recordID,v.observationID==observationID,v.workspaceID.rawValue==workspaceID,v.systemID==systemID,v.supersedesRecordID==supersedesRecordID,v.revision==revision,v.mutationID.rawValue==mutationID,v.observationSHA256==observationSHA256 else{throw LightingPersistenceFailureV1.corruptRow};return v }
}

@Model final class LightingIssueRow {
    @Attribute(.unique) var recordID: UUID
    var issueID: UUID; var workspaceID: UUID; var supersedesRecordID: UUID?
    var revision: UInt64; var mutationID: UUID; var issueSHA256: String; var canonicalData: Data
    init(_ value: LightingIssueV1) throws { try value.validateIntrinsic();recordID=value.recordID;issueID=value.issueID;workspaceID=value.workspaceID.rawValue;supersedesRecordID=value.supersedesRecordID;revision=value.revision;mutationID=value.mutationID.rawValue;issueSHA256=value.issueSHA256;canonicalData=try LightingCanonicalCodecV1.encode(value) }
    func value() throws -> LightingIssueV1 { let v=try LightingCanonicalCodecV1.decode(LightingIssueV1.self,from:canonicalData);try v.validateIntrinsic();guard v.recordID==recordID,v.issueID==issueID,v.workspaceID.rawValue==workspaceID,v.supersedesRecordID==supersedesRecordID,v.revision==revision,v.mutationID.rawValue==mutationID,v.issueSHA256==issueSHA256 else{throw LightingPersistenceFailureV1.corruptRow};return v }
}

@Model final class MeasurementPlanRow {
    @Attribute(.unique) var recordID: UUID
    var planID: UUID; var workspaceID: UUID; var systemID: UUID; var supersedesRecordID: UUID?
    var revision: UInt64; var mutationID: UUID; var planSHA256: String; var canonicalData: Data
    init(_ value: MeasurementPlanV1) throws { try value.validateIntrinsic();recordID=value.recordID;planID=value.planID;workspaceID=value.workspaceID.rawValue;systemID=value.systemID;supersedesRecordID=value.supersedesRecordID;revision=value.revision;mutationID=value.mutationID.rawValue;planSHA256=value.planSHA256;canonicalData=try LightingCanonicalCodecV1.encode(value) }
    func value() throws -> MeasurementPlanV1 { let v=try LightingCanonicalCodecV1.decode(MeasurementPlanV1.self,from:canonicalData);try v.validateIntrinsic();guard v.recordID==recordID,v.planID==planID,v.workspaceID.rawValue==workspaceID,v.systemID==systemID,v.supersedesRecordID==supersedesRecordID,v.revision==revision,v.mutationID.rawValue==mutationID,v.planSHA256==planSHA256 else{throw LightingPersistenceFailureV1.corruptRow};return v }
}

@Model final class LightingClaimStateRow {
    @Attribute(.unique) var recordID: UUID
    var claimID: UUID; var workspaceID: UUID; var subjectAssetID: UUID; var supersedesRecordID: UUID?
    var revision: UInt64; var mutationID: UUID; var claimSHA256: String; var canonicalData: Data
    init(_ value: LightingClaimStateV1) throws { try value.validateIntrinsic();recordID=value.recordID;claimID=value.claimID;workspaceID=value.workspaceID.rawValue;subjectAssetID=value.subjectAssetID;supersedesRecordID=value.supersedesRecordID;revision=value.revision;mutationID=value.mutationID.rawValue;claimSHA256=value.claimSHA256;canonicalData=try LightingCanonicalCodecV1.encode(value) }
    func value() throws -> LightingClaimStateV1 { let v=try LightingCanonicalCodecV1.decode(LightingClaimStateV1.self,from:canonicalData);try v.validateIntrinsic();guard v.recordID==recordID,v.claimID==claimID,v.workspaceID.rawValue==workspaceID,v.subjectAssetID==subjectAssetID,v.supersedesRecordID==supersedesRecordID,v.revision==revision,v.mutationID.rawValue==mutationID,v.claimSHA256==claimSHA256 else{throw LightingPersistenceFailureV1.corruptRow};return v }
}

enum LightingPersistenceEnrollmentV1 { static let persistentSchemaVersion=31;static let recordsSchemaVersion=30;static let durableModelCount=5;static let totalModelCount=109 }
// MARK: - C32 assistance lighting persistence boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_LightingPersistenceModelsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalNotPersistedInLightingRows = true

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

enum C33TemporalEvidenceBoundary_Domain_Models_LightingPersistenceModelsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row175 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

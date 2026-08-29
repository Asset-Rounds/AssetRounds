import Foundation
enum EvidenceContextSiteBoundaryV1{static let solarLocationIsFrozenInContextBytes=true;static let siteRowsDoNotCacheDerivedSolarValues=true}
enum PlacementPoseSitePersistenceBoundaryV1{static let workspaceAndPlacementEpisodeAdmissionIsExternalToSiteRows=true}
import SwiftData

enum PlanSitePersistenceBoundaryV1 { static let siteIdentityMayAnchorLocationSubjects = true; static let planRowsDoNotDuplicateSiteState = true }

@Model
final class Site {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var label: String
    var address: String?
    var timeZoneID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        address: String? = nil,
        timeZoneID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = 1
        self.label = label
        self.address = address
        self.timeZoneID = timeZoneID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum LightingSiteIdentityEnrollmentV1 { static let lightingSystemBindsExistingSiteID = true; static let createsNoSiteProjectionRow = true }

enum C31LightingSiteBoundaryV1 {
    static let siteIdentityIsAReferenceOnly = true
    static let siteNameIsNotALightingConclusion = true
    static let topologyDoesNotCreateSiteFacts = true
}
// MARK: - C32 assistance site model boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_Site_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let locationProposalDoesNotCreateSite = true

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

enum C33TemporalEvidenceBoundary_Domain_Models_Site_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row147 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

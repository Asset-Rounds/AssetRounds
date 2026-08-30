import Foundation
import SwiftData
@MainActor final class EvidenceAssuranceLifecycleAdapterV1{
    private let modelContext:ModelContext;init(modelContext:ModelContext){self.modelContext=modelContext}
    func currentLinks(workspaceID:WorkspaceID,audience:EvidenceAudienceV1)throws->[ClaimEvidenceLinkV1]{let raw=workspaceID.rawValue;let values=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.workspaceID==raw})).map{try $0.value()};let superseded=Set(values.compactMap(\.supersedesLinkID));return values.filter{!superseded.contains($0.linkID)&&$0.decision.audience==audience}.sorted{$0.linkID.uuidString<$1.linkID.uuidString}}
    func preview(previewID:UUID,workspaceID:WorkspaceID,audience:EvidenceAudienceV1,snapshotSHA256:String,projectionVersion:String,createdAt:Date)throws->AssuranceProjectionPreviewV1{try .init(previewID:previewID,workspaceID:workspaceID,audience:audience,snapshotSHA256:snapshotSHA256,projectionVersion:projectionVersion,links:currentLinks(workspaceID:workspaceID,audience:audience),createdAt:createdAt)}
    func manifest(id:UUID,workspaceID:WorkspaceID,revision:UInt64,sha256:String)throws->AssuranceManifestV1{let rows=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard rows.count==1,let row=rows.first else{throw EvidenceAssuranceFailureV1.invalidValue};return try row.exactReference(id:id,workspaceID:workspaceID,revision:revision,sha256:sha256)}
}

enum EvidenceAssuranceAccessibleDocumentLifecycleV1{
    static let externalProofRequiresCanonicalEvidenceLinks=true
    static let assessmentDoesNotReplaceAssuranceManifest=true
}

enum C48PortableReviewEvidenceAssuranceBoundaryV1 {
    static let reviewResponseIsNotEvidenceAssurance = true
    static let capabilityBytesBecomeEvidence = false
    static let capabilityProofBytesBecomeEvidence = false
    static let responseBodyBecomesEvidence = false
    static let rawRequestResponseBytesBecomeEvidence = false
    static let existingAssuranceManifestRemainsCanonical = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }
}

// MARK: - C49 work-resource assurance lifecycle

extension EvidenceAssuranceLifecycleAdapterV1 {
    nonisolated static func workResourceAssurance(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> C49WorkResourceAssuranceProjectionV1 {
        try C49WorkResourceEvidenceAssuranceBoundaryV1.assess(projection)
    }
}

enum C49WorkResourceAssuranceLifecycleBoundaryV1 {
    static let assuranceIsRebuiltFromProjection = true
    static let assuranceDoesNotReplaceCanonicalManifest = true
    static let unsupportedCertificationClaims = false
    static let liveInventoryClaimsAssured = false
}

/// Assurance remains a projection of accepted canonical evidence. C50 import
/// previews, source/quarantine bytes, and external availability do not upgrade
/// trust or create an assurance claim.
enum C50IncumbentFileExchangeAssuranceBoundaryV1 {
    static let importedFileIsNotAssuranceEvidence = true
    static let canonicalEvidenceAssuranceRemainsExistingAuthority = true
    static let sourceAndQuarantineBytesExcluded = true
    static let externalAvailabilityIsNotAssurance = true
    static let privateValuesRequireExplicitPrivacyApproval = true
    static let directCostProjectionIsAbsent = C50IncumbentFileExchangeLifecycleBoundaryV1.directCostProjectionIsAbsent
    static let liveInventoryClaimsAssured = false

    static func validate() -> Bool {
        importedFileIsNotAssuranceEvidence
            && canonicalEvidenceAssuranceRemainsExistingAuthority
            && sourceAndQuarantineBytesExcluded
            && externalAvailabilityIsNotAssurance
            && privateValuesRequireExplicitPrivacyApproval
            && directCostProjectionIsAbsent
            && !liveInventoryClaimsAssured
    }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Reporting_EvidenceAssuranceLifecycleAdapterV1_swift {
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

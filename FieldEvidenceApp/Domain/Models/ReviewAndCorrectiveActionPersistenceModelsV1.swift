import Foundation
import SwiftData
private func reviewStoredRevision(_ v:UInt64)throws->Int64{guard v>0,v<=UInt64(Int64.max)else{throw InspectionReviewFailureV1.invalidValue};return Int64(v)}
@Model final class InspectionReviewTransitionRow{@Attribute(.unique)private(set)var transitionID:UUID;private(set)var reviewID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ value:InspectionReviewTransitionV1)throws{try value.validate();let d=try InspectionReviewCanonicalCodecV1.encode(value);let v=try InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self,from:d);transitionID=v.transitionID;reviewID=v.reviewID;workspaceID=v.workspaceID.rawValue;revision=try reviewStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.transitionSHA256;canonicalData=d}func value()throws->InspectionReviewTransitionV1{let v=try InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self,from:canonicalData);guard revision>0,v.transitionID==transitionID,v.reviewID==reviewID,v.workspaceID.rawValue==workspaceID,v.revision==UInt64(revision),v.mutationID.rawValue==mutationID,v.transitionSHA256==canonicalSHA256 else{throw InspectionReviewFailureV1.digestMismatch};return v}}
@Model final class ReviewDispositionRow{@Attribute(.unique)private(set)var dispositionID:UUID;private(set)var reviewID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ value:ReviewDispositionV1)throws{try value.validate();let d=try InspectionReviewCanonicalCodecV1.encode(value);let v=try InspectionReviewCanonicalCodecV1.decode(ReviewDispositionV1.self,from:d);dispositionID=v.dispositionID;reviewID=v.reviewID;workspaceID=v.workspaceID.rawValue;revision=try reviewStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.dispositionSHA256;canonicalData=d}func value()throws->ReviewDispositionV1{let v=try InspectionReviewCanonicalCodecV1.decode(ReviewDispositionV1.self,from:canonicalData);guard revision>0,v.dispositionID==dispositionID,v.reviewID==reviewID,v.workspaceID.rawValue==workspaceID,v.revision==UInt64(revision),v.mutationID.rawValue==mutationID,v.dispositionSHA256==canonicalSHA256 else{throw InspectionReviewFailureV1.digestMismatch};return v}}
@Model final class ChangeRequestRow{@Attribute(.unique)private(set)var requestRevisionID:UUID;private(set)var requestID:UUID;private(set)var reviewID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ value:ChangeRequestV1)throws{try value.validate();let d=try InspectionReviewCanonicalCodecV1.encode(value);let v=try InspectionReviewCanonicalCodecV1.decode(ChangeRequestV1.self,from:d);requestRevisionID=v.requestRevisionID;requestID=v.requestID;reviewID=v.reviewID;workspaceID=v.workspaceID.rawValue;revision=try reviewStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.requestSHA256;canonicalData=d}func value()throws->ChangeRequestV1{let v=try InspectionReviewCanonicalCodecV1.decode(ChangeRequestV1.self,from:canonicalData);guard revision>0,v.requestRevisionID==requestRevisionID,v.requestID==requestID,v.reviewID==reviewID,v.workspaceID.rawValue==workspaceID,v.revision==UInt64(revision),v.mutationID.rawValue==mutationID,v.requestSHA256==canonicalSHA256 else{throw InspectionReviewFailureV1.digestMismatch};return v}}
@Model final class CorrectiveActionPolicyRow{@Attribute(.unique)private(set)var releaseID:UUID;private(set)var policyID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ value:CorrectiveActionPolicyV1)throws{try value.validate();let d=try InspectionReviewCanonicalCodecV1.encode(value);let v=try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self,from:d);releaseID=v.releaseID;policyID=v.policyID;workspaceID=v.workspaceID.rawValue;revision=try reviewStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.policySHA256;canonicalData=d}func value()throws->CorrectiveActionPolicyV1{let v=try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self,from:canonicalData);guard revision>0,v.releaseID==releaseID,v.policyID==policyID,v.workspaceID.rawValue==workspaceID,v.revision==UInt64(revision),v.mutationID.rawValue==mutationID,v.policySHA256==canonicalSHA256 else{throw InspectionReviewFailureV1.digestMismatch};return v}}
@Model final class CorrectiveActionEventRow{@Attribute(.unique)private(set)var eventID:UUID;private(set)var actionID:UUID;private(set)var workspaceID:UUID;private(set)var revision:Int64;private(set)var mutationID:UUID;private(set)var canonicalSHA256:String;private(set)var canonicalData:Data;init(_ value:CorrectiveActionEventV1)throws{try value.validate();let d=try InspectionReviewCanonicalCodecV1.encode(value);let v=try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionEventV1.self,from:d);eventID=v.eventID;actionID=v.actionID;workspaceID=v.workspaceID.rawValue;revision=try reviewStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.eventSHA256;canonicalData=d}func value()throws->CorrectiveActionEventV1{let v=try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionEventV1.self,from:canonicalData);guard revision>0,v.eventID==eventID,v.actionID==actionID,v.workspaceID.rawValue==workspaceID,v.revision==UInt64(revision),v.mutationID.rawValue==mutationID,v.eventSHA256==canonicalSHA256 else{throw InspectionReviewFailureV1.digestMismatch};return v}}

/// C48 accept-and-apply reuses these existing C14 row families exclusively.
/// Exact portable response/session bytes remain owned by the noncanonical
/// session store and deliberately introduce no SwiftData model or schema kind.
enum C48PortableReviewC14PersistenceBoundaryV1 {
    static let canonicalRowTypes: [Any.Type] = [
        InspectionReviewTransitionRow.self,
        ReviewDispositionRow.self,
        ChangeRequestRow.self,
        CorrectiveActionPolicyRow.self,
        CorrectiveActionEventRow.self,
    ]
    static let canonicalRowFamilyCount = 5
    static let createsPortableReviewSwiftDataRow = false

    static func acceptsExistingCanonicalRow(_ row: Any) -> Bool {
        row is InspectionReviewTransitionRow ||
            row is ReviewDispositionRow ||
            row is ChangeRequestRow ||
            row is CorrectiveActionPolicyRow ||
            row is CorrectiveActionEventRow
    }
}

/// C49 reuses the existing C14 review/corrective-action history as the
/// canonical subject authority.  Work-resource rows bind to a stable subject
/// identity and do not create parallel review or corrective-action rows.
enum C49WorkResourceReviewPersistenceBoundaryV1 {
    static let canonicalSubjectFamiliesRemainC14 = true
    static let createsParallelReviewRows = false
    static let createsParallelCorrectiveActionRows = false
    static let persistentSchemaVersion = C49WorkResourcePersistenceBoundaryV1.persistentSchemaVersion
    static let recordsSchemaVersion = C49WorkResourcePersistenceBoundaryV1.recordsSchemaVersion

    static func validate() throws {
        guard canonicalSubjectFamiliesRemainC14,
              !createsParallelReviewRows,
              !createsParallelCorrectiveActionRows else {
            throw InspectionReviewFailureV1.invalidValue
        }
        try C49WorkResourcePersistenceBoundaryV1.validate()
    }
}

// MARK: - C50 incumbent file-exchange persistence boundary

/// C50 profile, selection, and exchange metadata are nonpersistent. C14
/// review/corrective-action rows remain the only durable review truth; no file
/// bytes, session bytes, provider state, or quarantine payload is persisted.
enum C50InspectionReviewIncumbentPersistenceBoundaryV1 {
    static let nonPersistentContractTypes: [Any.Type] = [
        IncumbentFileAdapterV1.self,
        ClosedIncumbentAdapterRegistryV1.self,
        IncumbentFileProfileReleaseV1.self,
        IncumbentSelectionReceiptV1.self,
        IncumbentExchangeScopeV1.self,
        IncumbentFileExportManifestV1.self,
        IncumbentFileExchangeReceiptV1.self,
    ]
    static let quarantineReceiptContract: Any.Type = IncumbentFileQuarantineReceiptV1.self
    static let c14ReviewRowsRemainCanonical = true
    static let createsSecondReviewRowFamily = false
    static let persistsSourceBytes = false
    static let persistsSessionBytes = false
    static let persistsProviderState = false
    static let persistsQuarantinePayload = false
    static let backupRestoreReuseExistingReviewRows = true
    static let deleteEraseReuseExistingReviewRows = true

    static func validateExistingReview(_ value: InspectionReviewProjectionV1) throws {
        try InspectionReviewValidationV1.workspace(value.workspaceID)
        try InspectionReviewValidationV1.id(value.reviewID)
        try InspectionReviewValidationV1.revision(value.revision)
        try InspectionReviewValidationV1.id(value.headTransitionID)
        try value.openChangeRequests.forEach { try $0.validate() }
    }
}

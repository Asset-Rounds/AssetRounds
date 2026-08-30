import Foundation
import SwiftData

enum AccessibleDocumentPersistenceFailureV1:Error{case corruptRow}

@Model final class AccessibleDocumentAssessmentReceiptRow{
    @Attribute(.unique)var receiptID:UUID
    var workspaceID:UUID
    var revision:UInt64
    var mutationID:UUID
    var treeSHA256:String
    var outputSHA256:String
    var receiptSHA256:String
    var scopeRawValue:String
    var audienceRawValue:String
    var projectionVersion:String
    var manifestID:String
    var manifestVersion:Int
    var profileRelease:Int
    var brandProfileID:String
    var brandProfileRelease:Int
    var canonicalData:Data
    init(_ value:AccessibleDocumentAssessmentReceiptV1)throws{try value.validateIntrinsic();receiptID=value.receiptID;workspaceID=value.workspaceID.rawValue;revision=value.revision;mutationID=value.mutationID.rawValue;treeSHA256=value.treeSHA256;outputSHA256=value.outputSHA256;receiptSHA256=value.receiptSHA256;scopeRawValue=value.scope.rawValue;audienceRawValue=value.audience.rawValue;projectionVersion=value.projectionVersion;manifestID=value.manifestID;manifestVersion=value.manifestVersion;profileRelease=value.profileRelease;brandProfileID=value.brandProfileID;brandProfileRelease=value.brandProfileRelease;canonicalData=try AccessibleDocumentCanonicalCodecV1.encode(value)}
    convenience init(_ value:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)throws{try value.validate(tree:tree);try self.init(value)}
    func value()throws->AccessibleDocumentAssessmentReceiptV1{let value=try AccessibleDocumentCanonicalCodecV1.decode(AccessibleDocumentAssessmentReceiptV1.self,from:canonicalData);try value.validateIntrinsic();guard value.receiptID==receiptID,value.workspaceID.rawValue==workspaceID,value.revision==revision,value.mutationID.rawValue==mutationID,value.treeSHA256==treeSHA256,value.outputSHA256==outputSHA256,value.receiptSHA256==receiptSHA256,value.scope.rawValue==scopeRawValue,value.audience.rawValue==audienceRawValue,value.projectionVersion==projectionVersion,value.manifestID==manifestID,value.manifestVersion==manifestVersion,value.profileRelease==profileRelease,value.brandProfileID==brandProfileID,value.brandProfileRelease==brandProfileRelease else{throw AccessibleDocumentPersistenceFailureV1.corruptRow};return value}
    func value(tree:AccessibleDocumentSemanticTreeV1)throws->AccessibleDocumentAssessmentReceiptV1{let value=try value();try value.validate(tree:tree);return value}
}

// C48 review history is a derived, non-SwiftData projection.  This guard
// documents that the existing accessibility receipt row never gains a second
// exchange payload or a secret-bearing column.
enum C48PortableReviewAccessibleDocumentPersistenceBoundaryV1 {
    static let derivedHistoryIsNotPersistedInAssessmentReceiptRow = true
    static let capabilityBytesPersisted = false
    static let capabilityProofBytesPersisted = false
    static let responseBodyPersisted = false
    static let rawRequestResponseBytesPersisted = false
    static let workspaceAndReplicaIdentityPersistedInDerivedHistory = false
    static let existingAccessibleDocumentRowSchemaRemainsUnchanged = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }
}

/// C49 work-resource entries may reference an accessibility assessment as an
/// already-canonical subject fact, but never copy or mutate this receipt row.
/// The existing receipt remains append-only and is enrolled exactly once by
/// the pre-existing schema family.
enum C49WorkResourceAccessibleDocumentPersistenceBoundaryV1 {
    static let assessmentReceiptRemainsCanonical = true
    static let workResourceEntryDoesNotDuplicateAssessmentBytes = true
    static let immutableAssessmentReceiptRemainsBackupEligible = true
    static let persistentSchemaVersion = C49WorkResourcePersistenceBoundaryV1.persistentSchemaVersion
    static let recordsSchemaVersion = C49WorkResourcePersistenceBoundaryV1.recordsSchemaVersion

    static func validate() throws {
        guard assessmentReceiptRemainsCanonical,
              workResourceEntryDoesNotDuplicateAssessmentBytes,
              immutableAssessmentReceiptRemainsBackupEligible else {
            throw AccessibleDocumentPersistenceFailureV1.corruptRow
        }
        try C49WorkResourcePersistenceBoundaryV1.validate()
    }
}

// MARK: - C50 incumbent file-exchange persistence boundary

/// C50's adapter/profile/exchange contracts are nonpersistent. Accessible
/// document rows retain only their existing assessment truth; leased source
/// bytes, session state, provider state, and quarantine payloads never become
/// SwiftData columns or a second durable family.
enum C50AccessibleDocumentIncumbentPersistenceBoundaryV1 {
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
    static let createsSecondSwiftDataFamily = false
    static let persistsSourceBytes = false
    static let persistsSessionBytes = false
    static let persistsProviderState = false
    static let persistsQuarantinePayload = false
    static let assessmentReceiptRemainsCanonical = true
    static let backupAndRestoreOwnOnlyExistingAssessmentRows = true
    static let deleteAndEraseOwnOnlyExistingAssessmentRows = true

    static func validateExistingAssessment(_ value: AccessibleDocumentAssessmentReceiptV1) throws {
        try value.validateIntrinsic()
    }
}

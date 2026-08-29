import Foundation
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

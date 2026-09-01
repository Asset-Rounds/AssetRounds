import Foundation
import SwiftData

@Model
final class PracticeWorkspaceProvenanceRowV1 {
    @Attribute(.unique) var workspaceID: UUID
    @Attribute(.unique) var provenanceID: UUID
    var templateID: UUID
    var templateRelease: Int64
    var installReceiptID: UUID
    var revision: Int64
    var mutationID: UUID
    var provenanceSHA256: String
    var canonicalData: Data

    init(_ value: PracticeWorkspaceProvenanceV1) throws {
        try value.validate()
        guard value.templateRelease <= UInt64(Int64.max),
              value.revision <= UInt64(Int64.max) else {
            throw WorkspaceExperienceFailureV1.invalidValue
        }
        workspaceID = value.workspaceID.rawValue
        provenanceID = value.provenanceID
        templateID = value.templateID
        templateRelease = Int64(value.templateRelease)
        installReceiptID = value.installReceiptID
        revision = Int64(value.revision)
        mutationID = value.mutationID.rawValue
        provenanceSHA256 = value.provenanceSHA256
        canonicalData = try WorkspaceExperienceCanonicalCodecV1.data(value)
    }

    func value() throws -> PracticeWorkspaceProvenanceV1 {
        let decoded = try WorkspaceExperienceCanonicalCodecV1.decode(
            PracticeWorkspaceProvenanceV1.self,
            from: canonicalData,
            validate: { try $0.validate() }
        )
        guard templateRelease >= 0, revision >= 0,
              decoded.workspaceID.rawValue == workspaceID,
              decoded.provenanceID == provenanceID,
              decoded.templateID == templateID,
              decoded.templateRelease == UInt64(templateRelease),
              decoded.installReceiptID == installReceiptID,
              decoded.revision == UInt64(revision),
              decoded.mutationID.rawValue == mutationID,
              decoded.provenanceSHA256 == provenanceSHA256 else {
            throw WorkspaceExperienceFailureV1.invalidDigest
        }
        return decoded
    }
}

enum WorkspaceExperiencePersistenceBoundaryV1 {
    static let predecessorPersistentSchemaVersion = 50
    static let targetPersistentSchemaVersion = 51
    static let durableModelCount = 1
    static let totalModelCount = 166
    static let absenceMeansReal = true
    static let cloneAndForkOmitPracticeProvenance = true
    static let secondDurableInstallReceiptRow = false
    static let plansCatalogsAndProjectionsArePersistent = false
}

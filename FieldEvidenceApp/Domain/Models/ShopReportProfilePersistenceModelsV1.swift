import Foundation
import SwiftData

enum ShopReportProfilePersistenceFailureV1: Error { case corruptRow }

@Model final class ShopReportProfileRowV1 {
    @Attribute(.unique) var rowID: String
    var workspaceID: UUID
    var profileID: UUID
    var revision: UInt64
    var predecessorSHA256: String?
    var mutationID: UUID
    var activation: String
    var profileSHA256: String
    var canonicalData: Data

    init(_ value: ShopReportProfileV1) throws {
        rowID = Self.rowID(workspaceID: value.workspaceID, profileID: value.profileID, revision: value.revision)
        workspaceID = value.workspaceID.rawValue
        profileID = value.profileID
        revision = value.revision
        predecessorSHA256 = value.predecessor?.profileSHA256
        mutationID = value.mutationID.rawValue
        activation = value.activation.rawValue
        profileSHA256 = value.profileSHA256
        canonicalData = try ShopReportProfileCanonicalCodecV1.encode(value)
    }

    func value() throws -> ShopReportProfileV1 {
        let value = try ShopReportProfileCanonicalCodecV1.decode(
            ShopReportProfileV1.self, from: canonicalData
        )
        guard value.workspaceID.rawValue == workspaceID,
              value.profileID == profileID, value.revision == revision,
              value.predecessor?.profileSHA256 == predecessorSHA256,
              value.mutationID.rawValue == mutationID,
              value.activation.rawValue == activation,
              value.profileSHA256 == profileSHA256,
              rowID == Self.rowID(workspaceID: value.workspaceID, profileID: value.profileID, revision: value.revision) else {
            throw ShopReportProfilePersistenceFailureV1.corruptRow
        }
        return value
    }

    static func rowID(workspaceID: WorkspaceID, profileID: UUID, revision: UInt64) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased())|\(profileID.uuidString.lowercased())|\(String(format: "%020llu", revision))"
    }
}

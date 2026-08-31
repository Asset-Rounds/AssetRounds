import Foundation
import SwiftData

enum RoundSessionPersistenceFailureV1: Error { case corruptRow }

@Model final class RoundSessionRevisionRowV1 {
    @Attribute(.unique) var rowID: String
    var workspaceID: UUID
    var sessionID: UUID
    var revision: UInt64
    var predecessorSHA256: String?
    var mutationID: UUID
    var state: String
    var transition: String
    var sessionSHA256: String
    var canonicalData: Data

    init(_ value: RoundSessionV1) throws {
        try value.validateIntrinsic()
        rowID = Self.rowID(workspaceID: value.workspaceID, sessionID: value.sessionID, revision: value.revision)
        workspaceID = value.workspaceID.rawValue; sessionID = value.sessionID; revision = value.revision
        predecessorSHA256 = value.predecessor?.sessionSHA256; mutationID = value.mutationID.rawValue
        state = value.state.rawValue; transition = value.transition.rawValue
        sessionSHA256 = value.sessionSHA256; canonicalData = try RoundSessionCanonicalCodecV1.encode(value)
    }

    func value() throws -> RoundSessionV1 {
        let value = try RoundSessionCanonicalCodecV1.decode(RoundSessionV1.self, from: canonicalData)
        guard value.workspaceID.rawValue == workspaceID, value.sessionID == sessionID,
              value.revision == revision, value.predecessor?.sessionSHA256 == predecessorSHA256,
              value.mutationID.rawValue == mutationID, value.state.rawValue == state,
              value.transition.rawValue == transition, value.sessionSHA256 == sessionSHA256,
              rowID == Self.rowID(workspaceID: value.workspaceID, sessionID: value.sessionID, revision: value.revision) else {
            throw RoundSessionPersistenceFailureV1.corruptRow
        }
        return value
    }

    static func rowID(workspaceID: WorkspaceID, sessionID: UUID, revision: UInt64) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased())|\(sessionID.uuidString.lowercased())|\(String(format: "%020llu", revision))"
    }
}

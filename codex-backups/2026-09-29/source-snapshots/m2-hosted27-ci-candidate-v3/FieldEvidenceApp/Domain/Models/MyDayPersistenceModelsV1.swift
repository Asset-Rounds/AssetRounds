import Foundation
import SwiftData

@Model
final class MyDayPlanRowV1 {
    @Attribute(.unique) var rowID: String
    var planID: UUID
    var workspaceID: UUID
    var revision: UInt64
    var canonicalData: Data

    init(_ value: MyDayPlanV1) throws {
        try value.validate()
        rowID = Self.rowID(planID: value.planID, revision: value.revision)
        planID = value.planID
        workspaceID = value.key.workspaceID.rawValue
        revision = value.revision
        canonicalData = try MyDayCanonicalCodecV1.data(value)
    }

    func value() throws -> MyDayPlanV1 {
        let value = try MyDayCanonicalCodecV1.decode(MyDayPlanV1.self, from: canonicalData)
        guard rowID == Self.rowID(planID: planID, revision: revision),
              value.planID == planID, value.key.workspaceID.rawValue == workspaceID,
              value.revision == revision else { throw MyDayFailureV1.invalidDigest }
        return value
    }

    static func rowID(planID: UUID, revision: UInt64) -> String {
        "\(planID.uuidString.lowercased())|\(String(format: "%020llu", revision))"
    }
}

@Model
final class MyDayCarryoverReceiptRowV1 {
    @Attribute(.unique) var receiptSHA256: String
    var workspaceID: UUID
    var mutationID: UUID
    var canonicalData: Data

    init(_ value: MyDayCarryoverReceiptV1) throws {
        try value.validate()
        receiptSHA256 = value.receiptSHA256
        workspaceID = value.sourcePlan.key.workspaceID.rawValue
        mutationID = value.mutationID.rawValue
        canonicalData = try MyDayCanonicalCodecV1.data(value)
    }

    func value() throws -> MyDayCarryoverReceiptV1 {
        let value = try MyDayCanonicalCodecV1.decode(MyDayCarryoverReceiptV1.self, from: canonicalData)
        guard value.receiptSHA256 == receiptSHA256,
              value.sourcePlan.key.workspaceID.rawValue == workspaceID,
              value.mutationID.rawValue == mutationID else { throw MyDayFailureV1.invalidDigest }
        return value
    }
}

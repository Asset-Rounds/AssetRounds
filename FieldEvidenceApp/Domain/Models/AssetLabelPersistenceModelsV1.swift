import Foundation
import SwiftData

enum AssetLabelPersistenceFailureV1: Error, Equatable {
    case corruptRow
}

/// The sole C45 durable family. Plans, projection results, render checkpoints,
/// and output bytes remain derived scratch and never become SwiftData rows.
@Model final class AcceptedLabelGenerationSnapshotRow {
    @Attribute(.unique) var stableIdentity: String
    var snapshotID: UUID
    var workspaceID: UUID
    var planID: UUID
    var revision: UInt64
    var mutationID: UUID
    var dispositionRawValue: String
    var snapshotSHA256: String
    var canonicalData: Data

    init(_ value: AcceptedLabelGenerationSnapshotV1) throws {
        try value.validate()
        stableIdentity = Self.identity(
            workspaceID: value.workspaceID.rawValue,
            snapshotID: value.snapshotID
        )
        snapshotID = value.snapshotID
        workspaceID = value.workspaceID.rawValue
        planID = value.plan.planID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        dispositionRawValue = value.disposition.rawValue
        snapshotSHA256 = value.snapshotSHA256
        canonicalData = try AssetLabelCanonicalCodecV1.encode(value)
        guard try AssetLabelCanonicalCodecV1.decode(
            AcceptedLabelGenerationSnapshotV1.self,
            from: canonicalData
        ) == value else {
            throw AssetLabelPersistenceFailureV1.corruptRow
        }
    }

    func value() throws -> AcceptedLabelGenerationSnapshotV1 {
        let value = try AssetLabelCanonicalCodecV1.decode(
            AcceptedLabelGenerationSnapshotV1.self,
            from: canonicalData
        )
        try value.validate()
        guard value.snapshotID == snapshotID,
              stableIdentity == Self.identity(
                workspaceID: value.workspaceID.rawValue,
                snapshotID: value.snapshotID
              ),
              value.workspaceID.rawValue == workspaceID,
              value.plan.planID == planID,
              value.revision == revision,
              value.mutationID.rawValue == mutationID,
              value.disposition.rawValue == dispositionRawValue,
              value.snapshotSHA256 == snapshotSHA256 else {
            throw AssetLabelPersistenceFailureV1.corruptRow
        }
        return value
    }

    private static func identity(workspaceID: UUID, snapshotID: UUID) -> String {
        "\(workspaceID.uuidString.lowercased())|\(snapshotID.uuidString.lowercased())"
    }
}

@MainActor final class AcceptedLabelGenerationSnapshotQueryV1: AcceptedLabelGenerationSnapshotQueryingV1 {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func snapshot(
        id: UUID,
        workspaceID: WorkspaceID
    ) throws -> AcceptedLabelGenerationSnapshotV1? {
        let workspace = workspaceID.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<AcceptedLabelGenerationSnapshotRow>(
                predicate: #Predicate {
                    $0.snapshotID == id && $0.workspaceID == workspace
                }
            )
        )
        guard rows.count <= 1 else {
            throw AssetLabelPersistenceFailureV1.corruptRow
        }
        return try rows.first?.value()
    }

    func acceptedLabelSnapshot(
        workspaceID: WorkspaceID,
        snapshotID: UUID
    ) async throws -> AcceptedLabelGenerationSnapshotV1? {
        try snapshot(id: snapshotID, workspaceID: workspaceID)
    }

    func acceptedLabelSnapshot(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> AcceptedLabelGenerationSnapshotV1? {
        let workspace = workspaceID.rawValue
        let id = mutationID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<AcceptedLabelGenerationSnapshotRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.mutationID == id }
        ))
        guard rows.count <= 1 else { throw AssetLabelPersistenceFailureV1.corruptRow }
        return try rows.first?.value()
    }

    func snapshot(
        mutationID: MutationIDV1
    ) throws -> AcceptedLabelGenerationSnapshotV1? {
        let id = mutationID.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<AcceptedLabelGenerationSnapshotRow>(
                predicate: #Predicate { $0.mutationID == id }
            )
        )
        guard rows.count <= 1 else {
            throw AssetLabelPersistenceFailureV1.corruptRow
        }
        return try rows.first?.value()
    }
}

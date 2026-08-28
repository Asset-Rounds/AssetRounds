import Foundation
import SwiftData

enum AssetSemanticPersistenceReleaseV1: Int, Codable, CaseIterable, Sendable {
    case v10 = 10
    static let predecessorSchemaVersion = 9
    static let acceptedLegacySignSemanticID = "asset.sign.illuminated.v1"
}

private enum AssetSemanticRowCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try AssetSemanticCanonicalCodecV1.encode(value)
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let value = try AssetSemanticCanonicalCodecV1.decode(type, from: data)
        switch value {
        case let value as AssetKindBindingEventV1: try value.validate()
        case let value as AssetWorkflowCapabilityBindingEventV1: try value.validate()
        case let value as AssetProductIdentityV1: try value.validate()
        case let value as AssetLifecycleEventV1: try value.validate()
        case let value as AssetSuccessorLinkV1: try value.validate()
        case let value as WorkSubjectScopeSnapshotV1: try value.validate()
        default: throw AssetSemanticContractFailureV1.invalidValue
        }
        return value
    }
}

@Model
final class AssetKindBindingEventRow {
    @Attribute(.unique) private(set) var eventID: UUID
    private(set) var workspaceID: UUID
    private(set) var assetID: UUID
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var recordedAt: Date
    private(set) var canonicalData: Data

    init(_ value: AssetKindBindingEventV1) throws {
        try value.validate()
        guard value.revision <= UInt64(Int64.max) else { throw AssetSemanticContractFailureV1.invalidValue }
        let data = try AssetSemanticRowCodecV1.encode(value)
        let canonical = try AssetSemanticRowCodecV1.decode(AssetKindBindingEventV1.self, from: data)
        eventID = canonical.eventID; workspaceID = canonical.workspaceID.rawValue; assetID = canonical.assetID
        revision = Int64(canonical.revision); mutationID = canonical.mutationID.rawValue; recordedAt = canonical.recordedAt
        canonicalData = data
    }

    func value() throws -> AssetKindBindingEventV1 {
        let value = try AssetSemanticRowCodecV1.decode(AssetKindBindingEventV1.self, from: canonicalData)
        guard value.eventID == eventID, value.workspaceID.rawValue == workspaceID, value.assetID == assetID,
              value.revision == UInt64(revision), value.mutationID.rawValue == mutationID,
              value.recordedAt == recordedAt else { throw AssetSemanticContractFailureV1.nonCanonicalData }
        return value
    }
}

@Model
final class AssetWorkflowCapabilityBindingEventRow {
    @Attribute(.unique) private(set) var eventID: UUID
    private(set) var workspaceID: UUID
    private(set) var assetID: UUID
    private(set) var kindBindingEventID: UUID
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var recordedAt: Date
    private(set) var canonicalData: Data

    init(_ value: AssetWorkflowCapabilityBindingEventV1) throws {
        try value.validate()
        guard value.revision <= UInt64(Int64.max) else { throw AssetSemanticContractFailureV1.invalidValue }
        let data = try AssetSemanticRowCodecV1.encode(value)
        let canonical = try AssetSemanticRowCodecV1.decode(AssetWorkflowCapabilityBindingEventV1.self, from: data)
        eventID = canonical.eventID; workspaceID = canonical.workspaceID.rawValue; assetID = canonical.assetID
        kindBindingEventID = canonical.kindBindingEventID; revision = Int64(canonical.revision)
        mutationID = canonical.mutationID.rawValue; recordedAt = canonical.recordedAt
        canonicalData = data
    }

    func value() throws -> AssetWorkflowCapabilityBindingEventV1 {
        let value = try AssetSemanticRowCodecV1.decode(AssetWorkflowCapabilityBindingEventV1.self, from: canonicalData)
        guard value.eventID == eventID, value.workspaceID.rawValue == workspaceID, value.assetID == assetID,
              value.kindBindingEventID == kindBindingEventID, value.revision == UInt64(revision),
              value.mutationID.rawValue == mutationID, value.recordedAt == recordedAt else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        return value
    }
}

@Model
final class AssetProductIdentityRow {
    @Attribute(.unique) private(set) var identityID: UUID
    private(set) var workspaceID: UUID
    private(set) var assetID: UUID
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var recordedAt: Date
    private(set) var canonicalData: Data

    init(_ value: AssetProductIdentityV1) throws {
        try value.validate()
        guard value.revision <= UInt64(Int64.max) else { throw AssetSemanticContractFailureV1.invalidValue }
        let data = try AssetSemanticRowCodecV1.encode(value)
        let canonical = try AssetSemanticRowCodecV1.decode(AssetProductIdentityV1.self, from: data)
        identityID = canonical.identityID; workspaceID = canonical.workspaceID.rawValue; assetID = canonical.assetID
        revision = Int64(canonical.revision); mutationID = canonical.mutationID.rawValue; recordedAt = canonical.recordedAt
        canonicalData = data
    }

    func value() throws -> AssetProductIdentityV1 {
        let value = try AssetSemanticRowCodecV1.decode(AssetProductIdentityV1.self, from: canonicalData)
        guard value.identityID == identityID, value.workspaceID.rawValue == workspaceID, value.assetID == assetID,
              value.revision == UInt64(revision), value.mutationID.rawValue == mutationID,
              value.recordedAt == recordedAt else { throw AssetSemanticContractFailureV1.nonCanonicalData }
        return value
    }
}

@Model
final class AssetLifecycleEventRow {
    @Attribute(.unique) private(set) var eventID: UUID
    private(set) var workspaceID: UUID
    private(set) var assetID: UUID
    private(set) var kind: String
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var recordedAt: Date
    private(set) var canonicalData: Data

    init(_ value: AssetLifecycleEventV1) throws {
        try value.validate()
        let data = try AssetSemanticRowCodecV1.encode(value)
        let canonical = try AssetSemanticRowCodecV1.decode(AssetLifecycleEventV1.self, from: data)
        let record = canonical.record
        guard record.revision <= UInt64(Int64.max) else { throw AssetSemanticContractFailureV1.invalidValue }
        eventID = record.eventID; workspaceID = record.workspaceID.rawValue; assetID = record.assetID
        kind = canonical.kind.rawValue; revision = Int64(record.revision); mutationID = record.mutationID.rawValue
        recordedAt = record.recordedAt; canonicalData = data
    }

    func value() throws -> AssetLifecycleEventV1 {
        let value = try AssetSemanticRowCodecV1.decode(AssetLifecycleEventV1.self, from: canonicalData)
        let record = value.record
        guard record.eventID == eventID, record.workspaceID.rawValue == workspaceID, record.assetID == assetID,
              value.kind.rawValue == kind, record.revision == UInt64(revision),
              record.mutationID.rawValue == mutationID, record.recordedAt == recordedAt else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        return value
    }
}

@Model
final class AssetSuccessorLinkRow {
    @Attribute(.unique) private(set) var linkID: UUID
    private(set) var workspaceID: UUID
    private(set) var predecessorAssetID: UUID
    private(set) var successorAssetID: UUID
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var recordedAt: Date
    private(set) var canonicalData: Data

    init(_ value: AssetSuccessorLinkV1) throws {
        try value.validate()
        guard value.revision <= UInt64(Int64.max) else { throw AssetSemanticContractFailureV1.invalidValue }
        let data = try AssetSemanticRowCodecV1.encode(value)
        let canonical = try AssetSemanticRowCodecV1.decode(AssetSuccessorLinkV1.self, from: data)
        linkID = canonical.linkID; workspaceID = canonical.workspaceID.rawValue
        predecessorAssetID = canonical.predecessorAssetID; successorAssetID = canonical.successorAssetID
        revision = Int64(canonical.revision); mutationID = canonical.mutationID.rawValue; recordedAt = canonical.recordedAt
        canonicalData = data
    }

    func value() throws -> AssetSuccessorLinkV1 {
        let value = try AssetSemanticRowCodecV1.decode(AssetSuccessorLinkV1.self, from: canonicalData)
        guard value.linkID == linkID, value.workspaceID.rawValue == workspaceID,
              value.predecessorAssetID == predecessorAssetID, value.successorAssetID == successorAssetID,
              value.revision == UInt64(revision), value.mutationID.rawValue == mutationID,
              value.recordedAt == recordedAt else { throw AssetSemanticContractFailureV1.nonCanonicalData }
        return value
    }
}

@Model
final class WorkSubjectScopeSnapshotRow {
    @Attribute(.unique) private(set) var snapshotID: UUID
    private(set) var workspaceID: UUID
    private(set) var siteID: UUID
    private(set) var workspaceRevision: Int64
    private(set) var recordedAt: Date
    private(set) var canonicalData: Data

    init(_ value: WorkSubjectScopeSnapshotV1) throws {
        try value.validate()
        guard value.workspaceRevision <= UInt64(Int64.max) else { throw AssetSemanticContractFailureV1.invalidValue }
        let data = try AssetSemanticRowCodecV1.encode(value)
        let canonical = try AssetSemanticRowCodecV1.decode(WorkSubjectScopeSnapshotV1.self, from: data)
        snapshotID = canonical.snapshotID; workspaceID = canonical.workspaceID.rawValue; siteID = canonical.siteID
        workspaceRevision = Int64(canonical.workspaceRevision); recordedAt = canonical.recordedAt
        canonicalData = data
    }

    func value() throws -> WorkSubjectScopeSnapshotV1 {
        let value = try AssetSemanticRowCodecV1.decode(WorkSubjectScopeSnapshotV1.self, from: canonicalData)
        guard value.snapshotID == snapshotID, value.workspaceID.rawValue == workspaceID, value.siteID == siteID,
              value.workspaceRevision == UInt64(workspaceRevision), value.recordedAt == recordedAt else {
            throw AssetSemanticContractFailureV1.nonCanonicalData
        }
        return value
    }

    /// Rehydrates the existing frozen C39 row and proves that every functional
    /// relationship subject is an exact member of the completed C41 snapshot.
    /// No C41 projection or duplicate graph state is persisted on this row.
    func value(
        validatingAgainst snapshot: CompletedFunctionalRelationshipSnapshotV1
    ) throws -> WorkSubjectScopeSnapshotV1 {
        let value = try value()
        try snapshot.validate()
        guard value.workspaceID == snapshot.workspaceID else {
            throw AssetSemanticContractFailureV1.crossWorkspaceReference
        }
        if value.subjects.contains(where: { $0.functionalRelationship != nil }) {
            try value.validateFunctionalRelationshipSnapshot(snapshot)
        }
        return value
    }
}

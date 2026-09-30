import Foundation
import SwiftData

private func functionalRelationshipStoredRevision(_ value: UInt64) throws -> Int64 {
    guard value > 0, value <= UInt64(Int64.max) else {
        throw FunctionalRelationshipFailureV1.invalidValue
    }
    return Int64(value)
}

extension AssetFunctionalRelationshipEventRow{func exactCurrentReference(relationshipID:UUID,workspaceID:WorkspaceID)throws->AssetFunctionalRelationshipEventV1{let v=try value();guard v.relationshipID==relationshipID,v.workspaceID==workspaceID else{throw FunctionalRelationshipFailureV1.invalidValue};return v}}

private func functionalRelationshipDomainRevision(_ value: Int64) throws -> UInt64 {
    guard value > 0 else { throw FunctionalRelationshipFailureV1.digestMismatch }
    return UInt64(value)
}

@Model
final class FunctionalRelationshipTypeDescriptorRow {
    @Attribute(.unique) private(set) var descriptorReleaseID: UUID
    private(set) var workspaceID: UUID
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var canonicalSHA256: String
    private(set) var releasedAt: Date
    private(set) var canonicalData: Data

    init(_ value: FunctionalRelationshipTypeDescriptorV1) throws {
        try value.validate()
        let data = try FunctionalRelationshipCanonicalCodecV1.encode(value)
        let canonical = try FunctionalRelationshipCanonicalCodecV1.decode(
            FunctionalRelationshipTypeDescriptorV1.self, from: data
        )
        descriptorReleaseID = canonical.descriptorReleaseID
        workspaceID = canonical.workspaceID.rawValue
        revision = try functionalRelationshipStoredRevision(canonical.revision)
        mutationID = canonical.mutationID.rawValue
        canonicalSHA256 = canonical.descriptorSHA256
        releasedAt = canonical.releasedAt
        canonicalData = data
    }

    func value() throws -> FunctionalRelationshipTypeDescriptorV1 {
        let value = try FunctionalRelationshipCanonicalCodecV1.decode(
            FunctionalRelationshipTypeDescriptorV1.self, from: canonicalData
        )
        try value.validate()
        guard value.descriptorReleaseID == descriptorReleaseID,
              value.workspaceID.rawValue == workspaceID,
              value.revision == (try functionalRelationshipDomainRevision(revision)),
              value.mutationID.rawValue == mutationID,
              value.descriptorSHA256 == canonicalSHA256,
              value.releasedAt == releasedAt else {
            throw FunctionalRelationshipFailureV1.digestMismatch
        }
        return value
    }
}

@Model
final class AssetFunctionalRelationshipEventRow {
    @Attribute(.unique) private(set) var eventID: UUID
    private(set) var relationshipID: UUID
    private(set) var workspaceID: UUID
    private(set) var actionRawValue: String
    private(set) var predecessorEventID: UUID?
    private(set) var expectedRelationshipRevision: Int64
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var canonicalSHA256: String
    private(set) var effectiveAt: Date
    private(set) var recordedAt: Date
    private(set) var canonicalData: Data

    init(_ value: AssetFunctionalRelationshipEventV1) throws {
        try value.validate()
        let data = try FunctionalRelationshipCanonicalCodecV1.encode(value)
        let canonical = try FunctionalRelationshipCanonicalCodecV1.decode(
            AssetFunctionalRelationshipEventV1.self, from: data
        )
        eventID = canonical.eventID
        relationshipID = canonical.relationshipID
        workspaceID = canonical.workspaceID.rawValue
        actionRawValue = canonical.action.rawValue
        predecessorEventID = canonical.predecessorEventID
        guard canonical.expectedRelationshipRevision <= UInt64(Int64.max) else {
            throw FunctionalRelationshipFailureV1.invalidValue
        }
        expectedRelationshipRevision = Int64(canonical.expectedRelationshipRevision)
        revision = try functionalRelationshipStoredRevision(canonical.revision)
        mutationID = canonical.mutationID.rawValue
        canonicalSHA256 = canonical.eventSHA256
        effectiveAt = canonical.effectiveAt
        recordedAt = canonical.recordedAt
        canonicalData = data
    }

    func value() throws -> AssetFunctionalRelationshipEventV1 {
        let value = try FunctionalRelationshipCanonicalCodecV1.decode(
            AssetFunctionalRelationshipEventV1.self, from: canonicalData
        )
        try value.validate()
        guard expectedRelationshipRevision >= 0,
              value.eventID == eventID,
              value.relationshipID == relationshipID,
              value.workspaceID.rawValue == workspaceID,
              value.action.rawValue == actionRawValue,
              value.predecessorEventID == predecessorEventID,
              value.expectedRelationshipRevision == UInt64(expectedRelationshipRevision),
              value.revision == (try functionalRelationshipDomainRevision(revision)),
              value.mutationID.rawValue == mutationID,
              value.eventSHA256 == canonicalSHA256,
              value.effectiveAt == effectiveAt,
              value.recordedAt == recordedAt else {
            throw FunctionalRelationshipFailureV1.digestMismatch
        }
        return value
    }
}

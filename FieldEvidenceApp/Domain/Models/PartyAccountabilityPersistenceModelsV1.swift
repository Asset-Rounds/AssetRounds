import Foundation
import SwiftData

enum PartyAccountabilityPersistenceReleaseV1: Int, Codable, CaseIterable, Sendable {
    case v9 = 9
    static let predecessorSchemaVersion = 8
    static let partiesSemanticLabel = "PARTIES_V1"
    static let sitePartyRolesSemanticLabel = "SITE_PARTY_ROLES_V1"
    static let accountabilitySnapshotsSemanticLabel = "ACCOUNTABILITY_SNAPSHOTS_V1"
}

enum PartyAccountabilitySnapshotCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        switch value {
        case let value as ServicePartyReferenceV1: try value.validate()
        case let value as SitePartyRoleEventV1: try value.validate()
        case let value as LocalActorReferenceV1: try value.validate()
        case let value as ActorSnapshotV1: try value.validate()
        case let value as QualificationSnapshotV1: try value.validate()
        case let value as SignoffIntentDisclosureReleaseV1: try value.validate()
        case let value as SignoffRoleAssertionV1: try value.validate()
        case let value as SignoffSnapshotV1: try value.validate()
        default: throw PartyAccountabilityFailureV1.invalidValue
        }
        guard try encode(value) == data else { throw PartyAccountabilityFailureV1.digestMismatch }
        return value
    }
}

/// Canonical `PARTIES_V1` row. Contact points, authentication, and authorization
/// are intentionally absent from both the row and its canonical value.
@Model
final class ServicePartyRow {
    @Attribute(.unique) private(set) var partyID: UUID
    private(set) var schemaVersion: Int
    private(set) var workspaceID: UUID
    private(set) var kind: String
    private(set) var displayName: String
    private(set) var state: String
    private(set) var effectiveAt: Date
    private(set) var retiredAt: Date?
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var receiptSHA256: String
    private(set) var canonicalData: Data

    init(_ value: ServicePartyReferenceV1) throws {
        try value.validate()
        guard value.revision <= UInt64(Int64.max) else { throw PartyAccountabilityFailureV1.limitExceeded }
        partyID = value.partyID; schemaVersion = value.schemaVersion; workspaceID = value.workspaceID.rawValue
        kind = value.kind.rawValue; displayName = value.displayName; state = value.state.rawValue
        effectiveAt = value.effectiveAt; retiredAt = value.retiredAt; revision = Int64(value.revision)
        mutationID = value.mutationID.rawValue; receiptSHA256 = value.receiptSHA256
        canonicalData = try PartyAccountabilitySnapshotCodecV1.encode(value)
    }

    func value() throws -> ServicePartyReferenceV1 {
        guard revision > 0 else { throw PartyAccountabilityFailureV1.invalidValue }
        let value = try PartyAccountabilitySnapshotCodecV1.decode(ServicePartyReferenceV1.self, from: canonicalData)
        guard value.partyID == partyID, value.schemaVersion == schemaVersion,
              value.workspaceID.rawValue == workspaceID, value.kind.rawValue == kind,
              value.displayName == displayName, value.state.rawValue == state,
              value.effectiveAt == effectiveAt, value.retiredAt == retiredAt,
              value.revision == UInt64(revision), value.mutationID.rawValue == mutationID,
              value.receiptSHA256 == receiptSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch }
        return value
    }

    /// Called only by the canonical workspace writer after its MutationID and
    /// expected-revision guards pass. Frozen snapshots remain separate rows.
    func replace(with successor: ServicePartyReferenceV1, expectedRevision: UInt64) throws {
        let predecessor = try value()
        guard predecessor.revision == expectedRevision else { throw PartyAccountabilityFailureV1.staleRevision }
        try successor.validateSuccessor(of: predecessor)
        guard successor.revision <= UInt64(Int64.max) else { throw PartyAccountabilityFailureV1.limitExceeded }
        schemaVersion = successor.schemaVersion; kind = successor.kind.rawValue; displayName = successor.displayName
        state = successor.state.rawValue; retiredAt = successor.retiredAt; revision = Int64(successor.revision)
        mutationID = successor.mutationID.rawValue; receiptSHA256 = successor.receiptSHA256
        canonicalData = try PartyAccountabilitySnapshotCodecV1.encode(successor)
    }
}

/// Append-only `SITE_PARTY_ROLES_V1` history. Supersession inserts a new row;
/// it never mutates or deletes the predecessor row.
@Model
final class SitePartyRoleEventRow {
    @Attribute(.unique) private(set) var eventID: UUID
    private(set) var schemaVersion: Int
    private(set) var workspaceID: UUID
    private(set) var siteID: UUID
    private(set) var partyID: UUID
    private(set) var role: String
    private(set) var effectiveFrom: Date
    private(set) var effectiveUntil: Date?
    private(set) var supersedesEventID: UUID?
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var recordedAt: Date
    private(set) var receiptSHA256: String
    private(set) var canonicalData: Data

    init(_ value: SitePartyRoleEventV1, predecessor: SitePartyRoleEventV1? = nil) throws {
        try value.validate()
        if let predecessor { try value.validateSupersession(of: predecessor) }
        else if value.supersedesEventID != nil { throw PartyAccountabilityFailureV1.immutableHistory }
        guard value.revision <= UInt64(Int64.max) else { throw PartyAccountabilityFailureV1.limitExceeded }
        eventID = value.eventID; schemaVersion = value.schemaVersion; workspaceID = value.workspaceID.rawValue
        siteID = value.siteID; partyID = value.partyID; role = value.role.rawValue
        effectiveFrom = value.effectiveFrom; effectiveUntil = value.effectiveUntil
        supersedesEventID = value.supersedesEventID; revision = Int64(value.revision)
        mutationID = value.mutationID.rawValue; recordedAt = value.recordedAt; receiptSHA256 = value.receiptSHA256
        canonicalData = try PartyAccountabilitySnapshotCodecV1.encode(value)
    }

    func value() throws -> SitePartyRoleEventV1 {
        guard revision > 0 else { throw PartyAccountabilityFailureV1.invalidValue }
        let value = try PartyAccountabilitySnapshotCodecV1.decode(SitePartyRoleEventV1.self, from: canonicalData)
        guard value.eventID == eventID, value.schemaVersion == schemaVersion,
              value.workspaceID.rawValue == workspaceID, value.siteID == siteID, value.partyID == partyID,
              value.role.rawValue == role, value.effectiveFrom == effectiveFrom, value.effectiveUntil == effectiveUntil,
              value.supersedesEventID == supersedesEventID, value.revision == UInt64(revision),
              value.mutationID.rawValue == mutationID, value.recordedAt == recordedAt,
              value.receiptSHA256 == receiptSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch }
        return value
    }
}

@Model
final class ActorSnapshotRow {
    @Attribute(.unique) private(set) var snapshotID: UUID
    private(set) var schemaVersion: Int
    private(set) var workspaceID: UUID
    private(set) var actorReferenceID: UUID
    private(set) var responsibility: String
    private(set) var displayNameAtTime: String
    private(set) var capturedAt: Date
    private(set) var snapshotSHA256: String
    private(set) var canonicalData: Data

    init(_ value: ActorSnapshotV1) throws {
        try value.validate(); snapshotID = value.snapshotID; schemaVersion = value.schemaVersion
        workspaceID = value.workspaceID.rawValue; actorReferenceID = value.actor.actorReferenceID
        responsibility = value.responsibility.rawValue; displayNameAtTime = value.displayNameAtTime
        capturedAt = value.capturedAt; snapshotSHA256 = value.snapshotSHA256
        canonicalData = try PartyAccountabilitySnapshotCodecV1.encode(value)
    }
    func value() throws -> ActorSnapshotV1 {
        let value = try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: canonicalData)
        guard value.snapshotID == snapshotID, value.schemaVersion == schemaVersion,
              value.workspaceID.rawValue == workspaceID, value.actor.actorReferenceID == actorReferenceID,
              value.responsibility.rawValue == responsibility, value.displayNameAtTime == displayNameAtTime,
              value.capturedAt == capturedAt, value.snapshotSHA256 == snapshotSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch }
        return value
    }
}

@Model
final class QualificationSnapshotRow {
    @Attribute(.unique) private(set) var snapshotID: UUID
    private(set) var schemaVersion: Int
    private(set) var workspaceID: UUID
    private(set) var declaredScope: String
    private(set) var provenance: String
    private(set) var capturedAt: Date
    private(set) var snapshotSHA256: String
    private(set) var canonicalData: Data

    init(_ value: QualificationSnapshotV1) throws {
        try value.validate(); snapshotID = value.snapshotID; schemaVersion = value.schemaVersion
        workspaceID = value.workspaceID.rawValue; declaredScope = value.declaredScope
        provenance = value.provenance.rawValue; capturedAt = value.capturedAt; snapshotSHA256 = value.snapshotSHA256
        canonicalData = try PartyAccountabilitySnapshotCodecV1.encode(value)
    }
    func value() throws -> QualificationSnapshotV1 {
        let value = try PartyAccountabilitySnapshotCodecV1.decode(QualificationSnapshotV1.self, from: canonicalData)
        guard value.snapshotID == snapshotID, value.schemaVersion == schemaVersion,
              value.workspaceID.rawValue == workspaceID, value.declaredScope == declaredScope,
              value.provenance.rawValue == provenance, value.capturedAt == capturedAt,
              value.snapshotSHA256 == snapshotSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch }
        return value
    }
}

/// Immutable accountability assertion. Corrections are successor snapshots,
/// never in-place edits of historical display or qualification facts.
@Model
final class SignoffSnapshotRow {
    @Attribute(.unique) private(set) var snapshotID: UUID
    private(set) var schemaVersion: Int
    private(set) var workspaceID: UUID
    private(set) var subjectID: UUID
    private(set) var subjectRevision: Int64
    private(set) var disposition: String
    private(set) var method: String
    private(set) var actorSnapshotID: UUID?
    private(set) var qualificationSnapshotID: UUID?
    private(set) var supersedesSnapshotID: UUID?
    private(set) var mutationID: UUID
    private(set) var recordedAt: Date
    private(set) var snapshotSHA256: String
    private(set) var canonicalData: Data

    init(_ value: SignoffSnapshotV1, predecessor: SignoffSnapshotV1? = nil) throws {
        try value.validate()
        if let predecessor { try value.validateSupersession(of: predecessor) }
        else if value.supersedesSnapshotID != nil { throw PartyAccountabilityFailureV1.immutableHistory }
        guard value.subjectRevision <= UInt64(Int64.max) else { throw PartyAccountabilityFailureV1.limitExceeded }
        snapshotID = value.snapshotID; schemaVersion = value.schemaVersion; workspaceID = value.workspaceID.rawValue
        subjectID = value.subjectID; subjectRevision = Int64(value.subjectRevision); disposition = value.disposition.rawValue
        method = value.method.rawValue; actorSnapshotID = value.roleAssertion?.actor.snapshotID
        qualificationSnapshotID = value.qualification?.snapshotID; supersedesSnapshotID = value.supersedesSnapshotID
        mutationID = value.mutationID.rawValue; recordedAt = value.recordedAt; snapshotSHA256 = value.snapshotSHA256
        canonicalData = try PartyAccountabilitySnapshotCodecV1.encode(value)
    }
    func value() throws -> SignoffSnapshotV1 {
        guard subjectRevision > 0 else { throw PartyAccountabilityFailureV1.invalidValue }
        let value = try PartyAccountabilitySnapshotCodecV1.decode(SignoffSnapshotV1.self, from: canonicalData)
        guard value.snapshotID == snapshotID, value.schemaVersion == schemaVersion,
              value.workspaceID.rawValue == workspaceID, value.subjectID == subjectID,
              value.subjectRevision == UInt64(subjectRevision), value.disposition.rawValue == disposition,
              value.method.rawValue == method, value.roleAssertion?.actor.snapshotID == actorSnapshotID,
              value.qualification?.snapshotID == qualificationSnapshotID,
              value.supersedesSnapshotID == supersedesSnapshotID, value.mutationID.rawValue == mutationID,
              value.recordedAt == recordedAt, value.snapshotSHA256 == snapshotSHA256 else { throw PartyAccountabilityFailureV1.digestMismatch }
        return value
    }
}

import Foundation

struct WorkspaceID: Hashable, RawRepresentable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init() {
        self.rawValue = UUID()
    }
}

struct EntityID<Entity>: Hashable, RawRepresentable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init() {
        self.rawValue = UUID()
    }
}

typealias SiteID = EntityID<Site>
typealias AssetID = EntityID<Asset>
typealias WorkflowRecordID = EntityID<WorkflowRecord>
typealias EvidenceFileID = EntityID<EvidenceFile>
typealias IssueID = EntityID<Issue>
typealias PacketID = EntityID<Packet>
typealias ReportID = EntityID<Report>

enum ReplicaIdentityFailure: Error, Equatable {
    case destinationIdentityExhausted
}

struct ReplicaID: Hashable, RawRepresentable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Creates a random device-local identity without consulting hardware IDs.
    init() {
        self.rawValue = UUID()
    }

    /// Restore destinations always mint their own identity. A collision with
    /// the source or another unavailable identity is rejected and retried only
    /// within the supplied deterministic bound.
    static func destinationOwnedForRestore(
        excluding source: ReplicaID,
        disallowed: Set<ReplicaID> = [],
        maximumAttempts: Int = 16,
        generate: () -> UUID = { UUID() }
    ) throws -> ReplicaID {
        guard maximumAttempts > 0 else {
            throw ReplicaIdentityFailure.destinationIdentityExhausted
        }

        var unavailable = disallowed
        unavailable.insert(source)
        for _ in 0..<maximumAttempts {
            let candidate = ReplicaID(rawValue: generate())
            if !unavailable.contains(candidate) {
                return candidate
            }
        }
        throw ReplicaIdentityFailure.destinationIdentityExhausted
    }
}

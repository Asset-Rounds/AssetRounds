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

struct WorkspaceReplicaIdentityV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let replicaID: ReplicaID

    init(workspaceID: WorkspaceID, replicaID: ReplicaID) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard workspaceID.rawValue != zero,
              replicaID.rawValue != zero else {
            throw WorkspaceIdentityFailure.invalidIdentity
        }
        guard workspaceID.rawValue != replicaID.rawValue else {
            throw WorkspaceIdentityFailure.roleCollision
        }
        self.workspaceID = workspaceID
        self.replicaID = replicaID
    }
}

enum WorkspaceIdentityFailure: Error, Equatable {
    case roleCollision
    case invalidIdentity
    case replicaHistoryLimitExceeded
}

@MainActor
struct WorkspaceIdentitySourceV1 {
    let makeWorkspaceID: () -> WorkspaceID
    let makeReplicaID: () -> ReplicaID

    init(
        makeWorkspaceID: @escaping () -> WorkspaceID,
        makeReplicaID: @escaping () -> ReplicaID
    ) {
        self.makeWorkspaceID = makeWorkspaceID
        self.makeReplicaID = makeReplicaID
    }

    static var live: WorkspaceIdentitySourceV1 {
        WorkspaceIdentitySourceV1(
            makeWorkspaceID: WorkspaceID.init,
            makeReplicaID: ReplicaID.init
        )
    }

    func makeIdentity(maximumAttempts: Int = 16) throws -> WorkspaceReplicaIdentityV1 {
        guard maximumAttempts > 0 else {
            throw WorkspaceIdentityFailure.invalidIdentity
        }
        for _ in 0..<maximumAttempts {
            let workspaceID = makeWorkspaceID()
            let replicaID = makeReplicaID()
            if workspaceID.rawValue != replicaID.rawValue {
                return try WorkspaceReplicaIdentityV1(
                    workspaceID: workspaceID,
                    replicaID: replicaID
                )
            }
        }
        throw WorkspaceIdentityFailure.roleCollision
    }
}

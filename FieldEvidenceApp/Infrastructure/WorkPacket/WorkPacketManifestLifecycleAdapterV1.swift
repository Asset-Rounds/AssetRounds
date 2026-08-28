import Foundation

/// Read-only bridge to the canonical V15 rows. Implementations must read the
/// one workspace store; this protocol is not a persistence or writer owner.
@MainActor protocol WorkPacketManifestRecordSourceV1: AnyObject {
    func manifests(workspaceID: WorkspaceID) throws -> [WorkPacketManifestV1]
    func claims(workspaceID: WorkspaceID) throws -> [WorkItemClaimV1]
    func leases(workspaceID: WorkspaceID) throws -> [WorkLeaseV1]
    func releases(workspaceID: WorkspaceID) throws -> [WorkReleaseV1]
    func handoffs(workspaceID: WorkspaceID) throws -> [WorkHandoffV1]
}

@MainActor final class WorkPacketManifestLifecycleAdapterV1 {
    private let source: any WorkPacketManifestRecordSourceV1

    init(source: any WorkPacketManifestRecordSourceV1) {
        self.source = source
    }

    func manifest(
        workspaceID: WorkspaceID,
        manifestID: UUID
    ) throws -> WorkPacketManifestV1 {
        let matches = try source.manifests(workspaceID: workspaceID).filter {
            $0.workspaceID == workspaceID && $0.manifestID == manifestID
        }
        guard !matches.isEmpty, let value = matches.first else {
            throw WorkPacketFailureV1.invalidValue
        }
        guard Set(matches.map(\.manifestSHA256)).count == 1 else {
            throw WorkPacketFailureV1.divergentReplay
        }
        try value.validate()
        return value
    }

    func projection(
        workspaceID: WorkspaceID,
        manifestID: UUID,
        at instant: Date
    ) throws -> WorkPacketProjectionV1 {
        let value = try manifest(workspaceID: workspaceID, manifestID: manifestID)
        return try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: workspaceID,
            manifest: value,
            claims: source.claims(workspaceID: workspaceID),
            leases: source.leases(workspaceID: workspaceID),
            releases: source.releases(workspaceID: workspaceID),
            handoffs: source.handoffs(workspaceID: workspaceID),
            at: instant
        )
    }
}

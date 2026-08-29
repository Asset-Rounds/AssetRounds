import Foundation

enum WorkPacketScheduleLifecycleBoundaryV1 { static let dueQueueCreatesRows = false }

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

    /// C23 read-only projection path. The source still supplies only the
    /// existing work-packet rows; field-reference releases, bindings, and
    /// readiness are explicit inputs from their canonical owner.
    func projectionWithFieldReferences(
        workspaceID: WorkspaceID,
        manifestID: UUID,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1],
        subjectState: FieldReferenceSubjectStateV1 = .active,
        at instant: Date
    ) throws -> WorkPacketFieldReferenceProjectionV1 {
        let value = try manifest(workspaceID: workspaceID, manifestID: manifestID)
        return try WorkPacketReferenceProjectionBuilderV1.rebuild(
            workspaceID: workspaceID,
            manifest: value,
            claims: source.claims(workspaceID: workspaceID),
            leases: source.leases(workspaceID: workspaceID),
            releases: source.releases(workspaceID: workspaceID),
            handoffs: source.handoffs(workspaceID: workspaceID),
            fieldReferenceBindings: fieldReferenceBindings,
            fieldReferenceReleases: fieldReferenceReleases,
            fieldReferenceReadiness: fieldReferenceReadiness,
            subjectState: subjectState,
            at: instant
        )
    }

    /// Read-back guard used by session consumers before they display or
    /// finalize a packet. A stale or missing C23 binding is never inferred.
    func validateFieldReferenceBinding(
        workspaceID: WorkspaceID,
        manifestID: UUID,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        let value = try manifest(workspaceID: workspaceID, manifestID: manifestID)
        return try value.c23ValidateReferenceBinding(
            binding,
            release: release,
            readiness: readiness,
            subjectState: subjectState
        )
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_WorkPacket_WorkPacketManifestLifecycleAdapterV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

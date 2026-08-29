import Foundation

enum WorkPacketScheduleCoordinatorBoundaryV1 { static let startRequiresScheduleMutation = true }

/// Application bridge to the sole WorkspaceWriter. A conformer must route
/// these values through its canonical expected-revision mutation command and
/// return the durable workspace receipt; it may not persist independently.
@MainActor protocol WorkPacketManifestWritingV1: AnyObject {
    func append(manifest: WorkPacketManifestV1) throws -> MutationReceiptV1
    func append(claim: WorkItemClaimV1) throws -> MutationReceiptV1
    func append(lease: WorkLeaseV1) throws -> MutationReceiptV1
    func append(release: WorkReleaseV1) throws -> MutationReceiptV1
    func append(handoff: WorkHandoffV1) throws -> MutationReceiptV1
}

@MainActor final class WorkPacketManifestCoordinatorV1 {
    private let writer: any WorkPacketManifestWritingV1
    private let lifecycle: WorkPacketManifestLifecycleAdapterV1

    init(
        writer: any WorkPacketManifestWritingV1,
        lifecycle: WorkPacketManifestLifecycleAdapterV1
    ) {
        self.writer = writer
        self.lifecycle = lifecycle
    }

    func append(manifest: WorkPacketManifestV1) throws -> MutationReceiptV1 {
        try manifest.validate()
        return try writer.append(manifest: manifest)
    }

    func claim(
        _ claim: WorkItemClaimV1,
        manifest: WorkPacketManifestV1
    ) throws -> MutationReceiptV1 {
        try manifest.validate(); try claim.validate()
        guard claim.workspaceID == manifest.workspaceID,
              claim.manifest == (try WorkPacketManifestReferenceV1(manifest)),
              manifest.items.contains(where: {
                  $0.itemID == claim.item.itemID
                    && $0.kind == claim.item.itemKind
                    && $0.expectedRevision == claim.item.expectedRevision
                    && $0.itemSHA256 == claim.item.itemSHA256
              }) else { throw WorkPacketFailureV1.invalidValue }
        return try writer.append(claim: claim)
    }

    func lease(
        _ lease: WorkLeaseV1,
        claim: WorkItemClaimV1,
        at instant: Date
    ) throws -> MutationReceiptV1 {
        try claim.validate(); try lease.validate()
        guard try lease.isActive(at: instant),
              lease.workspaceID == claim.workspaceID,
              lease.claimID == claim.claimID,
              lease.item == claim.item,
              lease.holder.actor == claim.holder.actor,
              instant >= claim.claimedAt else { throw WorkPacketFailureV1.leaseExpired }
        return try writer.append(lease: lease)
    }

    func release(
        _ release: WorkReleaseV1,
        claim: WorkItemClaimV1,
        lease: WorkLeaseV1
    ) throws -> MutationReceiptV1 {
        try release.validate(claim: claim, lease: lease)
        return try writer.append(release: release)
    }

    func handoff(
        _ handoff: WorkHandoffV1,
        release: WorkReleaseV1
    ) throws -> MutationReceiptV1 {
        try handoff.validate(release: release)
        return try writer.append(handoff: handoff)
    }

    func projection(
        workspaceID: WorkspaceID,
        manifestID: UUID,
        at instant: Date
    ) throws -> WorkPacketProjectionV1 {
        try lifecycle.projection(
            workspaceID: workspaceID,
            manifestID: manifestID,
            at: instant
        )
    }

    /// Validates the C23 binding/readiness inputs before returning the normal
    /// work-packet projection. The binding remains owned by the field-
    /// reference writer; this application seam performs no second write.
    func projectionWithFieldReferences(
        workspaceID: WorkspaceID,
        manifestID: UUID,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1],
        subjectState: FieldReferenceSubjectStateV1 = .active,
        at instant: Date
    ) throws -> WorkPacketFieldReferenceProjectionV1 {
        try lifecycle.projectionWithFieldReferences(
            workspaceID: workspaceID,
            manifestID: manifestID,
            fieldReferenceBindings: fieldReferenceBindings,
            fieldReferenceReleases: fieldReferenceReleases,
            fieldReferenceReadiness: fieldReferenceReadiness,
            subjectState: subjectState,
            at: instant
        )
    }

    /// Appends a manifest only after proving that each supplied binding is
    /// for the exact packet generation. Binding writes themselves use the
    /// dedicated field-reference coordinator.
    func append(
        manifest: WorkPacketManifestV1,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1],
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws -> MutationReceiptV1 {
        try manifest.validate()
        let projection = try WorkPacketFieldReferenceProjectionV1(
            projection: try WorkPacketProjectionBuilderV1.rebuild(
                workspaceID: manifest.workspaceID,
                manifest: manifest,
                claims: [], leases: [], releases: [], handoffs: [], at: manifest.createdAt
            ),
            manifest: manifest,
            bindings: fieldReferenceBindings,
            releases: fieldReferenceReleases,
            readiness: fieldReferenceReadiness,
            subjectState: subjectState
        )
        try projection.validate()
        return try writer.append(manifest: manifest)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_WorkPacket_WorkPacketManifestCoordinatorV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

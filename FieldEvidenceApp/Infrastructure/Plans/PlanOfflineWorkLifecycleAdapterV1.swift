import Foundation

struct PlanOfflineWorkLifecycleOperationsV1: Sendable {
    let exactManifest: @Sendable (WorkPacketManifestReferenceV1) async throws -> WorkPacketManifestV1?
    let fieldReferenceProjection: @Sendable (WorkPacketManifestV1, Date) async throws -> WorkPacketFieldReferenceProjectionV1
    let exactPlanRevision: @Sendable (WorkspaceID, PlanRevisionReferenceV1) async throws -> PlanRevisionV1?
    let currentPlanRevision: @Sendable (WorkspaceID, UUID) async throws -> PlanRevisionReferenceV1?
    let placements: @Sendable (WorkspaceID, PlanRevisionReferenceV1) async throws -> [PlanPlacementV1]
    let prerequisites: @Sendable (PlanRevisionV1, [PlanPlacementV1]) async throws -> PlanPrerequisiteClosureV1
    let openability: @Sendable (PlanContentBindingV1, Date) async throws -> PlanDocumentOpenabilityObservationV1
    let storage: @Sendable (WorkspaceID) async throws -> OfflineReadinessStorageObservationV1
    let access: @Sendable (WorkspaceID) async throws -> OfflineReadinessAccessObservationV1
    let exactPoseEvent: @Sendable (AssetPoseEventReferenceV1) async throws -> AssetPoseEventV1?
}

struct PlanMaterializedPoseRequestV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let placementID: UUID
    let event: AssetPoseEventReferenceV1
    init(placementID: UUID, event: AssetPoseEventReferenceV1) throws {
        self.placementID = placementID; self.event = event
        try PlanOfflineWorkLimitsV1.id(placementID); try event.validate()
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.placementID.uuidString, lhs.event.axisID.rawValue, lhs.event.revision) <
            (rhs.placementID.uuidString, rhs.event.axisID.rawValue, rhs.event.revision)
    }
}

/// Exact-ID lifecycle source. Requested packet and plan identities include
/// revision and SHA; a current-tip lookup is used only to label current versus
/// historic and is never substituted for the requested value.
final class PlanOfflineWorkLifecycleAdapterV1: PlanOfflineWorkSourceResolvingV1, @unchecked Sendable {
    private let operations: PlanOfflineWorkLifecycleOperationsV1

    init(operations: PlanOfflineWorkLifecycleOperationsV1) {
        self.operations = operations
    }

    func source(for request: PlanOfflineWorkRequestV1) async throws -> PlanOfflineWorkSourceV1 {
        guard let manifest = try await operations.exactManifest(request.packet) else {
            throw PlanOfflineWorkFailureV1.missingExactSource
        }
        try manifest.validate()
        guard (try WorkPacketManifestReferenceV1(manifest)) == request.packet,
              let item = manifest.items.first(where: { candidate in
                  (try? WorkPacketItemReferenceV1(manifest: manifest, item: candidate)) == request.item
              }) else { throw PlanOfflineWorkFailureV1.staleSource }

        let packetProjection = try await operations.fieldReferenceProjection(manifest, request.checkedAt)
        try packetProjection.validate()
        guard let planRevision = try await operations.exactPlanRevision(
            request.workspaceID, request.exactPlanRevision
        ) else { throw PlanOfflineWorkFailureV1.missingExactSource }
        try planRevision.validateIntrinsic()
        guard try planRevision.reference == request.exactPlanRevision else {
            throw PlanOfflineWorkFailureV1.staleSource
        }
        let matchingReferences = packetProjection.references.filter {
            $0.releaseID == planRevision.contentBinding.fieldReferenceReleaseID &&
                $0.releaseRevision == planRevision.contentBinding.fieldReferenceReleaseRevision &&
                $0.releaseSHA256 == planRevision.contentBinding.fieldReferenceReleaseSHA256 &&
                $0.manifestSHA256 == planRevision.contentBinding.fieldReferenceManifestSHA256
        }
        guard matchingReferences.count == 1, let reference = matchingReferences.first,
              planRevision.contentBinding.fieldReferenceReleaseID == reference.releaseID,
              planRevision.contentBinding.fieldReferenceReleaseRevision == reference.releaseRevision,
              planRevision.contentBinding.fieldReferenceReleaseSHA256 == reference.releaseSHA256,
              planRevision.contentBinding.fieldReferenceManifestSHA256 == reference.manifestSHA256 else {
            throw PlanOfflineWorkFailureV1.staleSource
        }

        guard let current = try await operations.currentPlanRevision(
            request.workspaceID, request.exactPlanRevision.planDocumentID
        ) else { throw PlanOfflineWorkFailureV1.missingExactSource }
        try current.validate()
        guard current.planDocumentID == request.exactPlanRevision.planDocumentID else {
            throw PlanOfflineWorkFailureV1.staleSource
        }
        let disposition: PlanRevisionSelectionDispositionV1 =
            current == request.exactPlanRevision ? .current : .historic

        let placements = try await operations.placements(
            request.workspaceID, request.exactPlanRevision
        )
        let sortedPlacements = placements.sorted { $0.placementID.uuidString < $1.placementID.uuidString }
        try sortedPlacements.forEach { try $0.validate(planRevision: planRevision) }
        let prerequisites = try await operations.prerequisites(planRevision, sortedPlacements)
        try prerequisites.validate(revision: planRevision, placements: sortedPlacements)
        let openability = try await operations.openability(planRevision.contentBinding, request.checkedAt)
        let storage = try await operations.storage(request.workspaceID)
        let access = try await operations.access(request.workspaceID)
        let value = PlanOfflineWorkSourceV1(
            applicability: request.applicability, manifest: manifest, item: item,
            fieldReferenceProjection: packetProjection, fieldReference: reference,
            planRevision: planRevision, placements: sortedPlacements, prerequisites: prerequisites,
            openability: openability, storage: storage, access: access,
            revisionDisposition: disposition, checkedAt: request.checkedAt
        )
        try value.validate()
        return value
    }

    func materializedPoseSnapshots(
        _ requests: [PlanMaterializedPoseRequestV1],
        source: PlanOfflineWorkSourceV1
    ) async throws -> [PlanMaterializedPoseSnapshotV1] {
        try source.validate()
        let requests = requests.sorted()
        guard Set(requests).count == requests.count else { throw PlanOfflineWorkFailureV1.invalidValue }
        var values: [PlanMaterializedPoseSnapshotV1] = []
        for request in requests {
            guard source.placements.contains(where: { $0.placementID == request.placementID }),
                  request.event.workspaceID == source.manifest.workspaceID,
                  let event = try await operations.exactPoseEvent(request.event) else {
                throw PlanOfflineWorkFailureV1.missingExactSource
            }
            try event.validateIntrinsic()
            guard event.reference == request.event else { throw PlanOfflineWorkFailureV1.staleSource }
            values.append(try .init(placementID: request.placementID, event: event))
        }
        return values.sorted()
    }
}

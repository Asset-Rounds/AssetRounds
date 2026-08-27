import Foundation

@MainActor
final class AssetPlacementChangeCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let idSource: any ApplicationIDSource
    private let components: PlacementChangeComponentRegistryV1

    init(writer: WorkspaceWriterV1, idSource: any ApplicationIDSource, components: PlacementChangeComponentRegistryV1) {
        self.writer = writer; self.idSource = idSource; self.components = components
    }

    func previewAssetPlacementChange(_ basis: AssetPlacementPreviewBasisV1) throws -> AssetPlacementChangePlanV1 {
        let observedBefore = try writer.currentRevision()
        guard observedBefore == (try basis.expectedRevision.snapshotValue) else { throw LocationContractFailureV1.staleRevision }
        let contributions = try components.contributions(for: basis)
        guard try writer.currentRevision() == observedBefore else { throw LocationContractFailureV1.staleRevision }
        let mutationID = try MutationIDV1(rawValue: idSource.makeID())
        let episode: PhysicalPlacementEpisodeIDV1
        if basis.reviewedContinuity == .physicalMove || basis.currentPlacement == nil {
            episode = try PhysicalPlacementEpisodeIDV1(rawValue: idSource.makeID())
        } else if let prior = basis.currentPlacement?.physicalEpisodeID {
            episode = prior
        } else {
            throw LocationContractFailureV1.reviewRequired
        }
        return try AssetPlacementChangePlanV1(
            operationID: idSource.makeID(), mutationID: mutationID, basis: basis,
            newEventID: idSource.makeID(), resultingPhysicalEpisodeID: episode,
            componentContributions: contributions
        )
    }

    func commitAssetPlacementChange(_ plan: AssetPlacementChangePlanV1) throws -> AssetPlacementChangeReceiptV1 {
        let request = WorkspaceMutationRequestV1(
            mutationID: plan.mutationID,
            expectedRevision: plan.basis.expectedRevision,
            command: .applyAssetPlacementChange(plan)
        )
        _ = try writer.execute(request)
        guard let durable = try writer.durableReceipt(mutationID: plan.mutationID) else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        let event = try AssetPlacementEventV1(
            id: plan.newEventID, workspaceID: plan.basis.workspaceID, assetID: plan.basis.assetID,
            siteID: plan.basis.proposedSiteID, locationNodeID: plan.basis.proposedLocationNodeID,
            predecessorEventID: plan.basis.currentPlacement?.id, source: plan.basis.source,
            physicalEpisodeID: plan.resultingPhysicalEpisodeID, continuity: plan.basis.reviewedContinuity,
            pathSnapshot: plan.basis.proposedPath, mutationID: plan.mutationID, occurredAt: durable.committedAt
        )
        return try AssetPlacementChangeReceiptV1(plan: plan, placementEvent: event, mutationReceipt: durable)
    }

    func commitHierarchyChange(
        _ plan: LocationHierarchyChangePlanV1,
        placementChanges: [AssetPlacementChangePlanV1]
    ) throws -> LocationHierarchyChangeReceiptV1 {
        try plan.validate()
        let mutationID = try MutationIDV1(rawValue: plan.operationID)
        let reboundPlacements = try placementChanges.map {
            try AssetPlacementChangePlanV1(
                operationID: plan.operationID, mutationID: mutationID, basis: $0.basis,
                newEventID: $0.newEventID, resultingPhysicalEpisodeID: $0.resultingPhysicalEpisodeID,
                componentContributions: $0.componentContributions
            )
        }
        let value = try LocationHierarchyMutationV1(plan: plan, placementChanges: reboundPlacements)
        let request = WorkspaceMutationRequestV1(mutationID: mutationID, expectedRevision: plan.expectedRevision, command: .applyLocationHierarchyChange(value))
        _ = try writer.execute(request)
        guard let durable = try writer.durableReceipt(mutationID: mutationID) else { throw WorkspaceMutationFailureV1.invalidReceipt }
        return try LocationHierarchyChangeReceiptV1(plan: plan, mutationReceipt: durable)
    }

    func commitLocationDeletion(
        _ deletion: LocationDeletionPlanV1,
        hierarchyChange: LocationHierarchyChangePlanV1,
        placementChanges: [AssetPlacementChangePlanV1] = []
    ) throws -> LocationHierarchyChangeReceiptV1 {
        try deletion.validate()
        try hierarchyChange.validate()
        let beforeByID = Dictionary(uniqueKeysWithValues: hierarchyChange.beforeNodes.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: hierarchyChange.afterNodes.map { ($0.id, $0) })
        let affectedNodeIDs = Set(deletion.affectedNodeIDs)
        guard deletion.operationID == hierarchyChange.operationID,
              deletion.workspaceID == hierarchyChange.workspaceID,
              deletion.expectedRevision == hierarchyChange.expectedRevision,
              hierarchyChange.assetBindingsChange == !deletion.affectedAssetIDs.isEmpty,
              hierarchyChange.affectedAssetIDs == deletion.affectedAssetIDs,
              placementChanges.map(\.basis.assetID) == deletion.affectedAssetIDs,
              placementChanges.allSatisfy({ placement in
                  placement.basis.proposedLocationNodeID.map({ !affectedNodeIDs.contains($0) }) ?? true
              }),
              Set(beforeByID.keys) == affectedNodeIDs else {
            throw LocationContractFailureV1.hierarchyViolation
        }
        if deletion.archiveOnly {
            guard Set(afterByID.keys) == affectedNodeIDs,
                  deletion.affectedNodeIDs.allSatisfy({ id in
                      guard let before = beforeByID[id], let after = afterByID[id] else { return false }
                      return after.state == .archived
                        && after.id == before.id
                        && after.workspaceID == before.workspaceID
                        && after.siteID == before.siteID
                        && after.parentNodeID == before.parentNodeID
                        && after.kind == before.kind
                        && after.label == before.label
                        && after.shortCode == before.shortCode
                        && after.siblingOrder == before.siblingOrder
                        && after.revision == before.revision + 1
                  }) else {
                throw LocationContractFailureV1.hierarchyViolation
            }
        } else {
            guard afterByID.isEmpty,
                  deletion.affectedAssetIDs.isEmpty,
                  placementChanges.isEmpty else {
                throw LocationContractFailureV1.hierarchyViolation
            }
        }
        return try commitHierarchyChange(hierarchyChange, placementChanges: placementChanges)
    }

    func commitCompositionChange(_ plan: AssetCompositionChangePlanV1) throws -> MutationReceiptV1 {
        try plan.validate()
        let request = WorkspaceMutationRequestV1(mutationID: plan.mutationID, expectedRevision: plan.expectedRevision, command: .applyAssetCompositionChange(plan))
        _ = try writer.execute(request)
        guard let durable = try writer.durableReceipt(mutationID: plan.mutationID) else { throw WorkspaceMutationFailureV1.invalidReceipt }
        return durable
    }

    /// Read-only cross-check used before a completed activity freezes its
    /// subject scope. It never expands C35 composition policy or creates a
    /// functional relationship owned by C41.
    func validateFrozenWorkSubjectScope(
        _ snapshot: WorkSubjectScopeSnapshotV1,
        placementTips: [AssetPlacementEventV1],
        activeCompositionEdges: [AssetCompositionEdgeV1]
    ) throws {
        try snapshot.validate()
        try placementTips.forEach { try $0.validate() }
        try activeCompositionEdges.forEach { try $0.validate() }
        guard placementTips.allSatisfy({
            $0.workspaceID == snapshot.workspaceID && $0.siteID == snapshot.siteID
        }),
        activeCompositionEdges.allSatisfy({
            $0.workspaceID == snapshot.workspaceID && $0.isActive
        }) else {
            throw LocationContractFailureV1.invalidValue
        }
        let expectedAssetSubjects = try Set(placementTips.map {
            try $0.frozenAssetWorkSubjectReference().subjectID
        })
        let observedAssetSubjects = Set(snapshot.subjects.filter {
            $0.kind == .asset
        }.map(\.subjectID))
        let expectedComponentSubjects = try Set(activeCompositionEdges.map {
            try $0.frozenWorkSubjectReference().subjectID
        })
        let observedComponentSubjects = Set(snapshot.subjects.filter {
            $0.kind == .compositionComponent
        }.map(\.subjectID))
        guard observedAssetSubjects.isSubset(of: expectedAssetSubjects),
              observedComponentSubjects.isSubset(of: expectedComponentSubjects) else {
            throw LocationContractFailureV1.invalidValue
        }
    }
}

private extension WorkspaceExpectedRevisionV1 {
    var snapshotValue: WorkspaceRevisionV1 {
        get throws {
            try WorkspaceRevisionV1(
                workspaceID: workspaceID, generationID: generationID,
                writerInstanceID: writerInstanceID, revision: workspaceRevision,
                entityRevisions: entityRevisions
            )
        }
    }
}

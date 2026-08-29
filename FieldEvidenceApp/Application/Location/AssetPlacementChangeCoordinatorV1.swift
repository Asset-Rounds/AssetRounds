import Foundation

struct PosePlacementPostImageContextV1: Sendable {
    let mutationID: MutationIDV1; let newPlacementEventID: UUID
    let resultingPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1
    let basis: AssetPlacementPreviewBasisV1
    let contributions: [PlacementChangeComponentContributionV1]
}

@MainActor
final class AssetPlacementChangeCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let idSource: any ApplicationIDSource
    private let components: PlacementChangeComponentRegistryV1

    init(writer: WorkspaceWriterV1, idSource: any ApplicationIDSource, components: PlacementChangeComponentRegistryV1) {
        self.writer = writer; self.idSource = idSource; self.components = components
    }

    func previewAssetPlacementChange(_ basis: AssetPlacementPreviewBasisV1,
        poseAdmissionClosure: PlacementPoseAdmissionClosureV1? = nil,
        posePostImageBuilder: ((PosePlacementPostImageContextV1) throws -> (events: [AssetPoseEventV1], predecessors: [AssetPoseEventV1]))? = nil) throws -> AssetPlacementChangePlanV1 {
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
        let newEventID = idSource.makeID()
        let poseValues = try posePostImageBuilder?(.init(mutationID: mutationID,
            newPlacementEventID: newEventID, resultingPhysicalEpisodeID: episode,
            basis: basis, contributions: contributions)) ?? (events: [], predecessors: [])
        return try AssetPlacementChangePlanV1(
            operationID: idSource.makeID(), mutationID: mutationID, basis: basis,
            newEventID: newEventID, resultingPhysicalEpisodeID: episode,
            componentContributions: contributions, poseEvents: poseValues.events,
            poseEventPredecessors: poseValues.predecessors,
            poseAdmissionClosure: poseAdmissionClosure
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
            let reboundPoseEvents = try zip($0.poseEvents, $0.poseEventPredecessors).map {
                try $0.0.reissued(mutationID: mutationID, predecessor: $0.1)
            }
            try AssetPlacementChangePlanV1(
                operationID: plan.operationID, mutationID: mutationID, basis: $0.basis,
                newEventID: $0.newEventID, resultingPhysicalEpisodeID: $0.resultingPhysicalEpisodeID,
                componentContributions: $0.componentContributions,
                poseEvents: reboundPoseEvents, poseEventPredecessors: $0.poseEventPredecessors,
                poseAdmissionClosure: $0.poseAdmissionClosure
            )
        }
        let value = try LocationHierarchyMutationV1(plan: plan, placementChanges: reboundPlacements)
        let request = WorkspaceMutationRequestV1(mutationID: mutationID, expectedRevision: plan.expectedRevision, command: .applyLocationHierarchyChange(value))
        _ = try writer.execute(request)
        guard let durable = try writer.durableReceipt(mutationID: mutationID) else { throw WorkspaceMutationFailureV1.invalidReceipt }
        return try LocationHierarchyChangeReceiptV1(plan: plan,
            placementChanges: reboundPlacements, mutationReceipt: durable)
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

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_Location_AssetPlacementChangeCoordinatorV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_Location_AssetPlacementChangeCoordinatorV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Application_Location_AssetPlacementChangeCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Location/AssetPlacementChangeCoordinatorV1.swift", role: .location)
}

enum C31LightingConsumerBoundary_Application_Location_AssetPlacementChangeCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/asset-placement-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

// MARK: - C32 one-shot location proposal boundary

enum AssistanceLocationProposalBoundaryV1 {
    static let capabilityID = "ONE_SHOT_LOCATION_PROPOSAL"
    static let manualFallback: ManualFallbackActionV1 = .typeManually

    /// Location observations remain unverified proposal input. They do not
    /// create a placement, hierarchy node, or sensor truth before the shared
    /// expected-revision acceptance transaction succeeds.
    static func validateUnverified(
        _ proposal: AssistanceProposalV1,
        context: AssistanceProposalEvaluationContextV1
    ) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.capability.capabilityID == capabilityID,
              proposal.privacyClass == .preciseLocation,
              proposal.source.kind == .deviceObservation,
              context.policy.manualFallback == manualFallback,
              proposal.target.workspaceID == context.workspaceID,
              try proposal.expiryReason(in: context) == nil else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
    }

    static func validateAccepted(
        _ receipt: AssistanceAcceptanceReceiptV1,
        for proposal: AssistanceProposalV1
    ) throws -> ResponseValueV1 {
        try receipt.validate()
        try proposal.validate()
        guard proposal.capability.capabilityID == capabilityID,
              receipt.proposalID == proposal.proposalID,
              receipt.target == proposal.target,
              receipt.acceptedValue == proposal.value,
              receipt.privacyClass == .preciseLocation else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return receipt.acceptedValue
    }
}

enum C33TemporalEvidenceBoundary_Application_Location_AssetPlacementChangeCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row153 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

import Foundation

protocol PlacementPoseQueryingV1: Sendable {
    func currentPoseEvents(workspaceID: WorkspaceID, assetID: UUID) async throws -> [AssetPoseEventV1]
    func currentAnchor(workspaceID: WorkspaceID, assetID: UUID) async throws -> SpatialAnchorObservationV1?
    func placementEvent(workspaceID: WorkspaceID, eventID: UUID) async throws -> AssetPlacementEventV1?
}

@MainActor
protocol PlacementPoseMutationAuthorityV1: AnyObject {
    func appendPoseEvent(_ event: AssetPoseEventV1,
                         predecessor: AssetPoseEventV1?,
                         admissionClosure: PlacementPoseAdmissionClosureV1) async throws -> MutationReceiptV1
    func appendSpatialAnchor(_ observation: SpatialAnchorObservationV1,
                             predecessor: SpatialAnchorObservationV1?,
                             admissionClosure: PlacementPoseAdmissionClosureV1) async throws -> MutationReceiptV1
}

struct PlacementPoseAppendReceiptV1: Codable, Equatable, Sendable {
    let event: AssetPoseEventV1
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let canonicalMutationReceiptSHA256: String
    init(event: AssetPoseEventV1, mutationReceipt: MutationReceiptV1) throws {
        try event.validateIntrinsic(); try mutationReceipt.validate()
        guard mutationReceipt.mutationID == event.mutationID,
              mutationReceipt.identity.workspaceID == event.workspaceID else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
        self.event = event; mutationReceiptIdentity = mutationReceipt.identity
        canonicalMutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
    }
}

@MainActor
final class PlacementPoseCoordinatorV1 {
    private let query: any PlacementPoseQueryingV1
    private let authority: any PlacementPoseMutationAuthorityV1

    init(query: any PlacementPoseQueryingV1, authority: any PlacementPoseMutationAuthorityV1) {
        self.query = query; self.authority = authority
    }

    func append(_ event: AssetPoseEventV1,
                admissionClosure: PlacementPoseAdmissionClosureV1) async throws -> PlacementPoseAppendReceiptV1 {
        try event.validateIntrinsic()
        try admissionClosure.validate(events: [event], observations: [])
        guard let placement = try await query.placementEvent(workspaceID: event.workspaceID,
                                                              eventID: event.placementEventID) else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
        try placement.validate()
        guard placement.workspaceID == event.workspaceID, placement.assetID == event.assetID,
              placement.physicalEpisodeID == event.placementEpisodeID,
              placement.pathSnapshot == event.locationPathSnapshot else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
        let current = try await query.currentPoseEvents(workspaceID: event.workspaceID,
                                                        assetID: event.assetID)
            .filter { $0.axisDescriptor.axisID == event.axisDescriptor.axisID }
        let predecessor = current.max(by: { $0.revision < $1.revision })
        if let predecessor {
            try event.validateSuccessor(of: predecessor)
        } else if event.predecessor != nil || event.revision != 1 {
            throw PlacementPoseFailureV1.predecessorMismatch
        }
        let receipt = try await authority.appendPoseEvent(event, predecessor: predecessor,
                                                          admissionClosure: admissionClosure)
        return try .init(event: event, mutationReceipt: receipt)
    }

    func append(_ observation: SpatialAnchorObservationV1,
                admissionClosure: PlacementPoseAdmissionClosureV1) async throws -> MutationReceiptV1 {
        try observation.validateIntrinsic()
        try admissionClosure.validate(events: [], observations: [observation])
        let predecessor = try await query.currentAnchor(workspaceID: observation.workspaceID,
                                                         assetID: observation.assetID)
        if let predecessor {
            try observation.validateSuccessor(of: predecessor)
        } else if observation.predecessorObservationID != nil || observation.revision != 1 {
            throw PlacementPoseFailureV1.predecessorMismatch
        }
        return try await authority.appendSpatialAnchor(observation, predecessor: predecessor,
                                                        admissionClosure: admissionClosure)
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Application_Pose_PlacementPoseCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Pose/PlacementPoseCoordinatorV1.swift", role: .pose)
}

enum C31LightingConsumerBoundary_Application_Pose_PlacementPoseCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/placement-pose-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

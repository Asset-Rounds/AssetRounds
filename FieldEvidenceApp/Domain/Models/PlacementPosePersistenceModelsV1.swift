import Foundation
enum EvidenceContextPlacementPoseBoundaryV1{static let poseHistoryDoesNotOwnEvidenceContext=true;static let contextAssetRevisionMustRemainExact=true}
import SwiftData

enum PlacementPosePersistenceFailureV1: Error { case corruptRow }

@Model final class AssetPoseEventRow {
    @Attribute(.unique) var eventID: UUID
    var workspaceID: UUID; var assetID: UUID; var axisID: String
    var placementEpisodeID: UUID; var placementEventID: UUID
    var predecessorEventID: UUID?; var revision: UInt64; var mutationID: UUID
    var eventSHA256: String; var canonicalData: Data
    init(_ value: AssetPoseEventV1) throws {
        try value.validateIntrinsic(); eventID=value.eventID; workspaceID=value.workspaceID.rawValue
        assetID=value.assetID; axisID=value.axisDescriptor.axisID.rawValue
        placementEpisodeID=value.placementEpisodeID.rawValue; placementEventID=value.placementEventID
        predecessorEventID=value.predecessor?.eventID; revision=value.revision; mutationID=value.mutationID.rawValue
        eventSHA256=value.eventSHA256; canonicalData=try PlacementPoseCanonicalCodecV1.encode(value)
        guard try PlacementPoseCanonicalCodecV1.decode(AssetPoseEventV1.self,from:canonicalData)==value else{throw PlacementPosePersistenceFailureV1.corruptRow}
    }
    func value()throws->AssetPoseEventV1{let value=try PlacementPoseCanonicalCodecV1.decode(AssetPoseEventV1.self,from:canonicalData);try value.validateIntrinsic();guard value.eventID==eventID,value.workspaceID.rawValue==workspaceID,value.assetID==assetID,value.axisDescriptor.axisID.rawValue==axisID,value.placementEpisodeID.rawValue==placementEpisodeID,value.placementEventID==placementEventID,value.predecessor?.eventID==predecessorEventID,value.revision==revision,value.mutationID.rawValue==mutationID,value.eventSHA256==eventSHA256 else{throw PlacementPosePersistenceFailureV1.corruptRow};return value}
}

@Model final class SpatialAnchorObservationRow {
    @Attribute(.unique) var observationID: UUID
    var workspaceID: UUID; var assetID: UUID; var placementEpisodeID: UUID
    var planRevisionID: UUID; var pageID: UUID; var spatialFrameID: UUID
    var predecessorObservationID: UUID?; var revision: UInt64; var mutationID: UUID
    var observationSHA256: String; var canonicalData: Data
    init(_ value: SpatialAnchorObservationV1) throws {
        try value.validateIntrinsic(); observationID=value.observationID; workspaceID=value.workspaceID.rawValue
        assetID=value.assetID; placementEpisodeID=value.placementEpisodeID.rawValue
        planRevisionID=value.planFrame.planRevision.planRevisionID; pageID=value.planFrame.pageID; spatialFrameID=value.planFrame.spatialFrameID
        predecessorObservationID=value.predecessorObservationID; revision=value.revision; mutationID=value.mutationID.rawValue
        observationSHA256=value.observationSHA256; canonicalData=try PlacementPoseCanonicalCodecV1.encode(value)
        guard try PlacementPoseCanonicalCodecV1.decode(SpatialAnchorObservationV1.self,from:canonicalData)==value else{throw PlacementPosePersistenceFailureV1.corruptRow}
    }
    func value()throws->SpatialAnchorObservationV1{let value=try PlacementPoseCanonicalCodecV1.decode(SpatialAnchorObservationV1.self,from:canonicalData);try value.validateIntrinsic();guard value.observationID==observationID,value.workspaceID.rawValue==workspaceID,value.assetID==assetID,value.placementEpisodeID.rawValue==placementEpisodeID,value.planFrame.planRevision.planRevisionID==planRevisionID,value.planFrame.pageID==pageID,value.planFrame.spatialFrameID==spatialFrameID,value.predecessorObservationID==predecessorObservationID,value.revision==revision,value.mutationID.rawValue==mutationID,value.observationSHA256==observationSHA256 else{throw PlacementPosePersistenceFailureV1.corruptRow};return value}
}

enum PlacementPosePersistenceEnrollmentV1{static let durableModelCount=2;static let persistentSchemaVersion=29;static let recordsSchemaVersion=28;static let derivedTypes:[Any.Type]=[PoseAxisDescriptorRegistryV1.self,AssetPoseCurrentTipV1.self,CompletedPlacementPoseSnapshotV1.self]}

import Foundation
enum EvidenceContextPlanBoundaryV1{static let planFramesDoNotOwnEvidenceContext=true;static let pairedObservationLinksRemainSeparateHistory=true}
enum PlacementPosePlanPersistenceBoundaryV1{static let anchorObservationsBindExactEmbeddedFrames=true;static let framesRemainEmbeddedInPlanRevision=true}
import SwiftData

enum PlanPersistenceFailureV1: Error { case corruptRow }

@Model final class PlanDocumentRow {
    @Attribute(.unique) var rowID: UUID
    var planDocumentID: UUID; var workspaceID: UUID; var stablePlanKey: String
    var stateRawValue: String; var supersedesDocumentSHA256: String?
    var revision: UInt64; var mutationID: UUID; var documentSHA256: String; var canonicalData: Data
    init(_ value: PlanDocumentV1) throws {
        try value.validateIntrinsic(); rowID=value.mutationID.rawValue;planDocumentID=value.planDocumentID
        workspaceID=value.workspaceID.rawValue;stablePlanKey=value.stablePlanKey;stateRawValue=value.state.rawValue
        supersedesDocumentSHA256=value.supersedesDocumentSHA256;revision=value.revision
        mutationID=value.mutationID.rawValue;documentSHA256=value.documentSHA256;canonicalData=try PlanCanonicalCodecV1.encode(value)
        guard try PlanCanonicalCodecV1.decode(PlanDocumentV1.self,from:canonicalData)==value else{throw PlanPersistenceFailureV1.corruptRow}
    }
    func value() throws -> PlanDocumentV1 { let value=try PlanCanonicalCodecV1.decode(PlanDocumentV1.self,from:canonicalData);try value.validateIntrinsic();guard value.planDocumentID==planDocumentID,value.workspaceID.rawValue==workspaceID,value.stablePlanKey==stablePlanKey,value.state.rawValue==stateRawValue,value.supersedesDocumentSHA256==supersedesDocumentSHA256,value.revision==revision,value.mutationID.rawValue==mutationID,value.documentSHA256==documentSHA256 else{throw PlanPersistenceFailureV1.corruptRow};return value }
}

@Model final class PlanRevisionRow {
    @Attribute(.unique) var planRevisionID: UUID
    var workspaceID: UUID;var planDocumentID: UUID;var contentID:String;var fieldReferenceReleaseID:UUID
    var stateRawValue:String;var supersedesPlanRevisionID:UUID?;var revision:UInt64;var mutationID:UUID;var revisionSHA256:String;var canonicalData:Data
    init(_ value:PlanRevisionV1)throws{try value.validateIntrinsic();planRevisionID=value.planRevisionID;workspaceID=value.workspaceID.rawValue;planDocumentID=value.planDocument.planDocumentID;contentID=value.contentBinding.contentID;fieldReferenceReleaseID=value.contentBinding.fieldReferenceReleaseID;stateRawValue=value.state.rawValue;supersedesPlanRevisionID=value.supersedesPlanRevisionID;revision=value.revision;mutationID=value.mutationID.rawValue;revisionSHA256=value.revisionSHA256;canonicalData=try PlanCanonicalCodecV1.encode(value);guard try PlanCanonicalCodecV1.decode(PlanRevisionV1.self,from:canonicalData)==value else{throw PlanPersistenceFailureV1.corruptRow}}
    func value()throws->PlanRevisionV1{let value=try PlanCanonicalCodecV1.decode(PlanRevisionV1.self,from:canonicalData);try value.validateIntrinsic();guard value.planRevisionID==planRevisionID,value.workspaceID.rawValue==workspaceID,value.planDocument.planDocumentID==planDocumentID,value.contentBinding.contentID==contentID,value.contentBinding.fieldReferenceReleaseID==fieldReferenceReleaseID,value.state.rawValue==stateRawValue,value.supersedesPlanRevisionID==supersedesPlanRevisionID,value.revision==revision,value.mutationID.rawValue==mutationID,value.revisionSHA256==revisionSHA256 else{throw PlanPersistenceFailureV1.corruptRow};return value}
}

@Model final class PlanPlacementRow {
    @Attribute(.unique) var historyKey: String
    var placementID:UUID;var workspaceID:UUID;var subjectKindRawValue:String;var subjectID:UUID;var planRevisionID:UUID
    var spatialFrameID:UUID;var supersedesPlacementSHA256:String?;var revision:UInt64;var mutationID:UUID;var placementSHA256:String;var canonicalData:Data
    init(_ value:PlanPlacementV1)throws{try value.validateIntrinsic();historyKey=Self.key(value.placementID,value.revision);placementID=value.placementID;workspaceID=value.workspaceID.rawValue;subjectKindRawValue=value.subjectKind.rawValue;subjectID=value.subjectID;planRevisionID=value.planRevision.planRevisionID;spatialFrameID=value.spatialFrameID;supersedesPlacementSHA256=value.supersedesPlacementSHA256;revision=value.revision;mutationID=value.mutationID.rawValue;placementSHA256=value.placementSHA256;canonicalData=try PlanCanonicalCodecV1.encode(value);guard try PlanCanonicalCodecV1.decode(PlanPlacementV1.self,from:canonicalData)==value else{throw PlanPersistenceFailureV1.corruptRow}}
    func value()throws->PlanPlacementV1{let value=try PlanCanonicalCodecV1.decode(PlanPlacementV1.self,from:canonicalData);try value.validateIntrinsic();guard historyKey==Self.key(value.placementID,value.revision),value.placementID==placementID,value.workspaceID.rawValue==workspaceID,value.subjectKind.rawValue==subjectKindRawValue,value.subjectID==subjectID,value.planRevision.planRevisionID==planRevisionID,value.spatialFrameID==spatialFrameID,value.supersedesPlacementSHA256==supersedesPlacementSHA256,value.revision==revision,value.mutationID.rawValue==mutationID,value.placementSHA256==placementSHA256 else{throw PlanPersistenceFailureV1.corruptRow};return value}
    private static func key(_ placementID:UUID,_ revision:UInt64)->String{"\(placementID.uuidString.lowercased()):\(revision)"}
}

@Model final class RebaseReceiptRow {
    @Attribute(.unique) var receiptID:UUID
    var workspaceID:UUID;var previewID:UUID;var previewSHA256:String;var decisionRawValue:String
    var supersedesReceiptSHA256:String?;var revision:UInt64;var mutationID:UUID;var receiptSHA256:String;var canonicalData:Data
    init(_ value:RebaseReceiptV1)throws{try value.validateIntrinsic();receiptID=value.receiptID;workspaceID=value.workspaceID.rawValue;previewID=value.previewID;previewSHA256=value.previewSHA256;decisionRawValue=value.decision.rawValue;supersedesReceiptSHA256=value.supersedesReceiptSHA256;revision=value.revision;mutationID=value.mutationID.rawValue;receiptSHA256=value.receiptSHA256;canonicalData=try PlanCanonicalCodecV1.encode(value);guard try PlanCanonicalCodecV1.decode(RebaseReceiptV1.self,from:canonicalData)==value else{throw PlanPersistenceFailureV1.corruptRow}}
    func value()throws->RebaseReceiptV1{let value=try PlanCanonicalCodecV1.decode(RebaseReceiptV1.self,from:canonicalData);try value.validateIntrinsic();guard value.receiptID==receiptID,value.workspaceID.rawValue==workspaceID,value.previewID==previewID,value.previewSHA256==previewSHA256,value.decision.rawValue==decisionRawValue,value.supersedesReceiptSHA256==supersedesReceiptSHA256,value.revision==revision,value.mutationID.rawValue==mutationID,value.receiptSHA256==receiptSHA256 else{throw PlanPersistenceFailureV1.corruptRow};return value}
}

enum PlanPersistenceEnrollmentV1 { static let durableModelCount=4;static let persistentSchemaVersion=28;static let recordsSchemaVersion=27;static let derivedTypes:[Any.Type]=[RebasePreviewV1.self] }

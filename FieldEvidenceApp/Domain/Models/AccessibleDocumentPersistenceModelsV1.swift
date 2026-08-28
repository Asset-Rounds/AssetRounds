import Foundation
import SwiftData

enum AccessibleDocumentPersistenceFailureV1:Error{case corruptRow}

@Model final class AccessibleDocumentAssessmentReceiptRow{
    @Attribute(.unique)var receiptID:UUID
    var workspaceID:UUID
    var revision:UInt64
    var mutationID:UUID
    var treeSHA256:String
    var outputSHA256:String
    var receiptSHA256:String
    var scopeRawValue:String
    var audienceRawValue:String
    var projectionVersion:String
    var manifestID:String
    var manifestVersion:Int
    var profileRelease:Int
    var brandProfileID:String
    var brandProfileRelease:Int
    var canonicalData:Data
    init(_ value:AccessibleDocumentAssessmentReceiptV1)throws{try value.validateIntrinsic();receiptID=value.receiptID;workspaceID=value.workspaceID.rawValue;revision=value.revision;mutationID=value.mutationID.rawValue;treeSHA256=value.treeSHA256;outputSHA256=value.outputSHA256;receiptSHA256=value.receiptSHA256;scopeRawValue=value.scope.rawValue;audienceRawValue=value.audience.rawValue;projectionVersion=value.projectionVersion;manifestID=value.manifestID;manifestVersion=value.manifestVersion;profileRelease=value.profileRelease;brandProfileID=value.brandProfileID;brandProfileRelease=value.brandProfileRelease;canonicalData=try AccessibleDocumentCanonicalCodecV1.encode(value)}
    convenience init(_ value:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)throws{try value.validate(tree:tree);try self.init(value)}
    func value()throws->AccessibleDocumentAssessmentReceiptV1{let value=try AccessibleDocumentCanonicalCodecV1.decode(AccessibleDocumentAssessmentReceiptV1.self,from:canonicalData);try value.validateIntrinsic();guard value.receiptID==receiptID,value.workspaceID.rawValue==workspaceID,value.revision==revision,value.mutationID.rawValue==mutationID,value.treeSHA256==treeSHA256,value.outputSHA256==outputSHA256,value.receiptSHA256==receiptSHA256,value.scope.rawValue==scopeRawValue,value.audience.rawValue==audienceRawValue,value.projectionVersion==projectionVersion,value.manifestID==manifestID,value.manifestVersion==manifestVersion,value.profileRelease==profileRelease,value.brandProfileID==brandProfileID,value.brandProfileRelease==brandProfileRelease else{throw AccessibleDocumentPersistenceFailureV1.corruptRow};return value}
    func value(tree:AccessibleDocumentSemanticTreeV1)throws->AccessibleDocumentAssessmentReceiptV1{let value=try value();try value.validate(tree:tree);return value}
}

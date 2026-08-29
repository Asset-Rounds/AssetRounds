import Foundation
import SwiftData

enum SurveySessionPersistenceFailureV1: Error { case corruptRow }

private func surveySessionDecoded<T: Codable & Equatable>(_ type: T.Type, data: Data, expected: T? = nil) throws -> T {
    let value = try SurveySessionCanonicalCodecV1.decode(type, from: data)
    if let expected, value != expected { throw SurveySessionPersistenceFailureV1.corruptRow }
    return value
}

@Model final class SurveySessionRow {
    @Attribute(.unique) var sessionID: UUID; var workspaceID: UUID; var stateRawValue: String
    var revision: UInt64; var mutationID: UUID; var sessionSHA256: String; var canonicalData: Data
    init(_ value: SurveySessionV1) throws { try value.validateIntrinsic();sessionID=value.sessionID;workspaceID=value.workspaceID.rawValue;stateRawValue=value.state.rawValue;revision=value.revision;mutationID=value.mutationID.rawValue;sessionSHA256=value.sessionSHA256;canonicalData=try SurveySessionCanonicalCodecV1.encode(value);_ = try surveySessionDecoded(SurveySessionV1.self,data:canonicalData,expected:value) }
    func value() throws -> SurveySessionV1 { let v=try surveySessionDecoded(SurveySessionV1.self,data:canonicalData);try v.validateIntrinsic();guard v.sessionID==sessionID,v.workspaceID.rawValue==workspaceID,v.state.rawValue==stateRawValue,v.revision==revision,v.mutationID.rawValue==mutationID,v.sessionSHA256==sessionSHA256 else{throw SurveySessionPersistenceFailureV1.corruptRow};return v }
    func replace(with v:SurveySessionV1,publication:SurveyPublicationSnapshotV1?,expectedRevision:UInt64)throws{let old=try value();guard revision==expectedRevision else{throw SurveySessionPersistenceFailureV1.corruptRow};try v.validateSuccessor(of:old,publication:publication);stateRawValue=v.state.rawValue;revision=v.revision;mutationID=v.mutationID.rawValue;sessionSHA256=v.sessionSHA256;canonicalData=try SurveySessionCanonicalCodecV1.encode(v)}
}

@Model final class FactCaptureRow {
    @Attribute(.unique) var captureID:UUID;var workspaceID:UUID;var sessionID:UUID;var factID:String;var revision:UInt64;var mutationID:UUID;var captureSHA256:String;var canonicalData:Data
    init(_ v:FactCaptureV1)throws{try v.validateIntrinsic();captureID=v.captureID;workspaceID=v.workspaceID.rawValue;sessionID=v.sessionID;factID=v.factID;revision=v.revision;mutationID=v.mutationID.rawValue;captureSHA256=v.captureSHA256;canonicalData=try SurveySessionCanonicalCodecV1.encode(v);_ = try surveySessionDecoded(FactCaptureV1.self,data:canonicalData,expected:v)}
    func value()throws->FactCaptureV1{let v=try surveySessionDecoded(FactCaptureV1.self,data:canonicalData);try v.validateIntrinsic();guard v.captureID==captureID,v.workspaceID.rawValue==workspaceID,v.sessionID==sessionID,v.factID==factID,v.revision==revision,v.mutationID.rawValue==mutationID,v.captureSHA256==captureSHA256 else{throw SurveySessionPersistenceFailureV1.corruptRow};return v}
}

@Model final class ProvisionalSubjectRow {
    @Attribute(.unique) var provisionalSubjectID:UUID;var workspaceID:UUID;var siteID:UUID;var stateRawValue:String;var revision:UInt64;var mutationID:UUID;var subjectSHA256:String;var canonicalData:Data
    init(_ v:ProvisionalSubjectV1)throws{try v.validate();provisionalSubjectID=v.provisionalSubjectID;workspaceID=v.workspaceID.rawValue;siteID=v.siteID;stateRawValue=v.state.rawValue;revision=v.revision;mutationID=v.mutationID.rawValue;subjectSHA256=v.subjectSHA256;canonicalData=try SurveySessionCanonicalCodecV1.encode(v)}
    func value()throws->ProvisionalSubjectV1{let v=try surveySessionDecoded(ProvisionalSubjectV1.self,data:canonicalData);try v.validate();guard v.provisionalSubjectID==provisionalSubjectID,v.workspaceID.rawValue==workspaceID,v.siteID==siteID,v.state.rawValue==stateRawValue,v.revision==revision,v.mutationID.rawValue==mutationID,v.subjectSHA256==subjectSHA256 else{throw SurveySessionPersistenceFailureV1.corruptRow};return v}
    func replaceOrdinary(with v:ProvisionalSubjectV1,expectedRevision:UInt64)throws{let old=try value();let allowed=(old.state == .active && v.state == .active) || (old.state != .archived && v.state == .archived);guard allowed else{throw SurveySessionPersistenceFailureV1.corruptRow};try replaceScalars(with:v,expectedRevision:expectedRevision)}
    func replaceForPromotion(with v:ProvisionalSubjectV1,action:SubjectPromotionActionV1,expectedRevision:UInt64)throws{let old=try value(),expectedState:ProvisionalSubjectStateV1 = action == .promoteToAsset ? .promoted : (action == .reconcileAsAlias ? .reconciledAlias : .promotionReversed),sourceIsValid:Bool;switch action{case .promoteToAsset,.reconcileAsAlias:sourceIsValid=old.state == .active || old.state == .promotionReversed;case .reverse:sourceIsValid=old.state == .promoted || old.state == .reconciledAlias};guard sourceIsValid,v.state == expectedState else{throw SurveySessionPersistenceFailureV1.corruptRow};try replaceScalars(with:v,expectedRevision:expectedRevision)}
    private func replaceScalars(with v:ProvisionalSubjectV1,expectedRevision:UInt64)throws{let old=try value();try v.validate();guard old.provisionalSubjectID==v.provisionalSubjectID,old.workspaceID==v.workspaceID,old.siteID==v.siteID,old.revision==expectedRevision,old.revision<UInt64.max,v.revision==old.revision+1,v.supersedesSubjectSHA256==old.subjectSHA256,v.mutationID != old.mutationID else{throw SurveySessionPersistenceFailureV1.corruptRow};stateRawValue=v.state.rawValue;revision=v.revision;mutationID=v.mutationID.rawValue;subjectSHA256=v.subjectSHA256;canonicalData=try SurveySessionCanonicalCodecV1.encode(v)}
}

@Model final class SubjectPromotionReceiptRow {
    @Attribute(.unique) var receiptID:UUID;var workspaceID:UUID;var provisionalSubjectID:UUID;var revision:UInt64;var mutationID:UUID;var receiptSHA256:String;var canonicalData:Data
    init(_ v:SubjectPromotionReceiptV1)throws{try v.validateIntrinsic();receiptID=v.receiptID;workspaceID=v.workspaceID.rawValue;provisionalSubjectID=v.provisionalSubject.provisionalSubjectID;revision=v.revision;mutationID=v.mutationID.rawValue;receiptSHA256=v.receiptSHA256;canonicalData=try SurveySessionCanonicalCodecV1.encode(v);_ = try surveySessionDecoded(SubjectPromotionReceiptV1.self,data:canonicalData,expected:v)}
    func value()throws->SubjectPromotionReceiptV1{let v=try surveySessionDecoded(SubjectPromotionReceiptV1.self,data:canonicalData);try v.validateIntrinsic();guard v.receiptID==receiptID,v.workspaceID.rawValue==workspaceID,v.provisionalSubject.provisionalSubjectID==provisionalSubjectID,v.revision==revision,v.mutationID.rawValue==mutationID,v.receiptSHA256==receiptSHA256 else{throw SurveySessionPersistenceFailureV1.corruptRow};return v}
}

@Model final class SurveyPublicationSnapshotRow {
    @Attribute(.unique) var snapshotID:UUID;var workspaceID:UUID;var sessionID:UUID;var revision:UInt64;var mutationID:UUID;var snapshotSHA256:String;var canonicalData:Data
    init(_ v:SurveyPublicationSnapshotV1)throws{try v.validateIntrinsic();snapshotID=v.snapshotID;workspaceID=v.workspaceID.rawValue;sessionID=v.sessionID;revision=v.revision;mutationID=v.mutationID.rawValue;snapshotSHA256=v.snapshotSHA256;canonicalData=try SurveySessionCanonicalCodecV1.encode(v);_ = try surveySessionDecoded(SurveyPublicationSnapshotV1.self,data:canonicalData,expected:v)}
    func value()throws->SurveyPublicationSnapshotV1{let v=try surveySessionDecoded(SurveyPublicationSnapshotV1.self,data:canonicalData);try v.validateIntrinsic();guard v.snapshotID==snapshotID,v.workspaceID.rawValue==workspaceID,v.sessionID==sessionID,v.revision==revision,v.mutationID.rawValue==mutationID,v.snapshotSHA256==snapshotSHA256 else{throw SurveySessionPersistenceFailureV1.corruptRow};return v}
}

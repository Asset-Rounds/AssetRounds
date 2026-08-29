import Foundation

enum SurveySessionScheduleBoundaryV1 { static let dueProjectionMayCreateSession = false }

enum SurveySessionFailureV1: Error, Equatable {
    case invalidValue, invalidDigest, wrongWorkspace, wrongDefinition, invalidTransition
    case staleRevision, unresolvedConflict, incompleteSurvey, unsafePromotion, passFailClaimForbidden
}

enum SurveySessionStateV1: String, Codable, CaseIterable, Sendable {
    case draft = "DRAFT", paused = "PAUSED", reviewRequired = "REVIEW_REQUIRED"
    case completed = "COMPLETED", amended = "AMENDED", superseded = "SUPERSEDED"
    case archived = "ARCHIVED", deleted = "DELETED"
}

enum SurveySessionTransitionV1: String, Codable, CaseIterable, Sendable {
    case create = "CREATE", pause = "PAUSE", resume = "RESUME", submitForReview = "SUBMIT_FOR_REVIEW"
    case returnForAmendment = "RETURN_FOR_AMENDMENT", complete = "COMPLETE"
    case reopenAmendment = "REOPEN_AMENDMENT", supersede = "SUPERSEDE", archive = "ARCHIVE", delete = "DELETE"
}

enum SurveyPinnedRevisionKindV1: String, Codable, CaseIterable, Sendable {
    case workPlan = "WORK_PLAN", fieldReferenceBinding = "FIELD_REFERENCE_BINDING"
}

struct SurveyPinnedRevisionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let kind: SurveyPinnedRevisionKindV1
    let referenceID: UUID
    let revision: UInt64
    let semanticSHA256: String
    var stableKey: String { "\(kind.rawValue)|\(referenceID.uuidString)" }
    func validate() throws {
        guard referenceID != UUID.zero, revision > 0, MutationEnvelopeV1.isSHA256(semanticSHA256) else { throw SurveySessionFailureV1.invalidValue }
    }
}

struct SurveyPackageReleaseReferenceV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let packageReleaseID:String;let packageID:String;let packageContentVersion:Int;let packageSHA256:String;let workflowSHA256:String;let releaseState:InspectionPackageReleaseStateV1
    init(_ release:InspectionPackageReleaseV1)throws{try release.validate();guard release.state == .published else{throw SurveySessionFailureV1.wrongDefinition};schemaVersion=Self.schemaVersion;packageReleaseID=release.packageReleaseID;packageID=release.packageID;packageContentVersion=release.packageContentVersion;packageSHA256=release.packageSHA256;workflowSHA256=release.workflowSHA256;releaseState=release.state;try validate()}
    func validate()throws{guard schemaVersion==Self.schemaVersion,KernelCanonicalHashV1.validSHA256(packageReleaseID),WorkflowGrammarValidationV1.validID(packageID),packageContentVersion>0,KernelCanonicalHashV1.validSHA256(packageSHA256),KernelCanonicalHashV1.validSHA256(workflowSHA256),releaseState == .published else{throw SurveySessionFailureV1.invalidValue}}
    func validate(against release:InspectionPackageReleaseV1)throws{try validate();try release.validate();guard self == (try Self(release))else{throw SurveySessionFailureV1.wrongDefinition}}
}

struct SurveySessionAuthorityV1: Codable, Equatable, Sendable {
    let definitionRelease: SurveyDefinitionReleaseReferenceV1
    let packageRelease: SurveyPackageReleaseReferenceV1
    let claimsProfile: ClaimsProfileV1
    let claimsProfileSHA256: String
    let reportProjection: SurveyReportProjectionV1
    let reportProjectionSHA256: String
    let localizationReleaseSHA256: String
    let pinnedRevisions: [SurveyPinnedRevisionReferenceV1]
    let authoritySHA256: String

    init(definition: SurveyDefinitionReleaseV1, packageRelease: InspectionPackageReleaseV1, pinnedRevisions: [SurveyPinnedRevisionReferenceV1]) throws {
        try definition.validate()
        guard definition.activityKind == .survey, definition.ownerPackageID == packageRelease.packageID else { throw SurveySessionFailureV1.wrongDefinition }
        self.definitionRelease = try .init(definition)
        self.packageRelease = try .init(packageRelease)
        self.claimsProfile = definition.claimsProfile
        self.claimsProfileSHA256 = try WorkspaceMutationCanonicalV1.sha256(definition.claimsProfile)
        self.reportProjection = definition.reportProjection
        self.reportProjectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(definition.reportProjection)
        self.localizationReleaseSHA256 = definition.localizationReleaseSHA256
        self.pinnedRevisions = pinnedRevisions.sorted { $0.stableKey < $1.stableKey }
        authoritySHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(definitionRelease: self.definitionRelease, packageRelease: self.packageRelease, claimsProfile: definition.claimsProfile, claimsProfileSHA256: claimsProfileSHA256, reportProjection: definition.reportProjection, reportProjectionSHA256: reportProjectionSHA256, localizationReleaseSHA256: definition.localizationReleaseSHA256, pinnedRevisions: self.pinnedRevisions))
        try validate(definition: definition)
    }

    func validate(definition: SurveyDefinitionReleaseV1) throws {
        try definition.validate(); try definitionRelease.validate(); try packageRelease.validate(); try claimsProfile.validate(); try reportProjection.validate(); try pinnedRevisions.forEach { try $0.validate() }
        let keys = pinnedRevisions.map(\.stableKey)
        guard definition.activityKind == .survey, definitionRelease == (try SurveyDefinitionReleaseReferenceV1(definition)), packageRelease.packageID == definition.ownerPackageID, claimsProfile == definition.claimsProfile, reportProjection == definition.reportProjection, localizationReleaseSHA256 == definition.localizationReleaseSHA256, claimsProfileSHA256 == (try WorkspaceMutationCanonicalV1.sha256(claimsProfile)), reportProjectionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(reportProjection)), keys == keys.sorted(), Set(keys).count == keys.count, authoritySHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else { throw SurveySessionFailureV1.invalidDigest }
    }
    func validate(definition:SurveyDefinitionReleaseV1,packageRelease:InspectionPackageReleaseV1)throws{try validate(definition:definition);try self.packageRelease.validate(against:packageRelease)}
    private var basis: Basis { .init(definitionRelease: definitionRelease, packageRelease: packageRelease, claimsProfile: claimsProfile, claimsProfileSHA256: claimsProfileSHA256, reportProjection: reportProjection, reportProjectionSHA256: reportProjectionSHA256, localizationReleaseSHA256: localizationReleaseSHA256, pinnedRevisions: pinnedRevisions) }
    private struct Basis: Codable { let definitionRelease: SurveyDefinitionReleaseReferenceV1; let packageRelease: SurveyPackageReleaseReferenceV1; let claimsProfile: ClaimsProfileV1; let claimsProfileSHA256: String; let reportProjection: SurveyReportProjectionV1; let reportProjectionSHA256: String; let localizationReleaseSHA256: String; let pinnedRevisions: [SurveyPinnedRevisionReferenceV1] }
}

struct ProvisionalSubjectReferenceV1: Codable, Equatable, Hashable, Sendable {
    let provisionalSubjectID: UUID; let revision: UInt64; let subjectSHA256: String
    func validate() throws { guard provisionalSubjectID != UUID.zero, revision > 0, MutationEnvelopeV1.isSHA256(subjectSHA256) else { throw SurveySessionFailureV1.invalidValue } }
}

enum SurveySessionSubjectV1: Codable, Equatable, Hashable, Sendable {
    case canonical(WorkSubjectReferenceV1), provisional(ProvisionalSubjectReferenceV1)
    func validate() throws { switch self { case .canonical(let value): try value.validate(); case .provisional(let value): try value.validate() } }
}

struct SurveyPublicationReferenceV1: Codable, Equatable, Hashable, Sendable {
    let snapshotID: UUID; let revision: UInt64; let snapshotSHA256: String
    func validate() throws { guard snapshotID != UUID.zero, revision > 0, MutationEnvelopeV1.isSHA256(snapshotSHA256) else { throw SurveySessionFailureV1.invalidValue } }
}

struct SurveySessionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let sessionID: UUID; let workspaceID: WorkspaceID; let authority: SurveySessionAuthorityV1
    let activityKind: ActivityKindV1; let subject: SurveySessionSubjectV1; let state: SurveySessionStateV1
    let transition: SurveySessionTransitionV1; let latestPublication: SurveyPublicationReferenceV1?
    let startedBy: ActorSnapshotV1; let lastTransitionBy: ActorSnapshotV1; let startedAt: Date; let transitionedAt: Date
    let predecessorSessionSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let sessionSHA256: String

    init(sessionID: UUID, workspaceID: WorkspaceID, authority: SurveySessionAuthorityV1, subject: SurveySessionSubjectV1, state: SurveySessionStateV1, transition: SurveySessionTransitionV1, latestPublication: SurveyPublicationReferenceV1? = nil, startedBy: ActorSnapshotV1, lastTransitionBy: ActorSnapshotV1, startedAt: Date, transitionedAt: Date, predecessorSessionSHA256: String? = nil, revision: UInt64, mutationID: MutationIDV1) throws {
        schemaVersion=Self.schemaVersion; self.sessionID=sessionID; self.workspaceID=workspaceID; self.authority=authority; activityKind = .survey; self.subject=subject; self.state=state; self.transition=transition; self.latestPublication=latestPublication; self.startedBy=startedBy; self.lastTransitionBy=lastTransitionBy; self.startedAt=startedAt; self.transitionedAt=transitionedAt; self.predecessorSessionSHA256=predecessorSessionSHA256; self.revision=revision; self.mutationID=mutationID
        sessionSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,sessionID:sessionID,workspaceID:workspaceID,authority:authority,activityKind:.survey,subject:subject,state:state,transition:transition,latestPublication:latestPublication,startedBy:startedBy,lastTransitionBy:lastTransitionBy,startedAt:startedAt,transitionedAt:transitionedAt,predecessorSessionSHA256:predecessorSessionSHA256,revision:revision,mutationID:mutationID)); try validateIntrinsic()
    }
    func validate(definition: SurveyDefinitionReleaseV1) throws { try validateIntrinsic(); try authority.validate(definition: definition); guard definition.workspaceID == workspaceID else { throw SurveySessionFailureV1.wrongWorkspace } }
    func validateSuccessor(of old: Self, publication: SurveyPublicationSnapshotV1? = nil) throws {
        try old.validateIntrinsic(); try validateIntrinsic(); let expected = Self.allowed(old.state, state, transition)
        guard sessionID == old.sessionID, workspaceID == old.workspaceID, authority == old.authority, activityKind == .survey, subject == old.subject, startedBy == old.startedBy, startedAt == old.startedAt, predecessorSessionSHA256 == old.sessionSHA256, old.revision < UInt64.max, revision == old.revision + 1, mutationID != old.mutationID, expected else { throw SurveySessionFailureV1.invalidTransition }
        if transition == .complete { guard let publication, latestPublication == publication.reference, publication.sessionID == sessionID, publication.sessionRevision == revision else { throw SurveySessionFailureV1.invalidTransition } }
    }
    func validateIntrinsic() throws { try subject.validate(); try startedBy.validate(); try lastTransitionBy.validate(); try latestPublication?.validate(); guard schemaVersion == Self.schemaVersion, sessionID != UUID.zero, activityKind == .survey, startedBy.workspaceID == workspaceID, lastTransitionBy.workspaceID == workspaceID, startedAt.isFiniteSurveyDate, transitionedAt.isFiniteSurveyDate, transitionedAt >= startedAt, revision > 0, (revision == 1) == (transition == .create && predecessorSessionSHA256 == nil && state == .draft), predecessorSessionSHA256.map(MutationEnvelopeV1.isSHA256) ?? true, sessionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else { throw SurveySessionFailureV1.invalidDigest } }
    private static func allowed(_ from: SurveySessionStateV1, _ to: SurveySessionStateV1, _ action: SurveySessionTransitionV1) -> Bool { switch (from,to,action) { case (.draft,.paused,.pause),(.paused,.draft,.resume),(.draft,.reviewRequired,.submitForReview),(.amended,.reviewRequired,.submitForReview),(.reviewRequired,.amended,.returnForAmendment),(.reviewRequired,.completed,.complete),(.completed,.amended,.reopenAmendment),(.completed,.superseded,.supersede),(.completed,.archived,.archive),(.superseded,.archived,.archive): return true; case (_, .deleted, .delete): return from != .deleted; default:return false } }
    private var basis:Basis{.init(schemaVersion:schemaVersion,sessionID:sessionID,workspaceID:workspaceID,authority:authority,activityKind:activityKind,subject:subject,state:state,transition:transition,latestPublication:latestPublication,startedBy:startedBy,lastTransitionBy:lastTransitionBy,startedAt:startedAt,transitionedAt:transitionedAt,predecessorSessionSHA256:predecessorSessionSHA256,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let sessionID:UUID;let workspaceID:WorkspaceID;let authority:SurveySessionAuthorityV1;let activityKind:ActivityKindV1;let subject:SurveySessionSubjectV1;let state:SurveySessionStateV1;let transition:SurveySessionTransitionV1;let latestPublication:SurveyPublicationReferenceV1?;let startedBy,lastTransitionBy:ActorSnapshotV1;let startedAt,transitionedAt:Date;let predecessorSessionSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct SurveyRepeatCoordinateV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let groupFactID: String; let occurrenceID: UUID; let ordinal: Int
    static func <(l:Self,r:Self)->Bool{l.stableKey<r.stableKey}; var stableKey:String{"\(groupFactID)|\(ordinal)|\(occurrenceID.uuidString)"}
    func validate()throws{guard SurveyDefinitionLimitsV1.token(groupFactID),occurrenceID != UUID.zero,ordinal>=0 else{throw SurveySessionFailureV1.invalidValue}}
}
struct FactCaptureReferenceV1:Codable,Equatable,Hashable,Sendable{let captureID:UUID;let revision:UInt64;let captureSHA256:String;func validate()throws{guard captureID != UUID.zero,revision>0,MutationEnvelopeV1.isSHA256(captureSHA256)else{throw SurveySessionFailureV1.invalidValue}}}
enum FactCaptureActionV1:String,Codable,CaseIterable,Sendable{case record="RECORD",correct="CORRECT",retract="RETRACT",resolveConflict="RESOLVE_CONFLICT"}

struct FactCaptureV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let captureID:UUID;let workspaceID:WorkspaceID;let sessionID:UUID;let definitionRelease:SurveyDefinitionReleaseReferenceV1;let factID:String;let repeatCoordinates:[SurveyRepeatCoordinateV1];let action:FactCaptureActionV1;let value:ResponseValueV1?;let evidence:[ContentReferenceV1];let predecessors:[FactCaptureReferenceV1];let capturedBy:ActorSnapshotV1;let capturedAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let captureSHA256:String
    init(captureID:UUID,workspaceID:WorkspaceID,sessionID:UUID,definitionRelease:SurveyDefinitionReleaseReferenceV1,factID:String,repeatCoordinates:[SurveyRepeatCoordinateV1]=[],action:FactCaptureActionV1,value:ResponseValueV1?,evidence:[ContentReferenceV1]=[],predecessors:[FactCaptureReferenceV1]=[],capturedBy:ActorSnapshotV1,capturedAt:Date,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.captureID=captureID;self.workspaceID=workspaceID;self.sessionID=sessionID;self.definitionRelease=definitionRelease;self.factID=factID;self.repeatCoordinates=repeatCoordinates.sorted();self.action=action;self.value=value;self.evidence=evidence.sorted{$0.contentID<$1.contentID};self.predecessors=predecessors.sorted{$0.captureID.uuidString<$1.captureID.uuidString};self.capturedBy=capturedBy;self.capturedAt=capturedAt;self.revision=revision;self.mutationID=mutationID;captureSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,captureID:captureID,workspaceID:workspaceID,sessionID:sessionID,definitionRelease:definitionRelease,factID:factID,repeatCoordinates:self.repeatCoordinates,action:action,value:value,evidence:self.evidence,predecessors:self.predecessors,capturedBy:capturedBy,capturedAt:capturedAt,revision:revision,mutationID:mutationID));try validateIntrinsic()}
    func validate(session:SurveySessionV1,definition:SurveyDefinitionReleaseV1)throws{try validateIntrinsic();try session.validate(definition:definition);guard workspaceID==session.workspaceID,sessionID==session.sessionID else{throw SurveySessionFailureV1.wrongWorkspace};guard definitionRelease==session.authority.definitionRelease,let field=definition.sections.flatMap(\.facts).first(where:{$0.factID==factID}),action == .retract || (value.map{SurveyDefinitionStaticValidationV1.response($0,isCompatibleWith:field)} == true) else{throw SurveySessionFailureV1.wrongDefinition}}
    func validateSuccessor(of prior:[Self],session:SurveySessionV1,definition:SurveyDefinitionReleaseV1)throws{try validate(session:session,definition:definition);try prior.forEach{$0.validate(session:session,definition:definition)};let refs=try prior.map(\.reference).sorted{$0.captureID.uuidString<$1.captureID.uuidString};guard predecessors==refs,!prior.isEmpty,prior.allSatisfy({$0.factID==factID&&$0.repeatCoordinates==repeatCoordinates}),revision==(prior.map(\.revision).max() ?? 0)+1,action == .resolveConflict ? prior.count>1:prior.count==1 else{throw SurveySessionFailureV1.unresolvedConflict}}
    var reference:FactCaptureReferenceV1{get throws{let value=FactCaptureReferenceV1(captureID:captureID,revision:revision,captureSHA256:captureSHA256);try value.validate();return value}}
    func validateIntrinsic()throws{try definitionRelease.validate();try repeatCoordinates.forEach{$0.validate()};try predecessors.forEach{$0.validate()};try value?.validate();try capturedBy.validate();let coordinateKeys=repeatCoordinates.map(\.stableKey),predecessorIDs=predecessors.map(\.captureID),evidenceIDs=evidence.map(\.contentID);guard schemaVersion==Self.schemaVersion,captureID != UUID.zero,sessionID != UUID.zero,SurveyDefinitionLimitsV1.token(factID),coordinateKeys==coordinateKeys.sorted(),Set(coordinateKeys).count==coordinateKeys.count,Set(predecessorIDs).count==predecessorIDs.count,Set(evidenceIDs).count==evidenceIDs.count,capturedBy.workspaceID==workspaceID,capturedAt.isFiniteSurveyDate,revision>0,(action == .record)==predecessors.isEmpty,(action == .retract)==(value==nil),action != .retract || evidence.isEmpty,action != .resolveConflict || predecessors.count>1,captureSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveySessionFailureV1.invalidDigest}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,captureID:captureID,workspaceID:workspaceID,sessionID:sessionID,definitionRelease:definitionRelease,factID:factID,repeatCoordinates:repeatCoordinates,action:action,value:value,evidence:evidence,predecessors:predecessors,capturedBy:capturedBy,capturedAt:capturedAt,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let captureID:UUID;let workspaceID:WorkspaceID;let sessionID:UUID;let definitionRelease:SurveyDefinitionReleaseReferenceV1;let factID:String;let repeatCoordinates:[SurveyRepeatCoordinateV1];let action:FactCaptureActionV1;let value:ResponseValueV1?;let evidence:[ContentReferenceV1];let predecessors:[FactCaptureReferenceV1];let capturedBy:ActorSnapshotV1;let capturedAt:Date;let revision:UInt64;let mutationID:MutationIDV1}
}

enum ProvisionalSubjectStateV1:String,Codable,CaseIterable,Sendable{case active="ACTIVE",promoted="PROMOTED",reconciledAlias="RECONCILED_ALIAS",promotionReversed="PROMOTION_REVERSED",archived="ARCHIVED"}
struct ProvisionalSubjectV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let provisionalSubjectID:UUID;let workspaceID:WorkspaceID;let siteID:UUID;let localLabel:String;let proposedSubjectKind:WorkSubjectKindV1?;let state:ProvisionalSubjectStateV1;let createdBy:ActorSnapshotV1;let createdAt:Date;let supersedesSubjectSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let subjectSHA256:String
    init(provisionalSubjectID:UUID,workspaceID:WorkspaceID,siteID:UUID,localLabel:String,proposedSubjectKind:WorkSubjectKindV1?,state:ProvisionalSubjectStateV1,createdBy:ActorSnapshotV1,createdAt:Date,supersedesSubjectSHA256:String?=nil,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.provisionalSubjectID=provisionalSubjectID;self.workspaceID=workspaceID;self.siteID=siteID;self.localLabel=localLabel;self.proposedSubjectKind=proposedSubjectKind;self.state=state;self.createdBy=createdBy;self.createdAt=createdAt;self.supersedesSubjectSHA256=supersedesSubjectSHA256;self.revision=revision;self.mutationID=mutationID;subjectSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,provisionalSubjectID:provisionalSubjectID,workspaceID:workspaceID,siteID:siteID,localLabel:localLabel,proposedSubjectKind:proposedSubjectKind,state:state,createdBy:createdBy,createdAt:createdAt,supersedesSubjectSHA256:supersedesSubjectSHA256,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try createdBy.validate();guard schemaVersion==Self.schemaVersion,provisionalSubjectID != UUID.zero,siteID != UUID.zero,!localLabel.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,localLabel.utf8.count<=256,createdBy.workspaceID==workspaceID,createdAt.isFiniteSurveyDate,revision>0,(revision==1)==(supersedesSubjectSHA256==nil),supersedesSubjectSHA256.map(MutationEnvelopeV1.isSHA256) ?? true,subjectSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveySessionFailureV1.invalidDigest}}
    var reference:ProvisionalSubjectReferenceV1{.init(provisionalSubjectID:provisionalSubjectID,revision:revision,subjectSHA256:subjectSHA256)};private var basis:Basis{.init(schemaVersion:schemaVersion,provisionalSubjectID:provisionalSubjectID,workspaceID:workspaceID,siteID:siteID,localLabel:localLabel,proposedSubjectKind:proposedSubjectKind,state:state,createdBy:createdBy,createdAt:createdAt,supersedesSubjectSHA256:supersedesSubjectSHA256,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let provisionalSubjectID:UUID;let workspaceID:WorkspaceID;let siteID:UUID;let localLabel:String;let proposedSubjectKind:WorkSubjectKindV1?;let state:ProvisionalSubjectStateV1;let createdBy:ActorSnapshotV1;let createdAt:Date;let supersedesSubjectSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1}}

enum SubjectPromotionActionV1:String,Codable,CaseIterable,Sendable{case promoteToAsset="PROMOTE_TO_ASSET",reconcileAsAlias="RECONCILE_AS_ALIAS",reverse="REVERSE"}
struct SubjectPromotionPreviewV1:Codable,Equatable,Sendable{let previewID:String;let workspaceID:WorkspaceID;let provisionalSubject:ProvisionalSubjectReferenceV1;let canonicalSubject:WorkSubjectReferenceV1;let action:SubjectPromotionActionV1;let affectedSessionIDs:[UUID];let safeToReverse:Bool;let generatedAt:Date;let previewSHA256:String
    init(workspaceID:WorkspaceID,provisionalSubject:ProvisionalSubjectReferenceV1,canonicalSubject:WorkSubjectReferenceV1,action:SubjectPromotionActionV1,affectedSessionIDs:[UUID],safeToReverse:Bool,generatedAt:Date)throws{self.workspaceID=workspaceID;self.provisionalSubject=provisionalSubject;self.canonicalSubject=canonicalSubject;self.action=action;self.affectedSessionIDs=affectedSessionIDs.sorted{$0.uuidString<$1.uuidString};self.safeToReverse=safeToReverse;self.generatedAt=generatedAt;previewSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID:workspaceID,provisionalSubject:provisionalSubject,canonicalSubject:canonicalSubject,action:action,affectedSessionIDs:self.affectedSessionIDs,safeToReverse:safeToReverse,generatedAt:generatedAt));previewID=previewSHA256;try validate()}
    func validate()throws{try provisionalSubject.validate();try canonicalSubject.validate();guard affectedSessionIDs==affectedSessionIDs.sorted(by:{$0.uuidString<$1.uuidString}),Set(affectedSessionIDs).count==affectedSessionIDs.count,generatedAt.isFiniteSurveyDate,previewID==previewSHA256,previewSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveySessionFailureV1.invalidDigest}}
    private var basis:Basis{.init(workspaceID:workspaceID,provisionalSubject:provisionalSubject,canonicalSubject:canonicalSubject,action:action,affectedSessionIDs:affectedSessionIDs,safeToReverse:safeToReverse,generatedAt:generatedAt)};private struct Basis:Codable{let workspaceID:WorkspaceID;let provisionalSubject:ProvisionalSubjectReferenceV1;let canonicalSubject:WorkSubjectReferenceV1;let action:SubjectPromotionActionV1;let affectedSessionIDs:[UUID];let safeToReverse:Bool;let generatedAt:Date}}

struct SubjectPromotionReceiptV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let provisionalSubject:ProvisionalSubjectReferenceV1;let canonicalSubject:WorkSubjectReferenceV1;let action:SubjectPromotionActionV1;let affectedSessionIDs:[UUID];let safeToReverse:Bool;let previewGeneratedAt:Date;let previewSHA256:String;let predecessorReceiptID:UUID?;let predecessorReceiptSHA256:String?;let actor:ActorSnapshotV1;let recordedAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let receiptSHA256:String
    init(receiptID:UUID,preview:SubjectPromotionPreviewV1,predecessor:Self?,actor:ActorSnapshotV1,recordedAt:Date,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.receiptID=receiptID;workspaceID=preview.workspaceID;provisionalSubject=preview.provisionalSubject;canonicalSubject=preview.canonicalSubject;action=preview.action;affectedSessionIDs=preview.affectedSessionIDs;safeToReverse=preview.safeToReverse;previewGeneratedAt=preview.generatedAt;previewSHA256=preview.previewSHA256;predecessorReceiptID=predecessor?.receiptID;predecessorReceiptSHA256=predecessor?.receiptSHA256;self.actor=actor;self.recordedAt=recordedAt;self.revision=revision;self.mutationID=mutationID;receiptSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,receiptID:receiptID,workspaceID:preview.workspaceID,provisionalSubject:preview.provisionalSubject,canonicalSubject:preview.canonicalSubject,action:preview.action,affectedSessionIDs:preview.affectedSessionIDs,safeToReverse:preview.safeToReverse,previewGeneratedAt:preview.generatedAt,previewSHA256:preview.previewSHA256,predecessorReceiptID:predecessor?.receiptID,predecessorReceiptSHA256:predecessor?.receiptSHA256,actor:actor,recordedAt:recordedAt,revision:revision,mutationID:mutationID));try validate(preview:preview,predecessor:predecessor)}
    var reconstructedPreview:SubjectPromotionPreviewV1{get throws{try .init(workspaceID:workspaceID,provisionalSubject:provisionalSubject,canonicalSubject:canonicalSubject,action:action,affectedSessionIDs:affectedSessionIDs,safeToReverse:safeToReverse,generatedAt:previewGeneratedAt)}}
    func validateIntrinsic()throws{let preview=try reconstructedPreview;try actor.validate();guard schemaVersion==Self.schemaVersion,receiptID != UUID.zero,previewSHA256==preview.previewSHA256,actor.workspaceID==workspaceID,recordedAt.isFiniteSurveyDate,revision>0,(revision==1)==(predecessorReceiptID==nil&&predecessorReceiptSHA256==nil),receiptSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveySessionFailureV1.unsafePromotion}}
    func validate(preview:SubjectPromotionPreviewV1,predecessor:Self?)throws{try validateIntrinsic();guard preview == (try reconstructedPreview),predecessorReceiptID==predecessor?.receiptID,predecessorReceiptSHA256==predecessor?.receiptSHA256,predecessor.map{$0.revision<UInt64.max&&revision==$0.revision+1&&$0.workspaceID==workspaceID&&$0.provisionalSubject.provisionalSubjectID==provisionalSubject.provisionalSubjectID} ?? (revision==1),action != .reverse || (predecessor != nil && safeToReverse)else{throw SurveySessionFailureV1.unsafePromotion}}
    func rebound(to workspaceID:WorkspaceID,provisionalSubject:ProvisionalSubjectReferenceV1,canonicalSubject:WorkSubjectReferenceV1,affectedSessionIDs:[UUID],actor:ActorSnapshotV1,predecessor:Self?)throws->Self{let preview=try SubjectPromotionPreviewV1(workspaceID:workspaceID,provisionalSubject:provisionalSubject,canonicalSubject:canonicalSubject,action:action,affectedSessionIDs:affectedSessionIDs,safeToReverse:safeToReverse,generatedAt:previewGeneratedAt);return try .init(receiptID:receiptID,preview:preview,predecessor:predecessor,actor:actor,recordedAt:recordedAt,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,receiptID:receiptID,workspaceID:workspaceID,provisionalSubject:provisionalSubject,canonicalSubject:canonicalSubject,action:action,affectedSessionIDs:affectedSessionIDs,safeToReverse:safeToReverse,previewGeneratedAt:previewGeneratedAt,previewSHA256:previewSHA256,predecessorReceiptID:predecessorReceiptID,predecessorReceiptSHA256:predecessorReceiptSHA256,actor:actor,recordedAt:recordedAt,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let provisionalSubject:ProvisionalSubjectReferenceV1;let canonicalSubject:WorkSubjectReferenceV1;let action:SubjectPromotionActionV1;let affectedSessionIDs:[UUID];let safeToReverse:Bool;let previewGeneratedAt:Date;let previewSHA256:String;let predecessorReceiptID:UUID?;let predecessorReceiptSHA256:String?;let actor:ActorSnapshotV1;let recordedAt:Date;let revision:UInt64;let mutationID:MutationIDV1}}

struct PublishedSurveyFactV1:Codable,Equatable,Sendable{let factID:String;let repeatCoordinates:[SurveyRepeatCoordinateV1];let value:ResponseValueV1;let evidence:[ContentReferenceV1];let sourceCapture:FactCaptureReferenceV1;var stableKey:String{"\(factID)|\(repeatCoordinates.map(\.stableKey).joined(separator:"/"))"}}
struct SurveyPublicationSnapshotV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let snapshotID:UUID;let workspaceID:WorkspaceID;let sessionID:UUID;let sessionRevision:UInt64;let authority:SurveySessionAuthorityV1;let subjectAtPublication:SurveySessionSubjectV1;let promotionReceiptsAtPublication:[SubjectPromotionReceiptV1];let facts:[PublishedSurveyFactV1];let satisfiedCompletionRuleIDs:[String];let publishedBy:ActorSnapshotV1;let publishedAt:Date;let supersedesSnapshotID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let snapshotSHA256:String
    init(snapshotID:UUID,session:SurveySessionV1,definition:SurveyDefinitionReleaseV1,currentCaptures:[FactCaptureV1],promotionReceipts:[SubjectPromotionReceiptV1],publishedBy:ActorSnapshotV1,publishedAt:Date,supersedesSnapshotID:UUID?=nil,revision:UInt64,mutationID:MutationIDV1)throws{try session.validate(definition:definition);guard session.state == .completed,session.transition == .complete else{throw SurveySessionFailureV1.invalidTransition};let projected=try SurveyPublicationProjectionV1.project(definition:definition,captures:currentCaptures);schemaVersion=Self.schemaVersion;self.snapshotID=snapshotID;workspaceID=session.workspaceID;sessionID=session.sessionID;sessionRevision=session.revision;authority=session.authority;subjectAtPublication=session.subject;promotionReceiptsAtPublication=promotionReceipts;facts=projected.facts;satisfiedCompletionRuleIDs=projected.ruleIDs;self.publishedBy=publishedBy;self.publishedAt=publishedAt;self.supersedesSnapshotID=supersedesSnapshotID;self.revision=revision;self.mutationID=mutationID;snapshotSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,snapshotID:snapshotID,workspaceID:session.workspaceID,sessionID:session.sessionID,sessionRevision:session.revision,authority:session.authority,subjectAtPublication:session.subject,promotionReceiptsAtPublication:promotionReceipts,facts:projected.facts,satisfiedCompletionRuleIDs:projected.ruleIDs,publishedBy:publishedBy,publishedAt:publishedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID));try validateIntrinsic()}
    var reference:SurveyPublicationReferenceV1{.init(snapshotID:snapshotID,revision:revision,snapshotSHA256:snapshotSHA256)}
    func validate(session:SurveySessionV1,definition:SurveyDefinitionReleaseV1,captures:[FactCaptureV1])throws{try validateIntrinsic();try session.validate(definition:definition);guard session.state == .completed,session.transition == .complete,session.latestPublication==reference else{throw SurveySessionFailureV1.invalidTransition};let p=try SurveyPublicationProjectionV1.project(definition:definition,captures:captures);guard workspaceID==session.workspaceID,sessionID==session.sessionID,sessionRevision==session.revision,authority==session.authority,subjectAtPublication==session.subject,facts==p.facts,satisfiedCompletionRuleIDs==p.ruleIDs else{throw SurveySessionFailureV1.incompleteSurvey}}
    func validateIntrinsic()throws{try subjectAtPublication.validate();try publishedBy.validate();try promotionReceiptsAtPublication.forEach{$0.validateIntrinsic()};let keys=facts.map(\.stableKey);guard schemaVersion==Self.schemaVersion,snapshotID != UUID.zero,sessionID != UUID.zero,sessionRevision>0,keys==keys.sorted(),Set(keys).count==keys.count,satisfiedCompletionRuleIDs==satisfiedCompletionRuleIDs.sorted(),Set(satisfiedCompletionRuleIDs).count==satisfiedCompletionRuleIDs.count,publishedBy.workspaceID==workspaceID,publishedAt.isFiniteSurveyDate,revision>0,(revision==1)==(supersedesSnapshotID==nil),snapshotSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw SurveySessionFailureV1.invalidDigest}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,snapshotID:snapshotID,workspaceID:workspaceID,sessionID:sessionID,sessionRevision:sessionRevision,authority:authority,subjectAtPublication:subjectAtPublication,promotionReceiptsAtPublication:promotionReceiptsAtPublication,facts:facts,satisfiedCompletionRuleIDs:satisfiedCompletionRuleIDs,publishedBy:publishedBy,publishedAt:publishedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let snapshotID:UUID;let workspaceID:WorkspaceID;let sessionID:UUID;let sessionRevision:UInt64;let authority:SurveySessionAuthorityV1;let subjectAtPublication:SurveySessionSubjectV1;let promotionReceiptsAtPublication:[SubjectPromotionReceiptV1];let facts:[PublishedSurveyFactV1];let satisfiedCompletionRuleIDs:[String];let publishedBy:ActorSnapshotV1;let publishedAt:Date;let supersedesSnapshotID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}}

private enum SurveyPublicationProjectionV1{
    static func project(definition:SurveyDefinitionReleaseV1,captures:[FactCaptureV1])throws->(facts:[PublishedSurveyFactV1],ruleIDs:[String]){
        try definition.validate()
        for capture in captures where capture.value != nil { try capture.validateIntrinsicForProjection(definition:definition) }
        let predecessorIDs=Set(captures.flatMap{$0.predecessors.map(\.captureID)})
        let heads=captures.filter{!predecessorIDs.contains($0.captureID)}
        let groups=Dictionary(grouping:heads){"\($0.factID)|\($0.repeatCoordinates.map(\.stableKey).joined(separator:"/"))"}
        guard groups.values.allSatisfy({$0.count==1})else{throw SurveySessionFailureV1.unresolvedConflict}
        let selected=groups.values.compactMap{$0[0]}.filter{$0.action != .retract}
        var values:[String:ResponseValueV1]=[:],facts:[PublishedSurveyFactV1]=[]
        for capture in selected{guard let value=capture.value else{continue};if capture.repeatCoordinates.isEmpty{values[capture.factID]=value};facts.append(.init(factID:capture.factID,repeatCoordinates:capture.repeatCoordinates,value:value,evidence:capture.evidence,sourceCapture:try capture.reference))}
        facts.sort{$0.stableKey<$1.stableKey}
        let definitions=definition.sections.flatMap(\.facts),visible=definitions.filter{visibility($0.visibility,values)},answered=Set(facts.map(\.factID))
        guard visible.filter(\.required).allSatisfy({answered.contains($0.factID)&&values[$0.factID] != .noValue})else{throw SurveySessionFailureV1.incompleteSurvey}
        let rules=definition.completionRules.filter{completion($0.expression,values:values,requiredVisible:visible.filter(\.required).map(\.factID))}.map(\.ruleID).sorted()
        guard rules.count==definition.completionRules.count else{throw SurveySessionFailureV1.incompleteSurvey}
        return(facts,rules)
    }
    private static func visibility(_ expression:SurveyVisibilityExpressionV1?,_ values:[String:ResponseValueV1])->Bool{guard let expression else{return true};switch expression{case .predicate(let p):return values[p.factID]==p.expectedValue;case .all(let a):return a.allSatisfy{visibility($0,values)};case .any(let a):return a.contains{visibility($0,values)};case .not(let x):return !visibility(x,values)}}
    private static func completion(_ expression:SurveyCompletionExpressionV1,values:[String:ResponseValueV1],requiredVisible:[String])->Bool{switch expression{case .allRequiredVisibleFactsAnswered:return requiredVisible.allSatisfy{values[$0] != nil&&values[$0] != .noValue};case .factPresent(let id):return values[id] != nil&&values[id] != .noValue;case .all(let a):return a.allSatisfy{completion($0,values:values,requiredVisible:requiredVisible)};case .any(let a):return a.contains{completion($0,values:values,requiredVisible:requiredVisible)}}}
}

private extension FactCaptureV1{func validateIntrinsicForProjection(definition:SurveyDefinitionReleaseV1)throws{guard let field=definition.sections.flatMap(\.facts).first(where:{$0.factID==factID}),let value,SurveyDefinitionStaticValidationV1.response(value,isCompatibleWith:field)else{throw SurveySessionFailureV1.wrongDefinition}}}
private extension Date{var isFiniteSurveyDate:Bool{timeIntervalSinceReferenceDate.isFinite}}

extension SurveySessionAuthorityV1 {
    func rebound(to definition:SurveyDefinitionReleaseV1,packageRelease:InspectionPackageReleaseV1)throws->Self{try .init(definition:definition,packageRelease:packageRelease,pinnedRevisions:pinnedRevisions)}
}
extension SurveySessionV1 {
    func rebound(to workspaceID:WorkspaceID,definition:SurveyDefinitionReleaseV1,packageRelease:InspectionPackageReleaseV1,subject:SurveySessionSubjectV1,startedBy:ActorSnapshotV1,lastTransitionBy:ActorSnapshotV1,predecessorSessionSHA256:String?,latestPublication:SurveyPublicationReferenceV1?)throws->Self{try .init(sessionID:sessionID,workspaceID:workspaceID,authority:authority.rebound(to:definition,packageRelease:packageRelease),subject:subject,state:state,transition:transition,latestPublication:latestPublication,startedBy:startedBy,lastTransitionBy:lastTransitionBy,startedAt:startedAt,transitionedAt:transitionedAt,predecessorSessionSHA256:predecessorSessionSHA256,revision:revision,mutationID:mutationID)}
}
extension FactCaptureV1 {
    func rebound(to workspaceID:WorkspaceID,definitionRelease:SurveyDefinitionReleaseReferenceV1,evidence:[ContentReferenceV1],predecessors:[FactCaptureReferenceV1],capturedBy:ActorSnapshotV1)throws->Self{try .init(captureID:captureID,workspaceID:workspaceID,sessionID:sessionID,definitionRelease:definitionRelease,factID:factID,repeatCoordinates:repeatCoordinates,action:action,value:value,evidence:evidence,predecessors:predecessors,capturedBy:capturedBy,capturedAt:capturedAt,revision:revision,mutationID:mutationID)}
}
extension ProvisionalSubjectV1 {
    func rebound(to workspaceID:WorkspaceID,siteID:UUID,createdBy:ActorSnapshotV1,supersedesSubjectSHA256:String?)throws->Self{try .init(provisionalSubjectID:provisionalSubjectID,workspaceID:workspaceID,siteID:siteID,localLabel:localLabel,proposedSubjectKind:proposedSubjectKind,state:state,createdBy:createdBy,createdAt:createdAt,supersedesSubjectSHA256:supersedesSubjectSHA256,revision:revision,mutationID:mutationID)}
}
extension SurveyPublicationSnapshotV1 {
    func rebound(to workspaceID:WorkspaceID,session:SurveySessionV1,definition:SurveyDefinitionReleaseV1,captures:[FactCaptureV1],promotionReceipts:[SubjectPromotionReceiptV1],publishedBy:ActorSnapshotV1)throws->Self{guard workspaceID==session.workspaceID else{throw SurveySessionFailureV1.wrongWorkspace};return try .init(snapshotID:snapshotID,session:session,definition:definition,currentCaptures:captures,promotionReceipts:promotionReceipts,publishedBy:publishedBy,publishedAt:publishedAt,supersedesSnapshotID:supersedesSnapshotID,revision:revision,mutationID:mutationID)}
}

struct SurveySessionLifecycleClosureV1:Codable,Equatable,Sendable{
    let definition:SurveyDefinitionReleaseV1;let sessions:[SurveySessionV1];let captures:[FactCaptureV1];let provisionalSubjects:[ProvisionalSubjectV1];let promotionReceipts:[SubjectPromotionReceiptV1];let publications:[SurveyPublicationSnapshotV1]
    init(definition:SurveyDefinitionReleaseV1,sessions:[SurveySessionV1],captures:[FactCaptureV1],provisionalSubjects:[ProvisionalSubjectV1],promotionReceipts:[SubjectPromotionReceiptV1],publications:[SurveyPublicationSnapshotV1])throws{self.definition=definition;self.sessions=sessions.sorted{$0.sessionID.uuidString<$1.sessionID.uuidString};self.captures=captures.sorted{$0.captureID.uuidString<$1.captureID.uuidString};self.provisionalSubjects=provisionalSubjects.sorted{$0.provisionalSubjectID.uuidString<$1.provisionalSubjectID.uuidString};self.promotionReceipts=promotionReceipts.sorted{$0.receiptID.uuidString<$1.receiptID.uuidString};self.publications=publications.sorted{$0.snapshotID.uuidString<$1.snapshotID.uuidString};try validate()}
    func validate()throws{try definition.validate();guard definition.activityKind == .survey,Set(sessions.map(\.sessionID)).count==sessions.count,Set(captures.map(\.captureID)).count==captures.count,Set(provisionalSubjects.map(\.provisionalSubjectID)).count==provisionalSubjects.count,Set(promotionReceipts.map(\.receiptID)).count==promotionReceipts.count,Set(publications.map(\.snapshotID)).count==publications.count else{throw SurveySessionFailureV1.passFailClaimForbidden};try sessions.forEach{$0.validate(definition:definition)};for capture in captures{guard let session=sessions.first(where:{$0.sessionID==capture.sessionID})else{throw SurveySessionFailureV1.invalidValue};try capture.validate(session:session,definition:definition);if !capture.predecessors.isEmpty{let prior=try capture.predecessors.map{reference in guard let value=captures.first(where:{$0.captureID==reference.captureID})else{throw SurveySessionFailureV1.invalidValue};guard try value.reference==reference else{throw SurveySessionFailureV1.invalidDigest};return value};try capture.validateSuccessor(of:prior,session:session,definition:definition)}};try provisionalSubjects.forEach{$0.validate()};for receipt in promotionReceipts{let predecessor=receipt.predecessorReceiptID.flatMap{id in promotionReceipts.first{$0.receiptID==id}};try receipt.validate(preview:receipt.reconstructedPreview,predecessor:predecessor)};let sessionIDs=Set(sessions.map(\.sessionID));guard promotionReceipts.allSatisfy({Set($0.affectedSessionIDs).isSubset(of:sessionIDs)})else{throw SurveySessionFailureV1.invalidValue};for publication in publications{guard let session=sessions.first(where:{$0.sessionID==publication.sessionID})else{throw SurveySessionFailureV1.invalidValue};try publication.validate(session:session,definition:definition,captures:captures.filter{$0.sessionID==session.sessionID})};try Self.validateDAG(captures.map{($0.captureID,$0.predecessors.map(\.captureID))});try Self.rejectForks(promotionReceipts.map{($0.receiptID,$0.predecessorReceiptID.map{[$0]} ?? [])})}
    private static func validateDAG(_ values:[(UUID,[UUID])])throws{let ids=Set(values.map(\.0)),parents=Dictionary(uniqueKeysWithValues:values);guard values.allSatisfy({$0.1.allSatisfy(ids.contains)})else{throw SurveySessionFailureV1.invalidValue};var visiting=Set<UUID>(),visited=Set<UUID>();func visit(_ id:UUID)throws{if visiting.contains(id){throw SurveySessionFailureV1.unresolvedConflict};if visited.contains(id){return};visiting.insert(id);for parent in parents[id] ?? []{try visit(parent)};visiting.remove(id);visited.insert(id)};for id in ids{try visit(id)}}
    private static func rejectForks(_ values:[(UUID,[UUID])])throws{let ids=Set(values.map(\.0));var childCounts:[UUID:Int]=[:];for (_,parents) in values{for parent in parents{guard ids.contains(parent)else{throw SurveySessionFailureV1.invalidValue};childCounts[parent,default:0]+=1}};guard childCounts.values.allSatisfy({$0<=1})else{throw SurveySessionFailureV1.unresolvedConflict}}
}

enum SurveySessionCanonicalCodecV1{static func encode<T:Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];e.dateEncodingStrategy = .millisecondsSince1970;return try e.encode(value)};static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{let d=JSONDecoder();d.dateDecodingStrategy = .millisecondsSince1970;let value=try d.decode(type,from:data);guard try encode(value)==data else{throw SurveySessionFailureV1.invalidDigest};return value}}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Workflow_SurveySessionContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Workflow_SurveySessionContractsV1_swift {
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

enum C30EvidenceContextSurveySessionBoundaryV1 {
    static let sessionContextBindingIsWorkspaceScoped = true
    static let pairedEvidenceIsReferenceOnly = true
    static let sessionCreatesNoInferredContext = true

    static func validate(context: EvidenceContextV1,
                         link: PairedObservationLinkV1? = nil,
                         workspaceID: WorkspaceID) throws {
        try C30EvidenceContextWorkflowBoundaryV1.validate(context: context, pairedLink: link)
        guard context.workspaceID == workspaceID,
              sessionContextBindingIsWorkspaceScoped, pairedEvidenceIsReferenceOnly,
              sessionCreatesNoInferredContext else { throw EvidenceContextFailureV1.wrongWorkspace }
    }
}

enum C31LightingSurveySessionBoundaryV1 {
    static let sessionReadsFrozenLightingReferences = true
    static let sessionDoesNotRewriteMeasurementOriginals = true
    static let derivedSessionViewsAreRebuildable = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        try C31LightingWorkflowBoundaryV1.validate(
            records: records,
            workspaceID: workspaceID
        )
        guard sessionReadsFrozenLightingReferences,
              sessionDoesNotRewriteMeasurementOriginals,
              derivedSessionViewsAreRebuildable else {
            throw LightingContractFailureV1.invalidValue
        }
    }
}
// MARK: - C32 assistance survey session boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Workflow_SurveySessionContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptedValueReusesFactCaptureValidation = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}


// MARK: - C33 temporal evidence survey binding

enum SurveyTemporalEvidenceBindingV1 {
    static func validate(
        clip: TemporalEvidenceClipV1,
        profile: TemporalEvidenceLimitProfileV1,
        session: SurveySessionV1,
        definition: SurveyDefinitionReleaseV1,
        existingClips: [TemporalEvidenceClipV1]
    ) throws {
        try session.validate(definition: definition); try clip.validate(profile: profile)
        try existingClips.forEach { try $0.validateIntrinsic() }
        let target = clip.target
        let requirementCount = existingClips.filter {
            $0.target.sessionID == target.sessionID
                && $0.target.factID == target.factID
                && $0.target.repeatCoordinates == target.repeatCoordinates
        }.count
        let sessionCount = existingClips.filter { $0.target.sessionID == target.sessionID }.count
        guard target.workspaceID == session.workspaceID,
              target.sessionID == session.sessionID,
              target.sessionRevision == session.revision,
              target.sessionSHA256 == session.sessionSHA256,
              target.definitionRelease == session.authority.definitionRelease,
              target.definitionRelease == (try SurveyDefinitionReleaseReferenceV1(definition)),
              requirementCount < profile.maximumClipsPerRequirement,
              sessionCount < profile.maximumClipsPerSession else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row125 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Workflow_SurveySessionContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

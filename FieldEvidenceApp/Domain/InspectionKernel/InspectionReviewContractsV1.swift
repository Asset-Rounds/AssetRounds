import Foundation

enum InspectionReviewFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion, invalidValue, invalidTransition, staleRevision
    case wrongWorkspace, digestMismatch, historyRewrite, missingEvidence
    case verifierRequired, assigneeRequired, unsupportedTimeZone, limitExceeded
}

enum InspectionReviewLimitsV1 {
    static let maximumTextBytes = 4_096
    static let maximumItems = 256
    static let maximumHistory = 4_096
}

private enum InspectionReviewValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) throws { guard value != zero else { throw InspectionReviewFailureV1.invalidValue } }
    static func workspace(_ value: WorkspaceID) throws { guard value.rawValue != zero else { throw InspectionReviewFailureV1.wrongWorkspace } }
    static func text(_ value: String) throws { guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines), value.utf8.count <= InspectionReviewLimitsV1.maximumTextBytes else { throw InspectionReviewFailureV1.invalidValue } }
    static func digest(_ value: String) throws { guard MutationEnvelopeV1.isSHA256(value) else { throw InspectionReviewFailureV1.digestMismatch } }
    static func instant(_ value: Date) throws { guard value.timeIntervalSinceReferenceDate.isFinite else { throw InspectionReviewFailureV1.invalidValue } }
    static func revision(_ value: UInt64) throws { guard value > 0 else { throw InspectionReviewFailureV1.invalidValue } }
    static func next(_ predecessor: UInt64, _ successor: UInt64) throws { let n = predecessor.addingReportingOverflow(1); guard !n.overflow, successor == n.partialValue else { throw InspectionReviewFailureV1.staleRevision } }
}

private enum InspectionReviewRebindV1 {
    static func actor(_ value: ActorSnapshotV1, to workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: value.actor.actorReferenceID, workspaceID: workspaceID,
            partyID: value.actor.partyID, displayName: value.actor.displayName
        )
        return try ActorSnapshotV1(
            snapshotID: value.snapshotID, workspaceID: workspaceID, actor: reference,
            responsibility: value.responsibility, displayNameAtTime: value.displayNameAtTime,
            capturedAt: value.capturedAt
        )
    }
}

enum InspectionReviewSubjectKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case completedActivitySnapshot = "COMPLETED_ACTIVITY_SNAPSHOT"
    case reportSnapshot = "REPORT_SNAPSHOT"
    case finding = "FINDING"
}

struct InspectionReviewSubjectReferenceV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID; let kind: InspectionReviewSubjectKindV1
    let subjectID: String; let subjectRevision: UInt64; let subjectSHA256: String
    let packageRelease: PackageReleaseIdentityV1?
    init(workspaceID: WorkspaceID, kind: InspectionReviewSubjectKindV1, subjectID: String,
         subjectRevision: UInt64, subjectSHA256: String, packageRelease: PackageReleaseIdentityV1? = nil) throws {
        self.workspaceID=workspaceID;self.kind=kind;self.subjectID=subjectID;self.subjectRevision=subjectRevision
        self.subjectSHA256=subjectSHA256;self.packageRelease=packageRelease;try validate()
    }
    func validate() throws { try InspectionReviewValidationV1.workspace(workspaceID);try InspectionReviewValidationV1.text(subjectID);try InspectionReviewValidationV1.revision(subjectRevision);try InspectionReviewValidationV1.digest(subjectSHA256) }
    func rebound(to workspaceID: WorkspaceID) throws -> Self { try .init(workspaceID: workspaceID,kind:kind,subjectID:subjectID,subjectRevision:subjectRevision,subjectSHA256:subjectSHA256,packageRelease:packageRelease) }
}

enum InspectionReviewStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case draft="DRAFT", fieldComplete="FIELD_COMPLETE", readyForReview="READY_FOR_REVIEW"
    case changesRequested="CHANGES_REQUESTED", accepted="ACCEPTED", finalized="FINALIZED"
    case amended="AMENDED", superseded="SUPERSEDED"
}

enum InspectionReviewTransitionTableV1 {
    static func permits(from: InspectionReviewStateV1, to: InspectionReviewStateV1,
                        hasExactSuccessorSubject: Bool = false) -> Bool {
        if to == .superseded { return from != .superseded && hasExactSuccessorSubject }
        switch (from,to) {
        case (.draft,.fieldComplete),(.fieldComplete,.readyForReview),(.readyForReview,.changesRequested),
             (.changesRequested,.readyForReview),(.readyForReview,.accepted),(.accepted,.finalized),
             (.finalized,.amended): return true
        default: return false
        }
    }
}

struct InspectionReviewTransitionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let transitionID:UUID;let reviewID:UUID;let workspaceID:WorkspaceID
    let subject:InspectionReviewSubjectReferenceV1;let fromState:InspectionReviewStateV1;let toState:InspectionReviewStateV1
    let actor:ActorSnapshotV1;let reason:String;let dispositionID:UUID?;let changeRequestIDs:[UUID]
    let successorReviewID:UUID?;let successorSubject:InspectionReviewSubjectReferenceV1?
    let occurredAt:Date;let recordedAt:Date;let predecessorTransitionID:UUID?;let revision:UInt64
    let mutationID:MutationIDV1;let transitionSHA256:String
    init(transitionID:UUID,reviewID:UUID,workspaceID:WorkspaceID,subject:InspectionReviewSubjectReferenceV1,
         fromState:InspectionReviewStateV1,toState:InspectionReviewStateV1,actor:ActorSnapshotV1,reason:String,
         dispositionID:UUID?=nil,changeRequestIDs:[UUID]=[],successorReviewID:UUID?=nil,
         successorSubject:InspectionReviewSubjectReferenceV1?=nil,occurredAt:Date,recordedAt:Date,
         predecessorTransitionID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1) throws {
        let requests=changeRequestIDs.sorted{$0.uuidString<$1.uuidString}
        schemaVersion=Self.schemaVersion;self.transitionID=transitionID;self.reviewID=reviewID;self.workspaceID=workspaceID
        self.subject=subject;self.fromState=fromState;self.toState=toState;self.actor=actor;self.reason=reason
        self.dispositionID=dispositionID;self.changeRequestIDs=requests;self.successorReviewID=successorReviewID
        self.successorSubject=successorSubject;self.occurredAt=occurredAt;self.recordedAt=recordedAt
        self.predecessorTransitionID=predecessorTransitionID;self.revision=revision;self.mutationID=mutationID
        transitionSHA256=try InspectionReviewCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,transitionID:transitionID,reviewID:reviewID,workspaceID:workspaceID,subject:subject,fromState:fromState,toState:toState,actor:actor,reason:reason,dispositionID:dispositionID,changeRequestIDs:requests,successorReviewID:successorReviewID,successorSubject:successorSubject,occurredAt:occurredAt,recordedAt:recordedAt,predecessorTransitionID:predecessorTransitionID,revision:revision,mutationID:mutationID));try validate()
    }
    func validate() throws {
        try [transitionID,reviewID].forEach(InspectionReviewValidationV1.id);try InspectionReviewValidationV1.workspace(workspaceID);try subject.validate();try actor.validate();try InspectionReviewValidationV1.text(reason);try InspectionReviewValidationV1.instant(occurredAt);try InspectionReviewValidationV1.instant(recordedAt);try InspectionReviewValidationV1.revision(revision)
        if let dispositionID{try InspectionReviewValidationV1.id(dispositionID)};if let successorReviewID{try InspectionReviewValidationV1.id(successorReviewID)};if let predecessorTransitionID{try InspectionReviewValidationV1.id(predecessorTransitionID)};try changeRequestIDs.forEach(InspectionReviewValidationV1.id);try successorSubject?.validate()
        let successorShape=(successorReviewID==nil)==(successorSubject==nil)
        let requiredResponsibility:ResponsibilityKindV1 = toState == .changesRequested || toState == .accepted ? .reviewedBy : .recordedBy
        guard schemaVersion==Self.schemaVersion,subject.workspaceID==workspaceID,actor.workspaceID==workspaceID,actor.responsibility == requiredResponsibility,
              recordedAt>=occurredAt,changeRequestIDs.count<=InspectionReviewLimitsV1.maximumItems,
              changeRequestIDs==changeRequestIDs.sorted(by:{$0.uuidString<$1.uuidString}),Set(changeRequestIDs).count==changeRequestIDs.count,
              (predecessorTransitionID==nil)==(revision==1),successorShape,
              InspectionReviewTransitionTableV1.permits(from:fromState,to:toState,hasExactSuccessorSubject:successorSubject != nil),
              toState != .changesRequested || (dispositionID != nil && !changeRequestIDs.isEmpty),
              toState != .accepted || dispositionID != nil,
              toState != .superseded || successorSubject?.workspaceID==workspaceID,
              transitionSHA256==(try InspectionReviewCanonicalCodecV1.sha256(basis)) else { throw InspectionReviewFailureV1.digestMismatch }
    }
    func validateSuccessor(of p:Self) throws { try p.validate();try validate();try InspectionReviewValidationV1.next(p.revision,revision);guard workspaceID==p.workspaceID,reviewID==p.reviewID,subject==p.subject,predecessorTransitionID==p.transitionID,fromState==p.toState,recordedAt>=p.recordedAt,mutationID != p.mutationID else{throw InspectionReviewFailureV1.historyRewrite} }
    func rebound(to workspaceID:WorkspaceID)throws->Self{try rebound(to:workspaceID,actor:InspectionReviewRebindV1.actor(actor,to:workspaceID))}
    func rebound(to workspaceID:WorkspaceID,actor:ActorSnapshotV1) throws->Self{try .init(transitionID:transitionID,reviewID:reviewID,workspaceID:workspaceID,subject:subject.rebound(to:workspaceID),fromState:fromState,toState:toState,actor:actor,reason:reason,dispositionID:dispositionID,changeRequestIDs:changeRequestIDs,successorReviewID:successorReviewID,successorSubject:try successorSubject?.rebound(to:workspaceID),occurredAt:occurredAt,recordedAt:recordedAt,predecessorTransitionID:predecessorTransitionID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,transitionID:transitionID,reviewID:reviewID,workspaceID:workspaceID,subject:subject,fromState:fromState,toState:toState,actor:actor,reason:reason,dispositionID:dispositionID,changeRequestIDs:changeRequestIDs,successorReviewID:successorReviewID,successorSubject:successorSubject,occurredAt:occurredAt,recordedAt:recordedAt,predecessorTransitionID:predecessorTransitionID,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let transitionID:UUID;let reviewID:UUID;let workspaceID:WorkspaceID;let subject:InspectionReviewSubjectReferenceV1;let fromState:InspectionReviewStateV1;let toState:InspectionReviewStateV1;let actor:ActorSnapshotV1;let reason:String;let dispositionID:UUID?;let changeRequestIDs:[UUID];let successorReviewID:UUID?;let successorSubject:InspectionReviewSubjectReferenceV1?;let occurredAt:Date;let recordedAt:Date;let predecessorTransitionID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

enum ReviewDispositionKindV1:String,CaseIterable,Codable,Hashable,Sendable{case changesRequested="CHANGES_REQUESTED",accepted="ACCEPTED"}
struct ReviewDispositionV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let dispositionID:UUID;let reviewID:UUID;let workspaceID:WorkspaceID
    let subject:InspectionReviewSubjectReferenceV1;let reviewRevision:UInt64;let kind:ReviewDispositionKindV1
    let reviewer:ActorSnapshotV1;let reason:String;let changeRequestIDs:[UUID];let assuranceManifestID:UUID?
    let assuranceManifestRevision:UInt64?;let assuranceManifestSHA256:String?;let recordedAt:Date
    let supersedesDispositionID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let dispositionSHA256:String
    init(dispositionID:UUID,reviewID:UUID,workspaceID:WorkspaceID,subject:InspectionReviewSubjectReferenceV1,
         reviewRevision:UInt64,kind:ReviewDispositionKindV1,reviewer:ActorSnapshotV1,reason:String,
         changeRequestIDs:[UUID]=[],assuranceManifestID:UUID?=nil,assuranceManifestRevision:UInt64?=nil,
         assuranceManifestSHA256:String?=nil,recordedAt:Date,supersedesDispositionID:UUID?=nil,
         revision:UInt64=1,mutationID:MutationIDV1)throws{
        let requests=changeRequestIDs.sorted{$0.uuidString<$1.uuidString};schemaVersion=Self.schemaVersion
        self.dispositionID=dispositionID;self.reviewID=reviewID;self.workspaceID=workspaceID;self.subject=subject
        self.reviewRevision=reviewRevision;self.kind=kind;self.reviewer=reviewer;self.reason=reason;self.changeRequestIDs=requests
        self.assuranceManifestID=assuranceManifestID;self.assuranceManifestRevision=assuranceManifestRevision
        self.assuranceManifestSHA256=assuranceManifestSHA256;self.recordedAt=recordedAt;self.supersedesDispositionID=supersedesDispositionID
        self.revision=revision;self.mutationID=mutationID
        dispositionSHA256=try InspectionReviewCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,dispositionID:dispositionID,reviewID:reviewID,workspaceID:workspaceID,subject:subject,reviewRevision:reviewRevision,kind:kind,reviewer:reviewer,reason:reason,changeRequestIDs:requests,assuranceManifestID:assuranceManifestID,assuranceManifestRevision:assuranceManifestRevision,assuranceManifestSHA256:assuranceManifestSHA256,recordedAt:recordedAt,supersedesDispositionID:supersedesDispositionID,revision:revision,mutationID:mutationID));try validate()
    }
    func validate()throws{try [dispositionID,reviewID].forEach(InspectionReviewValidationV1.id);try InspectionReviewValidationV1.workspace(workspaceID);try subject.validate();try InspectionReviewValidationV1.revision(reviewRevision);try reviewer.validate();try InspectionReviewValidationV1.text(reason);try InspectionReviewValidationV1.instant(recordedAt);try InspectionReviewValidationV1.revision(revision);try changeRequestIDs.forEach(InspectionReviewValidationV1.id);if let supersedesDispositionID{try InspectionReviewValidationV1.id(supersedesDispositionID)}
        let manifestComplete=assuranceManifestID != nil && assuranceManifestRevision != nil && assuranceManifestSHA256 != nil
        let manifestEmpty=assuranceManifestID==nil && assuranceManifestRevision==nil && assuranceManifestSHA256==nil
        if let assuranceManifestID{try InspectionReviewValidationV1.id(assuranceManifestID)};if let assuranceManifestRevision{try InspectionReviewValidationV1.revision(assuranceManifestRevision)};if let assuranceManifestSHA256{try InspectionReviewValidationV1.digest(assuranceManifestSHA256)}
        guard schemaVersion==Self.schemaVersion,subject.workspaceID==workspaceID,reviewer.workspaceID==workspaceID,reviewer.responsibility == .reviewedBy,
              changeRequestIDs==changeRequestIDs.sorted(by:{$0.uuidString<$1.uuidString}),Set(changeRequestIDs).count==changeRequestIDs.count,
              (kind == .changesRequested ? !changeRequestIDs.isEmpty : changeRequestIDs.isEmpty),manifestComplete || manifestEmpty,
              (supersedesDispositionID==nil)==(revision==1),dispositionSHA256==(try InspectionReviewCanonicalCodecV1.sha256(basis)) else{throw InspectionReviewFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();try InspectionReviewValidationV1.next(p.revision,revision);guard workspaceID==p.workspaceID,reviewID==p.reviewID,subject==p.subject,supersedesDispositionID==p.dispositionID,recordedAt>=p.recordedAt,mutationID != p.mutationID else{throw InspectionReviewFailureV1.historyRewrite}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try rebound(to:workspaceID,reviewer:InspectionReviewRebindV1.actor(reviewer,to:workspaceID))}
    func rebound(to workspaceID:WorkspaceID,reviewer:ActorSnapshotV1)throws->Self{try .init(dispositionID:dispositionID,reviewID:reviewID,workspaceID:workspaceID,subject:subject.rebound(to:workspaceID),reviewRevision:reviewRevision,kind:kind,reviewer:reviewer,reason:reason,changeRequestIDs:changeRequestIDs,assuranceManifestID:assuranceManifestID,assuranceManifestRevision:assuranceManifestRevision,assuranceManifestSHA256:assuranceManifestSHA256,recordedAt:recordedAt,supersedesDispositionID:supersedesDispositionID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,dispositionID:dispositionID,reviewID:reviewID,workspaceID:workspaceID,subject:subject,reviewRevision:reviewRevision,kind:kind,reviewer:reviewer,reason:reason,changeRequestIDs:changeRequestIDs,assuranceManifestID:assuranceManifestID,assuranceManifestRevision:assuranceManifestRevision,assuranceManifestSHA256:assuranceManifestSHA256,recordedAt:recordedAt,supersedesDispositionID:supersedesDispositionID,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let dispositionID:UUID;let reviewID:UUID;let workspaceID:WorkspaceID;let subject:InspectionReviewSubjectReferenceV1;let reviewRevision:UInt64;let kind:ReviewDispositionKindV1;let reviewer:ActorSnapshotV1;let reason:String;let changeRequestIDs:[UUID];let assuranceManifestID:UUID?;let assuranceManifestRevision:UInt64?;let assuranceManifestSHA256:String?;let recordedAt:Date;let supersedesDispositionID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

enum ChangeRequestItemKindV1:String,CaseIterable,Codable,Hashable,Sendable{case review="REVIEW",finding="FINDING",criterion="CRITERION",evidence="EVIDENCE",functionalRelationship="FUNCTIONAL_RELATIONSHIP"}
struct ChangeRequestItemReferenceV1:Codable,Equatable,Hashable,Sendable{let kind:ChangeRequestItemKindV1;let itemID:String;let itemRevision:UInt64;let itemSHA256:String;init(kind:ChangeRequestItemKindV1,itemID:String,itemRevision:UInt64,itemSHA256:String)throws{self.kind=kind;self.itemID=itemID;self.itemRevision=itemRevision;self.itemSHA256=itemSHA256;try validate()}func validate()throws{try InspectionReviewValidationV1.text(itemID);try InspectionReviewValidationV1.digest(itemSHA256)}}
enum ChangeRequestRequirementKindV1:String,CaseIterable,Codable,Hashable,Sendable{case recordedChange="RECORDED_CHANGE",additionalEvidence="ADDITIONAL_EVIDENCE"}
struct ChangeRequestRequirementV1:Codable,Equatable,Hashable,Comparable,Sendable{let requirementID:String;let kind:ChangeRequestRequirementKindV1;let description:String;init(requirementID:String,kind:ChangeRequestRequirementKindV1,description:String)throws{self.requirementID=requirementID;self.kind=kind;self.description=description;try InspectionReviewValidationV1.text(requirementID);try InspectionReviewValidationV1.text(description)}static func <(l:Self,r:Self)->Bool{l.requirementID<r.requirementID}}
enum ChangeRequestStateV1:String,CaseIterable,Codable,Hashable,Sendable{case open="OPEN",resolved="RESOLVED",withdrawn="WITHDRAWN",superseded="SUPERSEDED"}
enum ChangeRequestResolutionKindV1:String,CaseIterable,Codable,Hashable,Sendable{case fulfilled="FULFILLED",withdrawnWithReason="WITHDRAWN_WITH_REASON",superseded="SUPERSEDED"}
struct ChangeRequestResolutionV1:Codable,Equatable,Hashable,Sendable{let kind:ChangeRequestResolutionKindV1;let resolver:ActorSnapshotV1;let evidence:[ReviewEvidenceReferenceV1];let reason:String;let resolvedAt:Date;init(kind:ChangeRequestResolutionKindV1,resolver:ActorSnapshotV1,evidence:[ReviewEvidenceReferenceV1],reason:String,resolvedAt:Date)throws{self.kind=kind;self.resolver=resolver;self.evidence=evidence.sorted();self.reason=reason;self.resolvedAt=resolvedAt;try validate()}func validate()throws{try resolver.validate();try evidence.forEach{$0.validate()};try InspectionReviewValidationV1.text(reason);try InspectionReviewValidationV1.instant(resolvedAt);guard evidence==evidence.sorted(),Set(evidence).count==evidence.count,kind != .fulfilled || !evidence.isEmpty else{throw InspectionReviewFailureV1.missingEvidence}}}

enum ReviewEvidenceKindV1:String,CaseIterable,Codable,Hashable,Sendable{case claimEvidenceLink="CLAIM_EVIDENCE_LINK",verifiedRecheck="VERIFIED_RECHECK",completedActivitySnapshot="COMPLETED_ACTIVITY_SNAPSHOT",requirementEvaluation="REQUIREMENT_EVALUATION",functionalRelationshipSnapshot="FUNCTIONAL_RELATIONSHIP_SNAPSHOT",externalEvidenceReference="EXTERNAL_EVIDENCE_REFERENCE"}
struct ReviewEvidenceReferenceV1:Codable,Equatable,Hashable,Comparable,Sendable{let kind:ReviewEvidenceKindV1;let referenceID:String;let revision:UInt64;let sha256:String;init(kind:ReviewEvidenceKindV1,referenceID:String,revision:UInt64,sha256:String)throws{self.kind=kind;self.referenceID=referenceID;self.revision=revision;self.sha256=sha256;try validate()}func validate()throws{try InspectionReviewValidationV1.text(referenceID);try InspectionReviewValidationV1.revision(revision);try InspectionReviewValidationV1.digest(sha256)}static func <(l:Self,r:Self)->Bool{(l.kind.rawValue,l.referenceID,l.revision)<(r.kind.rawValue,r.referenceID,r.revision)}}

struct ChangeRequestV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let requestRevisionID:UUID;let requestID:UUID;let reviewID:UUID;let workspaceID:WorkspaceID;let reviewRevision:UInt64;let item:ChangeRequestItemReferenceV1;let reason:String;let requirements:[ChangeRequestRequirementV1];let requester:ActorSnapshotV1;let state:ChangeRequestStateV1;let resolution:ChangeRequestResolutionV1?;let recordedAt:Date;let supersedesRequestRevisionID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let requestSHA256:String
    init(requestRevisionID:UUID,requestID:UUID,reviewID:UUID,workspaceID:WorkspaceID,reviewRevision:UInt64,item:ChangeRequestItemReferenceV1,reason:String,requirements:[ChangeRequestRequirementV1],requester:ActorSnapshotV1,state:ChangeRequestStateV1,resolution:ChangeRequestResolutionV1?=nil,recordedAt:Date,supersedesRequestRevisionID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{let requirements=requirements.sorted();schemaVersion=Self.schemaVersion;self.requestRevisionID=requestRevisionID;self.requestID=requestID;self.reviewID=reviewID;self.workspaceID=workspaceID;self.reviewRevision=reviewRevision;self.item=item;self.reason=reason;self.requirements=requirements;self.requester=requester;self.state=state;self.resolution=resolution;self.recordedAt=recordedAt;self.supersedesRequestRevisionID=supersedesRequestRevisionID;self.revision=revision;self.mutationID=mutationID;requestSHA256=try InspectionReviewCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,requestRevisionID:requestRevisionID,requestID:requestID,reviewID:reviewID,workspaceID:workspaceID,reviewRevision:reviewRevision,item:item,reason:reason,requirements:requirements,requester:requester,state:state,resolution:resolution,recordedAt:recordedAt,supersedesRequestRevisionID:supersedesRequestRevisionID,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [requestRevisionID,requestID,reviewID].forEach(InspectionReviewValidationV1.id);try InspectionReviewValidationV1.workspace(workspaceID);try InspectionReviewValidationV1.revision(reviewRevision);try item.validate();try InspectionReviewValidationV1.text(reason);try requester.validate();try requirements.forEach{try InspectionReviewValidationV1.text($0.requirementID)};try resolution?.validate();try InspectionReviewValidationV1.instant(recordedAt);try InspectionReviewValidationV1.revision(revision);if let supersedesRequestRevisionID{try InspectionReviewValidationV1.id(supersedesRequestRevisionID)};let resolutionMatchesState=(state == .open && resolution == nil)||(state == .resolved && resolution?.kind == .fulfilled)||(state == .withdrawn && resolution?.kind == .withdrawnWithReason)||(state == .superseded && resolution?.kind == .superseded);guard schemaVersion==Self.schemaVersion,requester.workspaceID==workspaceID,requester.responsibility == .reviewedBy,!requirements.isEmpty,requirements.count<=InspectionReviewLimitsV1.maximumItems,requirements==requirements.sorted(),Set(requirements.map(\.requirementID)).count==requirements.count,resolutionMatchesState,(supersedesRequestRevisionID==nil)==(revision==1),(resolution?.resolver.workspaceID ?? workspaceID)==workspaceID,(resolution?.resolver.responsibility ?? .reviewedBy) == .reviewedBy,requestSHA256==(try InspectionReviewCanonicalCodecV1.sha256(basis))else{throw InspectionReviewFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();try InspectionReviewValidationV1.next(p.revision,revision);guard workspaceID==p.workspaceID,requestID==p.requestID,reviewID==p.reviewID,item==p.item,requirements==p.requirements,supersedesRequestRevisionID==p.requestRevisionID,p.state == .open,state != .open,recordedAt>=p.recordedAt,mutationID != p.mutationID else{throw InspectionReviewFailureV1.historyRewrite}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{let requester=try InspectionReviewRebindV1.actor(requester,to:workspaceID);let resolution=try resolution.map{try ChangeRequestResolutionV1(kind:$0.kind,resolver:InspectionReviewRebindV1.actor($0.resolver,to:workspaceID),evidence:$0.evidence,reason:$0.reason,resolvedAt:$0.resolvedAt)};return try .init(requestRevisionID:requestRevisionID,requestID:requestID,reviewID:reviewID,workspaceID:workspaceID,reviewRevision:reviewRevision,item:item,reason:reason,requirements:requirements,requester:requester,state:state,resolution:resolution,recordedAt:recordedAt,supersedesRequestRevisionID:supersedesRequestRevisionID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,requestRevisionID:requestRevisionID,requestID:requestID,reviewID:reviewID,workspaceID:workspaceID,reviewRevision:reviewRevision,item:item,reason:reason,requirements:requirements,requester:requester,state:state,resolution:resolution,recordedAt:recordedAt,supersedesRequestRevisionID:supersedesRequestRevisionID,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let requestRevisionID:UUID;let requestID:UUID;let reviewID:UUID;let workspaceID:WorkspaceID;let reviewRevision:UInt64;let item:ChangeRequestItemReferenceV1;let reason:String;let requirements:[ChangeRequestRequirementV1];let requester:ActorSnapshotV1;let state:ChangeRequestStateV1;let resolution:ChangeRequestResolutionV1?;let recordedAt:Date;let supersedesRequestRevisionID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

enum CorrectiveActionPriorityV1:String,CaseIterable,Codable,Hashable,Sendable{case urgent="URGENT",high="HIGH",normal="NORMAL",low="LOW"}
enum CorrectiveActionDueRuleKindV1:String,CaseIterable,Codable,Hashable,Sendable{case noDueDate="NO_DUE_DATE",elapsedSeconds="ELAPSED_SECONDS",calendarDaysAtLocalTime="CALENDAR_DAYS_AT_LOCAL_TIME"}
struct CorrectiveActionDueRuleV1:Codable,Equatable,Hashable,Sendable{let kind:CorrectiveActionDueRuleKindV1;let amount:UInt64?;let localHour:Int?;let localMinute:Int?;init(kind:CorrectiveActionDueRuleKindV1,amount:UInt64?=nil,localHour:Int?=nil,localMinute:Int?=nil)throws{self.kind=kind;self.amount=amount;self.localHour=localHour;self.localMinute=localMinute;try validate()}func validate()throws{switch kind{case .noDueDate:guard amount==nil,localHour==nil,localMinute==nil else{throw InspectionReviewFailureV1.invalidValue};case .elapsedSeconds:guard amount.map({$0>0})==true,localHour==nil,localMinute==nil else{throw InspectionReviewFailureV1.invalidValue};case .calendarDaysAtLocalTime:guard amount.map({$0>0 && $0<=36500})==true,(0...23).contains(localHour ?? -1),(0...59).contains(localMinute ?? -1)else{throw InspectionReviewFailureV1.invalidValue}}}}
struct CorrectiveActionPriorityRuleV1:Codable,Equatable,Hashable,Comparable,Sendable{let priority:CorrectiveActionPriorityV1;let dueRule:CorrectiveActionDueRuleV1;let graceSeconds:UInt64;init(priority:CorrectiveActionPriorityV1,dueRule:CorrectiveActionDueRuleV1,graceSeconds:UInt64=0)throws{self.priority=priority;self.dueRule=dueRule;self.graceSeconds=graceSeconds;try dueRule.validate()}static func <(l:Self,r:Self)->Bool{l.priority.rawValue<r.priority.rawValue}}
enum CorrectiveActionAssignmentRuleV1:String,CaseIterable,Codable,Hashable,Sendable{case prohibited="PROHIBITED",optional="OPTIONAL",required="REQUIRED"}
enum CorrectiveActionVerifierRuleV1:String,CaseIterable,Codable,Hashable,Sendable{case notRequired="NOT_REQUIRED",selfVerificationPermitted="SELF_VERIFICATION_PERMITTED",differentActorReferenceRequired="DIFFERENT_ACTOR_REFERENCE_REQUIRED",differentActorAndPartyRequired="DIFFERENT_ACTOR_AND_PARTY_REQUIRED"}
enum CorrectiveActionReopenTriggerV1:String,CaseIterable,Codable,Hashable,Sendable{case failedVerifiedRecheck="FAILED_VERIFIED_RECHECK",newEvidenceDigest="NEW_EVIDENCE_DIGEST",subjectAmended="SUBJECT_AMENDED",manualRecordedReason="MANUAL_RECORDED_REASON"}
struct CorrectiveClosureEvidenceRequirementV1:Codable,Equatable,Hashable,Comparable,Sendable{let requirementID:String;let kind:ReviewEvidenceKindV1;let minimumCount:Int;init(requirementID:String,kind:ReviewEvidenceKindV1,minimumCount:Int)throws{self.requirementID=requirementID;self.kind=kind;self.minimumCount=minimumCount;try InspectionReviewValidationV1.text(requirementID);guard minimumCount>0 && minimumCount<=InspectionReviewLimitsV1.maximumItems else{throw InspectionReviewFailureV1.invalidValue}}static func <(l:Self,r:Self)->Bool{l.requirementID<r.requirementID}}

struct CorrectiveActionPolicyV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let releaseID:UUID;let policyID:UUID;let workspaceID:WorkspaceID;let packageRelease:PackageReleaseIdentityV1?;let priorityRules:[CorrectiveActionPriorityRuleV1];let assignmentRule:CorrectiveActionAssignmentRuleV1;let closureEvidenceRequirements:[CorrectiveClosureEvidenceRequirementV1];let verifierRule:CorrectiveActionVerifierRuleV1;let reopenTriggers:[CorrectiveActionReopenTriggerV1];let effectiveAt:Date;let supersedesReleaseID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let policySHA256:String
    init(releaseID:UUID,policyID:UUID,workspaceID:WorkspaceID,packageRelease:PackageReleaseIdentityV1?=nil,priorityRules:[CorrectiveActionPriorityRuleV1],assignmentRule:CorrectiveActionAssignmentRuleV1,closureEvidenceRequirements:[CorrectiveClosureEvidenceRequirementV1],verifierRule:CorrectiveActionVerifierRuleV1,reopenTriggers:[CorrectiveActionReopenTriggerV1],effectiveAt:Date,supersedesReleaseID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{let priorities=priorityRules.sorted();let evidence=closureEvidenceRequirements.sorted();let triggers=reopenTriggers.sorted{$0.rawValue<$1.rawValue};schemaVersion=Self.schemaVersion;self.releaseID=releaseID;self.policyID=policyID;self.workspaceID=workspaceID;self.packageRelease=packageRelease;self.priorityRules=priorities;self.assignmentRule=assignmentRule;self.closureEvidenceRequirements=evidence;self.verifierRule=verifierRule;self.reopenTriggers=triggers;self.effectiveAt=effectiveAt;self.supersedesReleaseID=supersedesReleaseID;self.revision=revision;self.mutationID=mutationID;policySHA256=try InspectionReviewCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,releaseID:releaseID,policyID:policyID,workspaceID:workspaceID,packageRelease:packageRelease,priorityRules:priorities,assignmentRule:assignmentRule,closureEvidenceRequirements:evidence,verifierRule:verifierRule,reopenTriggers:triggers,effectiveAt:effectiveAt,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [releaseID,policyID].forEach(InspectionReviewValidationV1.id);try InspectionReviewValidationV1.workspace(workspaceID);try priorityRules.forEach{$0.dueRule.validate()};try closureEvidenceRequirements.forEach{try InspectionReviewValidationV1.text($0.requirementID)};try InspectionReviewValidationV1.instant(effectiveAt);try InspectionReviewValidationV1.revision(revision);if let supersedesReleaseID{try InspectionReviewValidationV1.id(supersedesReleaseID)};guard schemaVersion==Self.schemaVersion,!priorityRules.isEmpty,priorityRules==priorityRules.sorted(),Set(priorityRules.map(\.priority)).count==priorityRules.count,closureEvidenceRequirements==closureEvidenceRequirements.sorted(),Set(closureEvidenceRequirements.map(\.requirementID)).count==closureEvidenceRequirements.count,reopenTriggers==reopenTriggers.sorted(by:{$0.rawValue<$1.rawValue}),Set(reopenTriggers).count==reopenTriggers.count,(supersedesReleaseID==nil)==(revision==1),policySHA256==(try InspectionReviewCanonicalCodecV1.sha256(basis))else{throw InspectionReviewFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();try InspectionReviewValidationV1.next(p.revision,revision);guard workspaceID==p.workspaceID,policyID==p.policyID,supersedesReleaseID==p.releaseID,effectiveAt>=p.effectiveAt,mutationID != p.mutationID else{throw InspectionReviewFailureV1.historyRewrite}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(releaseID:releaseID,policyID:policyID,workspaceID:workspaceID,packageRelease:packageRelease,priorityRules:priorityRules,assignmentRule:assignmentRule,closureEvidenceRequirements:closureEvidenceRequirements,verifierRule:verifierRule,reopenTriggers:reopenTriggers,effectiveAt:effectiveAt,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,releaseID:releaseID,policyID:policyID,workspaceID:workspaceID,packageRelease:packageRelease,priorityRules:priorityRules,assignmentRule:assignmentRule,closureEvidenceRequirements:closureEvidenceRequirements,verifierRule:verifierRule,reopenTriggers:reopenTriggers,effectiveAt:effectiveAt,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let releaseID:UUID;let policyID:UUID;let workspaceID:WorkspaceID;let packageRelease:PackageReleaseIdentityV1?;let priorityRules:[CorrectiveActionPriorityRuleV1];let assignmentRule:CorrectiveActionAssignmentRuleV1;let closureEvidenceRequirements:[CorrectiveClosureEvidenceRequirementV1];let verifierRule:CorrectiveActionVerifierRuleV1;let reopenTriggers:[CorrectiveActionReopenTriggerV1];let effectiveAt:Date;let supersedesReleaseID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct CorrectiveActionPolicyReferenceV1:Codable,Equatable,Hashable,Sendable{let releaseID:UUID;let policyID:UUID;let revision:UInt64;let sha256:String;init(_ p:CorrectiveActionPolicyV1)throws{try p.validate();releaseID=p.releaseID;policyID=p.policyID;revision=p.revision;sha256=p.policySHA256}}
struct CorrectiveActionDueCalculationV1:Codable,Equatable,Hashable,Sendable{let openedAt:Date;let timeZoneIdentifier:String?;let dueAt:Date?;let graceEndsAt:Date?;let resolvedUTCOffsetSeconds:Int?;let calculationSHA256:String;init(openedAt:Date,timeZoneIdentifier:String?,dueAt:Date?,graceEndsAt:Date?,resolvedUTCOffsetSeconds:Int?)throws{self.openedAt=openedAt;self.timeZoneIdentifier=timeZoneIdentifier;self.dueAt=dueAt;self.graceEndsAt=graceEndsAt;self.resolvedUTCOffsetSeconds=resolvedUTCOffsetSeconds;calculationSHA256=try InspectionReviewCanonicalCodecV1.sha256(Basis(openedAt:openedAt,timeZoneIdentifier:timeZoneIdentifier,dueAt:dueAt,graceEndsAt:graceEndsAt,resolvedUTCOffsetSeconds:resolvedUTCOffsetSeconds));try validate()}func validate()throws{try InspectionReviewValidationV1.instant(openedAt);if let dueAt{try InspectionReviewValidationV1.instant(dueAt)};if let graceEndsAt{try InspectionReviewValidationV1.instant(graceEndsAt)};guard (dueAt==nil)==(graceEndsAt==nil),(dueAt==nil)==(resolvedUTCOffsetSeconds==nil),dueAt.map{$0>=openedAt} ?? true,graceEndsAt.map{g in dueAt.map{$0<=g} ?? false} ?? true,calculationSHA256==(try InspectionReviewCanonicalCodecV1.sha256(Basis(openedAt:openedAt,timeZoneIdentifier:timeZoneIdentifier,dueAt:dueAt,graceEndsAt:graceEndsAt,resolvedUTCOffsetSeconds:resolvedUTCOffsetSeconds)))else{throw InspectionReviewFailureV1.digestMismatch}}private struct Basis:Codable{let openedAt:Date;let timeZoneIdentifier:String?;let dueAt:Date?;let graceEndsAt:Date?;let resolvedUTCOffsetSeconds:Int?}}
enum CorrectiveActionDueStatusV1:String,Codable,Hashable,Sendable{case noDueDate="NO_DUE_DATE",notDue="NOT_DUE",dueWithinGrace="DUE_WITHIN_GRACE",overdue="OVERDUE"}
enum CorrectiveActionDueCalculatorV1{
    static func calculate(policy:CorrectiveActionPolicyV1,priority:CorrectiveActionPriorityV1,openedAt:Date,timeZoneIdentifier:String?)throws->CorrectiveActionDueCalculationV1{try policy.validate();guard let rule=policy.priorityRules.first(where:{$0.priority==priority})else{throw InspectionReviewFailureV1.invalidValue};let due:Date?;let offset:Int?
        switch rule.dueRule.kind{case .noDueDate:due=nil;offset=nil
        case .elapsedSeconds:guard let seconds=rule.dueRule.amount,seconds<=UInt64(Int.max)else{throw InspectionReviewFailureV1.invalidValue};due=openedAt.addingTimeInterval(TimeInterval(seconds));offset=0
        case .calendarDaysAtLocalTime:guard let identifier=timeZoneIdentifier,let zone=TimeZone(identifier:identifier),let days=rule.dueRule.amount,days<=UInt64(Int.max),let hour=rule.dueRule.localHour,let minute=rule.dueRule.localMinute else{throw InspectionReviewFailureV1.unsupportedTimeZone};var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone;guard let targetDay=calendar.date(byAdding:.day,value:Int(days),to:openedAt)else{throw InspectionReviewFailureV1.invalidValue};var components=calendar.dateComponents([.year,.month,.day],from:targetDay);components.hour=hour;components.minute=minute;components.second=0;guard let dayStart=calendar.date(from:DateComponents(timeZone:zone,year:components.year,month:components.month,day:components.day,hour:0,minute:0,second:0)),let resolved=calendar.nextDate(after:dayStart.addingTimeInterval(-1),matching:components,matchingPolicy:.nextTime,repeatedTimePolicy:.first,direction:.forward)else{throw InspectionReviewFailureV1.invalidValue};due=resolved;offset=zone.secondsFromGMT(for:resolved)}
        let grace=due?.addingTimeInterval(TimeInterval(rule.graceSeconds));return try .init(openedAt:openedAt,timeZoneIdentifier:timeZoneIdentifier,dueAt:due,graceEndsAt:grace,resolvedUTCOffsetSeconds:offset)}
    static func status(_ calculation:CorrectiveActionDueCalculationV1,at now:Date)throws->CorrectiveActionDueStatusV1{try calculation.validate();guard let due=calculation.dueAt,let grace=calculation.graceEndsAt else{return .noDueDate};if now<=due{return .notDue};if now<=grace{return .dueWithinGrace};return .overdue}
}

enum CorrectiveActionStateV1:String,CaseIterable,Codable,Hashable,Sendable{case open="OPEN",inProgress="IN_PROGRESS",awaitingVerification="AWAITING_VERIFICATION",closed="CLOSED",reopened="REOPENED",superseded="SUPERSEDED"}
enum CorrectiveActionTransitionTableV1{static func permits(from:CorrectiveActionStateV1,to:CorrectiveActionStateV1)->Bool{if to == .superseded{return from != .superseded};switch(from,to){case(.open,.inProgress),(.open,.awaitingVerification),(.inProgress,.awaitingVerification),(.awaitingVerification,.inProgress),(.awaitingVerification,.closed),(.closed,.reopened),(.reopened,.inProgress),(.reopened,.awaitingVerification):return true;default:return false}}}

struct CorrectiveActionEventV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let eventID:UUID;let actionID:UUID;let workspaceID:WorkspaceID;let source:ChangeRequestItemReferenceV1;let policy:CorrectiveActionPolicyReferenceV1;let priority:CorrectiveActionPriorityV1;let state:CorrectiveActionStateV1;let assignee:LocalActorReferenceV1?;let recorder:ActorSnapshotV1;let due:CorrectiveActionDueCalculationV1;let closureEvidence:[ReviewEvidenceReferenceV1];let verifier:ActorSnapshotV1?;let reopenTrigger:CorrectiveActionReopenTriggerV1?;let reason:String;let occurredAt:Date;let recordedAt:Date;let predecessorEventID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,actionID:UUID,workspaceID:WorkspaceID,source:ChangeRequestItemReferenceV1,policy:CorrectiveActionPolicyReferenceV1,priority:CorrectiveActionPriorityV1,state:CorrectiveActionStateV1,assignee:LocalActorReferenceV1?=nil,recorder:ActorSnapshotV1,due:CorrectiveActionDueCalculationV1,closureEvidence:[ReviewEvidenceReferenceV1]=[],verifier:ActorSnapshotV1?=nil,reopenTrigger:CorrectiveActionReopenTriggerV1?=nil,reason:String,occurredAt:Date,recordedAt:Date,predecessorEventID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{let evidence=closureEvidence.sorted();schemaVersion=Self.schemaVersion;self.eventID=eventID;self.actionID=actionID;self.workspaceID=workspaceID;self.source=source;self.policy=policy;self.priority=priority;self.state=state;self.assignee=assignee;self.recorder=recorder;self.due=due;self.closureEvidence=evidence;self.verifier=verifier;self.reopenTrigger=reopenTrigger;self.reason=reason;self.occurredAt=occurredAt;self.recordedAt=recordedAt;self.predecessorEventID=predecessorEventID;self.revision=revision;self.mutationID=mutationID;eventSHA256=try InspectionReviewCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,eventID:eventID,actionID:actionID,workspaceID:workspaceID,source:source,policy:policy,priority:priority,state:state,assignee:assignee,recorder:recorder,due:due,closureEvidence:evidence,verifier:verifier,reopenTrigger:reopenTrigger,reason:reason,occurredAt:occurredAt,recordedAt:recordedAt,predecessorEventID:predecessorEventID,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [eventID,actionID,policy.releaseID,policy.policyID].forEach(InspectionReviewValidationV1.id);try InspectionReviewValidationV1.workspace(workspaceID);try source.validate();try recorder.validate();try assignee?.validate();try verifier?.validate();try due.validate();try closureEvidence.forEach{$0.validate()};try InspectionReviewValidationV1.text(reason);try InspectionReviewValidationV1.instant(occurredAt);try InspectionReviewValidationV1.instant(recordedAt);try InspectionReviewValidationV1.revision(revision);if let predecessorEventID{try InspectionReviewValidationV1.id(predecessorEventID)};guard schemaVersion==Self.schemaVersion,recorder.workspaceID==workspaceID,recorder.responsibility == .recordedBy,(assignee?.workspaceID ?? workspaceID)==workspaceID,(verifier?.workspaceID ?? workspaceID)==workspaceID,(verifier?.responsibility ?? .verifiedBy) == .verifiedBy,closureEvidence==closureEvidence.sorted(),Set(closureEvidence).count==closureEvidence.count,recordedAt>=occurredAt,(predecessorEventID==nil)==(revision==1),(state == .reopened)==(reopenTrigger != nil),eventSHA256==(try InspectionReviewCanonicalCodecV1.sha256(basis))else{throw InspectionReviewFailureV1.digestMismatch}}
    func validateAdmission(policy release:CorrectiveActionPolicyV1)throws{try validate();try release.validate();guard state == .open,revision==1,predecessorEventID==nil,workspaceID==release.workspaceID,policy==(try CorrectiveActionPolicyReferenceV1(release)),due==(try CorrectiveActionDueCalculatorV1.calculate(policy:release,priority:priority,openedAt:occurredAt,timeZoneIdentifier:due.timeZoneIdentifier))else{throw InspectionReviewFailureV1.invalidValue};switch release.assignmentRule{case .required:guard assignee != nil else{throw InspectionReviewFailureV1.assigneeRequired};case .prohibited:guard assignee == nil else{throw InspectionReviewFailureV1.invalidValue};case .optional:break}}
    func validateSuccessor(of p:Self,policy release:CorrectiveActionPolicyV1)throws{try p.validate();try validate();try release.validate();try InspectionReviewValidationV1.next(p.revision,revision);guard workspaceID==p.workspaceID,actionID==p.actionID,source==p.source,policy==p.policy,policy==(try CorrectiveActionPolicyReferenceV1(release)),priority==p.priority,due==p.due,predecessorEventID==p.eventID,CorrectiveActionTransitionTableV1.permits(from:p.state,to:state),recordedAt>=p.recordedAt,mutationID != p.mutationID else{throw InspectionReviewFailureV1.historyRewrite};if state == .reopened{guard let trigger=reopenTrigger,release.reopenTriggers.contains(trigger)else{throw InspectionReviewFailureV1.invalidTransition}};if state == .closed{try CorrectiveActionClosureValidatorV1.validate(event:self,policy:release,predecessor:p)}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{let assignee=try assignee.map{try LocalActorReferenceV1(actorReferenceID:$0.actorReferenceID,workspaceID:workspaceID,partyID:$0.partyID,displayName:$0.displayName)};return try .init(eventID:eventID,actionID:actionID,workspaceID:workspaceID,source:source,policy:policy,priority:priority,state:state,assignee:assignee,recorder:InspectionReviewRebindV1.actor(recorder,to:workspaceID),due:due,closureEvidence:closureEvidence,verifier:try verifier.map{try InspectionReviewRebindV1.actor($0,to:workspaceID)},reopenTrigger:reopenTrigger,reason:reason,occurredAt:occurredAt,recordedAt:recordedAt,predecessorEventID:predecessorEventID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,actionID:actionID,workspaceID:workspaceID,source:source,policy:policy,priority:priority,state:state,assignee:assignee,recorder:recorder,due:due,closureEvidence:closureEvidence,verifier:verifier,reopenTrigger:reopenTrigger,reason:reason,occurredAt:occurredAt,recordedAt:recordedAt,predecessorEventID:predecessorEventID,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID:UUID;let actionID:UUID;let workspaceID:WorkspaceID;let source:ChangeRequestItemReferenceV1;let policy:CorrectiveActionPolicyReferenceV1;let priority:CorrectiveActionPriorityV1;let state:CorrectiveActionStateV1;let assignee:LocalActorReferenceV1?;let recorder:ActorSnapshotV1;let due:CorrectiveActionDueCalculationV1;let closureEvidence:[ReviewEvidenceReferenceV1];let verifier:ActorSnapshotV1?;let reopenTrigger:CorrectiveActionReopenTriggerV1?;let reason:String;let occurredAt:Date;let recordedAt:Date;let predecessorEventID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

enum CorrectiveActionClosureValidatorV1{static func validate(event:CorrectiveActionEventV1,policy:CorrectiveActionPolicyV1,predecessor:CorrectiveActionEventV1)throws{guard event.policy == (try CorrectiveActionPolicyReferenceV1(policy)),event.workspaceID==policy.workspaceID else{throw InspectionReviewFailureV1.invalidValue};for requirement in policy.closureEvidenceRequirements{guard event.closureEvidence.filter({$0.kind==requirement.kind}).count>=requirement.minimumCount else{throw InspectionReviewFailureV1.missingEvidence}};switch policy.assignmentRule{case .required:guard event.assignee != nil else{throw InspectionReviewFailureV1.assigneeRequired};case .prohibited:guard event.assignee == nil else{throw InspectionReviewFailureV1.invalidValue};case .optional:break};switch policy.verifierRule{case .notRequired:guard event.verifier==nil else{throw InspectionReviewFailureV1.invalidValue};case .selfVerificationPermitted:guard event.verifier != nil else{throw InspectionReviewFailureV1.verifierRequired};case .differentActorReferenceRequired:guard let v=event.verifier,v.actor.actorReferenceID != predecessor.recorder.actor.actorReferenceID,v.actor.actorReferenceID != event.assignee?.actorReferenceID else{throw InspectionReviewFailureV1.verifierRequired};case .differentActorAndPartyRequired:guard let v=event.verifier,let vp=v.actor.partyID,let rp=predecessor.recorder.actor.partyID,v.actor.actorReferenceID != predecessor.recorder.actor.actorReferenceID,v.actor.actorReferenceID != event.assignee?.actorReferenceID,vp != rp,event.assignee?.partyID.map({$0 != vp}) ?? true else{throw InspectionReviewFailureV1.verifierRequired}}}
}

struct InspectionReviewProjectionV1:Equatable,Sendable{let workspaceID:WorkspaceID;let reviewID:UUID;let state:InspectionReviewStateV1;let revision:UInt64;let headTransitionID:UUID;let openChangeRequests:[ChangeRequestV1]}
enum InspectionReviewProjectionBuilderV1{
    static func rebuild(workspaceID:WorkspaceID,reviewID:UUID,transitions:[InspectionReviewTransitionV1],changeRequests:[ChangeRequestV1])throws->InspectionReviewProjectionV1{try rebuild(workspaceID:workspaceID,reviewID:reviewID,transitions:transitions,dispositions:[],changeRequests:changeRequests,requireDispositionBindings:true)}
    static func rebuild(workspaceID:WorkspaceID,reviewID:UUID,transitions:[InspectionReviewTransitionV1],dispositions:[ReviewDispositionV1],changeRequests:[ChangeRequestV1])throws->InspectionReviewProjectionV1{try rebuild(workspaceID:workspaceID,reviewID:reviewID,transitions:transitions,dispositions:dispositions,changeRequests:changeRequests,requireDispositionBindings:true)}
    private static func rebuild(workspaceID:WorkspaceID,reviewID:UUID,transitions:[InspectionReviewTransitionV1],dispositions:[ReviewDispositionV1],changeRequests:[ChangeRequestV1],requireDispositionBindings:Bool)throws->InspectionReviewProjectionV1{
        try InspectionReviewValidationV1.workspace(workspaceID);try InspectionReviewValidationV1.id(reviewID)
        let history=transitions.filter{$0.workspaceID==workspaceID&&$0.reviewID==reviewID}.sorted{$0.revision<$1.revision}
        guard !history.isEmpty,history.count<=InspectionReviewLimitsV1.maximumHistory else{throw InspectionReviewFailureV1.invalidValue}
        let relevantDispositions=dispositions.filter{$0.workspaceID==workspaceID&&$0.reviewID==reviewID}
        try relevantDispositions.forEach{$0.validate()}
        let dispositionGroups=Dictionary(grouping:relevantDispositions,by:{$0.dispositionID})
        guard dispositionGroups.values.allSatisfy({$0.count==1})else{throw InspectionReviewFailureV1.historyRewrite}
        let dispositionByID=dispositionGroups.compactMapValues(\.first)
        let requests=changeRequests.filter{$0.workspaceID==workspaceID&&$0.reviewID==reviewID}
        let requestGroups=Dictionary(grouping:requests,by:{$0.requestID})
        for revisions in requestGroups.values{
            let ordered=revisions.sorted{$0.revision<$1.revision}
            guard ordered.count<=InspectionReviewLimitsV1.maximumHistory else{throw InspectionReviewFailureV1.limitExceeded}
            for(index,request)in ordered.enumerated(){if index==0{try request.validate();guard request.revision==1,request.supersedesRequestRevisionID==nil else{throw InspectionReviewFailureV1.historyRewrite}}else{try request.validateSuccessor(of:ordered[index-1])}}
        }
        let requestIDs=Set(requestGroups.keys)
        for(index,event)in history.enumerated(){
            if index==0{try event.validate();guard event.revision==1,event.predecessorTransitionID==nil,event.fromState == .draft else{throw InspectionReviewFailureV1.historyRewrite}}
            else{try event.validateSuccessor(of:history[index-1])}
            if requireDispositionBindings,event.toState == .changesRequested || event.toState == .accepted{
                guard let id=event.dispositionID,let disposition=dispositionByID[id],disposition.workspaceID==event.workspaceID,disposition.reviewRevision==event.revision,disposition.subject==event.subject,disposition.mutationID==event.mutationID,disposition.kind == (event.toState == .accepted ? .accepted : .changesRequested),event.changeRequestIDs.allSatisfy(requestIDs.contains)else{throw InspectionReviewFailureV1.invalidTransition}
            }
        }
        let requestHeads=requestGroups.compactMap{_,values in values.max{$0.revision<$1.revision}}
        let open=requestHeads.filter{$0.state == .open}.sorted{$0.requestID.uuidString<$1.requestID.uuidString}
        guard let head=history.last,(head.toState != .readyForReview && head.toState != .accepted) || open.isEmpty else{throw InspectionReviewFailureV1.invalidTransition}
        return .init(workspaceID:workspaceID,reviewID:reviewID,state:head.toState,revision:head.revision,headTransitionID:head.transitionID,openChangeRequests:open)
    }
}
struct CorrectiveActionProjectionV1:Equatable,Sendable{let workspaceID:WorkspaceID;let actionID:UUID;let state:CorrectiveActionStateV1;let revision:UInt64;let headEventID:UUID;let dueStatus:CorrectiveActionDueStatusV1}
enum CorrectiveActionProjectionBuilderV1{
    static func rebuild(workspaceID:WorkspaceID,actionID:UUID,events:[CorrectiveActionEventV1],policies:[CorrectiveActionPolicyV1],now:Date)throws->CorrectiveActionProjectionV1{
        try InspectionReviewValidationV1.workspace(workspaceID);try InspectionReviewValidationV1.id(actionID);try InspectionReviewValidationV1.instant(now)
        let history=events.filter{$0.workspaceID==workspaceID&&$0.actionID==actionID}.sorted{$0.revision<$1.revision}
        let relevantPolicies=policies.filter{$0.workspaceID==workspaceID}
        guard !history.isEmpty,history.count<=InspectionReviewLimitsV1.maximumHistory else{throw InspectionReviewFailureV1.invalidValue}
        for(index,event)in history.enumerated(){
            var matched:CorrectiveActionPolicyV1?
            for candidate in relevantPolicies{
                let reference=try CorrectiveActionPolicyReferenceV1(candidate)
                if reference==event.policy{
                    guard matched==nil else{throw InspectionReviewFailureV1.historyRewrite}
                    matched=candidate
                }
            }
            guard let policy=matched else{throw InspectionReviewFailureV1.invalidValue}
            if index==0{try event.validateAdmission(policy:policy)}else{try event.validateSuccessor(of:history[index-1],policy:policy)}
        }
        guard let head=history.last else{throw InspectionReviewFailureV1.invalidValue}
        return .init(workspaceID:workspaceID,actionID:actionID,state:head.state,revision:head.revision,headEventID:head.eventID,dueStatus:try CorrectiveActionDueCalculatorV1.status(head.due,at:now))
    }
}

protocol InspectionReviewValidatableV1{func validate()throws}
extension InspectionReviewTransitionV1:InspectionReviewValidatableV1{};extension ReviewDispositionV1:InspectionReviewValidatableV1{};extension ChangeRequestV1:InspectionReviewValidatableV1{};extension CorrectiveActionPolicyV1:InspectionReviewValidatableV1{};extension CorrectiveActionEventV1:InspectionReviewValidatableV1{}
enum InspectionReviewCanonicalCodecV1{static func encode<T:Encodable>(_ value:T)throws->Data{try WorkspaceMutationCanonicalV1.data(value)}static func sha256<T:Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)}static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=8_388_608 else{throw InspectionReviewFailureV1.invalidValue};let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970;let value=try decoder.decode(type,from:data);if let v=value as? any InspectionReviewValidatableV1{try v.validate()};guard try encode(value)==data else{throw InspectionReviewFailureV1.digestMismatch};return value}}

/// C48 may append an ordinary C14 bundle, but it cannot create a second
/// subject/item ledger or relax the existing transition validator.
enum PortableReviewC14ReconciliationV1 {
    static func validate(
        plan: ExternalReviewImportPlanV1,
        bundle: InspectionReviewAtomicBundleV1
    ) throws {
        try plan.validate(); try bundle.validate()
        guard plan.decision == .acceptAndApply,
              bundle.transition.workspaceID == plan.workspaceID,
              bundle.transition.subject == plan.c14Mapping.subject,
              bundle.changeRequests.allSatisfy({ plan.c14Mapping.items.contains($0.item) }) else {
            throw InspectionReviewFailureV1.invalidValue
        }
        let body: ReviewResponseBodyV1
        switch try PortableReviewCanonicalCodecV1.decodeCanonicalResponseRecord(
            plan.responseRecord.canonicalResponse.canonicalBytes
        ) {
        case let .portable(response): body = response.body
        case let .originRecorded(response): body = response.responseBody
        }
        switch body.disposition {
        case .approved:
            guard bundle.transition.toState == .accepted,
                  bundle.disposition?.kind == .accepted,
                  bundle.changeRequests.isEmpty else { throw InspectionReviewFailureV1.invalidTransition }
        case .changesRequested:
            guard bundle.transition.toState == .changesRequested,
                  bundle.disposition?.kind == .changesRequested,
                  !bundle.changeRequests.isEmpty,
                  bundle.changeRequests.count == body.changeItems.count else {
                throw InspectionReviewFailureV1.invalidTransition
            }
        case .acknowledged:
            throw InspectionReviewFailureV1.invalidTransition
        }
    }
}

// MARK: - C49 inspection-review subject projection

enum C49WorkResourceInspectionReviewBoundaryV1 {
    static let reviewConsumesCanonicalSubject = true
    static let reviewProjectionIsReadOnly = true
    static let reviewDoesNotInferApprovalOrInventoryState = true

    static func report(
        subject: WorkResourceSubjectV1,
        snapshots: [WorkResourceSnapshotV1],
        includeDirectCostPreview: Bool = false
    ) throws -> C49WorkResourceReportProjectionV1 {
        guard snapshots.allSatisfy({
            $0.entry.workspaceID == subject.workspaceID && $0.entry.subject == subject
        }) else {
            throw C49WorkResourceProjectionFailureV1.invalidWorkspace
        }
        return try C49WorkResourceReportProjectionV1(
            workspaceID: subject.workspaceID,
            snapshots: snapshots,
            audience: .internalOnly,
            includeDirectCostPreview: includeDirectCostPreview
        )
    }
}

// MARK: - C50 incumbent file-exchange cross-contract boundary

/// Inspection review may display only a validated, allowlisted, quarantined
/// projection. It never treats an adapter profile or external file as review
/// truth, and all review mutations remain C14 writer-owned.
enum C50InspectionReviewIncumbentExchangeBoundaryV1 {
    static let adapterContract: Any.Type = IncumbentFileAdapterV1.self
    static let registryContract: Any.Type = ClosedIncumbentAdapterRegistryV1.self
    static let profileReleaseContract: Any.Type = IncumbentFileProfileReleaseV1.self
    static let selectionReceiptContract: Any.Type = IncumbentSelectionReceiptV1.self
    static let exchangeScopeContract: Any.Type = IncumbentExchangeScopeV1.self
    static let exportManifestContract: Any.Type = IncumbentFileExportManifestV1.self
    static let exchangeReceiptContract: Any.Type = IncumbentFileExchangeReceiptV1.self
    static let quarantineReceiptContract: Any.Type = IncumbentFileQuarantineReceiptV1.self
    static let reviewProjectionType: Any.Type = InspectionReviewProjectionV1.self
    static let accessibleDocumentType: Any.Type = AccessibleDocumentSemanticTreeV1.self
    static let packageBindingType: Any.Type = PackageReleaseBindingV1.self
    static let evidenceLinkType: Any.Type = AccessibleEvidenceLinkV1.self
    static let privacyAllowlistIsClosed = true
    static let quarantinePrecedesReview = true
    static let sourceAndSessionBytesAreExcluded = true
    static let providerStateIsNotReviewTruth = true
    static let reviewWriterIsDelegated = true
    static let reviewLifecycleIsDerivedOnly = true
    static let conformanceClaimsAreNotInferred = true
    static let disabledProfileRemainsTruthful = true

    static func validateReviewProjection(_ projection: InspectionReviewProjectionV1) throws {
        try InspectionReviewValidationV1.workspace(projection.workspaceID)
        try InspectionReviewValidationV1.id(projection.reviewID)
        try InspectionReviewValidationV1.revision(projection.revision)
        try InspectionReviewValidationV1.id(projection.headTransitionID)
        try projection.openChangeRequests.forEach { try $0.validate() }
    }
}
enum C52ServiceRequestBoundary_InspectionReviewContractsV1 {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}

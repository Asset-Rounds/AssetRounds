import Foundation
import CryptoKit

enum FieldDraftFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, unknownPurpose, unknownCodec, wrongWorkspace
    case staleDraftRevision, staleBaseRevision, invalidTransition, digestMismatch
    case missingReceipt, missingContent, limitExceeded, conflictRequired
}

enum FieldDraftLimitsV1 {
    static let maximumPayloadBytes = 2 * 1_024 * 1_024
    static let maximumStageItems = 128
    static let maximumScopeComponents = 16
    static let maximumAnchorComponents = 12
    static let maximumTextBytes = 512
    static let maximumCanonicalBytes = 16 * 1_024 * 1_024
}

private enum FieldDraftValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) throws { guard value != zero else { throw FieldDraftFailureV1.invalidValue } }
    static func workspace(_ value: WorkspaceID) throws { guard value.rawValue != zero else { throw FieldDraftFailureV1.wrongWorkspace } }
    static func revision(_ value: UInt64) throws { guard value > 0 else { throw FieldDraftFailureV1.invalidValue } }
    static func next(_ predecessor: UInt64, _ successor: UInt64) throws { let n=predecessor.addingReportingOverflow(1);guard !n.overflow,successor==n.partialValue else{throw FieldDraftFailureV1.staleDraftRevision} }
    static func text(_ value: String) throws { guard !value.isEmpty,value==value.trimmingCharacters(in:.whitespacesAndNewlines),value.utf8.count<=FieldDraftLimitsV1.maximumTextBytes,!value.unicodeScalars.contains(where:{$0.properties.isBidiControl||($0.value<0x20&&$0.value != 0x09)}) else{throw FieldDraftFailureV1.invalidValue} }
    static func digest(_ value:String)throws{guard MutationEnvelopeV1.isSHA256(value)else{throw FieldDraftFailureV1.digestMismatch}}
    static func instant(_ value:Date)throws{guard value.timeIntervalSinceReferenceDate.isFinite else{throw FieldDraftFailureV1.invalidValue}}
}

enum DraftPurposeV1:String,CaseIterable,Codable,Hashable,Sendable{
    case inspectionReview="INSPECTION_REVIEW",workPacket="WORK_PACKET",correctiveAction="CORRECTIVE_ACTION"
    case requirementEvaluation="REQUIREMENT_EVALUATION",evidenceCuration="EVIDENCE_CURATION",assetFieldEdit="ASSET_FIELD_EDIT"
}
enum DraftPrivacyClassV1:String,Codable,Hashable,Sendable{case workspacePrivate="WORKSPACE_PRIVATE",restrictedEvidence="RESTRICTED_EVIDENCE"}
enum DraftRetentionPolicyV1:String,Codable,Hashable,Sendable{case explicitDiscardOnly="EXPLICIT_DISCARD_ONLY",retireAfterCommit="RETIRE_AFTER_COMMIT"}
enum DraftAttachmentKindV1:String,CaseIterable,Codable,Hashable,Comparable,Sendable{case photo="PHOTO",audio="AUDIO",video="VIDEO",file="FILE";static func <(l:Self,r:Self)->Bool{l.rawValue<r.rawValue}}

struct DraftPayloadCodecReleaseV1:Codable,Equatable,Hashable,Sendable{
    let codecID:String;let codecVersion:UInt64;let releaseSHA256:String
    init(codecID:String,codecVersion:UInt64,releaseSHA256:String)throws{self.codecID=codecID;self.codecVersion=codecVersion;self.releaseSHA256=releaseSHA256;try validate()}
    func validate()throws{try FieldDraftValidationV1.text(codecID);try FieldDraftValidationV1.revision(codecVersion);try FieldDraftValidationV1.digest(releaseSHA256)}
}
struct DraftPurposeDefinitionV1:Codable,Equatable,Hashable,Sendable{
    let purpose:DraftPurposeV1;let codec:DraftPayloadCodecReleaseV1;let maximumPayloadBytes:Int;let maximumStageItems:Int
    let targetCommandKind:WorkspaceCommandKindV1;let retention:DraftRetentionPolicyV1;let attachmentKinds:[DraftAttachmentKindV1];let privacyClass:DraftPrivacyClassV1
    init(purpose:DraftPurposeV1,codec:DraftPayloadCodecReleaseV1,maximumPayloadBytes:Int,maximumStageItems:Int,targetCommandKind:WorkspaceCommandKindV1,retention:DraftRetentionPolicyV1,attachmentKinds:[DraftAttachmentKindV1],privacyClass:DraftPrivacyClassV1)throws{self.purpose=purpose;self.codec=codec;self.maximumPayloadBytes=maximumPayloadBytes;self.maximumStageItems=maximumStageItems;self.targetCommandKind=targetCommandKind;self.retention=retention;self.attachmentKinds=attachmentKinds.sorted();self.privacyClass=privacyClass;try validate()}
    func validate()throws{try codec.validate();guard maximumPayloadBytes>0,maximumPayloadBytes<=FieldDraftLimitsV1.maximumPayloadBytes,maximumStageItems>=0,maximumStageItems<=FieldDraftLimitsV1.maximumStageItems,attachmentKinds==attachmentKinds.sorted(),Set(attachmentKinds).count==attachmentKinds.count else{throw FieldDraftFailureV1.limitExceeded}}
}
struct DraftPurposeRegistryV1:Sendable{
    let definitions:[DraftPurposeV1:DraftPurposeDefinitionV1]
    init(_ values:[DraftPurposeDefinitionV1])throws{try values.forEach{$0.validate()};let pairs=values.map{($0.purpose,$0)};guard values.count==DraftPurposeV1.allCases.count,Set(pairs.map(\.0)).count==values.count else{throw FieldDraftFailureV1.unknownPurpose};definitions=Dictionary(uniqueKeysWithValues:pairs)}
    func require(_ purpose:DraftPurposeV1,codec:DraftPayloadCodecReleaseV1)throws->DraftPurposeDefinitionV1{guard let value=definitions[purpose]else{throw FieldDraftFailureV1.unknownPurpose};guard value.codec==codec else{throw FieldDraftFailureV1.unknownCodec};return value}
}

struct DraftScopeKeyV1:Codable,Equatable,Hashable,Sendable{
    let scopeKind:String;let stableComponentIDs:[String]
    init(scopeKind:String,stableComponentIDs:[String])throws{self.scopeKind=scopeKind;self.stableComponentIDs=stableComponentIDs;try validate()}
    func validate()throws{try FieldDraftValidationV1.text(scopeKind);try stableComponentIDs.forEach(FieldDraftValidationV1.text);guard !stableComponentIDs.isEmpty,stableComponentIDs.count<=FieldDraftLimitsV1.maximumScopeComponents,Set(stableComponentIDs).count==stableComponentIDs.count else{throw FieldDraftFailureV1.limitExceeded}}
}
struct DraftResumeAnchorV1:Codable,Equatable,Hashable,Sendable{
    let sectionID:String?;let fieldID:String?;let selectedStableID:String?;let boundedPosition:Int?
    init(sectionID:String?=nil,fieldID:String?=nil,selectedStableID:String?=nil,boundedPosition:Int?=nil)throws{self.sectionID=sectionID;self.fieldID=fieldID;self.selectedStableID=selectedStableID;self.boundedPosition=boundedPosition;try validate()}
    func validate()throws{try [sectionID,fieldID,selectedStableID].compactMap{$0}.forEach(FieldDraftValidationV1.text);guard boundedPosition.map({$0>=0&&$0<=100_000}) ?? true else{throw FieldDraftFailureV1.invalidValue}}
}
enum FieldDraftStateV1:String,CaseIterable,Codable,Hashable,Sendable{case active="ACTIVE",committing="COMMITTING",conflicted="CONFLICTED",recoveryRequired="RECOVERY_REQUIRED",committed="COMMITTED",discardPending="DISCARD_PENDING",discarded="DISCARDED"}
enum DraftDurabilityPresentationStateV1:String,CaseIterable,Codable,Hashable,Sendable{case unsavedChanges="UNSAVED_CHANGES",savingOnThisIPhone="SAVING_ON_THIS_IPHONE",savedOnThisIPhone="SAVED_ON_THIS_IPHONE",saveBlocked="SAVE_BLOCKED",committing="COMMITTING",conflicted="CONFLICTED",recoveryRequired="RECOVERY_REQUIRED",committed="COMMITTED",discarding="DISCARDING",discarded="DISCARDED"}
enum DraftDurabilityPresentationMapperV1{static func state(checkpoint:FieldDraftCheckpointV1,hasDirtyChanges:Bool,writeInFlight:Bool,writeBlocked:Bool,receiptReadBack:Bool)->DraftDurabilityPresentationStateV1{switch checkpoint.state{case .active:if writeBlocked{return .saveBlocked};if writeInFlight{return .savingOnThisIPhone};return hasDirtyChanges ? .unsavedChanges:(receiptReadBack ? .savedOnThisIPhone:.unsavedChanges);case .committing:return .committing;case .conflicted:return .conflicted;case .recoveryRequired:return .recoveryRequired;case .committed:return receiptReadBack ? .committed:.committing;case .discardPending:return .discarding;case .discarded:return receiptReadBack ? .discarded:.discarding}}}

struct FieldDraftCheckpointV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let draftID:UUID;let workspaceID:WorkspaceID;let scope:DraftScopeKeyV1;let purpose:DraftPurposeV1;let codec:DraftPayloadCodecReleaseV1;let baseCanonicalRevision:UInt64;let draftRevision:UInt64;let payloadData:Data;let payloadSHA256:String;let stageIDs:[UUID];let resumeAnchor:DraftResumeAnchorV1;let state:FieldDraftStateV1;let lastDurableMutationID:MutationIDV1?;let lastReceiptSHA256:String?;let updatedAt:Date;let mutationID:MutationIDV1;let checkpointSHA256:String
    init(draftID:UUID,workspaceID:WorkspaceID,scope:DraftScopeKeyV1,purpose:DraftPurposeV1,codec:DraftPayloadCodecReleaseV1,baseCanonicalRevision:UInt64,draftRevision:UInt64,payloadData:Data,stageIDs:[UUID],resumeAnchor:DraftResumeAnchorV1,state:FieldDraftStateV1,lastDurableMutationID:MutationIDV1?=nil,lastReceiptSHA256:String?=nil,updatedAt:Date,mutationID:MutationIDV1)throws{let ids=stageIDs.sorted{$0.uuidString<$1.uuidString};schemaVersion=Self.schemaVersion;self.draftID=draftID;self.workspaceID=workspaceID;self.scope=scope;self.purpose=purpose;self.codec=codec;self.baseCanonicalRevision=baseCanonicalRevision;self.draftRevision=draftRevision;self.payloadData=payloadData;payloadSHA256=try FieldDraftCanonicalCodecV1.sha256(payloadData);self.stageIDs=ids;self.resumeAnchor=resumeAnchor;self.state=state;self.lastDurableMutationID=lastDurableMutationID;self.lastReceiptSHA256=lastReceiptSHA256;self.updatedAt=updatedAt;self.mutationID=mutationID;checkpointSHA256=try FieldDraftCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,draftID:draftID,workspaceID:workspaceID,scope:scope,purpose:purpose,codec:codec,baseCanonicalRevision:baseCanonicalRevision,draftRevision:draftRevision,payloadSHA256:payloadSHA256,stageIDs:ids,resumeAnchor:resumeAnchor,state:state,lastDurableMutationID:lastDurableMutationID,lastReceiptSHA256:lastReceiptSHA256,updatedAt:updatedAt,mutationID:mutationID));try validate()}
    func validate(registry:DraftPurposeRegistryV1?=nil)throws{try FieldDraftValidationV1.id(draftID);try FieldDraftValidationV1.workspace(workspaceID);try scope.validate();try codec.validate();try FieldDraftValidationV1.revision(draftRevision);try resumeAnchor.validate();try FieldDraftValidationV1.instant(updatedAt);if let lastReceiptSHA256{try FieldDraftValidationV1.digest(lastReceiptSHA256)};if let registry{let d=try registry.require(purpose,codec:codec);guard payloadData.count<=d.maximumPayloadBytes,stageIDs.count<=d.maximumStageItems else{throw FieldDraftFailureV1.limitExceeded}};let terminalReceiptBound=(state != .committed && state != .discarded)||(lastDurableMutationID != nil && lastReceiptSHA256 != nil);guard schemaVersion==Self.schemaVersion,terminalReceiptBound,payloadData.count<=FieldDraftLimitsV1.maximumPayloadBytes,stageIDs.count<=FieldDraftLimitsV1.maximumStageItems,stageIDs==stageIDs.sorted(by:{$0.uuidString<$1.uuidString}),Set(stageIDs).count==stageIDs.count,payloadSHA256==FieldDraftCanonicalCodecV1.sha256(payloadData),checkpointSHA256==(try FieldDraftCanonicalCodecV1.sha256(basis)) else{throw FieldDraftFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self,expectedDraftRevision:UInt64,expectedBaseRevision:UInt64)throws{try p.validate();try validate();try FieldDraftValidationV1.next(p.draftRevision,draftRevision);guard expectedDraftRevision==p.draftRevision,expectedBaseRevision==p.baseCanonicalRevision,workspaceID==p.workspaceID,draftID==p.draftID,scope==p.scope,purpose==p.purpose,codec==p.codec,baseCanonicalRevision==p.baseCanonicalRevision,updatedAt>=p.updatedAt,mutationID != p.mutationID,Self.permits(p.state,state) else{throw FieldDraftFailureV1.staleDraftRevision}}
    static func permits(_ from:FieldDraftStateV1,_ to:FieldDraftStateV1)->Bool{switch(from,to){case(.active,.active),(.active,.committing),(.active,.discardPending),(.committing,.committed),(.committing,.conflicted),(.committing,.recoveryRequired),(.conflicted,.active),(.conflicted,.discardPending),(.recoveryRequired,.active),(.recoveryRequired,.committing),(.recoveryRequired,.discardPending),(.discardPending,.discarded),(.discardPending,.recoveryRequired):return true;default:return false}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,draftID:draftID,workspaceID:workspaceID,scope:scope,purpose:purpose,codec:codec,baseCanonicalRevision:baseCanonicalRevision,draftRevision:draftRevision,payloadSHA256:payloadSHA256,stageIDs:stageIDs,resumeAnchor:resumeAnchor,state:state,lastDurableMutationID:lastDurableMutationID,lastReceiptSHA256:lastReceiptSHA256,updatedAt:updatedAt,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let draftID:UUID;let workspaceID:WorkspaceID;let scope:DraftScopeKeyV1;let purpose:DraftPurposeV1;let codec:DraftPayloadCodecReleaseV1;let baseCanonicalRevision:UInt64;let draftRevision:UInt64;let payloadSHA256:String;let stageIDs:[UUID];let resumeAnchor:DraftResumeAnchorV1;let state:FieldDraftStateV1;let lastDurableMutationID:MutationIDV1?;let lastReceiptSHA256:String?;let updatedAt:Date;let mutationID:MutationIDV1}
}

enum AttachmentStagingStateV1:String,CaseIterable,Codable,Hashable,Sendable{case capturing="CAPTURING",hashing="HASHING",processing="PROCESSING",readyLocal="READY_LOCAL",failedRetryable="FAILED_RETRYABLE",failedFinal="FAILED_FINAL",removePending="REMOVE_PENDING",committed="COMMITTED",orphanQuarantined="ORPHAN_QUARANTINED"}
enum DraftProtectionStateV1:String,Codable,Hashable,Sendable{case available="AVAILABLE",protectedDataUnavailable="PROTECTED_DATA_UNAVAILABLE",lowStorage="LOW_STORAGE"}
enum DraftStageRetryClassV1:String,Codable,Hashable,Sendable{case none="NONE",retryable="RETRYABLE",final="FINAL"}
enum DraftAttachmentPresentationStateV1:String,CaseIterable,Codable,Hashable,Sendable{case selected="SELECTED",loading="LOADING",stagedLocal="STAGED_LOCAL",processing="PROCESSING",ready="READY",retryableFailure="RETRYABLE_FAILURE",blocked="BLOCKED",removed="REMOVED",promoted="PROMOTED"}
enum DraftAttachmentPresentationMapperV1{static func state(for item:AttachmentStagingItemV1,durableReceiptReadBack:Bool)->DraftAttachmentPresentationStateV1{switch item.state{case .capturing:return .selected;case .hashing:return .loading;case .processing:return .processing;case .readyLocal:return durableReceiptReadBack ? .ready:.stagedLocal;case .failedRetryable:return .retryableFailure;case .failedFinal,.orphanQuarantined:return .blocked;case .removePending:return .removed;case .committed:return durableReceiptReadBack ? .promoted:.ready}}}
struct AttachmentStagingItemV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let stageID:UUID;let draftID:UUID;let workspaceID:WorkspaceID;let attachmentKind:DraftAttachmentKindV1;let scratchLeaseID:UUID;let expectedByteCount:Int64;let actualByteCount:Int64?;let contentDigest:ContentDigestV1?;let contentReference:ContentReferenceV1?;let processingJobID:UUID?;let retryClass:DraftStageRetryClassV1;let protectionState:DraftProtectionStateV1;let state:AttachmentStagingStateV1;let revision:UInt64;let mutationID:MutationIDV1;let stageSHA256:String
    init(stageID:UUID,draftID:UUID,workspaceID:WorkspaceID,attachmentKind:DraftAttachmentKindV1,scratchLeaseID:UUID,expectedByteCount:Int64,actualByteCount:Int64?=nil,contentDigest:ContentDigestV1?=nil,contentReference:ContentReferenceV1?=nil,processingJobID:UUID?=nil,retryClass:DraftStageRetryClassV1,state:AttachmentStagingStateV1,protectionState:DraftProtectionStateV1,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.stageID=stageID;self.draftID=draftID;self.workspaceID=workspaceID;self.attachmentKind=attachmentKind;self.scratchLeaseID=scratchLeaseID;self.expectedByteCount=expectedByteCount;self.actualByteCount=actualByteCount;self.contentDigest=contentDigest;self.contentReference=contentReference;self.processingJobID=processingJobID;self.retryClass=retryClass;self.state=state;self.protectionState=protectionState;self.revision=revision;self.mutationID=mutationID;stageSHA256=try FieldDraftCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,stageID:stageID,draftID:draftID,workspaceID:workspaceID,attachmentKind:attachmentKind,scratchLeaseID:scratchLeaseID,expectedByteCount:expectedByteCount,actualByteCount:actualByteCount,contentDigest:contentDigest,contentReference:contentReference,processingJobID:processingJobID,retryClass:retryClass,protectionState:protectionState,state:state,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [stageID,draftID,scratchLeaseID].forEach(FieldDraftValidationV1.id);try FieldDraftValidationV1.workspace(workspaceID);try FieldDraftValidationV1.revision(revision);if let processingJobID{try FieldDraftValidationV1.id(processingJobID)};guard schemaVersion==Self.schemaVersion,expectedByteCount>=0,actualByteCount.map({$0>=0&&$0==expectedByteCount}) ?? true,contentReference.map({$0.workspaceID.lowercased()==workspaceID.rawValue.uuidString.lowercased()&&$0.byteLength==actualByteCount}) ?? true,(state == .readyLocal ? actualByteCount != nil && contentDigest != nil:true),(state == .committed ? contentReference != nil:true),stageSHA256==(try FieldDraftCanonicalCodecV1.sha256(basis))else{throw FieldDraftFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();try FieldDraftValidationV1.next(p.revision,revision);guard stageID==p.stageID,draftID==p.draftID,workspaceID==p.workspaceID,attachmentKind==p.attachmentKind,scratchLeaseID==p.scratchLeaseID,expectedByteCount==p.expectedByteCount,mutationID != p.mutationID,Self.permits(p.state,state) else{throw FieldDraftFailureV1.invalidTransition}}
    static func permits(_ from:AttachmentStagingStateV1,_ to:AttachmentStagingStateV1)->Bool{switch(from,to){case(.capturing,.hashing),(.capturing,.failedRetryable),(.capturing,.failedFinal),(.capturing,.removePending),(.hashing,.processing),(.hashing,.readyLocal),(.hashing,.failedRetryable),(.hashing,.failedFinal),(.hashing,.removePending),(.processing,.readyLocal),(.processing,.failedRetryable),(.processing,.failedFinal),(.processing,.removePending),(.failedRetryable,.capturing),(.failedRetryable,.hashing),(.failedRetryable,.processing),(.failedRetryable,.removePending),(.readyLocal,.committed),(.readyLocal,.removePending),(.removePending,.orphanQuarantined),(.committed,.orphanQuarantined):return true;default:return false}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,stageID:stageID,draftID:draftID,workspaceID:workspaceID,attachmentKind:attachmentKind,scratchLeaseID:scratchLeaseID,expectedByteCount:expectedByteCount,actualByteCount:actualByteCount,contentDigest:contentDigest,contentReference:contentReference,processingJobID:processingJobID,retryClass:retryClass,protectionState:protectionState,state:state,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let stageID:UUID;let draftID:UUID;let workspaceID:WorkspaceID;let attachmentKind:DraftAttachmentKindV1;let scratchLeaseID:UUID;let expectedByteCount:Int64;let actualByteCount:Int64?;let contentDigest:ContentDigestV1?;let contentReference:ContentReferenceV1?;let processingJobID:UUID?;let retryClass:DraftStageRetryClassV1;let protectionState:DraftProtectionStateV1;let state:AttachmentStagingStateV1;let revision:UInt64;let mutationID:MutationIDV1}
}

enum DraftConflictResolutionPlanV1:String,CaseIterable,Codable,Hashable,Sendable{case reviewAndRebase="REVIEW_AND_REBASE",commitAsCopy="COMMIT_AS_COPY",continueEditing="CONTINUE_EDITING",discard="DISCARD"}
struct DraftCommitPlanV1:Codable,Equatable,Hashable,Sendable{let planID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let draftRevision:UInt64;let baseCanonicalRevision:UInt64;let payloadSHA256:String;let stageDigests:[String];let targetCommandKind:WorkspaceCommandKindV1;let expectedTargetRevision:UInt64;let mutationID:MutationIDV1;let outputKeys:[String];let planSHA256:String
    init(planID:UUID,workspaceID:WorkspaceID,draftID:UUID,draftRevision:UInt64,baseCanonicalRevision:UInt64,payloadSHA256:String,stageDigests:[String],targetCommandKind:WorkspaceCommandKindV1,expectedTargetRevision:UInt64,mutationID:MutationIDV1,outputKeys:[String])throws{let stages=stageDigests.sorted(),outputs=outputKeys.sorted();self.planID=planID;self.workspaceID=workspaceID;self.draftID=draftID;self.draftRevision=draftRevision;self.baseCanonicalRevision=baseCanonicalRevision;self.payloadSHA256=payloadSHA256;self.stageDigests=stages;self.targetCommandKind=targetCommandKind;self.expectedTargetRevision=expectedTargetRevision;self.mutationID=mutationID;self.outputKeys=outputs;planSHA256=try FieldDraftCanonicalCodecV1.sha256(Basis(planID:planID,workspaceID:workspaceID,draftID:draftID,draftRevision:draftRevision,baseCanonicalRevision:baseCanonicalRevision,payloadSHA256:payloadSHA256,stageDigests:stages,targetCommandKind:targetCommandKind,expectedTargetRevision:expectedTargetRevision,mutationID:mutationID,outputKeys:outputs));try validate()}
    func validate()throws{try [planID,draftID].forEach(FieldDraftValidationV1.id);try FieldDraftValidationV1.workspace(workspaceID);try FieldDraftValidationV1.revision(draftRevision);try FieldDraftValidationV1.digest(payloadSHA256);try stageDigests.forEach(FieldDraftValidationV1.digest);try outputKeys.forEach(FieldDraftValidationV1.text);guard stageDigests==stageDigests.sorted(),Set(stageDigests).count==stageDigests.count,outputKeys==outputKeys.sorted(),Set(outputKeys).count==outputKeys.count,planSHA256==(try FieldDraftCanonicalCodecV1.sha256(basis))else{throw FieldDraftFailureV1.digestMismatch}}
    private var basis:Basis{.init(planID:planID,workspaceID:workspaceID,draftID:draftID,draftRevision:draftRevision,baseCanonicalRevision:baseCanonicalRevision,payloadSHA256:payloadSHA256,stageDigests:stageDigests,targetCommandKind:targetCommandKind,expectedTargetRevision:expectedTargetRevision,mutationID:mutationID,outputKeys:outputKeys)};private struct Basis:Codable{let planID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let draftRevision:UInt64;let baseCanonicalRevision:UInt64;let payloadSHA256:String;let stageDigests:[String];let targetCommandKind:WorkspaceCommandKindV1;let expectedTargetRevision:UInt64;let mutationID:MutationIDV1;let outputKeys:[String]}}

/// Mutation IDs for operational rows are distinct from the canonical target
/// mutation and are supplied up front so retries reproduce the same effects.
struct DraftCommitRowMutationIDsV1:Equatable,Sendable{
    let reservationByStageID:[UUID:MutationIDV1]
    let terminalBundleMutationID:MutationIDV1
    init(reservationByStageID:[UUID:MutationIDV1],terminalBundleMutationID:MutationIDV1)throws{self.reservationByStageID=reservationByStageID;self.terminalBundleMutationID=terminalBundleMutationID;guard Set(reservationByStageID.values.map(\.rawValue)).count==reservationByStageID.count else{throw FieldDraftFailureV1.invalidValue}}
    func validate(stageIDs:[UUID],targetMutationID:MutationIDV1,sagaMutationIDs:[MutationIDV1])throws{let expected=Set(stageIDs);guard expected.count==stageIDs.count,Set(reservationByStageID.keys)==expected else{throw FieldDraftFailureV1.invalidValue};let all=[targetMutationID.rawValue,terminalBundleMutationID.rawValue]+sagaMutationIDs.map(\.rawValue)+reservationByStageID.values.map(\.rawValue);guard Set(all).count==all.count else{throw FieldDraftFailureV1.invalidValue}}
}

enum DraftCommitSagaStateV1:String,CaseIterable,Codable,Hashable,Sendable{case prepared="PREPARED",contentPromotedUnbound="CONTENT_PROMOTED_UNBOUND",targetCommitted="TARGET_COMMITTED",draftRetirePending="DRAFT_RETIRE_PENDING",draftRetired="DRAFT_RETIRED",conflicted="CONFLICTED",recoveryRequired="RECOVERY_REQUIRED"}
struct DraftCommitSagaV1:Codable,Equatable,Hashable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let sagaID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let plan:DraftCommitPlanV1;let state:DraftCommitSagaStateV1;let predecessorSagaID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let updatedAt:Date;let sagaSHA256:String
    init(sagaID:UUID,workspaceID:WorkspaceID,draftID:UUID,plan:DraftCommitPlanV1,state:DraftCommitSagaStateV1,predecessorSagaID:UUID?=nil,revision:UInt64,mutationID:MutationIDV1,updatedAt:Date)throws{schemaVersion=Self.schemaVersion;self.sagaID=sagaID;self.workspaceID=workspaceID;self.draftID=draftID;self.plan=plan;self.state=state;self.predecessorSagaID=predecessorSagaID;self.revision=revision;self.mutationID=mutationID;self.updatedAt=updatedAt;sagaSHA256=try FieldDraftCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,sagaID:sagaID,workspaceID:workspaceID,draftID:draftID,plan:plan,state:state,predecessorSagaID:predecessorSagaID,revision:revision,mutationID:mutationID,updatedAt:updatedAt));try validate()}
    func validate()throws{try [sagaID,draftID].forEach(FieldDraftValidationV1.id);try FieldDraftValidationV1.workspace(workspaceID);try plan.validate();try FieldDraftValidationV1.revision(revision);try FieldDraftValidationV1.instant(updatedAt);guard schemaVersion==Self.schemaVersion,workspaceID==plan.workspaceID,draftID==plan.draftID,(predecessorSagaID==nil)==(revision==1),predecessorSagaID != sagaID,sagaSHA256==(try FieldDraftCanonicalCodecV1.sha256(basis))else{throw FieldDraftFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();try FieldDraftValidationV1.next(p.revision,revision);guard sagaID != p.sagaID,predecessorSagaID==p.sagaID,workspaceID==p.workspaceID,draftID==p.draftID,plan==p.plan,updatedAt>=p.updatedAt,Self.permits(p.state,state)else{throw FieldDraftFailureV1.invalidTransition}}
    static func permits(_ from:DraftCommitSagaStateV1,_ to:DraftCommitSagaStateV1)->Bool{switch(from,to){case(.prepared,.contentPromotedUnbound),(.prepared,.conflicted),(.prepared,.recoveryRequired),(.contentPromotedUnbound,.targetCommitted),(.contentPromotedUnbound,.conflicted),(.contentPromotedUnbound,.recoveryRequired),(.targetCommitted,.draftRetirePending),(.targetCommitted,.recoveryRequired),(.draftRetirePending,.draftRetired),(.draftRetirePending,.recoveryRequired),(.conflicted,.prepared),(.conflicted,.recoveryRequired),(.recoveryRequired,.prepared),(.recoveryRequired,.contentPromotedUnbound),(.recoveryRequired,.targetCommitted),(.recoveryRequired,.draftRetirePending):return true;default:return false}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,sagaID:sagaID,workspaceID:workspaceID,draftID:draftID,plan:plan,state:state,predecessorSagaID:predecessorSagaID,revision:revision,mutationID:mutationID,updatedAt:updatedAt)};private struct Basis:Codable{let schemaVersion:Int;let sagaID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let plan:DraftCommitPlanV1;let state:DraftCommitSagaStateV1;let predecessorSagaID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let updatedAt:Date}}

enum DraftReservationReconciliationStateV1:String,CaseIterable,Codable,Hashable,Sendable{case reserved="RESERVED",reused="REUSED",associated="ASSOCIATED",orphanQuarantined="ORPHAN_QUARANTINED",deleted="DELETED"}
struct DraftContentReservationV1:Codable,Equatable,Hashable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let reservationID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let stageID:UUID;let commitPlanSHA256:String;let mutationID:MutationIDV1;let contentDigest:ContentDigestV1;let locator:ContentLocatorV1;let createdAt:Date;let reviewAfter:Date;let reconciliationState:DraftReservationReconciliationStateV1;let revision:UInt64;let reservationSHA256:String
    init(reservationID:UUID,workspaceID:WorkspaceID,draftID:UUID,stageID:UUID,commitPlanSHA256:String,mutationID:MutationIDV1,contentDigest:ContentDigestV1,locator:ContentLocatorV1,createdAt:Date,reviewAfter:Date,reconciliationState:DraftReservationReconciliationStateV1,revision:UInt64)throws{schemaVersion=Self.schemaVersion;self.reservationID=reservationID;self.workspaceID=workspaceID;self.draftID=draftID;self.stageID=stageID;self.commitPlanSHA256=commitPlanSHA256;self.mutationID=mutationID;self.contentDigest=contentDigest;self.locator=locator;self.createdAt=createdAt;self.reviewAfter=reviewAfter;self.reconciliationState=reconciliationState;self.revision=revision;reservationSHA256=try FieldDraftCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,reservationID:reservationID,workspaceID:workspaceID,draftID:draftID,stageID:stageID,commitPlanSHA256:commitPlanSHA256,mutationID:mutationID,contentDigest:contentDigest,locator:locator,createdAt:createdAt,reviewAfter:reviewAfter,reconciliationState:reconciliationState,revision:revision));try validate()}
    func validate()throws{try [reservationID,draftID,stageID].forEach(FieldDraftValidationV1.id);try FieldDraftValidationV1.workspace(workspaceID);try FieldDraftValidationV1.digest(commitPlanSHA256);try FieldDraftValidationV1.instant(createdAt);try FieldDraftValidationV1.instant(reviewAfter);try FieldDraftValidationV1.revision(revision);guard schemaVersion==Self.schemaVersion,reviewAfter>=createdAt,locator.workspaceID.lowercased()==workspaceID.rawValue.uuidString.lowercased(),locator.contentDigest==contentDigest,reservationSHA256==(try FieldDraftCanonicalCodecV1.sha256(basis))else{throw FieldDraftFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();try FieldDraftValidationV1.next(p.revision,revision);guard reservationID==p.reservationID,workspaceID==p.workspaceID,draftID==p.draftID,stageID==p.stageID,commitPlanSHA256==p.commitPlanSHA256,contentDigest==p.contentDigest,locator==p.locator,createdAt==p.createdAt,reviewAfter==p.reviewAfter,mutationID != p.mutationID,Self.permits(p.reconciliationState,reconciliationState) else{throw FieldDraftFailureV1.invalidTransition}}
    static func permits(_ from:DraftReservationReconciliationStateV1,_ to:DraftReservationReconciliationStateV1)->Bool{switch(from,to){case(.reserved,.reused),(.reserved,.associated),(.reserved,.orphanQuarantined),(.orphanQuarantined,.deleted):return true;default:return false}}
    func mayDelete(hasLiveReference:Bool)->Bool{!hasLiveReference&&(reconciliationState == .orphanQuarantined||reconciliationState == .deleted)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,reservationID:reservationID,workspaceID:workspaceID,draftID:draftID,stageID:stageID,commitPlanSHA256:commitPlanSHA256,mutationID:mutationID,contentDigest:contentDigest,locator:locator,createdAt:createdAt,reviewAfter:reviewAfter,reconciliationState:reconciliationState,revision:revision)};private struct Basis:Codable{let schemaVersion:Int;let reservationID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let stageID:UUID;let commitPlanSHA256:String;let mutationID:MutationIDV1;let contentDigest:ContentDigestV1;let locator:ContentLocatorV1;let createdAt:Date;let reviewAfter:Date;let reconciliationState:DraftReservationReconciliationStateV1;let revision:UInt64}}

struct DraftCommitReceiptV1:Codable,Equatable,Sendable{let receiptID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let sagaID:UUID;let commitPlanSHA256:String;let sagaEventSHA256Chain:[String];let targetMutationID:MutationIDV1;let targetReceiptSHA256:String;let consumedStageToContentID:[String:String];let committedAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let receiptSHA256:String
    init(receiptID:UUID,workspaceID:WorkspaceID,draftID:UUID,sagaID:UUID,commitPlanSHA256:String,sagaEventSHA256Chain:[String],targetMutationID:MutationIDV1,targetReceiptSHA256:String,consumedStageToContentID:[String:String],committedAt:Date,revision:UInt64=1,mutationID:MutationIDV1)throws{self.receiptID=receiptID;self.workspaceID=workspaceID;self.draftID=draftID;self.sagaID=sagaID;self.commitPlanSHA256=commitPlanSHA256;self.sagaEventSHA256Chain=sagaEventSHA256Chain;self.targetMutationID=targetMutationID;self.targetReceiptSHA256=targetReceiptSHA256;self.consumedStageToContentID=consumedStageToContentID;self.committedAt=committedAt;self.revision=revision;self.mutationID=mutationID;receiptSHA256=try FieldDraftCanonicalCodecV1.sha256(Basis(receiptID:receiptID,workspaceID:workspaceID,draftID:draftID,sagaID:sagaID,commitPlanSHA256:commitPlanSHA256,sagaEventSHA256Chain:sagaEventSHA256Chain,targetMutationID:targetMutationID,targetReceiptSHA256:targetReceiptSHA256,consumedStageToContentID:consumedStageToContentID,committedAt:committedAt,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [receiptID,draftID,sagaID].forEach(FieldDraftValidationV1.id);try FieldDraftValidationV1.workspace(workspaceID);try FieldDraftValidationV1.digest(commitPlanSHA256);try sagaEventSHA256Chain.forEach(FieldDraftValidationV1.digest);try FieldDraftValidationV1.digest(targetReceiptSHA256);try FieldDraftValidationV1.instant(committedAt);try FieldDraftValidationV1.revision(revision);try consumedStageToContentID.forEach{try FieldDraftValidationV1.text($0.key);try FieldDraftValidationV1.text($0.value)};guard revision==1,!sagaEventSHA256Chain.isEmpty,Set(sagaEventSHA256Chain).count==sagaEventSHA256Chain.count,receiptSHA256==(try FieldDraftCanonicalCodecV1.sha256(basis))else{throw FieldDraftFailureV1.digestMismatch}}
    private var basis:Basis{.init(receiptID:receiptID,workspaceID:workspaceID,draftID:draftID,sagaID:sagaID,commitPlanSHA256:commitPlanSHA256,sagaEventSHA256Chain:sagaEventSHA256Chain,targetMutationID:targetMutationID,targetReceiptSHA256:targetReceiptSHA256,consumedStageToContentID:consumedStageToContentID,committedAt:committedAt,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let receiptID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let sagaID:UUID;let commitPlanSHA256:String;let sagaEventSHA256Chain:[String];let targetMutationID:MutationIDV1;let targetReceiptSHA256:String;let consumedStageToContentID:[String:String];let committedAt:Date;let revision:UInt64;let mutationID:MutationIDV1}}

struct DraftDiscardPlanV1:Codable,Equatable,Hashable,Sendable{let planID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let expectedDraftRevision:UInt64;let nonemptyPayload:Bool;let stageIDs:[UUID];let reservationIDs:[UUID];let estimatedBytes:Int64;let planSHA256:String
    init(planID:UUID,workspaceID:WorkspaceID,draftID:UUID,expectedDraftRevision:UInt64,nonemptyPayload:Bool,stageIDs:[UUID],reservationIDs:[UUID],estimatedBytes:Int64)throws{let s=stageIDs.sorted{$0.uuidString<$1.uuidString},r=reservationIDs.sorted{$0.uuidString<$1.uuidString};self.planID=planID;self.workspaceID=workspaceID;self.draftID=draftID;self.expectedDraftRevision=expectedDraftRevision;self.nonemptyPayload=nonemptyPayload;self.stageIDs=s;self.reservationIDs=r;self.estimatedBytes=estimatedBytes;planSHA256=try FieldDraftCanonicalCodecV1.sha256(Basis(planID:planID,workspaceID:workspaceID,draftID:draftID,expectedDraftRevision:expectedDraftRevision,nonemptyPayload:nonemptyPayload,stageIDs:s,reservationIDs:r,estimatedBytes:estimatedBytes));try validate()}
    func validate()throws{try [planID,draftID].forEach(FieldDraftValidationV1.id);try FieldDraftValidationV1.workspace(workspaceID);try FieldDraftValidationV1.revision(expectedDraftRevision);guard estimatedBytes>=0,stageIDs.count<=FieldDraftLimitsV1.maximumStageItems,Set(stageIDs).count==stageIDs.count,Set(reservationIDs).count==reservationIDs.count,planSHA256==(try FieldDraftCanonicalCodecV1.sha256(basis))else{throw FieldDraftFailureV1.digestMismatch}}
    private var basis:Basis{.init(planID:planID,workspaceID:workspaceID,draftID:draftID,expectedDraftRevision:expectedDraftRevision,nonemptyPayload:nonemptyPayload,stageIDs:stageIDs,reservationIDs:reservationIDs,estimatedBytes:estimatedBytes)};private struct Basis:Codable{let planID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let expectedDraftRevision:UInt64;let nonemptyPayload:Bool;let stageIDs:[UUID];let reservationIDs:[UUID];let estimatedBytes:Int64}}
struct DraftDiscardReceiptV1:Codable,Equatable,Hashable,Sendable{let receiptID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let planSHA256:String;let disposedStageIDs:[UUID];let quarantinedReservationIDs:[UUID];let discardedAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let receiptSHA256:String
    init(receiptID:UUID,workspaceID:WorkspaceID,draftID:UUID,planSHA256:String,disposedStageIDs:[UUID],quarantinedReservationIDs:[UUID],discardedAt:Date,revision:UInt64=1,mutationID:MutationIDV1)throws{let s=disposedStageIDs.sorted{$0.uuidString<$1.uuidString},r=quarantinedReservationIDs.sorted{$0.uuidString<$1.uuidString};self.receiptID=receiptID;self.workspaceID=workspaceID;self.draftID=draftID;self.planSHA256=planSHA256;self.disposedStageIDs=s;self.quarantinedReservationIDs=r;self.discardedAt=discardedAt;self.revision=revision;self.mutationID=mutationID;receiptSHA256=try FieldDraftCanonicalCodecV1.sha256(Basis(receiptID:receiptID,workspaceID:workspaceID,draftID:draftID,planSHA256:planSHA256,disposedStageIDs:s,quarantinedReservationIDs:r,discardedAt:discardedAt,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [receiptID,draftID].forEach(FieldDraftValidationV1.id);try FieldDraftValidationV1.workspace(workspaceID);try FieldDraftValidationV1.digest(planSHA256);try FieldDraftValidationV1.instant(discardedAt);guard revision==1,Set(disposedStageIDs).count==disposedStageIDs.count,Set(quarantinedReservationIDs).count==quarantinedReservationIDs.count,receiptSHA256==(try FieldDraftCanonicalCodecV1.sha256(basis))else{throw FieldDraftFailureV1.digestMismatch}}
    private var basis:Basis{.init(receiptID:receiptID,workspaceID:workspaceID,draftID:draftID,planSHA256:planSHA256,disposedStageIDs:disposedStageIDs,quarantinedReservationIDs:quarantinedReservationIDs,discardedAt:discardedAt,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let receiptID:UUID;let workspaceID:WorkspaceID;let draftID:UUID;let planSHA256:String;let disposedStageIDs:[UUID];let quarantinedReservationIDs:[UUID];let discardedAt:Date;let revision:UInt64;let mutationID:MutationIDV1}}

struct DraftCommitTerminalBundleV1:Codable,Equatable,Sendable{
    let retiredSaga:DraftCommitSagaV1;let committedCheckpoint:FieldDraftCheckpointV1;let receipt:DraftCommitReceiptV1
    var workspaceID:WorkspaceID{receipt.workspaceID};var mutationID:MutationIDV1{receipt.mutationID}
    init(retiredSaga:DraftCommitSagaV1,committedCheckpoint:FieldDraftCheckpointV1,receipt:DraftCommitReceiptV1)throws{self.retiredSaga=retiredSaga;self.committedCheckpoint=committedCheckpoint;self.receipt=receipt;try validate()}
    func validate()throws{try retiredSaga.validate();try committedCheckpoint.validate();try receipt.validate();guard retiredSaga.state == .draftRetired,retiredSaga.workspaceID==workspaceID,committedCheckpoint.workspaceID==workspaceID,retiredSaga.draftID==receipt.draftID,committedCheckpoint.draftID==receipt.draftID,receipt.sagaID==retiredSaga.sagaID,receipt.commitPlanSHA256==retiredSaga.plan.planSHA256,receipt.targetMutationID==retiredSaga.plan.mutationID,receipt.sagaEventSHA256Chain.count==5,receipt.sagaEventSHA256Chain.last==retiredSaga.sagaSHA256,retiredSaga.mutationID==mutationID,committedCheckpoint.mutationID==mutationID,committedCheckpoint.lastDurableMutationID==mutationID,committedCheckpoint.lastReceiptSHA256==receipt.receiptSHA256,committedCheckpoint.state == .committed else{throw FieldDraftFailureV1.invalidTransition}}
}
struct DraftDiscardTerminalBundleV1:Codable,Equatable,Sendable{
    let discardedCheckpoint:FieldDraftCheckpointV1;let receipt:DraftDiscardReceiptV1
    var workspaceID:WorkspaceID{receipt.workspaceID};var mutationID:MutationIDV1{receipt.mutationID}
    init(discardedCheckpoint:FieldDraftCheckpointV1,receipt:DraftDiscardReceiptV1)throws{self.discardedCheckpoint=discardedCheckpoint;self.receipt=receipt;try validate()}
    func validate()throws{try discardedCheckpoint.validate();try receipt.validate();guard discardedCheckpoint.workspaceID==workspaceID,discardedCheckpoint.draftID==receipt.draftID,discardedCheckpoint.mutationID==mutationID,discardedCheckpoint.lastDurableMutationID==mutationID,discardedCheckpoint.lastReceiptSHA256==receipt.receiptSHA256,discardedCheckpoint.state == .discarded else{throw FieldDraftFailureV1.invalidTransition}}
}

enum DraftRecoveryStatusV1:String,CaseIterable,Codable,Hashable,Sendable{case resumable="RESUMABLE",conflict="CONFLICT",missingMedia="MISSING_MEDIA",lowStorage="LOW_STORAGE",protectedData="PROTECTED_DATA",unsupportedCodec="UNSUPPORTED_CODEC",partialStage="PARTIAL_STAGE",staleTarget="STALE_TARGET",recoveryRequired="RECOVERY_REQUIRED"}
enum DraftRecoverySafeActionV1:String,CaseIterable,Codable,Hashable,Sendable{case resumeReview="RESUME_REVIEW",reviewConflict="REVIEW_CONFLICT",retryItem="RETRY_ITEM",freeStorage="FREE_STORAGE",unlockDevice="UNLOCK_DEVICE",discard="DISCARD",openSafeParent="OPEN_SAFE_PARENT"}
struct DraftRecoveryProjectionV1:Equatable,Hashable,Sendable{let workspaceID:WorkspaceID;let draftID:UUID;let purpose:DraftPurposeV1;let status:DraftRecoveryStatusV1;let safeAction:DraftRecoverySafeActionV1;let readyItemCount:Int;let failedItemCount:Int;let missingItemCount:Int;let updatedAt:Date}
enum DraftLifecycleDispositionV1:String,CaseIterable,Codable,Hashable,Sendable{case persistentWorkspaceOperational="PERSISTENT_WORKSPACE_OPERATIONAL",safeResumeDerivedOnly="SAFE_RESUME_DERIVED_ONLY",excludedFromCanonicalTruth="EXCLUDED_FROM_CANONICAL_TRUTH"}
struct DraftAutosavePolicyV1:Codable,Equatable,Hashable,Sendable{static let trailingNanoseconds:UInt64=750_000_000;static let maximumDirtyNanoseconds:UInt64=5_000_000_000;let trailingNanoseconds:UInt64;let maximumDirtyNanoseconds:UInt64;init(trailingNanoseconds:UInt64=Self.trailingNanoseconds,maximumDirtyNanoseconds:UInt64=Self.maximumDirtyNanoseconds)throws{guard trailingNanoseconds>0,trailingNanoseconds<=750_000_000,maximumDirtyNanoseconds>=trailingNanoseconds,maximumDirtyNanoseconds<=5_000_000_000 else{throw FieldDraftFailureV1.invalidValue};self.trailingNanoseconds=trailingNanoseconds;self.maximumDirtyNanoseconds=maximumDirtyNanoseconds}}

/// Drafts are workspace-operational state. They are deliberately absent from a
/// configuration-only clone and require explicit review after a workspace restore.
enum DraftConfigurationCloneDispositionV1:String,Codable,Hashable,Sendable{
    case excludedFromConfigurationClone="EXCLUDED_FROM_CONFIGURATION_CLONE"
    case restoreRequiresUserReview="RESTORE_REQUIRES_USER_REVIEW"
}


// MARK: - C33 temporal evidence draft adoption

enum TemporalEvidenceDraftAdoptionBoundaryV1 {
    static let stageIsCanonicalClip = false
    static let reservationIsCanonicalClip = false
    static let explicitReviewRequired = true

    static func validate(reservation: DraftContentReservationV1,
                         clip: TemporalEvidenceClipV1) throws {
        try reservation.validate(); try clip.validateIntrinsic()
        guard reservation.workspaceID == clip.workspaceID,
              reservation.locator == clip.locator,
              reservation.contentDigest
                == clip.original.digests.digest(for: reservation.contentDigest.algorithm),
              reservation.reconciliationState == .associated,
              explicitReviewRequired, !stageIsCanonicalClip,
              !reservationIsCanonicalClip else { throw FieldDraftFailureV1.invalidValue }
    }
}

/// A restore supplies the complete, deterministic identity map. No UUID is
/// generated while decoding or rebinding, so retrying the same restore is byte stable.
struct DraftRestoreIdentityMapV1:Codable,Equatable,Sendable{
    let targetWorkspaceID:WorkspaceID
    let draftIDs:[UUID:UUID]
    let stageIDs:[UUID:UUID]
    let sagaIDs:[UUID:UUID]
    let reservationIDs:[UUID:UUID]
    let receiptIDs:[UUID:UUID]
    let disposition:DraftConfigurationCloneDispositionV1
    init(targetWorkspaceID:WorkspaceID,draftIDs:[UUID:UUID],stageIDs:[UUID:UUID],sagaIDs:[UUID:UUID],reservationIDs:[UUID:UUID],receiptIDs:[UUID:UUID],disposition:DraftConfigurationCloneDispositionV1 = .restoreRequiresUserReview)throws{self.targetWorkspaceID=targetWorkspaceID;self.draftIDs=draftIDs;self.stageIDs=stageIDs;self.sagaIDs=sagaIDs;self.reservationIDs=reservationIDs;self.receiptIDs=receiptIDs;self.disposition=disposition;try validate()}
    func validate()throws{try FieldDraftValidationV1.workspace(targetWorkspaceID);guard disposition == .restoreRequiresUserReview else{throw FieldDraftFailureV1.invalidValue};for map in [draftIDs,stageIDs,sagaIDs,reservationIDs,receiptIDs]{try map.keys.forEach(FieldDraftValidationV1.id);try map.values.forEach(FieldDraftValidationV1.id);guard Set(map.values).count==map.count else{throw FieldDraftFailureV1.invalidValue}}}
    func draftID(_ source:UUID)throws->UUID{guard let value=draftIDs[source]else{throw FieldDraftFailureV1.invalidValue};return value}
    func stageID(_ source:UUID)throws->UUID{guard let value=stageIDs[source]else{throw FieldDraftFailureV1.invalidValue};return value}
    func sagaID(_ source:UUID)throws->UUID{guard let value=sagaIDs[source]else{throw FieldDraftFailureV1.invalidValue};return value}
    func reservationID(_ source:UUID)throws->UUID{guard let value=reservationIDs[source]else{throw FieldDraftFailureV1.invalidValue};return value}
    func receiptID(_ source:UUID)throws->UUID{guard let value=receiptIDs[source]else{throw FieldDraftFailureV1.invalidValue};return value}
}

extension FieldDraftCheckpointV1{
    func rebound(using map:DraftRestoreIdentityMapV1,scope:DraftScopeKeyV1,mutationID:MutationIDV1)throws->Self{try map.validate();return try .init(draftID:map.draftID(draftID),workspaceID:map.targetWorkspaceID,scope:scope,purpose:purpose,codec:codec,baseCanonicalRevision:baseCanonicalRevision,draftRevision:draftRevision,payloadData:payloadData,stageIDs:try stageIDs.map(map.stageID),resumeAnchor:resumeAnchor,state:.recoveryRequired,lastDurableMutationID:nil,lastReceiptSHA256:nil,updatedAt:updatedAt,mutationID:mutationID)}
}
extension AttachmentStagingItemV1{
    func rebound(using map:DraftRestoreIdentityMapV1,scratchLeaseID:UUID,contentReference:ContentReferenceV1?,processingJobID:UUID?,mutationID:MutationIDV1)throws->Self{try map.validate();return try .init(stageID:map.stageID(stageID),draftID:map.draftID(draftID),workspaceID:map.targetWorkspaceID,attachmentKind:attachmentKind,scratchLeaseID:scratchLeaseID,expectedByteCount:expectedByteCount,actualByteCount:actualByteCount,contentDigest:contentDigest,contentReference:contentReference,processingJobID:processingJobID,retryClass:retryClass,state:state,protectionState:protectionState,revision:revision,mutationID:mutationID)}
}
extension DraftCommitSagaV1{
    func rebound(using map:DraftRestoreIdentityMapV1,plan:DraftCommitPlanV1,mutationID:MutationIDV1)throws->Self{try map.validate();return try .init(sagaID:map.sagaID(sagaID),workspaceID:map.targetWorkspaceID,draftID:map.draftID(draftID),plan:plan,state:state,predecessorSagaID:try predecessorSagaID.map(map.sagaID),revision:revision,mutationID:mutationID,updatedAt:updatedAt)}
}
extension DraftCommitPlanV1{
    func rebound(using map:DraftRestoreIdentityMapV1,planID:UUID,stageDigests:[String],expectedTargetRevision:UInt64,mutationID:MutationIDV1,outputKeys:[String])throws->Self{try map.validate();return try .init(planID:planID,workspaceID:map.targetWorkspaceID,draftID:map.draftID(draftID),draftRevision:draftRevision,baseCanonicalRevision:baseCanonicalRevision,payloadSHA256:payloadSHA256,stageDigests:stageDigests,targetCommandKind:targetCommandKind,expectedTargetRevision:expectedTargetRevision,mutationID:mutationID,outputKeys:outputKeys)}
}
extension DraftContentReservationV1{
    func rebound(using map:DraftRestoreIdentityMapV1,commitPlanSHA256:String,contentDigest:ContentDigestV1,locator:ContentLocatorV1,mutationID:MutationIDV1)throws->Self{try map.validate();return try .init(reservationID:map.reservationID(reservationID),workspaceID:map.targetWorkspaceID,draftID:map.draftID(draftID),stageID:map.stageID(stageID),commitPlanSHA256:commitPlanSHA256,mutationID:mutationID,contentDigest:contentDigest,locator:locator,createdAt:createdAt,reviewAfter:reviewAfter,reconciliationState:.orphanQuarantined,revision:revision)}
}
extension DraftCommitReceiptV1{
    func rebound(using map:DraftRestoreIdentityMapV1,commitPlanSHA256:String,sagaEventSHA256Chain:[String],targetMutationID:MutationIDV1,targetReceiptSHA256:String,consumedStageToContentID:[String:String],mutationID:MutationIDV1)throws->Self{try map.validate();return try .init(receiptID:map.receiptID(receiptID),workspaceID:map.targetWorkspaceID,draftID:map.draftID(draftID),sagaID:map.sagaID(sagaID),commitPlanSHA256:commitPlanSHA256,sagaEventSHA256Chain:sagaEventSHA256Chain,targetMutationID:targetMutationID,targetReceiptSHA256:targetReceiptSHA256,consumedStageToContentID:consumedStageToContentID,committedAt:committedAt,revision:revision,mutationID:mutationID)}
}
extension DraftDiscardReceiptV1{
    func rebound(using map:DraftRestoreIdentityMapV1,planSHA256:String,mutationID:MutationIDV1)throws->Self{try map.validate();return try .init(receiptID:map.receiptID(receiptID),workspaceID:map.targetWorkspaceID,draftID:map.draftID(draftID),planSHA256:planSHA256,disposedStageIDs:try disposedStageIDs.map(map.stageID),quarantinedReservationIDs:try quarantinedReservationIDs.map(map.reservationID),discardedAt:discardedAt,revision:revision,mutationID:mutationID)}
}
extension DraftDiscardPlanV1{
    func rebound(using map:DraftRestoreIdentityMapV1,planID:UUID,estimatedBytes:Int64)throws->Self{try map.validate();return try .init(planID:planID,workspaceID:map.targetWorkspaceID,draftID:map.draftID(draftID),expectedDraftRevision:expectedDraftRevision,nonemptyPayload:nonemptyPayload,stageIDs:try stageIDs.map(map.stageID),reservationIDs:try reservationIDs.map(map.reservationID),estimatedBytes:estimatedBytes)}
}

private protocol FieldDraftValidatableV1{func validate()throws}
extension FieldDraftCheckpointV1:FieldDraftValidatableV1{};extension AttachmentStagingItemV1:FieldDraftValidatableV1{};extension DraftCommitSagaV1:FieldDraftValidatableV1{};extension DraftContentReservationV1:FieldDraftValidatableV1{};extension DraftCommitReceiptV1:FieldDraftValidatableV1{};extension DraftDiscardReceiptV1:FieldDraftValidatableV1{};extension DraftCommitTerminalBundleV1:FieldDraftValidatableV1{};extension DraftDiscardTerminalBundleV1:FieldDraftValidatableV1{}
enum FieldDraftCanonicalCodecV1{static func encode<T:Encodable>(_ value:T)throws->Data{try WorkspaceMutationCanonicalV1.data(value)}static func sha256(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}static func sha256<T:Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)}static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=FieldDraftLimitsV1.maximumCanonicalBytes else{throw FieldDraftFailureV1.limitExceeded};let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970;let value=try decoder.decode(type,from:data);if let v=value as? any FieldDraftValidatableV1{try v.validate()};guard try encode(value)==data else{throw FieldDraftFailureV1.digestMismatch};return value}}

// MARK: - C23 field-reference binding at the round-session boundary

/// A draft carries only a derived reference projection. The durable release
/// and binding rows remain in the FieldReferencePack family and are never
/// duplicated in the draft checkpoint schema.
struct FieldDraftReferenceProjectionV1: Codable, Equatable, Hashable, Sendable {
    let draftID: UUID
    let draftRevision: UInt64
    let draftState: FieldDraftStateV1
    let reference: WorkSessionFieldReferenceProjectionV1

    init(
        checkpoint: FieldDraftCheckpointV1,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws {
        try checkpoint.validate()
        let subjectState: FieldReferenceSubjectStateV1
        switch checkpoint.state {
        case .committed, .discarded:
            subjectState = .finalized
        case .active, .committing, .conflicted, .recoveryRequired, .discardPending:
            subjectState = .active
        }
        guard binding.subjectKind == .roundSession,
              binding.subjectID == checkpoint.draftID,
              binding.subjectRevision == checkpoint.draftRevision,
              binding.subjectState == subjectState else {
            throw FieldDraftFailureV1.staleDraftRevision
        }
        let value = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try value.validate(
            expectedWorkspaceID: checkpoint.workspaceID,
            expectedSubjectKind: .roundSession,
            expectedSubjectID: checkpoint.draftID,
            expectedSubjectRevision: checkpoint.draftRevision,
            expectedSubjectState: subjectState
        )
        draftID = checkpoint.draftID
        draftRevision = checkpoint.draftRevision
        draftState = checkpoint.state
        reference = value
    }

    func validate() throws {
        try reference.validate(
            expectedWorkspaceID: reference.workspaceID,
            expectedSubjectKind: .roundSession,
            expectedSubjectID: draftID,
            expectedSubjectRevision: draftRevision,
            expectedSubjectState: draftState == .committed || draftState == .discarded
                ? .finalized : .active
        )
    }
}

enum FieldDraftReferenceBindingPolicyV1 {
    static let persistentFamilies = FieldReferencePackLifecycleV1.persistentFamilies
    static let projectionPersistence = "DERIVED_ONLY"
    static let silentRebindAllowed = false

    static func subjectState(for state: FieldDraftStateV1) -> FieldReferenceSubjectStateV1 {
        switch state {
        case .committed, .discarded: return .finalized
        default: return .active
        }
    }
}

extension FieldDraftCheckpointV1 {
    func c23ReferenceProjection(
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws -> FieldDraftReferenceProjectionV1 {
        try FieldDraftReferenceProjectionV1(
            checkpoint: self,
            binding: binding,
            release: release,
            readiness: readiness
        )
    }

    func c23ValidateReferenceSuccessor(
        from predecessor: FieldReferenceBindingV1,
        to successor: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws -> FieldDraftReferenceProjectionV1 {
        guard state != .committed, state != .discarded else {
            throw FieldDraftFailureV1.invalidTransition
        }
        try WorkSessionFieldReferenceBindingV1.validateSuccessor(
            successor, release: release, after: predecessor
        )
        return try FieldDraftReferenceProjectionV1(
            checkpoint: self,
            binding: successor,
            release: release,
            readiness: readiness
        )
    }
}

/// C18 is a nonpersistent preview consumer of C36. It may create exactly one
/// active-checkpoint CAS successor and owns no draft row, store or writer.
enum PackageEvolutionDraftBoundaryV1 {
    static let planPersistence = "NONPERSISTENT"
    static let eligibleSourceState = FieldDraftStateV1.active
    static let writer = "EXISTING_C36_FIELD_DRAFT_WRITER"

    static func validateSource(_ checkpoint: FieldDraftCheckpointV1) throws {
        try checkpoint.validate()
        guard checkpoint.state == eligibleSourceState else {
            throw PackageEvolutionFailureV1.ineligibleDraft
        }
    }

    /// C21 capability admission is a preview input.  It authorizes the one
    /// safe draft migration operation, while the only durable result remains
    /// the existing checkpoint CAS successor.
    static func validateUpgradeAdmission(
        source: FieldDraftCheckpointV1,
        admittedBy capability: ClientCapabilityLifecycleClosureV1
    ) throws {
        try validateSource(source)
        try C21CapabilityAdmissionBoundaryV1.validate(
            capability,
            for: .upgradeDraft,
            historic: false
        )
        guard capability.policy.workspaceID == source.workspaceID,
              capability.decision.workspaceID == source.workspaceID,
              capability.decision.admission == .readWrite
                || capability.decision.admission == .migrationRequired else {
            throw ClientCapabilityFailureV1.admissionDenied
        }
    }

    static func validateUpgradePreview(
        plan: DraftUpgradePlanV1,
        source: FieldDraftCheckpointV1,
        diff: PackageSemanticDiffV1,
        admittedBy capability: ClientCapabilityLifecycleClosureV1
    ) throws {
        try validateUpgradeAdmission(source: source, admittedBy: capability)
        try plan.validate(source: source, diff: diff)
        guard plan.workspaceID == source.workspaceID,
              plan.targetPackageReleaseID == capability.release.packageReleaseID,
              capability.decision.packageReleaseID == capability.release.packageReleaseID,
              capability.decision.packageSHA256 == capability.release.packageSHA256,
              capability.decision.workflowSHA256 == capability.release.workflowSHA256 else {
            throw PackageEvolutionFailureV1.staleSource
        }
    }
}

/// Shared C21 operation matrix for draft, workflow, and package-evolution
/// consumers.  The evaluator remains the sole source of an admission; this
/// boundary only proves that a persisted decision is current and safe for the
/// requested operation.
enum C21CapabilityAdmissionBoundaryV1 {
    static func validate(
        _ capability: ClientCapabilityLifecycleClosureV1,
        for operation: PackageLifecycleOperationV1? = nil,
        historic: Bool = false
    ) throws {
        try capability.validate()
        let requestedOperation = operation ?? capability.decision.operation
        guard capability.decision.operation == requestedOperation else {
            throw ClientCapabilityFailureV1.staleReference
        }

        let expected = ClientCapabilityAdmissionEvaluatorV1.evaluate(
            profile: capability.profile,
            policy: capability.policy,
            disposition: capability.disposition,
            release: capability.release,
            operation: requestedOperation
        )
        guard capability.decision.admission == expected.0,
              capability.decision.reasons == expected.1.sorted(by: {
                  $0.rawValue < $1.rawValue
              }) else {
            throw ClientCapabilityFailureV1.admissionDenied
        }
        guard permits(
            capability.decision.admission,
            operation: requestedOperation,
            state: capability.disposition.state,
            historic: historic
        ) else {
            throw ClientCapabilityFailureV1.admissionDenied
        }
    }

    static func permits(
        _ admission: ClientAdmissionV1,
        operation: PackageLifecycleOperationV1,
        state: PackageLifecycleStateV1,
        historic: Bool = false
    ) -> Bool {
        switch state {
        case .quarantined, .superseded:
            return false
        case .withdrawn:
            guard historic,
                  [.view, .export, .restore, .replay].contains(operation) else {
                return false
            }
            // Withdrawn releases retain only their historic, non-mutating
            // read path; restore/replay are allowed solely for that history.
            return admission == .readOnly
        case .active, .deprecated:
            switch admission {
            case .readWrite:
                return true
            case .readOnly:
                return [.view, .export].contains(operation)
            case .migrationRequired:
                return operation == .upgradeDraft
            case .quarantine, .reject:
                return false
            }
        }
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Drafts_FieldDraftContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_Drafts_FieldDraftContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift", role: .draft)
}

enum C31LightingDraftBoundaryV1 {
    static let draftLightingEditsAreNotCompletedEvidence = true
    static let draftPreviewIsNotAppliedState = true
    static let draftLabelsRemainNoncanonical = true
}
// MARK: - C32 assistance field draft boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Drafts_FieldDraftContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let manualFallbackRemainsEquivalentDraftInput = true

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

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row160 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Drafts_FieldDraftContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C34DraftRouteSemanticIDAdapterV1 {
    static let routeAnchorType = FieldPositionAnchorV1.self
    static let routeStoresDraftValues = false

    static func fieldPosition(from anchor: DraftResumeAnchorV1) throws -> FieldPositionAnchorV1 {
        try anchor.validate()
        return try FieldPositionAnchorV1(
            sectionID: anchor.sectionID,
            fieldID: anchor.fieldID,
            selectedStableID: anchor.selectedStableID,
            boundedPosition: anchor.boundedPosition
        )
    }
}

enum C34RouteAdoptionBoundary_FieldDraftContractsV1 {
    static let draftAnchorType = DraftResumeAnchorV1.self
    static let routeAnchorType = FieldPositionAnchorV1.self
    static let routeCarriesSemanticIDsOnly = true
}

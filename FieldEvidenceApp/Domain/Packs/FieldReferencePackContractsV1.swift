import Foundation

enum FieldReferencePackFailureV1:Error,Equatable,Sendable{case invalidValue,invalidDigest,wrongWorkspace,wrongRelease,missingContent,staleBinding,restrictedContent,unsupported,divergentRetry,invalidSuccessor,finalizedWorkImmutable}
enum FieldReferenceKindV1:String,CaseIterable,Codable,Hashable,Sendable{case sop="SOP",manual="MANUAL",drawing="DRAWING",specification="SPECIFICATION"}
enum FieldReferenceProvenanceKindV1:String,CaseIterable,Codable,Hashable,Sendable{case licensed="LICENSED",synthetic="SYNTHETIC"}
enum FieldReferenceLicenseScopeV1:String,CaseIterable,Codable,Hashable,Sendable{case localUseOnly="LOCAL_USE_ONLY",citationAllowed="CITATION_ALLOWED",citationAndExportAllowed="CITATION_AND_EXPORT_ALLOWED",restricted="RESTRICTED"}
enum FieldReferenceReleaseDispositionV1:String,CaseIterable,Codable,Hashable,Sendable{case active="ACTIVE",revoked="REVOKED"}
enum FieldReferenceSubjectKindV1:String,CaseIterable,Codable,Hashable,Sendable{case workPacket="WORK_PACKET",roundSession="ROUND_SESSION"}
enum FieldReferenceSubjectStateV1:String,CaseIterable,Codable,Hashable,Sendable{case active="ACTIVE",finalized="FINALIZED"}
enum FieldReferenceAvailabilityV1:String,CaseIterable,Codable,Hashable,Sendable{case readyOffline="READY_OFFLINE",missingBytes="MISSING_BYTES",expired="EXPIRED",revoked="REVOKED",superseded="SUPERSEDED",staleBinding="STALE_BINDING",protectedDataUnavailable="PROTECTED_DATA_UNAVAILABLE",unavailable="UNAVAILABLE"}
enum FieldReferenceReadinessPolicyV1:String,CaseIterable,Codable,Hashable,Sendable{case exactLocalContentV1="EXACT_LOCAL_CONTENT_V1"}

enum FieldReferenceValidationV1{
    static let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    static func token(_ v:String)throws{guard ContentContractValidationV1.validID(v),v.utf8.count<=256 else{throw FieldReferencePackFailureV1.invalidValue}}
    static func text(_ v:String)throws{let t=v.trimmingCharacters(in:.whitespacesAndNewlines);guard v==t,!v.isEmpty,v.utf8.count<=512,v.unicodeScalars.allSatisfy({!CharacterSet.controlCharacters.contains($0)})else{throw FieldReferencePackFailureV1.invalidValue}}
    static func digest(_ v:String)throws{guard KernelCanonicalHashV1.validSHA256(v)else{throw FieldReferencePackFailureV1.invalidDigest}}
    static func workspaceString(_ id:WorkspaceID)->String{id.rawValue.uuidString.lowercased()}
}

struct FieldReferenceProvenanceV1:Codable,Equatable,Hashable,Sendable{
    let kind:FieldReferenceProvenanceKindV1;let sourceName:String;let sourceReleaseIdentifier:String;let licenseScope:FieldReferenceLicenseScopeV1;let licenseNotice:String?;let authorityClaimed:Bool
    init(kind:FieldReferenceProvenanceKindV1,sourceName:String,sourceReleaseIdentifier:String,licenseScope:FieldReferenceLicenseScopeV1,licenseNotice:String?=nil)throws{try FieldReferenceValidationV1.text(sourceName);try FieldReferenceValidationV1.token(sourceReleaseIdentifier);if let licenseNotice{try FieldReferenceValidationV1.text(licenseNotice)};guard !(kind == .licensed && licenseNotice == nil)else{throw FieldReferencePackFailureV1.invalidValue};self.kind=kind;self.sourceName=sourceName;self.sourceReleaseIdentifier=sourceReleaseIdentifier;self.licenseScope=licenseScope;self.licenseNotice=licenseNotice;authorityClaimed=false}
    func validate()throws{try FieldReferenceValidationV1.text(sourceName);try FieldReferenceValidationV1.token(sourceReleaseIdentifier);if let licenseNotice{try FieldReferenceValidationV1.text(licenseNotice)};guard !authorityClaimed,kind != .licensed || licenseNotice != nil else{throw FieldReferencePackFailureV1.invalidValue}}
}

struct FieldReferenceReleaseV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let referencePackID:String;let kind:FieldReferenceKindV1;let semanticVersion:String;let provenance:FieldReferenceProvenanceV1;let manifest:ContentManifestV1;let manifestSHA256:String;let releaseDisposition:FieldReferenceReleaseDispositionV1;let issuedAt:Date;let expiresAt:Date?;let revokedAt:Date?;let supersedesReleaseID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let releaseSHA256:String
    init(releaseID:UUID,workspaceID:WorkspaceID,referencePackID:String,kind:FieldReferenceKindV1,semanticVersion:String,provenance:FieldReferenceProvenanceV1,manifest:ContentManifestV1,releaseDisposition:FieldReferenceReleaseDispositionV1=.active,issuedAt:Date,expiresAt:Date?=nil,revokedAt:Date?=nil,supersedesReleaseID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{try FieldReferenceValidationV1.token(referencePackID);try FieldReferenceValidationV1.token(semanticVersion);try provenance.validate();let manifestDigest=try WorkspaceMutationCanonicalV1.sha256(manifest);schemaVersion=Self.schemaVersion;self.releaseID=releaseID;self.workspaceID=workspaceID;self.referencePackID=referencePackID;self.kind=kind;self.semanticVersion=semanticVersion;self.provenance=provenance;self.manifest=manifest;manifestSHA256=manifestDigest;self.releaseDisposition=releaseDisposition;self.issuedAt=issuedAt;self.expiresAt=expiresAt;self.revokedAt=revokedAt;self.supersedesReleaseID=supersedesReleaseID;self.revision=revision;self.mutationID=mutationID;releaseSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,releaseID:releaseID,workspaceID:workspaceID,referencePackID:referencePackID,kind:kind,semanticVersion:semanticVersion,provenance:provenance,manifest:manifest,manifestSHA256:manifestDigest,releaseDisposition:releaseDisposition,issuedAt:issuedAt,expiresAt:expiresAt,revokedAt:revokedAt,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try FieldReferenceValidationV1.token(referencePackID);try FieldReferenceValidationV1.token(semanticVersion);try provenance.validate();let expectedManifest=try WorkspaceMutationCanonicalV1.sha256(manifest);guard schemaVersion==Self.schemaVersion,releaseID != FieldReferenceValidationV1.zero,manifest.workspaceID==FieldReferenceValidationV1.workspaceString(workspaceID),!manifest.entries.isEmpty,manifest.entries.allSatisfy(\.requiredForOpen),manifestSHA256==expectedManifest,revision>0,(supersedesReleaseID==nil)==(revision==1),expiresAt.map{$0>issuedAt} ?? true,(releaseDisposition == .revoked)==(revokedAt != nil),revokedAt.map{$0>=issuedAt} ?? true,releaseSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw FieldReferencePackFailureV1.invalidDigest}}
    func validateContent(references:[ContentReferenceV1],locators:[ContentLocatorV1])throws{try validate();try manifest.validateOpenability(references:references,locators:locators);guard references.count==manifest.entries.count,references.allSatisfy({$0.byteRole == .immutableOriginal})else{throw FieldReferencePackFailureV1.missingContent}}
    func validateSuccessor(of old:Self)throws{try validate();try old.validate();guard releaseID != old.releaseID,supersedesReleaseID==old.releaseID,workspaceID==old.workspaceID,referencePackID==old.referencePackID,mutationID != old.mutationID,old.revision<UInt64.max,revision==old.revision+1 else{throw FieldReferencePackFailureV1.invalidSuccessor}}
    func rebound(to workspaceID:WorkspaceID,manifest:ContentManifestV1)throws->Self{try .init(releaseID:releaseID,workspaceID:workspaceID,referencePackID:referencePackID,kind:kind,semanticVersion:semanticVersion,provenance:provenance,manifest:manifest,releaseDisposition:releaseDisposition,issuedAt:issuedAt,expiresAt:expiresAt,revokedAt:revokedAt,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,releaseID:releaseID,workspaceID:workspaceID,referencePackID:referencePackID,kind:kind,semanticVersion:semanticVersion,provenance:provenance,manifest:manifest,manifestSHA256:manifestSHA256,releaseDisposition:releaseDisposition,issuedAt:issuedAt,expiresAt:expiresAt,revokedAt:revokedAt,supersedesReleaseID:supersedesReleaseID,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let referencePackID:String;let kind:FieldReferenceKindV1;let semanticVersion:String;let provenance:FieldReferenceProvenanceV1;let manifest:ContentManifestV1;let manifestSHA256:String;let releaseDisposition:FieldReferenceReleaseDispositionV1;let issuedAt:Date;let expiresAt:Date?;let revokedAt:Date?;let supersedesReleaseID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct FieldReferenceBindingV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let bindingID:UUID;let workspaceID:WorkspaceID;let subjectKind:FieldReferenceSubjectKindV1;let subjectID:UUID;let subjectRevision:UInt64;let subjectState:FieldReferenceSubjectStateV1;let releaseID:UUID;let releaseRevision:UInt64;let releaseSHA256:String;let manifestSHA256:String;let boundAt:Date;let supersedesBindingID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let bindingSHA256:String
    init(bindingID:UUID,workspaceID:WorkspaceID,subjectKind:FieldReferenceSubjectKindV1,subjectID:UUID,subjectRevision:UInt64,subjectState:FieldReferenceSubjectStateV1,release:FieldReferenceReleaseV1,boundAt:Date,supersedesBindingID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{try release.validate();schemaVersion=Self.schemaVersion;self.bindingID=bindingID;self.workspaceID=workspaceID;self.subjectKind=subjectKind;self.subjectID=subjectID;self.subjectRevision=subjectRevision;self.subjectState=subjectState;releaseID=release.releaseID;releaseRevision=release.revision;releaseSHA256=release.releaseSHA256;manifestSHA256=release.manifestSHA256;self.boundAt=boundAt;self.supersedesBindingID=supersedesBindingID;self.revision=revision;self.mutationID=mutationID;bindingSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,bindingID:bindingID,workspaceID:workspaceID,subjectKind:subjectKind,subjectID:subjectID,subjectRevision:subjectRevision,subjectState:subjectState,releaseID:release.releaseID,releaseRevision:release.revision,releaseSHA256:release.releaseSHA256,manifestSHA256:release.manifestSHA256,boundAt:boundAt,supersedesBindingID:supersedesBindingID,revision:revision,mutationID:mutationID));try validate(release:release)}
    func validate(release:FieldReferenceReleaseV1)throws{try release.validate();try validateIntrinsic();guard workspaceID==release.workspaceID,releaseID==release.releaseID,releaseRevision==release.revision,releaseSHA256==release.releaseSHA256,manifestSHA256==release.manifestSHA256,release.releaseDisposition == .active,release.expiresAt.map({$0>boundAt}) ?? true else{throw FieldReferencePackFailureV1.wrongRelease}}
    func validateSuccessor(of old:Self,release:FieldReferenceReleaseV1)throws{try validate(release:release);try old.validateIntrinsic();guard old.subjectState != .finalized else{throw FieldReferencePackFailureV1.finalizedWorkImmutable};guard bindingID != old.bindingID,supersedesBindingID==old.bindingID,workspaceID==old.workspaceID,subjectKind==old.subjectKind,subjectID==old.subjectID,subjectRevision>=old.subjectRevision,mutationID != old.mutationID,old.revision<UInt64.max,revision==old.revision+1 else{throw FieldReferencePackFailureV1.invalidSuccessor}}
    func rebound(to workspaceID:WorkspaceID,release:FieldReferenceReleaseV1)throws->Self{try .init(bindingID:bindingID,workspaceID:workspaceID,subjectKind:subjectKind,subjectID:subjectID,subjectRevision:subjectRevision,subjectState:subjectState,release:release,boundAt:boundAt,supersedesBindingID:supersedesBindingID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,bindingID:bindingID,workspaceID:workspaceID,subjectKind:subjectKind,subjectID:subjectID,subjectRevision:subjectRevision,subjectState:subjectState,releaseID:releaseID,releaseRevision:releaseRevision,releaseSHA256:releaseSHA256,manifestSHA256:manifestSHA256,boundAt:boundAt,supersedesBindingID:supersedesBindingID,revision:revision,mutationID:mutationID)}
    private func validateIntrinsic()throws{guard schemaVersion==Self.schemaVersion,bindingID != FieldReferenceValidationV1.zero,subjectID != FieldReferenceValidationV1.zero,subjectRevision>0,revision>0,(supersedesBindingID==nil)==(revision==1),bindingSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw FieldReferencePackFailureV1.invalidDigest}}
    private struct Basis:Codable{let schemaVersion:Int;let bindingID:UUID;let workspaceID:WorkspaceID;let subjectKind:FieldReferenceSubjectKindV1;let subjectID:UUID;let subjectRevision:UInt64;let subjectState:FieldReferenceSubjectStateV1;let releaseID:UUID;let releaseRevision:UInt64;let releaseSHA256:String;let manifestSHA256:String;let boundAt:Date;let supersedesBindingID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct FieldReferenceReadinessInputsV1: Equatable, Sendable {
    let references: [ContentReferenceV1]
    let locators: [ContentLocatorV1]
    let knownSupersededReleaseIDs: Set<UUID>
    let knownRevokedReleaseIDs: Set<UUID>
    let evaluatedAt: Date
    let policy: FieldReferenceReadinessPolicyV1
    let protectedDataAvailable: Bool

    init(references:[ContentReferenceV1],locators:[ContentLocatorV1],knownSupersededReleaseIDs:Set<UUID>=[],knownRevokedReleaseIDs:Set<UUID>=[],evaluatedAt:Date,policy:FieldReferenceReadinessPolicyV1 = .exactLocalContentV1,protectedDataAvailable:Bool=true){self.references=references;self.locators=locators;self.knownSupersededReleaseIDs=knownSupersededReleaseIDs;self.knownRevokedReleaseIDs=knownRevokedReleaseIDs;self.evaluatedAt=evaluatedAt;self.policy=policy;self.protectedDataAvailable=protectedDataAvailable}
}

struct FieldReferenceOfflineReadinessV1:Equatable,Sendable{
    let workspaceID:WorkspaceID;let releaseID:UUID;let releaseRevision:UInt64;let releaseSHA256:String;let manifestSHA256:String;let bindingID:UUID;let bindingRevision:UInt64;let bindingSHA256:String;let availability:FieldReferenceAvailabilityV1;let missingContentIDs:[String];let evaluatedAt:Date;let policy:FieldReferenceReadinessPolicyV1;let readinessSHA256:String
    var checkedAt:Date{evaluatedAt}
    init(release:FieldReferenceReleaseV1,binding:FieldReferenceBindingV1,references:[ContentReferenceV1],locators:[ContentLocatorV1],knownSuccessorReleaseIDs:Set<UUID>,knownRevokedReleaseIDs:Set<UUID>=[],checkedAt:Date,policy:FieldReferenceReadinessPolicyV1 = .exactLocalContentV1,protectedDataAvailable:Bool=true)throws{try binding.validate(release:release);guard knownSuccessorReleaseIDs.count<=4096,knownRevokedReleaseIDs.count<=4096 else{throw FieldReferencePackFailureV1.invalidValue};let available=Set(references.map(\.contentID)),missing=release.manifest.entries.map(\.contentID).filter{!available.contains($0)}.sorted();let state:FieldReferenceAvailabilityV1;if !protectedDataAvailable{state = .protectedDataUnavailable}else if knownRevokedReleaseIDs.contains(release.releaseID){state = .revoked}else if release.expiresAt.map({$0<=checkedAt}) == true{state = .expired}else if knownSuccessorReleaseIDs.contains(release.releaseID){state = .superseded}else if !missing.isEmpty{state = .missingBytes}else{do{try release.validateContent(references:references,locators:locators);state = .readyOffline}catch{state = .unavailable}};workspaceID=release.workspaceID;releaseID=release.releaseID;releaseRevision=release.revision;releaseSHA256=release.releaseSHA256;manifestSHA256=release.manifestSHA256;bindingID=binding.bindingID;bindingRevision=binding.revision;bindingSHA256=binding.bindingSHA256;availability=state;missingContentIDs=missing;evaluatedAt=checkedAt;self.policy=policy;readinessSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID:release.workspaceID,releaseID:release.releaseID,releaseRevision:release.revision,releaseSHA256:release.releaseSHA256,manifestSHA256:release.manifestSHA256,bindingID:binding.bindingID,bindingRevision:binding.revision,bindingSHA256:binding.bindingSHA256,availability:state,missingContentIDs:missing,evaluatedAt:checkedAt,policy:policy))}
    init(release:FieldReferenceReleaseV1,binding:FieldReferenceBindingV1,inputs:FieldReferenceReadinessInputsV1)throws{try self.init(release:release,binding:binding,references:inputs.references,locators:inputs.locators,knownSuccessorReleaseIDs:inputs.knownSupersededReleaseIDs,knownRevokedReleaseIDs:inputs.knownRevokedReleaseIDs,checkedAt:inputs.evaluatedAt,policy:inputs.policy,protectedDataAvailable:inputs.protectedDataAvailable)}
    func validate(recomputedFrom inputs:FieldReferenceReadinessInputsV1,release:FieldReferenceReleaseV1,binding:FieldReferenceBindingV1)throws{let expected=try Self(release:release,binding:binding,inputs:inputs);guard self==expected else{throw FieldReferencePackFailureV1.staleBinding};try validate(release:release,binding:binding,expectedEvaluatedAt:inputs.evaluatedAt,expectedPolicy:inputs.policy)}
    func validate(release:FieldReferenceReleaseV1,binding:FieldReferenceBindingV1,expectedEvaluatedAt:Date,expectedPolicy:FieldReferenceReadinessPolicyV1 = .exactLocalContentV1)throws{try binding.validate(release:release);guard workspaceID==release.workspaceID,releaseID==release.releaseID,releaseRevision==release.revision,releaseSHA256==release.releaseSHA256,manifestSHA256==release.manifestSHA256,bindingID==binding.bindingID,bindingRevision==binding.revision,bindingSHA256==binding.bindingSHA256,evaluatedAt==expectedEvaluatedAt,policy==expectedPolicy,missingContentIDs==missingContentIDs.sorted(),Set(missingContentIDs).count==missingContentIDs.count,availability != .readyOffline || missingContentIDs.isEmpty,readinessSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw FieldReferencePackFailureV1.staleBinding}}
    private var basis:Basis{.init(workspaceID:workspaceID,releaseID:releaseID,releaseRevision:releaseRevision,releaseSHA256:releaseSHA256,manifestSHA256:manifestSHA256,bindingID:bindingID,bindingRevision:bindingRevision,bindingSHA256:bindingSHA256,availability:availability,missingContentIDs:missingContentIDs,evaluatedAt:evaluatedAt,policy:policy)}
    private struct Basis:Codable{let workspaceID:WorkspaceID;let releaseID:UUID;let releaseRevision:UInt64;let releaseSHA256:String;let manifestSHA256:String;let bindingID:UUID;let bindingRevision:UInt64;let bindingSHA256:String;let availability:FieldReferenceAvailabilityV1;let missingContentIDs:[String];let evaluatedAt:Date;let policy:FieldReferenceReadinessPolicyV1}}

struct FieldReferenceLifecycleClosureV1: Sendable {
    let release: FieldReferenceReleaseV1
    let binding: FieldReferenceBindingV1
    let references: [ContentReferenceV1]
    let locators: [ContentLocatorV1]

    func validate(knownSupersededReleaseIDs: Set<UUID> = [], checkedAt: Date) throws -> FieldReferenceOfflineReadinessV1 {
        try binding.validate(release: release)
        try release.validateContent(references: references, locators: locators)
        return try FieldReferenceOfflineReadinessV1(
            release: release, binding: binding, references: references, locators: locators,
            knownSuccessorReleaseIDs: knownSupersededReleaseIDs, checkedAt: checkedAt
        )
    }
}

/// Metadata-only citation. Restricted source bytes and locators never enter a
/// report/export projection.
struct FieldReferenceCitationV1: Codable, Equatable, Sendable {
    let releaseID: UUID
    let referencePackID: String
    let semanticVersion: String
    let sourceName: String
    let sourceReleaseIdentifier: String
    let notice: String?

    init(release: FieldReferenceReleaseV1) throws {
        try release.validate()
        guard release.provenance.licenseScope != .restricted else {
            throw FieldReferencePackFailureV1.restrictedContent
        }
        releaseID = release.releaseID
        referencePackID = release.referencePackID
        semanticVersion = release.semanticVersion
        sourceName = release.provenance.sourceName
        sourceReleaseIdentifier = release.provenance.sourceReleaseIdentifier
        notice = release.provenance.licenseNotice
    }
}

enum FieldReferencePackCanonicalCodecV1{static func encode<T:Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];e.dateEncodingStrategy = .millisecondsSince1970;let d=try e.encode(value);guard d.count<=4_194_304 else{throw FieldReferencePackFailureV1.invalidValue};return d}static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=4_194_304 else{throw FieldReferencePackFailureV1.invalidValue};let d=JSONDecoder();d.dateDecodingStrategy = .millisecondsSince1970;let v=try d.decode(type,from:data);guard try encode(v)==data else{throw FieldReferencePackFailureV1.invalidDigest};return v}}
enum FieldReferencePackLifecycleV1{static let persistentFamilies=["FieldReferenceReleaseV1","FieldReferenceBindingV1"];static let stagingPersistence="DERIVED_ONLY";static let runtimeFetchingAllowed=false;static let drmOrAccountRequired=false;static let currentProjectionPersistent=false;static let writer="SOLE_CANONICAL_WORKSPACE_WRITER"}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Packs_FieldReferencePackContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Packs_FieldReferencePackContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_Packs_FieldReferencePackContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Packs/FieldReferencePackContractsV1.swift", role: .pack)
}

enum C31LightingReferencePackBoundaryV1 {
    static let criterionTextIsReferencedByReleaseDigest = true
    static let packProjectionExcludesLicensedPayload = true
    static let unavailableReferenceRemainsExplicit = true
}
// MARK: - C32 assistance reference pack boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Packs_FieldReferencePackContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let packSourceDeletionExpiresProposal = true

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

enum C33TemporalEvidenceBoundary_Domain_Packs_FieldReferencePackContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

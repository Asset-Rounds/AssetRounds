import Foundation

enum WorkPacketScheduleBoundaryV1 { static let occurrenceLinkRequiresExplicitStart = true }

enum C51WorkPacketScheduleBoundaryV1 {
    static let scheduleClosureReferenceType = C51ScheduleClosureReferenceV1.self
    static let scheduleClosureMetadataType = C51ScheduleClosureMetadataV1.self
    static let scheduleClosureIsDerivedMetadataOnly = true
    static let workPacketOwnsNoOccurrenceHistory = true
    static let explicitOccurrenceStartRemainsCanonical = true

    static func validate(_ metadata: C51ScheduleClosureMetadataV1) throws {
        try metadata.validate()
    }
}

enum WorkPacketFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion, invalidValue, wrongWorkspace, digestMismatch
    case staleRevision, reorderedEvent, leaseExpired, holderMismatch
    case divergentReplay, simultaneousClaim, missingResult, limitExceeded
}

enum WorkPacketLimitsV1 {
    static let maximumItems = 512
    static let maximumRequirementsPerItem = 64
    static let maximumResultsPerOperation = 128
    static let maximumHistory = 8_192
    static let maximumTextBytes = 4_096
    static let maximumLeaseSeconds: TimeInterval = 7 * 24 * 60 * 60
    static let maximumCanonicalBytes = 16 * 1_024 * 1_024
}

private enum WorkPacketValidationV1 {
    static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    static func id(_ value: UUID) throws { guard value != zero else { throw WorkPacketFailureV1.invalidValue } }
    static func workspace(_ value: WorkspaceID) throws { guard value.rawValue != zero else { throw WorkPacketFailureV1.wrongWorkspace } }
    static func revision(_ value: UInt64) throws { guard value > 0 else { throw WorkPacketFailureV1.invalidValue } }
    static func next(_ predecessor: UInt64, _ successor: UInt64) throws { let next = predecessor.addingReportingOverflow(1); guard !next.overflow, successor == next.partialValue else { throw WorkPacketFailureV1.staleRevision } }
    static func text(_ value: String) throws { guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines), value.utf8.count <= WorkPacketLimitsV1.maximumTextBytes else { throw WorkPacketFailureV1.invalidValue } }
    static func digest(_ value: String) throws { guard MutationEnvelopeV1.isSHA256(value) else { throw WorkPacketFailureV1.digestMismatch } }
    static func instant(_ value: Date) throws { guard value.timeIntervalSinceReferenceDate.isFinite else { throw WorkPacketFailureV1.invalidValue } }
    static func actor(_ value: ActorSnapshotV1, responsibility: ResponsibilityKindV1, workspaceID: WorkspaceID) throws { try value.validate(); guard value.workspaceID == workspaceID, value.responsibility == responsibility else { throw WorkPacketFailureV1.holderMismatch } }
    static func rebound(_ value: ActorSnapshotV1, to workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(actorReferenceID: value.actor.actorReferenceID, workspaceID: workspaceID, partyID: value.actor.partyID, displayName: value.actor.displayName)
        return try ActorSnapshotV1(snapshotID: value.snapshotID, workspaceID: workspaceID, actor: reference, responsibility: value.responsibility, displayNameAtTime: value.displayNameAtTime, capturedAt: value.capturedAt)
    }
}

enum WorkPacketItemKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case inspection = "INSPECTION", correctiveAction = "CORRECTIVE_ACTION"
    case reviewChangeRequest = "REVIEW_CHANGE_REQUEST", operationalRecheck = "OPERATIONAL_RECHECK"
}

enum WorkPacketCreationBasisV1: String, CaseIterable, Codable, Hashable, Sendable {
    case explicitLocalSelection = "EXPLICIT_LOCAL_SELECTION"
    case deterministicDueProjection = "DETERMINISTIC_DUE_PROJECTION"
    case recordedReviewDisposition = "RECORDED_REVIEW_DISPOSITION"
}

struct WorkPacketPolicyReferenceV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let policyID: String; let policyRevision: UInt64; let policySHA256: String
    init(policyID: String, policyRevision: UInt64, policySHA256: String) throws { self.policyID=policyID;self.policyRevision=policyRevision;self.policySHA256=policySHA256;try validate() }
    func validate() throws { try WorkPacketValidationV1.text(policyID);try WorkPacketValidationV1.revision(policyRevision);try WorkPacketValidationV1.digest(policySHA256) }
    static func <(lhs:Self,rhs:Self)->Bool{(lhs.policyID,lhs.policyRevision,lhs.policySHA256)<(rhs.policyID,rhs.policyRevision,rhs.policySHA256)}
}

struct WorkPacketEvidenceRequirementV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let requirementID:String;let evidenceKind:ReviewEvidenceKindV1;let minimumCount:Int
    init(requirementID:String,evidenceKind:ReviewEvidenceKindV1,minimumCount:Int)throws{self.requirementID=requirementID;self.evidenceKind=evidenceKind;self.minimumCount=minimumCount;try validate()}
    func validate()throws{try WorkPacketValidationV1.text(requirementID);guard minimumCount>0,minimumCount<=WorkPacketLimitsV1.maximumResultsPerOperation else{throw WorkPacketFailureV1.invalidValue}}
    static func <(l:Self,r:Self)->Bool{l.requirementID<r.requirementID}
}

struct WorkPacketItemV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let itemID:String;let kind:WorkPacketItemKindV1;let expectedRevision:UInt64
    let itemSHA256:String;let policyReferences:[WorkPacketPolicyReferenceV1]
    let evidenceRequirements:[WorkPacketEvidenceRequirementV1]
    init(itemID:String,kind:WorkPacketItemKindV1,expectedRevision:UInt64,itemSHA256:String,policyReferences:[WorkPacketPolicyReferenceV1]=[],evidenceRequirements:[WorkPacketEvidenceRequirementV1]=[])throws{
        self.itemID=itemID;self.kind=kind;self.expectedRevision=expectedRevision;self.itemSHA256=itemSHA256
        self.policyReferences=policyReferences.sorted();self.evidenceRequirements=evidenceRequirements.sorted();try validate()
    }
    func validate()throws{try WorkPacketValidationV1.text(itemID);try WorkPacketValidationV1.revision(expectedRevision);try WorkPacketValidationV1.digest(itemSHA256);try policyReferences.forEach{try $0.validate()};try evidenceRequirements.forEach{try $0.validate()};guard policyReferences.count<=WorkPacketLimitsV1.maximumRequirementsPerItem,evidenceRequirements.count<=WorkPacketLimitsV1.maximumRequirementsPerItem,policyReferences==policyReferences.sorted(),evidenceRequirements==evidenceRequirements.sorted(),Set(policyReferences).count==policyReferences.count,Set(evidenceRequirements.map(\.requirementID)).count==evidenceRequirements.count else{throw WorkPacketFailureV1.limitExceeded}}
    static func <(l:Self,r:Self)->Bool{(l.itemID,l.kind.rawValue)<(r.itemID,r.kind.rawValue)}
}

struct WorkPacketManifestV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let manifestID:UUID;let packetID:UUID;let packetVersion:UInt64
    let workspaceID:WorkspaceID;let items:[WorkPacketItemV1];let packageReleases:[PackageReleaseIdentityV1]
    let creationBasis:WorkPacketCreationBasisV1;let creator:ActorSnapshotV1;let createdAt:Date
    let revision:UInt64;let mutationID:MutationIDV1;let manifestSHA256:String
    init(manifestID:UUID,packetID:UUID,packetVersion:UInt64,workspaceID:WorkspaceID,items:[WorkPacketItemV1],packageReleases:[PackageReleaseIdentityV1],creationBasis:WorkPacketCreationBasisV1,creator:ActorSnapshotV1,createdAt:Date,revision:UInt64=1,mutationID:MutationIDV1)throws{
        let items=items.sorted();let packages=packageReleases.sorted()
        schemaVersion=Self.schemaVersion;self.manifestID=manifestID;self.packetID=packetID;self.packetVersion=packetVersion;self.workspaceID=workspaceID;self.items=items;self.packageReleases=packages;self.creationBasis=creationBasis;self.creator=creator;self.createdAt=createdAt;self.revision=revision;self.mutationID=mutationID
        manifestSHA256=try WorkPacketCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,manifestID:manifestID,packetID:packetID,packetVersion:packetVersion,workspaceID:workspaceID,items:items,packageReleases:packages,creationBasis:creationBasis,creator:creator,createdAt:createdAt,revision:revision,mutationID:mutationID));try validate()
    }
    func validate()throws{try [manifestID,packetID].forEach(WorkPacketValidationV1.id);try WorkPacketValidationV1.workspace(workspaceID);try WorkPacketValidationV1.revision(packetVersion);try WorkPacketValidationV1.revision(revision);try WorkPacketValidationV1.instant(createdAt);try WorkPacketValidationV1.actor(creator,responsibility:.recordedBy,workspaceID:workspaceID);try items.forEach{try $0.validate()};guard schemaVersion==Self.schemaVersion,!items.isEmpty,items.count<=WorkPacketLimitsV1.maximumItems,items==items.sorted(),Set(items.map(\.itemID)).count==items.count,packageReleases==packageReleases.sorted(),Set(packageReleases).count==packageReleases.count,packageReleases.allSatisfy({!$0.packageID.isEmpty&&$0.packageID==$0.packageID.trimmingCharacters(in:.whitespacesAndNewlines)&&$0.schemaVersion>0&&$0.contentVersion>0}),revision==1,manifestSHA256==(try WorkPacketCanonicalCodecV1.sha256(basis))else{throw WorkPacketFailureV1.digestMismatch}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(manifestID:manifestID,packetID:packetID,packetVersion:packetVersion,workspaceID:workspaceID,items:items,packageReleases:packageReleases,creationBasis:creationBasis,creator:WorkPacketValidationV1.rebound(creator,to:workspaceID),createdAt:createdAt,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,manifestID:manifestID,packetID:packetID,packetVersion:packetVersion,workspaceID:workspaceID,items:items,packageReleases:packageReleases,creationBasis:creationBasis,creator:creator,createdAt:createdAt,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let manifestID:UUID;let packetID:UUID;let packetVersion:UInt64;let workspaceID:WorkspaceID;let items:[WorkPacketItemV1];let packageReleases:[PackageReleaseIdentityV1];let creationBasis:WorkPacketCreationBasisV1;let creator:ActorSnapshotV1;let createdAt:Date;let revision:UInt64;let mutationID:MutationIDV1}
}

struct WorkPacketManifestReferenceV1:Codable,Equatable,Hashable,Sendable{
    let workspaceID:WorkspaceID;let manifestID:UUID;let packetID:UUID;let packetVersion:UInt64;let manifestSHA256:String
    init(_ v:WorkPacketManifestV1)throws{try v.validate();workspaceID=v.workspaceID;manifestID=v.manifestID;packetID=v.packetID;packetVersion=v.packetVersion;manifestSHA256=v.manifestSHA256}
    private init(workspaceID:WorkspaceID,manifestID:UUID,packetID:UUID,packetVersion:UInt64,manifestSHA256:String){self.workspaceID=workspaceID;self.manifestID=manifestID;self.packetID=packetID;self.packetVersion=packetVersion;self.manifestSHA256=manifestSHA256}
    func validate()throws{try WorkPacketValidationV1.workspace(workspaceID);try WorkPacketValidationV1.id(manifestID);try WorkPacketValidationV1.id(packetID);try WorkPacketValidationV1.revision(packetVersion);try WorkPacketValidationV1.digest(manifestSHA256)}
    func rebound(to workspaceID:WorkspaceID)throws->Self{let value=Self(workspaceID:workspaceID,manifestID:manifestID,packetID:packetID,packetVersion:packetVersion,manifestSHA256:manifestSHA256);try value.validate();return value}
}
struct WorkPacketItemReferenceV1:Codable,Equatable,Hashable,Sendable{
    let workspaceID:WorkspaceID;let packetID:UUID;let packetVersion:UInt64;let manifestSHA256:String;let itemID:String;let itemKind:WorkPacketItemKindV1;let expectedRevision:UInt64;let itemSHA256:String
    init(manifest:WorkPacketManifestV1,item:WorkPacketItemV1)throws{try manifest.validate();try item.validate();guard manifest.items.contains(item)else{throw WorkPacketFailureV1.invalidValue};workspaceID=manifest.workspaceID;packetID=manifest.packetID;packetVersion=manifest.packetVersion;manifestSHA256=manifest.manifestSHA256;itemID=item.itemID;itemKind=item.kind;expectedRevision=item.expectedRevision;itemSHA256=item.itemSHA256}
    private init(workspaceID:WorkspaceID,packetID:UUID,packetVersion:UInt64,manifestSHA256:String,itemID:String,itemKind:WorkPacketItemKindV1,expectedRevision:UInt64,itemSHA256:String){self.workspaceID=workspaceID;self.packetID=packetID;self.packetVersion=packetVersion;self.manifestSHA256=manifestSHA256;self.itemID=itemID;self.itemKind=itemKind;self.expectedRevision=expectedRevision;self.itemSHA256=itemSHA256}
    func validate()throws{try WorkPacketValidationV1.workspace(workspaceID);try WorkPacketValidationV1.id(packetID);try WorkPacketValidationV1.revision(packetVersion);try WorkPacketValidationV1.digest(manifestSHA256);try WorkPacketValidationV1.text(itemID);try WorkPacketValidationV1.revision(expectedRevision);try WorkPacketValidationV1.digest(itemSHA256)}
    func rebound(to workspaceID:WorkspaceID)throws->Self{let value=Self(workspaceID:workspaceID,packetID:packetID,packetVersion:packetVersion,manifestSHA256:manifestSHA256,itemID:itemID,itemKind:itemKind,expectedRevision:expectedRevision,itemSHA256:itemSHA256);try value.validate();return value}
}

struct WorkPacketResultLinkV1:Codable,Equatable,Hashable,Comparable,Sendable{
    let resultID:UUID;let resultMutationID:MutationIDV1;let itemExpectedRevision:UInt64;let resultRevision:UInt64;let resultSHA256:String;let evidence:[ReviewEvidenceReferenceV1]
    init(resultID:UUID,resultMutationID:MutationIDV1,itemExpectedRevision:UInt64,resultRevision:UInt64,resultSHA256:String,evidence:[ReviewEvidenceReferenceV1])throws{self.resultID=resultID;self.resultMutationID=resultMutationID;self.itemExpectedRevision=itemExpectedRevision;self.resultRevision=resultRevision;self.resultSHA256=resultSHA256;self.evidence=evidence.sorted();try validate()}
    func validate()throws{try WorkPacketValidationV1.id(resultID);try WorkPacketValidationV1.revision(itemExpectedRevision);try WorkPacketValidationV1.revision(resultRevision);try WorkPacketValidationV1.digest(resultSHA256);try evidence.forEach{try $0.validate()};guard evidence.count<=WorkPacketLimitsV1.maximumResultsPerOperation,evidence==evidence.sorted(),Set(evidence).count==evidence.count else{throw WorkPacketFailureV1.limitExceeded}}
    static func <(l:Self,r:Self)->Bool{l.resultID.uuidString<r.resultID.uuidString}
}

struct WorkItemClaimV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let claimID:UUID;let workspaceID:WorkspaceID;let manifest:WorkPacketManifestReferenceV1;let item:WorkPacketItemReferenceV1;let holder:ActorSnapshotV1;let claimSequence:UInt64;let claimedAt:Date;let supersedesClaimID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let claimSHA256:String
    init(claimID:UUID,workspaceID:WorkspaceID,manifest:WorkPacketManifestReferenceV1,item:WorkPacketItemReferenceV1,holder:ActorSnapshotV1,claimSequence:UInt64,claimedAt:Date,supersedesClaimID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.claimID=claimID;self.workspaceID=workspaceID;self.manifest=manifest;self.item=item;self.holder=holder;self.claimSequence=claimSequence;self.claimedAt=claimedAt;self.supersedesClaimID=supersedesClaimID;self.revision=revision;self.mutationID=mutationID;claimSHA256=try WorkPacketCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,claimID:claimID,workspaceID:workspaceID,manifest:manifest,item:item,holder:holder,claimSequence:claimSequence,claimedAt:claimedAt,supersedesClaimID:supersedesClaimID,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try WorkPacketValidationV1.id(claimID);try WorkPacketValidationV1.workspace(workspaceID);try manifest.validate();try item.validate();try WorkPacketValidationV1.revision(claimSequence);try WorkPacketValidationV1.revision(revision);try WorkPacketValidationV1.instant(claimedAt);try WorkPacketValidationV1.actor(holder,responsibility:.assignedTo,workspaceID:workspaceID);if let supersedesClaimID{try WorkPacketValidationV1.id(supersedesClaimID)};guard schemaVersion==Self.schemaVersion,supersedesClaimID != claimID,manifest.workspaceID==workspaceID,item.workspaceID==workspaceID,manifest.packetID==item.packetID,manifest.packetVersion==item.packetVersion,manifest.manifestSHA256==item.manifestSHA256,(supersedesClaimID==nil)==(revision==1),(supersedesClaimID==nil)==(claimSequence==1),claimSHA256==(try WorkPacketCanonicalCodecV1.sha256(basis))else{throw WorkPacketFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();try WorkPacketValidationV1.next(p.revision,revision);try WorkPacketValidationV1.next(p.claimSequence,claimSequence);guard claimID != p.claimID,workspaceID==p.workspaceID,manifest==p.manifest,item==p.item,supersedesClaimID==p.claimID,claimedAt>=p.claimedAt,mutationID != p.mutationID else{throw WorkPacketFailureV1.reorderedEvent}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(claimID:claimID,workspaceID:workspaceID,manifest:manifest.rebound(to:workspaceID),item:item.rebound(to:workspaceID),holder:WorkPacketValidationV1.rebound(holder,to:workspaceID),claimSequence:claimSequence,claimedAt:claimedAt,supersedesClaimID:supersedesClaimID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,claimID:claimID,workspaceID:workspaceID,manifest:manifest,item:item,holder:holder,claimSequence:claimSequence,claimedAt:claimedAt,supersedesClaimID:supersedesClaimID,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let claimID:UUID;let workspaceID:WorkspaceID;let manifest:WorkPacketManifestReferenceV1;let item:WorkPacketItemReferenceV1;let holder:ActorSnapshotV1;let claimSequence:UInt64;let claimedAt:Date;let supersedesClaimID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct WorkLeaseV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let leaseID:UUID;let workspaceID:WorkspaceID;let claimID:UUID;let item:WorkPacketItemReferenceV1;let holder:ActorSnapshotV1;let leaseSequence:UInt64;let startsAt:Date;let expiresAt:Date;let supersedesLeaseID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let leaseSHA256:String
    init(leaseID:UUID,workspaceID:WorkspaceID,claimID:UUID,item:WorkPacketItemReferenceV1,holder:ActorSnapshotV1,leaseSequence:UInt64,startsAt:Date,expiresAt:Date,supersedesLeaseID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.leaseID=leaseID;self.workspaceID=workspaceID;self.claimID=claimID;self.item=item;self.holder=holder;self.leaseSequence=leaseSequence;self.startsAt=startsAt;self.expiresAt=expiresAt;self.supersedesLeaseID=supersedesLeaseID;self.revision=revision;self.mutationID=mutationID;leaseSHA256=try WorkPacketCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,leaseID:leaseID,workspaceID:workspaceID,claimID:claimID,item:item,holder:holder,leaseSequence:leaseSequence,startsAt:startsAt,expiresAt:expiresAt,supersedesLeaseID:supersedesLeaseID,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [leaseID,claimID].forEach(WorkPacketValidationV1.id);try WorkPacketValidationV1.workspace(workspaceID);try item.validate();try WorkPacketValidationV1.revision(leaseSequence);try WorkPacketValidationV1.revision(revision);try WorkPacketValidationV1.instant(startsAt);try WorkPacketValidationV1.instant(expiresAt);try WorkPacketValidationV1.actor(holder,responsibility:.assignedTo,workspaceID:workspaceID);if let supersedesLeaseID{try WorkPacketValidationV1.id(supersedesLeaseID)};guard schemaVersion==Self.schemaVersion,supersedesLeaseID != leaseID,item.workspaceID==workspaceID,expiresAt>startsAt,expiresAt.timeIntervalSince(startsAt)<=WorkPacketLimitsV1.maximumLeaseSeconds,(supersedesLeaseID==nil)==(revision==1),(supersedesLeaseID==nil)==(leaseSequence==1),leaseSHA256==(try WorkPacketCanonicalCodecV1.sha256(basis))else{throw WorkPacketFailureV1.digestMismatch}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();try WorkPacketValidationV1.next(p.revision,revision);try WorkPacketValidationV1.next(p.leaseSequence,leaseSequence);guard leaseID != p.leaseID,workspaceID==p.workspaceID,claimID==p.claimID,item==p.item,holder.actor==p.holder.actor,supersedesLeaseID==p.leaseID,startsAt>=p.startsAt,mutationID != p.mutationID else{throw WorkPacketFailureV1.reorderedEvent}}
    func isActive(at instant:Date)throws->Bool{try validate();try WorkPacketValidationV1.instant(instant);return instant>=startsAt&&instant<expiresAt}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(leaseID:leaseID,workspaceID:workspaceID,claimID:claimID,item:item.rebound(to:workspaceID),holder:WorkPacketValidationV1.rebound(holder,to:workspaceID),leaseSequence:leaseSequence,startsAt:startsAt,expiresAt:expiresAt,supersedesLeaseID:supersedesLeaseID,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,leaseID:leaseID,workspaceID:workspaceID,claimID:claimID,item:item,holder:holder,leaseSequence:leaseSequence,startsAt:startsAt,expiresAt:expiresAt,supersedesLeaseID:supersedesLeaseID,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let leaseID:UUID;let workspaceID:WorkspaceID;let claimID:UUID;let item:WorkPacketItemReferenceV1;let holder:ActorSnapshotV1;let leaseSequence:UInt64;let startsAt:Date;let expiresAt:Date;let supersedesLeaseID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

enum WorkReleaseReasonV1:String,CaseIterable,Codable,Hashable,Sendable{case completed="COMPLETED",deliberatelyReleased="DELIBERATELY_RELEASED",leaseExpired="LEASE_EXPIRED",handoff="HANDOFF",reclaimed="RECLAIMED"}
struct WorkReleaseV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let claimID:UUID;let leaseID:UUID;let item:WorkPacketItemReferenceV1;let holder:ActorSnapshotV1;let reason:WorkReleaseReasonV1;let resultLinks:[WorkPacketResultLinkV1];let releasedAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let releaseSHA256:String
    init(releaseID:UUID,workspaceID:WorkspaceID,claimID:UUID,leaseID:UUID,item:WorkPacketItemReferenceV1,holder:ActorSnapshotV1,reason:WorkReleaseReasonV1,resultLinks:[WorkPacketResultLinkV1]=[],releasedAt:Date,revision:UInt64=1,mutationID:MutationIDV1)throws{let links=resultLinks.sorted();schemaVersion=Self.schemaVersion;self.releaseID=releaseID;self.workspaceID=workspaceID;self.claimID=claimID;self.leaseID=leaseID;self.item=item;self.holder=holder;self.reason=reason;self.resultLinks=links;self.releasedAt=releasedAt;self.revision=revision;self.mutationID=mutationID;releaseSHA256=try WorkPacketCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,releaseID:releaseID,workspaceID:workspaceID,claimID:claimID,leaseID:leaseID,item:item,holder:holder,reason:reason,resultLinks:links,releasedAt:releasedAt,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [releaseID,claimID,leaseID].forEach(WorkPacketValidationV1.id);try WorkPacketValidationV1.workspace(workspaceID);try item.validate();try WorkPacketValidationV1.actor(holder,responsibility:.assignedTo,workspaceID:workspaceID);try WorkPacketValidationV1.instant(releasedAt);try WorkPacketValidationV1.revision(revision);try resultLinks.forEach{try $0.validate()};guard schemaVersion==Self.schemaVersion,item.workspaceID==workspaceID,revision==1,resultLinks.count<=WorkPacketLimitsV1.maximumResultsPerOperation,resultLinks==resultLinks.sorted(),Set(resultLinks.map(\.resultID)).count==resultLinks.count,(reason == .completed ? !resultLinks.isEmpty : true),releaseSHA256==(try WorkPacketCanonicalCodecV1.sha256(basis))else{throw WorkPacketFailureV1.digestMismatch}}
    func validate(claim:WorkItemClaimV1,lease:WorkLeaseV1)throws{try validate();try claim.validate();try lease.validate();let requiresExpiredLease=reason == .leaseExpired || reason == .reclaimed;guard workspaceID==claim.workspaceID,claimID==claim.claimID,item==claim.item,lease.workspaceID==workspaceID,leaseID==lease.leaseID,lease.claimID==claimID,lease.item==item,holder.actor==lease.holder.actor,releasedAt>=lease.startsAt,!requiresExpiredLease || releasedAt>=lease.expiresAt else{throw WorkPacketFailureV1.holderMismatch}}
    func validate(claim:WorkItemClaimV1,lease:WorkLeaseV1,manifest:WorkPacketManifestV1)throws{
        try validate(claim:claim,lease:lease);try manifest.validate()
        guard try WorkPacketManifestReferenceV1(manifest)==claim.manifest,
              let manifestItem=manifest.items.first(where:{$0.itemID==item.itemID}),
              try WorkPacketItemReferenceV1(manifest:manifest,item:manifestItem)==item
        else{throw WorkPacketFailureV1.staleRevision}
        guard reason == .completed else{return}
        let evidence=Set(resultLinks.flatMap(\.evidence))
        guard manifestItem.evidenceRequirements.allSatisfy({requirement in evidence.filter({$0.kind==requirement.evidenceKind}).count>=requirement.minimumCount})else{throw WorkPacketFailureV1.missingResult}
    }
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(releaseID:releaseID,workspaceID:workspaceID,claimID:claimID,leaseID:leaseID,item:item.rebound(to:workspaceID),holder:WorkPacketValidationV1.rebound(holder,to:workspaceID),reason:reason,resultLinks:resultLinks,releasedAt:releasedAt,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,releaseID:releaseID,workspaceID:workspaceID,claimID:claimID,leaseID:leaseID,item:item,holder:holder,reason:reason,resultLinks:resultLinks,releasedAt:releasedAt,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let releaseID:UUID;let workspaceID:WorkspaceID;let claimID:UUID;let leaseID:UUID;let item:WorkPacketItemReferenceV1;let holder:ActorSnapshotV1;let reason:WorkReleaseReasonV1;let resultLinks:[WorkPacketResultLinkV1];let releasedAt:Date;let revision:UInt64;let mutationID:MutationIDV1}
}

struct WorkHandoffV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let handoffID:UUID;let workspaceID:WorkspaceID;let releaseID:UUID;let item:WorkPacketItemReferenceV1;let fromHolder:ActorSnapshotV1;let toHolder:ActorSnapshotV1;let resultLinks:[WorkPacketResultLinkV1];let reason:String;let handedOffAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let handoffSHA256:String
    init(handoffID:UUID,workspaceID:WorkspaceID,releaseID:UUID,item:WorkPacketItemReferenceV1,fromHolder:ActorSnapshotV1,toHolder:ActorSnapshotV1,resultLinks:[WorkPacketResultLinkV1],reason:String,handedOffAt:Date,revision:UInt64=1,mutationID:MutationIDV1)throws{let links=resultLinks.sorted();schemaVersion=Self.schemaVersion;self.handoffID=handoffID;self.workspaceID=workspaceID;self.releaseID=releaseID;self.item=item;self.fromHolder=fromHolder;self.toHolder=toHolder;self.resultLinks=links;self.reason=reason;self.handedOffAt=handedOffAt;self.revision=revision;self.mutationID=mutationID;handoffSHA256=try WorkPacketCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,handoffID:handoffID,workspaceID:workspaceID,releaseID:releaseID,item:item,fromHolder:fromHolder,toHolder:toHolder,resultLinks:links,reason:reason,handedOffAt:handedOffAt,revision:revision,mutationID:mutationID));try validate()}
    func validate()throws{try [handoffID,releaseID].forEach(WorkPacketValidationV1.id);try WorkPacketValidationV1.workspace(workspaceID);try item.validate();try WorkPacketValidationV1.actor(fromHolder,responsibility:.assignedTo,workspaceID:workspaceID);try WorkPacketValidationV1.actor(toHolder,responsibility:.assignedTo,workspaceID:workspaceID);try resultLinks.forEach{try $0.validate()};try WorkPacketValidationV1.text(reason);try WorkPacketValidationV1.instant(handedOffAt);try WorkPacketValidationV1.revision(revision);guard schemaVersion==Self.schemaVersion,item.workspaceID==workspaceID,revision==1,fromHolder.actor.actorReferenceID != toHolder.actor.actorReferenceID,resultLinks.count<=WorkPacketLimitsV1.maximumResultsPerOperation,resultLinks==resultLinks.sorted(),Set(resultLinks.map(\.resultID)).count==resultLinks.count,handoffSHA256==(try WorkPacketCanonicalCodecV1.sha256(basis))else{throw WorkPacketFailureV1.digestMismatch}}
    func validate(release:WorkReleaseV1)throws{try validate();try release.validate();guard releaseID==release.releaseID,workspaceID==release.workspaceID,item==release.item,release.reason == .handoff,fromHolder.actor==release.holder.actor,resultLinks==release.resultLinks,handedOffAt>=release.releasedAt else{throw WorkPacketFailureV1.holderMismatch}}
    func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(handoffID:handoffID,workspaceID:workspaceID,releaseID:releaseID,item:item.rebound(to:workspaceID),fromHolder:WorkPacketValidationV1.rebound(fromHolder,to:workspaceID),toHolder:WorkPacketValidationV1.rebound(toHolder,to:workspaceID),resultLinks:resultLinks,reason:reason,handedOffAt:handedOffAt,revision:revision,mutationID:mutationID)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,handoffID:handoffID,workspaceID:workspaceID,releaseID:releaseID,item:item,fromHolder:fromHolder,toHolder:toHolder,resultLinks:resultLinks,reason:reason,handedOffAt:handedOffAt,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let handoffID:UUID;let workspaceID:WorkspaceID;let releaseID:UUID;let item:WorkPacketItemReferenceV1;let fromHolder:ActorSnapshotV1;let toHolder:ActorSnapshotV1;let resultLinks:[WorkPacketResultLinkV1];let reason:String;let handedOffAt:Date;let revision:UInt64;let mutationID:MutationIDV1}
}

enum WorkPacketReplayDispositionV1:String,Codable,Hashable,Sendable{case apply="APPLY",idempotentReplay="IDEMPOTENT_REPLAY",quarantineDivergentBytes="QUARANTINE_DIVERGENT_BYTES"}
enum WorkPacketReplayValidatorV1{static func disposition<T:Encodable>(existing:T?,incoming:T,identityMatches:Bool)throws->WorkPacketReplayDispositionV1{guard identityMatches else{return .apply};guard let existing else{return .apply};return try WorkPacketCanonicalCodecV1.encode(existing)==WorkPacketCanonicalCodecV1.encode(incoming) ? .idempotentReplay:.quarantineDivergentBytes}}

enum WorkPacketConflictKindV1:String,Codable,Hashable,Sendable{case simultaneousClaim="SIMULTANEOUS_CLAIM",staleResultRevision="STALE_RESULT_REVISION",expiredLeaseResult="EXPIRED_LEASE_RESULT",divergentSameIdentity="DIVERGENT_SAME_IDENTITY"}
struct WorkPacketReviewExceptionV1:Equatable,Hashable,Sendable{let exceptionID:String;let workspaceID:WorkspaceID;let packetID:UUID;let itemID:String;let kind:WorkPacketConflictKindV1;let preservedResultLinks:[WorkPacketResultLinkV1];let conflictingDigests:[String]}
struct WorkPacketItemProjectionV1:Equatable,Hashable,Sendable{let item:WorkPacketItemReferenceV1;let currentClaim:WorkItemClaimV1?;let currentLease:WorkLeaseV1?;let latestRelease:WorkReleaseV1?;let latestHandoff:WorkHandoffV1?;let preservedResults:[WorkPacketResultLinkV1];let exceptions:[WorkPacketReviewExceptionV1]}
struct WorkPacketProjectionV1:Equatable,Sendable{let workspaceID:WorkspaceID;let manifest:WorkPacketManifestV1;let items:[WorkPacketItemProjectionV1]}

enum WorkPacketProjectionBuilderV1{
    static func rebuild(workspaceID:WorkspaceID,manifest:WorkPacketManifestV1,claims:[WorkItemClaimV1],leases:[WorkLeaseV1],releases:[WorkReleaseV1],handoffs:[WorkHandoffV1],at now:Date)throws->WorkPacketProjectionV1{
        try WorkPacketValidationV1.workspace(workspaceID);try WorkPacketValidationV1.instant(now);try manifest.validate();guard manifest.workspaceID==workspaceID else{throw WorkPacketFailureV1.wrongWorkspace}
        let claims=claims.filter{$0.workspaceID==workspaceID&&$0.manifest.manifestID==manifest.manifestID};let leases=leases.filter{$0.workspaceID==workspaceID&&$0.item.packetID==manifest.packetID};let releases=releases.filter{$0.workspaceID==workspaceID&&$0.item.packetID==manifest.packetID};let handoffs=handoffs.filter{$0.workspaceID==workspaceID&&$0.item.packetID==manifest.packetID}
        guard claims.count<=WorkPacketLimitsV1.maximumHistory,leases.count<=WorkPacketLimitsV1.maximumHistory,releases.count<=WorkPacketLimitsV1.maximumHistory,handoffs.count<=WorkPacketLimitsV1.maximumHistory else{throw WorkPacketFailureV1.limitExceeded}
        var projections:[WorkPacketItemProjectionV1]=[]
        for item in manifest.items{let reference=try WorkPacketItemReferenceV1(manifest:manifest,item:item);let itemClaims=Array(Set(claims.filter{$0.item==reference})).sorted{($0.claimSequence,$0.claimID.uuidString,$0.claimSHA256)<($1.claimSequence,$1.claimID.uuidString,$1.claimSHA256)};for v in itemClaims{try v.validate();if let predecessorID=v.supersedesClaimID{guard let predecessor=itemClaims.first(where:{$0.claimID==predecessorID})else{throw WorkPacketFailureV1.reorderedEvent};try v.validateSuccessor(of:predecessor)}else{guard v.claimSequence==1&&v.revision==1 else{throw WorkPacketFailureV1.reorderedEvent}}}
            let itemLeases=Array(Set(leases.filter{$0.item==reference})).sorted{($0.leaseSequence,$0.leaseID.uuidString,$0.leaseSHA256)<($1.leaseSequence,$1.leaseID.uuidString,$1.leaseSHA256)};for v in itemLeases{try v.validate();if let predecessorID=v.supersedesLeaseID{guard let predecessor=itemLeases.first(where:{$0.leaseID==predecessorID})else{throw WorkPacketFailureV1.reorderedEvent};try v.validateSuccessor(of:predecessor)}else{guard v.leaseSequence==1&&v.revision==1 else{throw WorkPacketFailureV1.reorderedEvent}}}
            let itemReleases=Array(Set(releases.filter{$0.item==reference})).sorted{($0.releasedAt,$0.releaseID.uuidString,$0.releaseSHA256)<($1.releasedAt,$1.releaseID.uuidString,$1.releaseSHA256)};for v in itemReleases{guard let c=itemClaims.first(where:{$0.claimID==v.claimID}),let l=itemLeases.first(where:{$0.leaseID==v.leaseID})else{throw WorkPacketFailureV1.invalidValue};try v.validate(claim:c,lease:l,manifest:manifest)}
            let itemHandoffs=Array(Set(handoffs.filter{$0.item==reference})).sorted{($0.handedOffAt,$0.handoffID.uuidString,$0.handoffSHA256)<($1.handedOffAt,$1.handoffID.uuidString,$1.handoffSHA256)};for v in itemHandoffs{guard let r=itemReleases.first(where:{$0.releaseID==v.releaseID})else{throw WorkPacketFailureV1.invalidValue};try v.validate(release:r)}
            var exceptions:[WorkPacketReviewExceptionV1]=[];let activeClaims=itemClaims.filter{claim in !itemReleases.contains(where:{$0.claimID==claim.claimID})};if activeClaims.count>1{exceptions.append(try exception(workspaceID:workspaceID,packetID:manifest.packetID,itemID:item.itemID,kind:.simultaneousClaim,results:itemReleases.flatMap(\.resultLinks)))}
            let results=(itemReleases.flatMap(\.resultLinks)+itemHandoffs.flatMap(\.resultLinks)).sorted();let grouped=Dictionary(grouping:results,by:{$0.resultID})
            let divergentDurableDigests = Dictionary(grouping:itemClaims,by:{$0.claimID}).values.flatMap{Set($0.map(\.claimSHA256)).count>1 ? $0.map(\.claimSHA256):[]}
                + Dictionary(grouping:itemLeases,by:{$0.leaseID}).values.flatMap{Set($0.map(\.leaseSHA256)).count>1 ? $0.map(\.leaseSHA256):[]}
                + Dictionary(grouping:itemReleases,by:{$0.releaseID}).values.flatMap{Set($0.map(\.releaseSHA256)).count>1 ? $0.map(\.releaseSHA256):[]}
                + Dictionary(grouping:itemHandoffs,by:{$0.handoffID}).values.flatMap{Set($0.map(\.handoffSHA256)).count>1 ? $0.map(\.handoffSHA256):[]}
            if grouped.values.contains(where:{$0.count>1&&Set($0.map(\.resultSHA256)).count>1}) || !divergentDurableDigests.isEmpty{exceptions.append(try exception(workspaceID:workspaceID,packetID:manifest.packetID,itemID:item.itemID,kind:.divergentSameIdentity,results:results,additionalDigests:divergentDurableDigests))};if results.contains(where:{$0.itemExpectedRevision != item.expectedRevision}){exceptions.append(try exception(workspaceID:workspaceID,packetID:manifest.packetID,itemID:item.itemID,kind:.staleResultRevision,results:results))}
            let hasExpiredLeaseResult=itemReleases.contains{release in
                guard !release.resultLinks.isEmpty,let sourceLease=itemLeases.first(where:{$0.leaseID==release.leaseID})else{return false}
                return release.releasedAt>sourceLease.expiresAt
            }
            if hasExpiredLeaseResult{exceptions.append(try exception(workspaceID:workspaceID,packetID:manifest.packetID,itemID:item.itemID,kind:.expiredLeaseResult,results:results))}
            let currentClaim=activeClaims.count==1 ? activeClaims[0]:nil
            let lease:WorkLeaseV1?
            if let claim=currentClaim,let candidate=itemLeases.last(where:{$0.claimID==claim.claimID}),try candidate.isActive(at:now){lease=candidate}else{lease=nil}
            projections.append(.init(item:reference,currentClaim:currentClaim,currentLease:lease,latestRelease:itemReleases.last,latestHandoff:itemHandoffs.last,preservedResults:results,exceptions:exceptions.sorted{$0.exceptionID<$1.exceptionID}))}
        return .init(workspaceID:workspaceID,manifest:manifest,items:projections)
    }
    private static func exception(workspaceID:WorkspaceID,packetID:UUID,itemID:String,kind:WorkPacketConflictKindV1,results:[WorkPacketResultLinkV1],additionalDigests:[String]=[])throws->WorkPacketReviewExceptionV1{let results=results.sorted();let digests=Array(Set(results.map(\.resultSHA256)+additionalDigests)).sorted();let basis=ExceptionBasis(workspaceID:workspaceID,packetID:packetID,itemID:itemID,kind:kind,preservedResultLinks:results,conflictingDigests:digests);return .init(exceptionID:try WorkPacketCanonicalCodecV1.sha256(basis),workspaceID:workspaceID,packetID:packetID,itemID:itemID,kind:kind,preservedResultLinks:results,conflictingDigests:digests)}
    private struct ExceptionBasis:Codable{let workspaceID:WorkspaceID;let packetID:UUID;let itemID:String;let kind:WorkPacketConflictKindV1;let preservedResultLinks:[WorkPacketResultLinkV1];let conflictingDigests:[String]}
}

private protocol WorkPacketValidatableV1{func validate()throws}
extension WorkPacketManifestV1:WorkPacketValidatableV1{};extension WorkItemClaimV1:WorkPacketValidatableV1{};extension WorkLeaseV1:WorkPacketValidatableV1{};extension WorkReleaseV1:WorkPacketValidatableV1{};extension WorkHandoffV1:WorkPacketValidatableV1{}
enum WorkPacketCanonicalCodecV1{static func encode<T:Encodable>(_ value:T)throws->Data{try WorkspaceMutationCanonicalV1.data(value)}static func sha256<T:Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)}static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=WorkPacketLimitsV1.maximumCanonicalBytes else{throw WorkPacketFailureV1.limitExceeded};let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970;let value=try decoder.decode(type,from:data);if let validatable=value as? any WorkPacketValidatableV1{try validatable.validate()};guard try encode(value)==data else{throw WorkPacketFailureV1.digestMismatch};return value}}

// MARK: - C23 immutable field-reference binding projection

/// Work-packet consumers receive reference metadata as a derived projection.
/// The canonical release/binding rows and their content remain owned by the
/// field-reference pack writer; this value deliberately carries no bytes or
/// locators.
struct WorkPacketFieldReferenceProjectionV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let packetID: UUID
    let packetVersion: UInt64
    let manifestSHA256: String
    let subjectState: FieldReferenceSubjectStateV1
    let projection: WorkPacketProjectionV1
    let references: [WorkSessionFieldReferenceProjectionV1]

    init(
        projection: WorkPacketProjectionV1,
        manifest: WorkPacketManifestV1,
        bindings: [FieldReferenceBindingV1],
        releases: [FieldReferenceReleaseV1],
        readiness: [FieldReferenceOfflineReadinessV1],
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws {
        try manifest.validate()
        guard projection.workspaceID == manifest.workspaceID,
              projection.manifest == manifest else {
            throw WorkPacketFailureV1.wrongWorkspace
        }
        var values: [WorkSessionFieldReferenceProjectionV1] = []
        guard bindings.allSatisfy({ $0.workspaceID == manifest.workspaceID }),
              releases.allSatisfy({ $0.workspaceID == manifest.workspaceID }),
              Set(bindings.map(\.bindingID)).count == bindings.count else {
            throw WorkPacketFailureV1.divergentReplay
        }
        for binding in bindings {
            guard binding.subjectKind == .workPacket,
                  binding.subjectID == manifest.packetID,
                  binding.subjectRevision == manifest.packetVersion,
                  binding.subjectState == subjectState else {
                throw WorkPacketFailureV1.wrongWorkspace
            }
            let matchingReleases = releases.filter {
                $0.workspaceID == manifest.workspaceID && $0.releaseID == binding.releaseID
            }
            guard matchingReleases.count == 1, let release = matchingReleases.first else {
                throw WorkPacketFailureV1.divergentReplay
            }
            let matchingReadiness = readiness.filter {
                $0.releaseID == release.releaseID && $0.bindingID == binding.bindingID
            }
            guard matchingReadiness.count == 1, let state = matchingReadiness.first else {
                throw WorkPacketFailureV1.divergentReplay
            }
            let value = try WorkSessionFieldReferenceProjectionV1(
                binding: binding, release: release, readiness: state
            )
            try value.validate(
                expectedWorkspaceID: manifest.workspaceID,
                expectedSubjectKind: .workPacket,
                expectedSubjectID: manifest.packetID,
                expectedSubjectRevision: manifest.packetVersion,
                expectedSubjectState: subjectState
            )
            values.append(value)
        }
        workspaceID = manifest.workspaceID
        packetID = manifest.packetID
        packetVersion = manifest.packetVersion
        manifestSHA256 = manifest.manifestSHA256
        self.subjectState = subjectState
        self.projection = projection
        references = values.sorted {
            ($0.releaseID.uuidString.lowercased(), $0.bindingID.uuidString.lowercased())
                < ($1.releaseID.uuidString.lowercased(), $1.bindingID.uuidString.lowercased())
        }
    }

    func validate() throws {
        try projection.manifest.validate()
        guard projection.workspaceID == workspaceID,
              projection.manifest.packetID == packetID,
              projection.manifest.packetVersion == packetVersion,
              projection.manifest.manifestSHA256 == manifestSHA256,
              projection.items.count == projection.manifest.items.count,
              references == references.sorted(by: {
                  ($0.releaseID.uuidString.lowercased(), $0.bindingID.uuidString.lowercased())
                      < ($1.releaseID.uuidString.lowercased(), $1.bindingID.uuidString.lowercased())
              }),
              Set(references.map(\.bindingID)).count == references.count else {
            throw WorkPacketFailureV1.digestMismatch
        }
        for reference in references {
            try reference.validate(
                expectedWorkspaceID: workspaceID,
                expectedSubjectKind: .workPacket,
                expectedSubjectID: packetID,
                expectedSubjectRevision: packetVersion,
                expectedSubjectState: subjectState
            )
        }
    }
}

enum WorkPacketReferenceProjectionBuilderV1 {
    static func rebuild(
        workspaceID: WorkspaceID,
        manifest: WorkPacketManifestV1,
        claims: [WorkItemClaimV1],
        leases: [WorkLeaseV1],
        releases: [WorkReleaseV1],
        handoffs: [WorkHandoffV1],
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1],
        subjectState: FieldReferenceSubjectStateV1 = .active,
        at instant: Date
    ) throws -> WorkPacketFieldReferenceProjectionV1 {
        let projection = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: workspaceID,
            manifest: manifest,
            claims: claims,
            leases: leases,
            releases: releases,
            handoffs: handoffs,
            at: instant
        )
        return try WorkPacketFieldReferenceProjectionV1(
            projection: projection,
            manifest: manifest,
            bindings: fieldReferenceBindings,
            releases: fieldReferenceReleases,
            readiness: fieldReferenceReadiness,
            subjectState: subjectState
        )
    }
}

extension WorkPacketManifestV1 {
    /// Proves a binding is for this exact packet generation. A different
    /// release must arrive as an explicit C23 binding successor; callers may
    /// not silently replace the release while a packet is active or final.
    func c23ValidateReferenceBinding(
        _ binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        guard binding.subjectKind == .workPacket,
              binding.subjectID == packetID,
              binding.subjectRevision == packetVersion,
              binding.subjectState == subjectState else {
            throw WorkPacketFailureV1.wrongWorkspace
        }
        let projection = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try projection.validate(
            expectedWorkspaceID: workspaceID,
            expectedSubjectKind: .workPacket,
            expectedSubjectID: packetID,
            expectedSubjectRevision: packetVersion,
            expectedSubjectState: subjectState
        )
        return projection
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_InspectionKernel_WorkPacketManifestContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_InspectionKernel_WorkPacketManifestContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_InspectionKernel_WorkPacketManifestContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/InspectionKernel/WorkPacketManifestContractsV1.swift", role: .workPacket)
}

enum C31LightingWorkPacketBoundaryV1 {
    static let packageReleaseIsReferencedByDigest = true
    static let lightingTopologyDoesNotCreateASecondManifest = true
    static let absentLightingInputsRemainExplicitlyAbsent = true
}
// MARK: - C32 assistance work packet manifest boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_InspectionKernel_WorkPacketManifestContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let assistanceDoesNotPromoteWorkPacket = true

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

enum C33TemporalEvidenceBoundary_Domain_InspectionKernel_WorkPacketManifestContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row123 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_InspectionKernel_WorkPacketManifestContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C34RouteAdoptionBoundary_WorkPacketManifestContractsV1 {
    static let canonicalTargetType = NavigationTargetV1.self
    static let workRoot = AppRootV1.work
    static let startsAutomaticWork = false
}
enum C52ServiceRequestBoundary_WorkPacketManifestContractsV1 {
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

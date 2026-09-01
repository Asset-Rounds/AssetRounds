import Foundation

enum OperationalContactFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case unknownKey
    case digestMismatch
    case crossWorkspaceReference
    case staleRevision
    case preferredConflict
    case invalidHandoffTarget
    case limitExceeded
}

enum OperationalContactLimitsV1 {
    static let maximumDisplayValueBytes = 1_024
    static let maximumImportFileNameBytes = 255
    static let maximumSourceFiles = 16
    static let maximumImportFileBytes:Int64 = 4 * 1_024 * 1_024
    static let maximumImportSourceSetBytes:Int64 = 16 * 1_024 * 1_024
    static let maximumMutationContacts = 64
}

private enum OperationalContactValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) throws { guard value != zero else { throw OperationalContactFailureV1.invalidValue } }
    static func digest(_ value: String) throws {
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw OperationalContactFailureV1.digestMismatch }
    }
    static func text(_ value: String, maximumBytes: Int) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes, value == value.precomposedStringWithCanonicalMapping else { throw OperationalContactFailureV1.invalidValue }
        for scalar in value.unicodeScalars {
            let n = scalar.value
            guard n >= 0x20, n != 0x7f, !(0x80...0x9f).contains(n), ![0x202a,0x202b,0x202c,0x202d,0x202e].contains(n), (n & 0xffff) != 0xfffe, (n & 0xffff) != 0xffff else { throw OperationalContactFailureV1.invalidValue }
        }
    }
    static func contactValue(_ value:String,kind:ServiceContactKindV1)throws{
        try text(value,maximumBytes:OperationalContactLimitsV1.maximumDisplayValueBytes)
        switch kind{
        case .email:
            let parts=value.split(separator:"@",omittingEmptySubsequences:false)
            guard parts.count==2,parts.allSatisfy({!$0.isEmpty}),!value.contains("?"),!value.contains("&"),!value.contains(","),!value.contains(";"),!value.contains("\r"),!value.contains("\n") else{throw OperationalContactFailureV1.invalidValue}
        case .phone:
            let allowed=CharacterSet(charactersIn:"+0123456789 -().extEXT")
            guard value.unicodeScalars.allSatisfy(allowed.contains),value.unicodeScalars.contains(where:{(48...57).contains(Int($0.value))}),!value.contains("*"),!value.contains("#"),!value.lowercased().contains("pause") else{throw OperationalContactFailureV1.invalidValue}
        }
    }
}

private enum OperationalContactClosedCodingV1 {
    private struct AnyKey: CodingKey { let stringValue: String; let intValue: Int?; init?(stringValue: String) { self.stringValue=stringValue;intValue=nil };init?(intValue:Int){stringValue=String(intValue);self.intValue=intValue} }
    static func requireExact<Key: CodingKey & CaseIterable>(_ decoder: Decoder, _ keys: Key.Type) throws where Key.AllCases: Collection {
        let actual=Set(try decoder.container(keyedBy:AnyKey.self).allKeys.map(\.stringValue));let expected=Set(Key.allCases.map(\.stringValue));guard actual.isSubset(of:expected) else{throw OperationalContactFailureV1.unknownKey}
    }
}

enum OperationalContactCanonicalCodecV1 {
    static func data<T: Encodable>(_ value:T)throws->Data{try WorkspaceMutationCanonicalV1.data(value)}
    static func sha256<T: Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)}
    static func decode<T:Decodable>(_ type:T.Type,from data:Data)throws->T{let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970;return try decoder.decode(type,from:data)}
}

enum ServiceContactKindV1: String, Codable, CaseIterable, Hashable, Sendable { case phone="PHONE";case email="EMAIL" }
enum ServiceContactLabelV1: String, Codable, CaseIterable, Hashable, Sendable { case mobile="MOBILE";case work="WORK";case office="OFFICE";case other="OTHER" }
enum ServiceContactProvenanceV1: String, Codable, CaseIterable, Hashable, Sendable { case manual="MANUAL";case importedExternalEvidence="IMPORTED_EXTERNAL_EVIDENCE" }
enum ServiceContactPrivacyClassV1: String, Codable, CaseIterable, Hashable, Sendable { case workspaceCustomerData="WORKSPACE_CUSTOMER_DATA" }
enum ServiceContactLifecycleV1: String, Codable, CaseIterable, Hashable, Sendable { case effective="EFFECTIVE";case retired="RETIRED" }

struct ServiceContactRevisionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let contactPointID:UUID;let revision:UInt64;let contactPointSHA256:String
    init(contactPointID:UUID,revision:UInt64,contactPointSHA256:String)throws{try OperationalContactValidationV1.id(contactPointID);try OperationalContactValidationV1.digest(contactPointSHA256);guard revision>0 else{throw OperationalContactFailureV1.invalidValue};self.contactPointID=contactPointID;self.revision=revision;self.contactPointSHA256=contactPointSHA256}
    private enum CodingKeys:String,CodingKey,CaseIterable{case contactPointID,revision,contactPointSHA256}
    init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(contactPointID:c.decode(UUID.self,forKey:.contactPointID),revision:c.decode(UInt64.self,forKey:.revision),contactPointSHA256:c.decode(String.self,forKey:.contactPointSHA256))}
}

struct ServiceContactPointV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let contactPointID:UUID;let workspaceID:WorkspaceID;let party:ServicePartyReferenceV1
    let kind:ServiceContactKindV1;let label:ServiceContactLabelV1;let displayValue:String;let preferred:Bool
    let provenance:ServiceContactProvenanceV1;let importSourceSetSHA256:String?;let privacyClass:ServiceContactPrivacyClassV1;let lifecycle:ServiceContactLifecycleV1
    let effectiveAt:Date;let retiredAt:Date?;let revision:UInt64;let supersedes:ServiceContactRevisionReferenceV1?
    let mutationID:MutationIDV1;let contactPointSHA256:String

    init(contactPointID:UUID,workspaceID:WorkspaceID,party:ServicePartyReferenceV1,kind:ServiceContactKindV1,label:ServiceContactLabelV1,displayValue:String,preferred:Bool,provenance:ServiceContactProvenanceV1,importSourceSetSHA256:String? = nil,privacyClass:ServiceContactPrivacyClassV1 = .workspaceCustomerData,lifecycle:ServiceContactLifecycleV1,effectiveAt:Date,retiredAt:Date? = nil,revision:UInt64,supersedes:ServiceContactRevisionReferenceV1? = nil,mutationID:MutationIDV1)throws{
        schemaVersion=Self.schemaVersion;self.contactPointID=contactPointID;self.workspaceID=workspaceID;self.party=party;self.kind=kind;self.label=label;self.displayValue=displayValue;self.preferred=preferred;self.provenance=provenance;self.importSourceSetSHA256=importSourceSetSHA256;self.privacyClass=privacyClass;self.lifecycle=lifecycle;self.effectiveAt=effectiveAt;self.retiredAt=retiredAt;self.revision=revision;self.supersedes=supersedes;self.mutationID=mutationID
        contactPointSHA256=try OperationalContactCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,contactPointID:contactPointID,workspaceID:workspaceID,party:party,kind:kind,label:label,displayValue:displayValue,preferred:preferred,provenance:provenance,importSourceSetSHA256:importSourceSetSHA256,privacyClass:privacyClass,lifecycle:lifecycle,effectiveAt:effectiveAt,retiredAt:retiredAt,revision:revision,supersedes:supersedes,mutationID:mutationID));try validate()
    }
    func validate()throws{
        try OperationalContactValidationV1.id(contactPointID);try party.validate();try OperationalContactValidationV1.contactValue(displayValue,kind:kind)
        guard schemaVersion==Self.schemaVersion,workspaceID==party.workspaceID,privacyClass == .workspaceCustomerData else{throw OperationalContactFailureV1.crossWorkspaceReference}
        guard revision > 0 else{throw OperationalContactFailureV1.staleRevision}
        if revision == 1 { guard supersedes == nil else{throw OperationalContactFailureV1.staleRevision} }
        else { guard let supersedes,supersedes.contactPointID==contactPointID,supersedes.revision == revision-1 else{throw OperationalContactFailureV1.staleRevision} }
        guard lifecycle == .effective ? retiredAt == nil : (retiredAt.map{$0>=effectiveAt} == true && preferred == false) else{throw OperationalContactFailureV1.invalidValue}
        guard provenance == .manual ? importSourceSetSHA256 == nil : importSourceSetSHA256 != nil else{throw OperationalContactFailureV1.invalidValue};if let importSourceSetSHA256{try OperationalContactValidationV1.digest(importSourceSetSHA256)}
        try OperationalContactValidationV1.digest(contactPointSHA256)
        let basis=Basis(schemaVersion:schemaVersion,contactPointID:contactPointID,workspaceID:workspaceID,party:party,kind:kind,label:label,displayValue:displayValue,preferred:preferred,provenance:provenance,importSourceSetSHA256:importSourceSetSHA256,privacyClass:privacyClass,lifecycle:lifecycle,effectiveAt:effectiveAt,retiredAt:retiredAt,revision:revision,supersedes:supersedes,mutationID:mutationID)
        guard contactPointSHA256 == (try OperationalContactCanonicalCodecV1.sha256(basis)) else{throw OperationalContactFailureV1.digestMismatch}
    }
    func rebound(to workspaceID:WorkspaceID,party:ServicePartyReferenceV1,mutationID:MutationIDV1)throws->Self{try Self(contactPointID:contactPointID,workspaceID:workspaceID,party:party,kind:kind,label:label,displayValue:displayValue,preferred:preferred,provenance:provenance,importSourceSetSHA256:importSourceSetSHA256,privacyClass:privacyClass,lifecycle:lifecycle,effectiveAt:effectiveAt,retiredAt:retiredAt,revision:1,supersedes:nil,mutationID:mutationID)}
    var revisionReference:ServiceContactRevisionReferenceV1{get throws{try .init(contactPointID:contactPointID,revision:revision,contactPointSHA256:contactPointSHA256)}}
    /// Contact revisions embed the Party snapshot observed when authored.
    /// A later Party rename does not rewrite older contacts; compatibility is
    /// stable workspace/Party/kind identity with monotonic Party revision.
    func validatePartyCompatibility(with currentParty:ServicePartyReferenceV1)throws{
        try validate();try party.validateHistoricalIdentity(with:currentParty)
        guard workspaceID==currentParty.workspaceID else{
            throw OperationalContactFailureV1.crossWorkspaceReference
        }
    }
    private struct Basis:Codable{let schemaVersion:Int;let contactPointID:UUID;let workspaceID:WorkspaceID;let party:ServicePartyReferenceV1;let kind:ServiceContactKindV1;let label:ServiceContactLabelV1;let displayValue:String;let preferred:Bool;let provenance:ServiceContactProvenanceV1;let importSourceSetSHA256:String?;let privacyClass:ServiceContactPrivacyClassV1;let lifecycle:ServiceContactLifecycleV1;let effectiveAt:Date;let retiredAt:Date?;let revision:UInt64;let supersedes:ServiceContactRevisionReferenceV1?;let mutationID:MutationIDV1}
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,contactPointID,workspaceID,party,kind,label,displayValue,preferred,provenance,importSourceSetSHA256,privacyClass,lifecycle,effectiveAt,retiredAt,revision,supersedes,mutationID,contactPointSHA256}
    init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(contactPointID:c.decode(UUID.self,forKey:.contactPointID),workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),party:c.decode(ServicePartyReferenceV1.self,forKey:.party),kind:c.decode(ServiceContactKindV1.self,forKey:.kind),label:c.decode(ServiceContactLabelV1.self,forKey:.label),displayValue:c.decode(String.self,forKey:.displayValue),preferred:c.decode(Bool.self,forKey:.preferred),provenance:c.decode(ServiceContactProvenanceV1.self,forKey:.provenance),importSourceSetSHA256:c.decodeIfPresent(String.self,forKey:.importSourceSetSHA256),privacyClass:c.decode(ServiceContactPrivacyClassV1.self,forKey:.privacyClass),lifecycle:c.decode(ServiceContactLifecycleV1.self,forKey:.lifecycle),effectiveAt:c.decode(Date.self,forKey:.effectiveAt),retiredAt:c.decodeIfPresent(Date.self,forKey:.retiredAt),revision:c.decode(UInt64.self,forKey:.revision),supersedes:c.decodeIfPresent(ServiceContactRevisionReferenceV1.self,forKey:.supersedes),mutationID:c.decode(MutationIDV1.self,forKey:.mutationID));guard try c.decode(Int.self,forKey:.schemaVersion)==Self.schemaVersion,c.decode(String.self,forKey:.contactPointSHA256)==rebuilt.contactPointSHA256 else{throw OperationalContactFailureV1.digestMismatch};self=rebuilt}
}

struct ServiceContactPreferredScopeV1: Codable, Equatable, Sendable {
    let partyID:UUID;let kind:ServiceContactKindV1;let activeContactPointIDs:[UUID];let preferredContactPointID:UUID?
    init(partyID:UUID,kind:ServiceContactKindV1,activeContactPointIDs:[UUID],preferredContactPointID:UUID?)throws{try OperationalContactValidationV1.id(partyID);let ids=activeContactPointIDs.sorted{$0.uuidString<$1.uuidString};guard ids.count==Set(ids).count,ids.count<=OperationalContactLimitsV1.maximumMutationContacts,preferredContactPointID.map(ids.contains) ?? true else{throw OperationalContactFailureV1.preferredConflict};self.partyID=partyID;self.kind=kind;self.activeContactPointIDs=ids;self.preferredContactPointID=preferredContactPointID}
    private enum CodingKeys:String,CodingKey,CaseIterable{case partyID,kind,activeContactPointIDs,preferredContactPointID}
    init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(partyID:c.decode(UUID.self,forKey:.partyID),kind:c.decode(ServiceContactKindV1.self,forKey:.kind),activeContactPointIDs:c.decode([UUID].self,forKey:.activeContactPointIDs),preferredContactPointID:c.decodeIfPresent(UUID.self,forKey:.preferredContactPointID))}
}

struct OperationalContactMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let workspaceID:WorkspaceID;let mutationID:MutationIDV1;let expectedRevision:WorkspaceExpectedRevisionV1
    let predecessors:[ServiceContactPointV1];let successors:[ServiceContactPointV1];let preferredScopes:[ServiceContactPreferredScopeV1];let handoffIntents:[SystemHandoffIntentV1];let importSourceSet:ImportSourceSetV1?
    init(workspaceID:WorkspaceID,mutationID:MutationIDV1,expectedRevision:WorkspaceExpectedRevisionV1,predecessors:[ServiceContactPointV1]=[],successors:[ServiceContactPointV1]=[],preferredScopes:[ServiceContactPreferredScopeV1]=[],handoffIntents:[SystemHandoffIntentV1]=[],importSourceSet:ImportSourceSetV1?=nil)throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.mutationID=mutationID;self.expectedRevision=expectedRevision;self.predecessors=predecessors.sorted{$0.contactPointID.uuidString<$1.contactPointID.uuidString};self.successors=successors.sorted{$0.contactPointID.uuidString<$1.contactPointID.uuidString};self.preferredScopes=preferredScopes.sorted{($0.partyID.uuidString,$0.kind.rawValue)<($1.partyID.uuidString,$1.kind.rawValue)};self.handoffIntents=handoffIntents.sorted{$0.intentID.uuidString<$1.intentID.uuidString};self.importSourceSet=importSourceSet;try validate()}
    func validate()throws{
        guard schemaVersion==Self.schemaVersion,expectedRevision.workspaceID==workspaceID,!successors.isEmpty || !handoffIntents.isEmpty,successors.count+handoffIntents.count<=OperationalContactLimitsV1.maximumMutationContacts,predecessors.count<=successors.count,Set(predecessors.map(\.contactPointID)).count==predecessors.count,Set(successors.map(\.contactPointID)).count==successors.count,Set(handoffIntents.map(\.intentID)).count==handoffIntents.count else{throw OperationalContactFailureV1.limitExceeded}
        let prior=Dictionary(uniqueKeysWithValues:predecessors.map{($0.contactPointID,$0)});for value in predecessors+successors{try value.validate();guard value.workspaceID==workspaceID else{throw OperationalContactFailureV1.crossWorkspaceReference}}
        for successor in successors { guard successor.mutationID==mutationID else{throw OperationalContactFailureV1.invalidValue};if let predecessor=prior[successor.contactPointID]{let(next,overflow)=predecessor.revision.addingReportingOverflow(1);guard !overflow,successor.revision==next,successor.supersedes==(try predecessor.revisionReference),successor.party.partyID==predecessor.party.partyID,successor.party.workspaceID==predecessor.party.workspaceID,successor.party.kind==predecessor.party.kind,successor.party.revision>=predecessor.party.revision,successor.kind==predecessor.kind else{throw OperationalContactFailureV1.staleRevision}}else{guard successor.revision==1,successor.supersedes==nil else{throw OperationalContactFailureV1.staleRevision}} }
        let scopeKeys=preferredScopes.map{"\($0.partyID.uuidString):\($0.kind.rawValue)"};guard Set(scopeKeys).count==scopeKeys.count else{throw OperationalContactFailureV1.preferredConflict}
        for successor in successors where successor.lifecycle == .effective { guard let scope=preferredScopes.first(where:{$0.partyID==successor.party.partyID&&$0.kind==successor.kind}),scope.activeContactPointIDs.contains(successor.contactPointID),(successor.preferred ? scope.preferredContactPointID==successor.contactPointID : true) else{throw OperationalContactFailureV1.preferredConflict} }
        for intent in handoffIntents{try intent.validate();guard intent.workspaceID==workspaceID,intent.mutationID==mutationID else{throw OperationalContactFailureV1.crossWorkspaceReference}}
        if let importSourceSet{guard importSourceSet.workspaceID==workspaceID else{throw OperationalContactFailureV1.crossWorkspaceReference}}
        let imported=successors.filter{$0.provenance == .importedExternalEvidence};guard imported.isEmpty ? importSourceSet == nil : (importSourceSet != nil && imported.allSatisfy{$0.importSourceSetSHA256==importSourceSet?.sourceSetSHA256}) else{throw OperationalContactFailureV1.invalidValue}
        let concurrency=try concurrencyIdentities;guard concurrency.allSatisfy({ identity in expectedRevision.entityRevisions.contains(where:{$0.identity==identity}) }) else{throw OperationalContactFailureV1.staleRevision}
        for successor in successors{let identity=try WorkspaceEntityIdentityV1(kind:.serviceContactPoint,id:successor.contactPointID),expected=try expectedRevision(for:identity);guard expected == (prior[successor.contactPointID]?.revision ?? 0) else{throw OperationalContactFailureV1.staleRevision}}
        for intent in handoffIntents{let identity=try WorkspaceEntityIdentityV1(kind:.systemHandoffIntent,id:intent.intentID);guard try expectedRevision(for:identity)==0 else{throw OperationalContactFailureV1.staleRevision}}
    }
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{try (successors.map{try .init(kind:.serviceContactPoint,id:$0.contactPointID)}+handoffIntents.map{try .init(kind:.systemHandoffIntent,id:$0.intentID)}).sorted{$0.stableKey<$1.stableKey}}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{try Array(Set(affectedIdentities+preferredScopes.map{try .init(kind:.serviceParty,id:$0.partyID)})).sorted{$0.stableKey<$1.stableKey}}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{guard let row=expectedRevision.entityRevisions.first(where:{$0.identity==identity})else{throw OperationalContactFailureV1.staleRevision};return row.revision}
    var mutationPostImages:[MutationPostImageV1]{get throws{try (successors.map{value in let c=try WorkspaceEntityIdentityV1(kind:.serviceContactPoint,id:value.contactPointID);return MutationPostImageV1.serviceContactPoint(id:value.contactPointID,concurrencyIdentity:c,revision:value.revision,semanticSHA256:value.contactPointSHA256)}+handoffIntents.map{value in let c=try WorkspaceEntityIdentityV1(kind:.systemHandoffIntent,id:value.intentID);return MutationPostImageV1.systemHandoffIntent(id:value.intentID,concurrencyIdentity:c,revision:value.revision,semanticSHA256:value.intentSHA256)}).sorted{try $0.identity.stableKey<$1.identity.stableKey}}}
    func canonicalWorkspaceMutationRequest()throws->WorkspaceMutationRequestV1{try validate();return WorkspaceMutationRequestV1(mutationID:mutationID,expectedRevision:expectedRevision,command:.applyOperationalContact(self))}
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,workspaceID,mutationID,expectedRevision,predecessors,successors,preferredScopes,handoffIntents,importSourceSet}
    init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);guard try c.decode(Int.self,forKey:.schemaVersion)==Self.schemaVersion else{throw OperationalContactFailureV1.incompatibleVersion};try self.init(workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),mutationID:c.decode(MutationIDV1.self,forKey:.mutationID),expectedRevision:c.decode(WorkspaceExpectedRevisionV1.self,forKey:.expectedRevision),predecessors:c.decode([ServiceContactPointV1].self,forKey:.predecessors),successors:c.decode([ServiceContactPointV1].self,forKey:.successors),preferredScopes:c.decode([ServiceContactPreferredScopeV1].self,forKey:.preferredScopes),handoffIntents:c.decode([SystemHandoffIntentV1].self,forKey:.handoffIntents),importSourceSet:c.decodeIfPresent(ImportSourceSetV1.self,forKey:.importSourceSet))}
}

enum SystemHandoffKindV1:String,Codable,CaseIterable,Hashable,Sendable{case directions="DIRECTIONS";case call="CALL";case text="TEXT";case email="EMAIL"}
enum SystemHandoffTargetKindV1:String,Codable,CaseIterable,Hashable,Sendable{case site="SITE";case serviceContactPoint="SERVICE_CONTACT_POINT"}
enum SystemHandoffIntentDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{case activeSourceWorkspace="ACTIVE_SOURCE_WORKSPACE";case historicReferenceOnly="HISTORIC_REFERENCE_ONLY"}
struct SystemHandoffTargetReferenceV1:Codable,Equatable,Hashable,Sendable{let workspaceID:WorkspaceID;let kind:SystemHandoffTargetKindV1;let targetID:UUID;let expectedRevision:UInt64;let expectedSHA256:String;init(workspaceID:WorkspaceID,kind:SystemHandoffTargetKindV1,targetID:UUID,expectedRevision:UInt64,expectedSHA256:String)throws{try OperationalContactValidationV1.id(targetID);try OperationalContactValidationV1.digest(expectedSHA256);guard expectedRevision>0 else{throw OperationalContactFailureV1.invalidHandoffTarget};self.workspaceID=workspaceID;self.kind=kind;self.targetID=targetID;self.expectedRevision=expectedRevision;self.expectedSHA256=expectedSHA256};private enum CodingKeys:String,CodingKey,CaseIterable{case workspaceID,kind,targetID,expectedRevision,expectedSHA256};init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),kind:c.decode(SystemHandoffTargetKindV1.self,forKey:.kind),targetID:c.decode(UUID.self,forKey:.targetID),expectedRevision:c.decode(UInt64.self,forKey:.expectedRevision),expectedSHA256:c.decode(String.self,forKey:.expectedSHA256))}}
struct SystemHandoffIntentV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let intentID:UUID;let workspaceID:WorkspaceID;let kind:SystemHandoffKindV1;let target:SystemHandoffTargetReferenceV1;let reviewedAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let disposition:SystemHandoffIntentDispositionV1;let intentSHA256:String;init(intentID:UUID,workspaceID:WorkspaceID,kind:SystemHandoffKindV1,target:SystemHandoffTargetReferenceV1,reviewedAt:Date,revision:UInt64,mutationID:MutationIDV1,disposition:SystemHandoffIntentDispositionV1 = .activeSourceWorkspace)throws{schemaVersion=Self.schemaVersion;self.intentID=intentID;self.workspaceID=workspaceID;self.kind=kind;self.target=target;self.reviewedAt=reviewedAt;self.revision=revision;self.mutationID=mutationID;self.disposition=disposition;intentSHA256=try OperationalContactCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,intentID:intentID,workspaceID:workspaceID,kind:kind,target:target,reviewedAt:reviewedAt,revision:revision,mutationID:mutationID,disposition:disposition));try validate()};func validate()throws{try OperationalContactValidationV1.id(intentID);let scopeIsValid=disposition == .activeSourceWorkspace ? target.workspaceID==workspaceID : target.workspaceID != workspaceID;guard schemaVersion==Self.schemaVersion,revision==1,scopeIsValid,(kind == .directions ? target.kind == .site : target.kind == .serviceContactPoint),intentSHA256==(try OperationalContactCanonicalCodecV1.sha256(Basis(schemaVersion:schemaVersion,intentID:intentID,workspaceID:workspaceID,kind:kind,target:target,reviewedAt:reviewedAt,revision:revision,mutationID:mutationID,disposition:disposition)))else{throw OperationalContactFailureV1.invalidHandoffTarget}};func reboundForHistoricRestore(to workspaceID:WorkspaceID,mutationID:MutationIDV1)throws->Self{try Self(intentID:intentID,workspaceID:workspaceID,kind:kind,target:target,reviewedAt:reviewedAt,revision:1,mutationID:mutationID,disposition:.historicReferenceOnly)};private struct Basis:Codable{let schemaVersion:Int;let intentID:UUID;let workspaceID:WorkspaceID;let kind:SystemHandoffKindV1;let target:SystemHandoffTargetReferenceV1;let reviewedAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let disposition:SystemHandoffIntentDispositionV1};private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,intentID,workspaceID,kind,target,reviewedAt,revision,mutationID,disposition,intentSHA256};init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let v=try Self(intentID:c.decode(UUID.self,forKey:.intentID),workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),kind:c.decode(SystemHandoffKindV1.self,forKey:.kind),target:c.decode(SystemHandoffTargetReferenceV1.self,forKey:.target),reviewedAt:c.decode(Date.self,forKey:.reviewedAt),revision:c.decode(UInt64.self,forKey:.revision),mutationID:c.decode(MutationIDV1.self,forKey:.mutationID),disposition:c.decode(SystemHandoffIntentDispositionV1.self,forKey:.disposition));guard try c.decode(Int.self,forKey:.schemaVersion)==Self.schemaVersion,c.decode(String.self,forKey:.intentSHA256)==v.intentSHA256 else{throw OperationalContactFailureV1.digestMismatch};self=v}}
enum SystemHandoffDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{case handedOffToSystem="HANDED_OFF_TO_SYSTEM";case targetMissing="TARGET_MISSING";case targetStale="TARGET_STALE";case targetInvalid="TARGET_INVALID";case systemUnavailable="SYSTEM_UNAVAILABLE";case systemRejected="SYSTEM_REJECTED";case cancelledBeforeHandoff="CANCELLED_BEFORE_HANDOFF"}
struct SystemHandoffResultV1:Codable,Equatable,Sendable{let intentID:UUID;let disposition:SystemHandoffDispositionV1;let evaluatedAt:Date;let resolvedTargetRevision:UInt64?;init(intentID:UUID,disposition:SystemHandoffDispositionV1,evaluatedAt:Date,resolvedTargetRevision:UInt64?=nil)throws{try OperationalContactValidationV1.id(intentID);guard resolvedTargetRevision.map{$0>0} ?? true else{throw OperationalContactFailureV1.invalidValue};self.intentID=intentID;self.disposition=disposition;self.evaluatedAt=evaluatedAt;self.resolvedTargetRevision=resolvedTargetRevision}}
enum SystemHandoffDestinationV1:Equatable,Sendable{case geographicCoordinate(latitudeMicrodegrees:Int32,longitudeMicrodegrees:Int32);case exactAddress(String);case phone(String);case email(String)
    func validate(for kind:SystemHandoffKindV1)throws{switch(self,kind){case let(.geographicCoordinate(lat,lon),.directions):guard (-90_000_000...90_000_000).contains(lat),(-180_000_000...180_000_000).contains(lon)else{throw OperationalContactFailureV1.invalidHandoffTarget};case let(.exactAddress(value),.directions):try OperationalContactValidationV1.text(value,maximumBytes:OperationalContactLimitsV1.maximumDisplayValueBytes);guard !value.contains("?")&&!value.contains("\r")&&!value.contains("\n")else{throw OperationalContactFailureV1.invalidHandoffTarget};case let(.phone(value),.call),let(.phone(value),.text):try OperationalContactValidationV1.text(value,maximumBytes:OperationalContactLimitsV1.maximumDisplayValueBytes);let allowed=CharacterSet(charactersIn:"+0123456789 -().");guard value.unicodeScalars.allSatisfy(allowed.contains),value.unicodeScalars.contains(where:{(48...57).contains(Int($0.value))}),!value.contains("*")&&!value.contains("#")&&!value.contains(",")&&!value.contains(";")else{throw OperationalContactFailureV1.invalidHandoffTarget};case let(.email(value),.email):try OperationalContactValidationV1.text(value,maximumBytes:OperationalContactLimitsV1.maximumDisplayValueBytes);guard value.filter({$0=="@"}).count==1,!value.contains("?")&&!value.contains("&")&&!value.contains(",")&&!value.contains(";")&&!value.contains("\r")&&!value.contains("\n")else{throw OperationalContactFailureV1.invalidHandoffTarget};default:throw OperationalContactFailureV1.invalidHandoffTarget}}
}
struct SystemHandoffRequestV1:Equatable,Sendable{let intent:SystemHandoffIntentV1;let currentTarget:SystemHandoffTargetReferenceV1;let destination:SystemHandoffDestinationV1;init(intent:SystemHandoffIntentV1,currentTarget:SystemHandoffTargetReferenceV1,destination:SystemHandoffDestinationV1)throws{try intent.validate();guard intent.disposition == .activeSourceWorkspace,currentTarget==intent.target else{throw OperationalContactFailureV1.staleRevision};try destination.validate(for:intent.kind);self.intent=intent;self.currentTarget=currentTarget;self.destination=destination}}
enum SystemHandoffResolutionV1:Equatable,Sendable{case resolved(SystemHandoffRequestV1);case targetMissing;case targetStale;case targetInvalid}
@MainActor protocol SystemHandoffTargetResolvingV1:AnyObject{func resolveForHandoff(_ intent:SystemHandoffIntentV1)async->SystemHandoffResolutionV1}
@MainActor protocol SystemHandoffPortV1:AnyObject{func handOff(_ request:SystemHandoffRequestV1)async->SystemHandoffResultV1}

enum PartyContactsImportPrivacyClassV1:String,Codable,CaseIterable,Hashable,Sendable{case restrictedContactValue="RESTRICTED_CONTACT_VALUE";case stableWorkspaceKey="STABLE_WORKSPACE_KEY";case operationalDescriptor="OPERATIONAL_DESCRIPTOR"}
struct ImportSourceFileV1:Codable,Equatable,Sendable{let schemaID:String;let schemaVersion:Int;let fileName:String;let orderIndex:Int;let byteCount:Int64;let sha256:String;init(schemaID:String,schemaVersion:Int,fileName:String,orderIndex:Int,byteCount:Int64,sha256:String)throws{try OperationalContactValidationV1.text(schemaID,maximumBytes:64);try OperationalContactValidationV1.text(fileName,maximumBytes:OperationalContactLimitsV1.maximumImportFileNameBytes);try OperationalContactValidationV1.digest(sha256);guard schemaVersion>0,orderIndex>=0,byteCount>0,byteCount<=OperationalContactLimitsV1.maximumImportFileBytes else{throw OperationalContactFailureV1.limitExceeded};self.schemaID=schemaID;self.schemaVersion=schemaVersion;self.fileName=fileName;self.orderIndex=orderIndex;self.byteCount=byteCount;self.sha256=sha256};private enum CodingKeys:String,CodingKey,CaseIterable{case schemaID,schemaVersion,fileName,orderIndex,byteCount,sha256};init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(schemaID:c.decode(String.self,forKey:.schemaID),schemaVersion:c.decode(Int.self,forKey:.schemaVersion),fileName:c.decode(String.self,forKey:.fileName),orderIndex:c.decode(Int.self,forKey:.orderIndex),byteCount:c.decode(Int64.self,forKey:.byteCount),sha256:c.decode(String.self,forKey:.sha256))}}
struct ImportSourceSetV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let files:[ImportSourceFileV1];let sourceSetSHA256:String;init(workspaceID:WorkspaceID,files:[ImportSourceFileV1])throws{let ordered=files.sorted{$0.orderIndex<$1.orderIndex};guard !ordered.isEmpty,ordered.count<=OperationalContactLimitsV1.maximumSourceFiles,ordered.map(\.orderIndex)==Array(0..<ordered.count),Set(ordered.map(\.fileName)).count==ordered.count else{throw OperationalContactFailureV1.limitExceeded};var aggregate:Int64=0;for file in ordered{let(next,overflow)=aggregate.addingReportingOverflow(file.byteCount);guard !overflow,next<=OperationalContactLimitsV1.maximumImportSourceSetBytes else{throw OperationalContactFailureV1.limitExceeded};aggregate=next};schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.files=ordered;sourceSetSHA256=try OperationalContactCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,workspaceID:workspaceID,files:ordered))};private struct Basis:Codable{let schemaVersion:Int;let workspaceID:WorkspaceID;let files:[ImportSourceFileV1]};private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,workspaceID,files,sourceSetSHA256};init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let v=try Self(workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),files:c.decode([ImportSourceFileV1].self,forKey:.files));guard try c.decode(Int.self,forKey:.schemaVersion)==Self.schemaVersion,c.decode(String.self,forKey:.sourceSetSHA256)==v.sourceSetSHA256 else{throw OperationalContactFailureV1.digestMismatch};self=v}}
struct PartyContactCSVRowV1:Codable,Equatable,Sendable{static let schemaID="PARTY_CONTACTS_V1";static let schemaVersion=1;let rowIndex:Int;let contactPointID:UUID;let partyID:UUID;let kind:ServiceContactKindV1;let label:ServiceContactLabelV1;let displayValue:String;let preferred:Bool;let effectiveAt:Date;let retiredAt:Date?;let revision:UInt64;init(rowIndex:Int,contactPointID:UUID,partyID:UUID,kind:ServiceContactKindV1,label:ServiceContactLabelV1,displayValue:String,preferred:Bool,effectiveAt:Date,retiredAt:Date?=nil,revision:UInt64)throws{guard rowIndex>0,revision>0 else{throw OperationalContactFailureV1.invalidValue};try OperationalContactValidationV1.id(contactPointID);try OperationalContactValidationV1.id(partyID);try OperationalContactValidationV1.contactValue(displayValue,kind:kind);guard retiredAt.map{$0>=effectiveAt} ?? true else{throw OperationalContactFailureV1.invalidValue};self.rowIndex=rowIndex;self.contactPointID=contactPointID;self.partyID=partyID;self.kind=kind;self.label=label;self.displayValue=displayValue;self.preferred=preferred;self.effectiveAt=effectiveAt;self.retiredAt=retiredAt;self.revision=revision};private enum CodingKeys:String,CodingKey,CaseIterable{case rowIndex,contactPointID,partyID,kind,label,displayValue,preferred,effectiveAt,retiredAt,revision};init(from decoder:Decoder)throws{try OperationalContactClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(rowIndex:c.decode(Int.self,forKey:.rowIndex),contactPointID:c.decode(UUID.self,forKey:.contactPointID),partyID:c.decode(UUID.self,forKey:.partyID),kind:c.decode(ServiceContactKindV1.self,forKey:.kind),label:c.decode(ServiceContactLabelV1.self,forKey:.label),displayValue:c.decode(String.self,forKey:.displayValue),preferred:c.decode(Bool.self,forKey:.preferred),effectiveAt:c.decode(Date.self,forKey:.effectiveAt),retiredAt:c.decodeIfPresent(Date.self,forKey:.retiredAt),revision:c.decode(UInt64.self,forKey:.revision))}}
enum PartyContactsCSVContractV1{static let schemaID=PartyContactCSVRowV1.schemaID;static let schemaVersion=PartyContactCSVRowV1.schemaVersion;static let defaultExportEnabled=false;static let valuePrivacyClass:PartyContactsImportPrivacyClassV1 = .restrictedContactValue;static let correctionFields=["displayValue"]}
enum OperationalContactPersistenceEnrollmentV1{static let persistentSchemaVersion=35;static let recordsSchemaVersion=34;static let durableModelCount=2;static let persistentFamilies=["ServiceContactPointRow","SystemHandoffIntentRow"];static let handoffIntentIsPersistent=true;static let handoffOutcomeIsPersistent=false;static let importSourceBytesArePersistent=false}

@MainActor protocol OperationalContactQueryingV1:AnyObject{
    func currentContactPoint(workspaceID:WorkspaceID,contactPointID:UUID)async throws->ServiceContactPointV1?
    func currentContactPoints(workspaceID:WorkspaceID,partyID:UUID,kind:ServiceContactKindV1)async throws->[ServiceContactPointV1]
    func handoffIntent(workspaceID:WorkspaceID,intentID:UUID)async throws->SystemHandoffIntentV1?
}
@MainActor protocol OperationalContactMutationCommittingV1:AnyObject{
    func commitOperationalContact(_ mutation:OperationalContactMutationV1)async throws->OperationalContactMutationReceiptV1
    func durableOperationalContactReceipt(workspaceID:WorkspaceID,mutationID:MutationIDV1)async throws->OperationalContactMutationReceiptV1?
}
enum OperationalContactProjectionPolicyV1{
    static let includedInDefaultExport=false
    static let includedInSpotlight=false
    static let includedInDiagnostics=false
    static let includedInMeasurement=false
    static let includedInMarketing=false
    static let reportProjectionCarriesContactValue=false
}
enum C52ServiceRequestBoundary_OperationalContactContractsV1 {
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

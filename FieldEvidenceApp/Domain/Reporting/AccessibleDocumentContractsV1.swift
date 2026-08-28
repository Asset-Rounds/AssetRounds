import Foundation

enum AccessibleDocumentFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, duplicateIdentity, missingParent, invalidOrder
    case invalidHeading, invalidTable, inventedAlternateText, privacyViolation, missingEvidence
    case digestMismatch, staleAssessment, invalidSuccessor, unsupportedConformanceClaim
}

enum AccessibleDocumentRoleV1: String, CaseIterable, Codable, Hashable, Sendable {
    case document = "DOCUMENT", section = "SECTION", heading = "HEADING", paragraph = "PARAGRAPH"
    case list = "LIST", listItem = "LIST_ITEM", table = "TABLE", tableRow = "TABLE_ROW"
    case tableHeader = "TABLE_HEADER", tableCell = "TABLE_CELL", figure = "FIGURE"
    case evidenceLink = "EVIDENCE_LINK", note = "NOTE"
}

enum AccessibleDocumentSensitivityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case customerSafe = "CUSTOMER_SAFE", internalOnly = "INTERNAL_ONLY"
}

enum AccessibleAlternateTextProvenanceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case authoredForSource = "AUTHORED_FOR_SOURCE"
    case sourceCaption = "SOURCE_CAPTION"
    case notProvided = "NOT_PROVIDED"
}

enum AccessibleTableHeaderScopeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case row = "ROW", column = "COLUMN", rowGroup = "ROW_GROUP", columnGroup = "COLUMN_GROUP"
}

enum AccessibleDocumentAssessmentStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case internalPass = "INTERNAL_PASS"
    case internalFail = "INTERNAL_FAIL"
    case incomplete = "INCOMPLETE"
    case externallyProved = "EXTERNALLY_PROVED"
}
enum AccessibleDocumentAssessmentScopeV1:String,CaseIterable,Codable,Hashable,Sendable{case currentOutput="CURRENT_OUTPUT",historicSource="HISTORIC_SOURCE"}

enum AccessibleDocumentValidationV1 {
    static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    static func id(_ value: String) throws {
        guard SnapshotProjectionValidationV1.validID(value), value.utf8.count <= 256 else { throw AccessibleDocumentFailureV1.invalidValue }
    }
    static func text(_ value: String, maximumBytes: Int = 2_048) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == trimmed, !value.isEmpty, value.utf8.count <= maximumBytes,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0.value == 10 }) else {
            throw AccessibleDocumentFailureV1.invalidValue
        }
    }
    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw AccessibleDocumentFailureV1.digestMismatch }
    }
}

struct AccessibleEvidenceLinkV1: Codable, Equatable, Hashable, Sendable {
    let evidenceID: String
    let evidenceSHA256: String
    let mediaType: String
    init(evidenceID: String, evidenceSHA256: String, mediaType: String = "application/octet-stream") throws {
        try AccessibleDocumentValidationV1.id(evidenceID); try AccessibleDocumentValidationV1.digest(evidenceSHA256)
        guard ContentContractValidationV1.validMediaType(mediaType) else { throw AccessibleDocumentFailureV1.invalidValue }
        self.evidenceID = evidenceID; self.evidenceSHA256 = evidenceSHA256; self.mediaType = mediaType
    }
    init(outputReference:OutputScopedContentReferenceV1)throws{try outputReference.validate();try self.init(evidenceID:outputReference.outputReferenceID,evidenceSHA256:outputReference.contentSHA256,mediaType:outputReference.mediaType)}
    func validate()throws{try AccessibleDocumentValidationV1.id(evidenceID);try AccessibleDocumentValidationV1.digest(evidenceSHA256);guard ContentContractValidationV1.validMediaType(mediaType) else{throw AccessibleDocumentFailureV1.invalidValue}}
}

struct AccessibleDocumentNodeV1: Codable, Equatable, Sendable {
    let nodeID: String
    let role: AccessibleDocumentRoleV1
    let parentNodeID: String?
    let order: Int
    let headingLevel: Int?
    let tableHeaderScope: AccessibleTableHeaderScopeV1?
    let tableHeaderNodeIDs: [String]
    let localizedText: String?
    let alternateText: String?
    let alternateTextProvenance: AccessibleAlternateTextProvenanceV1?
    let decorative: Bool
    let evidenceLinks: [AccessibleEvidenceLinkV1]
    let sensitivity: AccessibleDocumentSensitivityV1

    init(nodeID:String,role:AccessibleDocumentRoleV1,parentNodeID:String?,order:Int,headingLevel:Int?=nil,
         tableHeaderScope:AccessibleTableHeaderScopeV1?=nil,tableHeaderNodeIDs:[String]=[],localizedText:String?=nil,
         alternateText:String?=nil,alternateTextProvenance:AccessibleAlternateTextProvenanceV1?=nil,
         decorative:Bool=false,evidenceLinks:[AccessibleEvidenceLinkV1]=[],sensitivity:AccessibleDocumentSensitivityV1) throws {
        self.nodeID=nodeID;self.role=role;self.parentNodeID=parentNodeID;self.order=order;self.headingLevel=headingLevel
        self.tableHeaderScope=tableHeaderScope;self.tableHeaderNodeIDs=tableHeaderNodeIDs
        self.localizedText=localizedText;self.alternateText=alternateText;self.alternateTextProvenance=alternateTextProvenance
        self.decorative=decorative;self.evidenceLinks=evidenceLinks.sorted{$0.evidenceID<$1.evidenceID};self.sensitivity=sensitivity
        try validate()
    }

    func validate() throws {
        try AccessibleDocumentValidationV1.id(nodeID); if let parentNodeID { try AccessibleDocumentValidationV1.id(parentNodeID) }
        guard order >= 0, tableHeaderNodeIDs == tableHeaderNodeIDs.sorted(), Set(tableHeaderNodeIDs).count == tableHeaderNodeIDs.count,
              evidenceLinks == evidenceLinks.sorted(by:{$0.evidenceID<$1.evidenceID}), Set(evidenceLinks.map(\.evidenceID)).count == evidenceLinks.count else {
            throw AccessibleDocumentFailureV1.invalidOrder
        }
        try tableHeaderNodeIDs.forEach(AccessibleDocumentValidationV1.id);try evidenceLinks.forEach{$0.validate()}
        if let localizedText { try AccessibleDocumentValidationV1.text(localizedText) }
        if let alternateText { try AccessibleDocumentValidationV1.text(alternateText) }
        guard (role == .heading) == (headingLevel != nil), headingLevel.map{(1...6).contains($0)} ?? true,
              (role == .tableHeader) == (tableHeaderScope != nil),
              role == .tableCell || tableHeaderNodeIDs.isEmpty else { throw AccessibleDocumentFailureV1.invalidValue }
        if role == .figure {
            if decorative {
                guard alternateText == nil, alternateTextProvenance == nil else { throw AccessibleDocumentFailureV1.inventedAlternateText }
            } else {
                guard (alternateText == nil) == (alternateTextProvenance == .notProvided),
                      alternateText == nil || alternateTextProvenance == .authoredForSource || alternateTextProvenance == .sourceCaption else {
                    throw AccessibleDocumentFailureV1.inventedAlternateText
                }
            }
        } else {
            guard !decorative, alternateText == nil, alternateTextProvenance == nil else { throw AccessibleDocumentFailureV1.inventedAlternateText }
        }
    }
}

struct AccessibleDocumentPublicationBindingV1: Codable, Equatable, Sendable {
    let snapshotSHA256: String
    let manifestID: String
    let manifestVersion: Int
    let manifestSHA256: String
    let localeIdentifier: String
    let profileID: String
    let profileRelease: Int
    let profileSHA256: String
    let brandProfileID: String
    let brandProfileRelease: Int
    let brandProfileSHA256: String

    init(snapshotSHA256:String,manifestID:String,manifestVersion:Int,manifestSHA256:String,localeIdentifier:String,
         profileID:String,profileRelease:Int,profileSHA256:String,brandProfileID:String,brandProfileRelease:Int,
         brandProfileSHA256:String) throws {
        try AccessibleDocumentValidationV1.digest(snapshotSHA256);try AccessibleDocumentValidationV1.id(manifestID)
        try AccessibleDocumentValidationV1.digest(manifestSHA256);try AccessibleDocumentValidationV1.text(localeIdentifier,maximumBytes:64)
        try AccessibleDocumentValidationV1.id(profileID);try AccessibleDocumentValidationV1.digest(profileSHA256)
        try AccessibleDocumentValidationV1.id(brandProfileID);try AccessibleDocumentValidationV1.digest(brandProfileSHA256)
        guard manifestVersion>0,profileRelease>0,brandProfileRelease>0 else{throw AccessibleDocumentFailureV1.invalidValue}
        self.snapshotSHA256=snapshotSHA256;self.manifestID=manifestID;self.manifestVersion=manifestVersion;self.manifestSHA256=manifestSHA256
        self.localeIdentifier=localeIdentifier;self.profileID=profileID;self.profileRelease=profileRelease;self.profileSHA256=profileSHA256
        self.brandProfileID=brandProfileID;self.brandProfileRelease=brandProfileRelease;self.brandProfileSHA256=brandProfileSHA256
    }
    func validate()throws{try AccessibleDocumentValidationV1.digest(snapshotSHA256);try AccessibleDocumentValidationV1.id(manifestID);try AccessibleDocumentValidationV1.digest(manifestSHA256);try AccessibleDocumentValidationV1.text(localeIdentifier,maximumBytes:64);try AccessibleDocumentValidationV1.id(profileID);try AccessibleDocumentValidationV1.digest(profileSHA256);try AccessibleDocumentValidationV1.id(brandProfileID);try AccessibleDocumentValidationV1.digest(brandProfileSHA256);guard manifestVersion>0,profileRelease>0,brandProfileRelease>0 else{throw AccessibleDocumentFailureV1.invalidValue}}
}

struct AccessibleDocumentSemanticTreeV1: Codable, Equatable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let treeID:UUID;let workspaceID:WorkspaceID;let audience:ReportAudienceV1
    let publication:AccessibleDocumentPublicationBindingV1;let nodes:[AccessibleDocumentNodeV1]
    let projectionVersion:String;let pdfUAClaimed:Bool;let wcagClaimed:Bool;let legalCertificationClaimed:Bool
    let s10BrandReconciled:Bool;let treeSHA256:String

    init(treeID:UUID,workspaceID:WorkspaceID,audience:ReportAudienceV1,publication:AccessibleDocumentPublicationBindingV1,
         nodes:[AccessibleDocumentNodeV1],projectionVersion:String,pdfUAClaimed:Bool=false,wcagClaimed:Bool=false,
         legalCertificationClaimed:Bool=false,s10BrandReconciled:Bool=false)throws{
        let canonicalNodes=nodes.sorted{(($0.parentNodeID ?? ""),$0.order,$0.nodeID)<(($1.parentNodeID ?? ""),$1.order,$1.nodeID)}
        schemaVersion=Self.schemaVersion;self.treeID=treeID;self.workspaceID=workspaceID;self.audience=audience;self.publication=publication
        self.nodes=canonicalNodes;self.projectionVersion=projectionVersion;self.pdfUAClaimed=pdfUAClaimed;self.wcagClaimed=wcagClaimed
        self.legalCertificationClaimed=legalCertificationClaimed;self.s10BrandReconciled=s10BrandReconciled
        treeSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,treeID:treeID,workspaceID:workspaceID,audience:audience,publication:publication,nodes:canonicalNodes,projectionVersion:projectionVersion,pdfUAClaimed:pdfUAClaimed,wcagClaimed:wcagClaimed,legalCertificationClaimed:legalCertificationClaimed,s10BrandReconciled:s10BrandReconciled));try validate()
    }

    func validate()throws{
        try AccessibleDocumentValidationV1.id(projectionVersion);try publication.validate();guard schemaVersion==Self.schemaVersion,treeID != AccessibleDocumentValidationV1.zero,
              !nodes.isEmpty,nodes.count<=10_000,nodes==nodes.sorted(by:{(($0.parentNodeID ?? ""),$0.order,$0.nodeID)<(($1.parentNodeID ?? ""),$1.order,$1.nodeID)}),Set(nodes.map(\.nodeID)).count==nodes.count,
              nodes.filter({$0.role == .document && $0.parentNodeID == nil}).count==1,
              !pdfUAClaimed,!wcagClaimed,!legalCertificationClaimed,!s10BrandReconciled else{throw AccessibleDocumentFailureV1.unsupportedConformanceClaim}
        try nodes.forEach{$0.validate()};let byID=Dictionary(uniqueKeysWithValues:nodes.map{($0.nodeID,$0)});guard nodes.filter({$0.parentNodeID == nil}).count==1 else{throw AccessibleDocumentFailureV1.missingParent}
        for node in nodes{if let parent=node.parentNodeID{guard let parentNode=byID[parent],parent != node.nodeID else{throw AccessibleDocumentFailureV1.missingParent};guard node.order < nodes.filter({$0.parentNodeID==parent}).count else{throw AccessibleDocumentFailureV1.invalidOrder};if node.role == .tableRow{guard parentNode.role == .table else{throw AccessibleDocumentFailureV1.invalidTable}};if [.tableHeader,.tableCell].contains(node.role){guard parentNode.role == .tableRow else{throw AccessibleDocumentFailureV1.invalidTable}}};for header in node.tableHeaderNodeIDs{guard byID[header]?.role == .tableHeader else{throw AccessibleDocumentFailureV1.invalidTable}}}
        for parent in Set(nodes.compactMap(\.parentNodeID)){let orders=nodes.filter{$0.parentNodeID==parent}.map(\.order).sorted();guard orders==Array(0..<orders.count)else{throw AccessibleDocumentFailureV1.invalidOrder}}
        guard let root=nodes.first(where:{$0.parentNodeID==nil})else{throw AccessibleDocumentFailureV1.missingParent};for node in nodes{var cursor=node;var visited=Set<String>();while let parent=cursor.parentNodeID{guard visited.insert(cursor.nodeID).inserted,let next=byID[parent]else{throw AccessibleDocumentFailureV1.missingParent};cursor=next};guard cursor.nodeID==root.nodeID else{throw AccessibleDocumentFailureV1.missingParent}}
        if audience == .customerSafe, nodes.contains(where:{$0.sensitivity == .internalOnly}){throw AccessibleDocumentFailureV1.privacyViolation}
        guard treeSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw AccessibleDocumentFailureV1.digestMismatch}
    }
    private var basis:Basis{.init(schemaVersion:schemaVersion,treeID:treeID,workspaceID:workspaceID,audience:audience,publication:publication,nodes:nodes,projectionVersion:projectionVersion,pdfUAClaimed:pdfUAClaimed,wcagClaimed:wcagClaimed,legalCertificationClaimed:legalCertificationClaimed,s10BrandReconciled:s10BrandReconciled)}
    private struct Basis:Codable{let schemaVersion:Int;let treeID:UUID;let workspaceID:WorkspaceID;let audience:ReportAudienceV1;let publication:AccessibleDocumentPublicationBindingV1;let nodes:[AccessibleDocumentNodeV1];let projectionVersion:String;let pdfUAClaimed:Bool;let wcagClaimed:Bool;let legalCertificationClaimed:Bool;let s10BrandReconciled:Bool}
}

struct AccessibleDocumentTreeBuildInputV1: Sendable {
    let workspaceID: WorkspaceID
    let audience: ReportAudienceV1
    let publication: AccessibleDocumentPublicationBindingV1
    let nodes: [AccessibleDocumentNodeV1]
    let projectionVersion: String
    init(workspaceID:WorkspaceID,audience:ReportAudienceV1,publication:AccessibleDocumentPublicationBindingV1,nodes:[AccessibleDocumentNodeV1],projectionVersion:String){self.workspaceID=workspaceID;self.audience=audience;self.publication=publication;self.nodes=nodes;self.projectionVersion=projectionVersion}
}

enum AccessibleDocumentSemanticTreeResolverV1 {
    static func rebuild(_ input:AccessibleDocumentTreeBuildInputV1)throws->AccessibleDocumentSemanticTreeV1{
        let seed=try WorkspaceMutationCanonicalV1.sha256(TreeIdentityBasis(workspaceID:input.workspaceID,audience:input.audience,publication:input.publication,projectionVersion:input.projectionVersion))
        let characters=Array(seed);guard characters.count==64 else{throw AccessibleDocumentFailureV1.digestMismatch};let bytes=try stride(from:0,to:32,by:2).map{index->UInt8 in guard let value=UInt8(String([characters[index],characters[index+1]]),radix:16)else{throw AccessibleDocumentFailureV1.digestMismatch};return value}
        let id=UUID(uuid:(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        return try AccessibleDocumentSemanticTreeV1(treeID:id,workspaceID:input.workspaceID,audience:input.audience,publication:input.publication,nodes:input.nodes,projectionVersion:input.projectionVersion)
    }
    private struct TreeIdentityBasis:Codable{let workspaceID:WorkspaceID;let audience:ReportAudienceV1;let publication:AccessibleDocumentPublicationBindingV1;let projectionVersion:String}
}

struct AccessibleDocumentSemanticTreeResolutionRequestV1:Sendable{
    let workspaceID:WorkspaceID;let treeSHA256:String;let snapshotSHA256:String;let audience:ReportAudienceV1;let projectionVersion:String
    let manifestID:String;let manifestVersion:Int;let manifestSHA256:String;let localeIdentifier:String
    let profileID:String;let profileRelease:Int;let profileSHA256:String
    let brandProfileID:String;let brandProfileRelease:Int;let brandProfileSHA256:String
    init(receipt:AccessibleDocumentAssessmentReceiptV1)throws{try receipt.validateIntrinsic();workspaceID=receipt.workspaceID;treeSHA256=receipt.treeSHA256;snapshotSHA256=receipt.snapshotSHA256;audience=receipt.audience;projectionVersion=receipt.projectionVersion;manifestID=receipt.manifestID;manifestVersion=receipt.manifestVersion;manifestSHA256=receipt.manifestSHA256;localeIdentifier=receipt.localeIdentifier;profileID=receipt.profileID;profileRelease=receipt.profileRelease;profileSHA256=receipt.profileSHA256;brandProfileID=receipt.brandProfileID;brandProfileRelease=receipt.brandProfileRelease;brandProfileSHA256=receipt.brandProfileSHA256}
    func validate(_ tree:AccessibleDocumentSemanticTreeV1)throws{try tree.validate();guard tree.workspaceID==workspaceID,tree.treeSHA256==treeSHA256,tree.audience==audience,tree.projectionVersion==projectionVersion,tree.publication.snapshotSHA256==snapshotSHA256,tree.publication.manifestID==manifestID,tree.publication.manifestVersion==manifestVersion,tree.publication.manifestSHA256==manifestSHA256,tree.publication.localeIdentifier==localeIdentifier,tree.publication.profileID==profileID,tree.publication.profileRelease==profileRelease,tree.publication.profileSHA256==profileSHA256,tree.publication.brandProfileID==brandProfileID,tree.publication.brandProfileRelease==brandProfileRelease,tree.publication.brandProfileSHA256==brandProfileSHA256 else{throw AccessibleDocumentFailureV1.staleAssessment}}
}
protocol AccessibleDocumentSemanticTreeResolvingV1:Sendable{func resolve(_ request:AccessibleDocumentSemanticTreeResolutionRequestV1)async throws->AccessibleDocumentSemanticTreeV1}
extension AccessibleDocumentSemanticTreeResolvingV1{func resolveValidatedTree(for receipt:AccessibleDocumentAssessmentReceiptV1)async throws->AccessibleDocumentSemanticTreeV1{let request=try AccessibleDocumentSemanticTreeResolutionRequestV1(receipt:receipt);let tree=try await resolve(request);try request.validate(tree);try receipt.validate(tree:tree);return tree}}

enum AccessibleDocumentAudienceProjectorV1{
    static func project(_ input:AccessibleDocumentTreeBuildInputV1)throws->AccessibleDocumentSemanticTreeV1{
        guard input.audience == .customerSafe else{return try AccessibleDocumentSemanticTreeResolverV1.rebuild(input)}
        _ = try AccessibleDocumentSemanticTreeResolverV1.rebuild(.init(workspaceID:input.workspaceID,audience:.internalUse,publication:input.publication,nodes:input.nodes,projectionVersion:input.projectionVersion))
        let sourceIDs=Set(input.nodes.map(\.nodeID));guard sourceIDs.count==input.nodes.count,let root=input.nodes.first(where:{$0.parentNodeID==nil}),root.sensitivity == .customerSafe else{throw AccessibleDocumentFailureV1.privacyViolation}
        var allowed=Set([root.nodeID]);var changed=true;while changed{changed=false;for node in input.nodes where node.sensitivity == .customerSafe && !allowed.contains(node.nodeID){if let parent=node.parentNodeID,allowed.contains(parent){allowed.insert(node.nodeID);changed=true}}}
        var nextOrder:[String:Int]=[:];var projected:[AccessibleDocumentNodeV1]=[];for node in input.nodes where allowed.contains(node.nodeID){let key=node.parentNodeID ?? "<ROOT>";let order=nextOrder[key,default:0];nextOrder[key]=order+1;let headers=node.tableHeaderNodeIDs.filter(allowed.contains);projected.append(try .init(nodeID:node.nodeID,role:node.role,parentNodeID:node.parentNodeID,order:order,headingLevel:node.headingLevel,tableHeaderScope:node.tableHeaderScope,tableHeaderNodeIDs:headers,localizedText:node.localizedText,alternateText:node.alternateText,alternateTextProvenance:node.alternateTextProvenance,decorative:node.decorative,evidenceLinks:node.evidenceLinks,sensitivity:.customerSafe))}
        guard projected.count==allowed.count,projected.allSatisfy({sourceIDs.contains($0.nodeID)})else{throw AccessibleDocumentFailureV1.privacyViolation}
        return try AccessibleDocumentSemanticTreeResolverV1.rebuild(.init(workspaceID:input.workspaceID,audience:input.audience,publication:input.publication,nodes:projected,projectionVersion:input.projectionVersion))
    }
}

struct AccessibleDocumentAssessmentReceiptV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let treeSHA256:String;let snapshotSHA256:String
    let audience:ReportAudienceV1;let projectionVersion:String;let manifestID:String;let manifestVersion:Int;let manifestSHA256:String
    let outputSHA256:String;let outputByteCount:Int64;let outputMediaType:String
    let localeIdentifier:String;let profileID:String;let profileRelease:Int;let profileSHA256:String
    let brandProfileID:String;let brandProfileRelease:Int;let brandProfileSHA256:String
    let rendererID:String;let rendererVersion:String;let assessmentToolID:String;let assessmentToolVersion:String
    let assessor:ActorSnapshotV1;let scope:AccessibleDocumentAssessmentScopeV1;let state:AccessibleDocumentAssessmentStateV1;let externalProof:[AccessibleEvidenceLinkV1]
    let limitations:[String];let assessedAt:Date;let supersedesReceiptID:UUID?;let revision:UInt64;let mutationID:MutationIDV1
    let receiptSHA256:String
    init(receiptID:UUID,workspaceID:WorkspaceID,tree:AccessibleDocumentSemanticTreeV1,outputSHA256:String,outputByteCount:Int64,
         outputMediaType:String,rendererID:String,rendererVersion:String,assessmentToolID:String,assessmentToolVersion:String,
         assessor:ActorSnapshotV1,scope:AccessibleDocumentAssessmentScopeV1 = .currentOutput,state:AccessibleDocumentAssessmentStateV1,externalProof:[AccessibleEvidenceLinkV1]=[],limitations:[String]=[],
         assessedAt:Date,supersedesReceiptID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{
        try tree.validate();schemaVersion=Self.schemaVersion;self.receiptID=receiptID;self.workspaceID=workspaceID;treeSHA256=tree.treeSHA256
        snapshotSHA256=tree.publication.snapshotSHA256;audience=tree.audience;projectionVersion=tree.projectionVersion
        manifestID=tree.publication.manifestID;manifestVersion=tree.publication.manifestVersion;manifestSHA256=tree.publication.manifestSHA256;self.outputSHA256=outputSHA256
        self.outputByteCount=outputByteCount;self.outputMediaType=outputMediaType;localeIdentifier=tree.publication.localeIdentifier
        profileID=tree.publication.profileID;profileRelease=tree.publication.profileRelease;profileSHA256=tree.publication.profileSHA256
        brandProfileID=tree.publication.brandProfileID;brandProfileRelease=tree.publication.brandProfileRelease;brandProfileSHA256=tree.publication.brandProfileSHA256
        self.rendererID=rendererID;self.rendererVersion=rendererVersion;self.assessmentToolID=assessmentToolID;self.assessmentToolVersion=assessmentToolVersion
        self.assessor=assessor;self.scope=scope;self.state=state;self.externalProof=externalProof.sorted{$0.evidenceID<$1.evidenceID};self.limitations=limitations.sorted()
        self.assessedAt=assessedAt;self.supersedesReceiptID=supersedesReceiptID;self.revision=revision;self.mutationID=mutationID
        receiptSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,receiptID:receiptID,workspaceID:workspaceID,treeSHA256:tree.treeSHA256,snapshotSHA256:tree.publication.snapshotSHA256,audience:tree.audience,projectionVersion:tree.projectionVersion,manifestID:tree.publication.manifestID,manifestVersion:tree.publication.manifestVersion,manifestSHA256:tree.publication.manifestSHA256,outputSHA256:outputSHA256,outputByteCount:outputByteCount,outputMediaType:outputMediaType,localeIdentifier:tree.publication.localeIdentifier,profileID:tree.publication.profileID,profileRelease:tree.publication.profileRelease,profileSHA256:tree.publication.profileSHA256,brandProfileID:tree.publication.brandProfileID,brandProfileRelease:tree.publication.brandProfileRelease,brandProfileSHA256:tree.publication.brandProfileSHA256,rendererID:rendererID,rendererVersion:rendererVersion,assessmentToolID:assessmentToolID,assessmentToolVersion:assessmentToolVersion,assessor:assessor,scope:scope,state:state,externalProof:self.externalProof,limitations:self.limitations,assessedAt:assessedAt,supersedesReceiptID:supersedesReceiptID,revision:revision,mutationID:mutationID));try validate(tree:tree)
    }
    func validateIntrinsic()throws{try assessor.validate();try externalProof.forEach{$0.validate()};try [treeSHA256,snapshotSHA256,manifestSHA256,outputSHA256,profileSHA256,brandProfileSHA256,receiptSHA256].forEach(AccessibleDocumentValidationV1.digest);try [projectionVersion,manifestID,outputMediaType,rendererID,rendererVersion,assessmentToolID,assessmentToolVersion,localeIdentifier,profileID,brandProfileID].forEach{try AccessibleDocumentValidationV1.text($0)};try limitations.forEach{try AccessibleDocumentValidationV1.text($0)};guard schemaVersion==Self.schemaVersion,receiptID != AccessibleDocumentValidationV1.zero,manifestVersion>0,profileRelease>0,brandProfileRelease>0,assessor.workspaceID==workspaceID,assessor.responsibility == .reviewedBy,outputByteCount>0,externalProof==externalProof.sorted(by:{$0.evidenceID<$1.evidenceID}),Set(externalProof.map(\.evidenceID)).count==externalProof.count,limitations==limitations.sorted(),Set(limitations).count==limitations.count,state != .externallyProved || !externalProof.isEmpty,scope != .historicSource || (state == .incomplete && limitations.contains(Self.historicSourceLimitation)),revision>0,(supersedesReceiptID==nil)==(revision==1),receiptSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw AccessibleDocumentFailureV1.invalidValue}}
    func validate(tree:AccessibleDocumentSemanticTreeV1)throws{try validateIntrinsic();try tree.validate();guard workspaceID==tree.workspaceID,treeSHA256==tree.treeSHA256,audience==tree.audience,projectionVersion==tree.projectionVersion,snapshotSHA256==tree.publication.snapshotSHA256,manifestID==tree.publication.manifestID,manifestVersion==tree.publication.manifestVersion,manifestSHA256==tree.publication.manifestSHA256,localeIdentifier==tree.publication.localeIdentifier,profileID==tree.publication.profileID,profileRelease==tree.publication.profileRelease,profileSHA256==tree.publication.profileSHA256,brandProfileID==tree.publication.brandProfileID,brandProfileRelease==tree.publication.brandProfileRelease,brandProfileSHA256==tree.publication.brandProfileSHA256 else{throw AccessibleDocumentFailureV1.staleAssessment};for proof in externalProof{let matches=tree.nodes.flatMap{node in node.evidenceLinks.filter{$0.evidenceID==proof.evidenceID}.map{(node.sensitivity,$0)}};guard !matches.isEmpty else{throw AccessibleDocumentFailureV1.missingEvidence};guard matches.count==1,let match=matches.first else{throw AccessibleDocumentFailureV1.duplicateIdentity};guard match.0 == .customerSafe else{throw AccessibleDocumentFailureV1.privacyViolation};guard match.1==proof else{throw AccessibleDocumentFailureV1.missingEvidence}}}
    func validateOutput(_ bytes:Data)throws{guard Int64(bytes.count)==outputByteCount,KernelCanonicalHashV1.sha256(bytes)==outputSHA256 else{throw AccessibleDocumentFailureV1.digestMismatch}}
    func validateSuccessor(of old:Self,tree:AccessibleDocumentSemanticTreeV1)throws{try validate(tree:tree);try old.validateTargetIdentity();guard receiptID != old.receiptID,supersedesReceiptID==old.receiptID,workspaceID==old.workspaceID,treeSHA256==old.treeSHA256,snapshotSHA256==old.snapshotSHA256,audience==old.audience,projectionVersion==old.projectionVersion,manifestID==old.manifestID,manifestVersion==old.manifestVersion,manifestSHA256==old.manifestSHA256,outputSHA256==old.outputSHA256,outputByteCount==old.outputByteCount,outputMediaType==old.outputMediaType,localeIdentifier==old.localeIdentifier,profileID==old.profileID,profileRelease==old.profileRelease,profileSHA256==old.profileSHA256,brandProfileID==old.brandProfileID,brandProfileRelease==old.brandProfileRelease,brandProfileSHA256==old.brandProfileSHA256,rendererID==old.rendererID,rendererVersion==old.rendererVersion,assessmentToolID==old.assessmentToolID,assessmentToolVersion==old.assessmentToolVersion,(old.scope == .historicSource && scope == .currentOutput) || scope == old.scope,mutationID != old.mutationID,old.revision<UInt64.max,revision==old.revision+1 else{throw AccessibleDocumentFailureV1.invalidSuccessor}}
    func rebound(to workspaceID:WorkspaceID,tree:AccessibleDocumentSemanticTreeV1,assessor:ActorSnapshotV1)throws->Self{let reboundLimitations=Array(Set(limitations+[Self.historicSourceLimitation])).sorted();return try .init(receiptID:receiptID,workspaceID:workspaceID,tree:tree,outputSHA256:outputSHA256,outputByteCount:outputByteCount,outputMediaType:outputMediaType,rendererID:rendererID,rendererVersion:rendererVersion,assessmentToolID:assessmentToolID,assessmentToolVersion:assessmentToolVersion,assessor:assessor,scope:.historicSource,state:.incomplete,externalProof:externalProof,limitations:reboundLimitations,assessedAt:assessedAt,supersedesReceiptID:supersedesReceiptID,revision:revision,mutationID:mutationID)}
    static let historicSourceLimitation="RESTORED_HISTORIC_SOURCE_REQUIRES_DESTINATION_REASSESSMENT"
    private func validateTargetIdentity()throws{try validateIntrinsic()}
    private var basis:Basis{.init(schemaVersion:schemaVersion,receiptID:receiptID,workspaceID:workspaceID,treeSHA256:treeSHA256,snapshotSHA256:snapshotSHA256,audience:audience,projectionVersion:projectionVersion,manifestID:manifestID,manifestVersion:manifestVersion,manifestSHA256:manifestSHA256,outputSHA256:outputSHA256,outputByteCount:outputByteCount,outputMediaType:outputMediaType,localeIdentifier:localeIdentifier,profileID:profileID,profileRelease:profileRelease,profileSHA256:profileSHA256,brandProfileID:brandProfileID,brandProfileRelease:brandProfileRelease,brandProfileSHA256:brandProfileSHA256,rendererID:rendererID,rendererVersion:rendererVersion,assessmentToolID:assessmentToolID,assessmentToolVersion:assessmentToolVersion,assessor:assessor,scope:scope,state:state,externalProof:externalProof,limitations:limitations,assessedAt:assessedAt,supersedesReceiptID:supersedesReceiptID,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let treeSHA256:String;let snapshotSHA256:String;let audience:ReportAudienceV1;let projectionVersion:String;let manifestID:String;let manifestVersion:Int;let manifestSHA256:String;let outputSHA256:String;let outputByteCount:Int64;let outputMediaType:String;let localeIdentifier:String;let profileID:String;let profileRelease:Int;let profileSHA256:String;let brandProfileID:String;let brandProfileRelease:Int;let brandProfileSHA256:String;let rendererID:String;let rendererVersion:String;let assessmentToolID:String;let assessmentToolVersion:String;let assessor:ActorSnapshotV1;let scope:AccessibleDocumentAssessmentScopeV1;let state:AccessibleDocumentAssessmentStateV1;let externalProof:[AccessibleEvidenceLinkV1];let limitations:[String];let assessedAt:Date;let supersedesReceiptID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

enum AccessibleDocumentCanonicalCodecV1{static func encode<T:Encodable>(_ value:T)throws->Data{if let tree=value as? AccessibleDocumentSemanticTreeV1{try tree.validate()};if let receipt=value as? AccessibleDocumentAssessmentReceiptV1{try receipt.validateIntrinsic()};let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];e.dateEncodingStrategy = .millisecondsSince1970;return try e.encode(value)}static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=8_388_608 else{throw AccessibleDocumentFailureV1.invalidValue};let d=JSONDecoder();d.dateDecodingStrategy = .millisecondsSince1970;let value=try d.decode(type,from:data);if let tree=value as? AccessibleDocumentSemanticTreeV1{try tree.validate()};if let receipt=value as? AccessibleDocumentAssessmentReceiptV1{try receipt.validateIntrinsic()};guard try encode(value)==data else{throw AccessibleDocumentFailureV1.digestMismatch};return value}}
enum AccessibleDocumentLifecycleV1{static let persistentFamilies=["AccessibleDocumentAssessmentReceiptV1"];static let semanticTreePersistence="DERIVED_ONLY";static let pdfUAClaimed=false;static let wcagClaimed=false;static let legalCertificationClaimed=false;static let s10BrandReconciled=false;static let rendererAuthority="EXISTING_REPORT_RENDERERS_ONLY"}

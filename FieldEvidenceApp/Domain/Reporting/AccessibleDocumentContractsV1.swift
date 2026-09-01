import Foundation

enum GuidedSurveyAccessibleDocumentBoundaryV1 {
    static func validate(_ projection: SurveyPublicationReportProjectionV1) throws {
        try projection.validate()
    }
    static let laterPromotionMayRewriteExistingTree = false
}

struct C18LightingAccessibleDocumentProjectionV1:Codable,Equatable,Sendable{
    let headingKey:String;let orderedStateKeys:[String];let limitationKey:String
    let stateUsesColorAlone:Bool;let conformanceClaimed:Bool
    init(_ value:LightingReportProjectionV1)throws{try C18LightingReportProjectionSupportV1.validate(value);headingKey=C18LightingNightLocalizationKeyV1.title.rawValue;var keys=[C18LightingNightLocalizationKeyV1.expectedState.rawValue,C18LightingNightLocalizationKeyV1.observedState.rawValue];if !value.openIssueIDs.isEmpty{keys.append(C18LightingNightLocalizationKeyV1.issueOpen.rawValue)};if !value.resolvedForRecordedScopeIssueIDs.isEmpty{keys.append(C18LightingNightLocalizationKeyV1.issueResolved.rawValue)};if !value.reopenedIssueIDs.isEmpty{keys.append(C18LightingNightLocalizationKeyV1.issueReopened.rawValue)};if value.measurementDispositions.contains(.inconclusiveUncertaintyCrossesCriterion){keys.append(C18LightingNightLocalizationKeyV1.inconclusive.rawValue)};orderedStateKeys=keys;limitationKey=C18LightingNightLocalizationKeyV1.claimBoundary.rawValue;stateUsesColorAlone=false;conformanceClaimed=false;try validate()}
    func validate()throws{let allowed=Set(C18LightingNightLocalizationKeyV1.allCases.map(\.rawValue));guard headingKey==C18LightingNightLocalizationKeyV1.title.rawValue,Array(orderedStateKeys.prefix(2))==[C18LightingNightLocalizationKeyV1.expectedState.rawValue,C18LightingNightLocalizationKeyV1.observedState.rawValue],Set(orderedStateKeys).count==orderedStateKeys.count,Set(orderedStateKeys).isSubset(of:allowed),limitationKey==C18LightingNightLocalizationKeyV1.claimBoundary.rawValue,!stateUsesColorAlone,!conformanceClaimed else{throw SnapshotProjectionFailureV1.unsupportedAccessibilityClaim}}
}

// MARK: - C19 accessible plan work and historic revision opening

struct C19PlanAccessibleDocumentProjectionV1: Codable, Equatable, Sendable {
    let planRevision: PlanRevisionReferenceV1
    let orderedPlacementIDs: [UUID]
    let orderedPlacementLabelKeys: [String]
    let readinessFindingCodes: [PlanOfflineReadinessFindingCodeV1]
    let rebaseDisposition: RebaseReviewDispositionV1?
    let viewportConveysPhysicalDirection: Bool
    let stateUsesColorAlone: Bool

    init(surface: PlanWorkSurfaceStateV1,
         readiness: OfflineWorkPacketReadinessV1,
         review: RebaseReviewStateV1?) throws {
        let reviewMatchesSurface = review.map { value in
            guard value.workspaceID == surface.workspaceID,
                  value.preview.oldRevision.planDocumentID == surface.planRevision.planDocumentID else {
                return false
            }
            switch value.disposition {
            case .pending, .rejected:
                return surface.planRevision == value.preview.oldRevision
            case .approvedActivated:
                return surface.planRevision == value.preview.newRevision
            }
        } ?? true
        guard surface.workspaceID == readiness.workspaceID,
              surface.planRevision == readiness.planRevision,
              reviewMatchesSurface else {
            throw AccessibleDocumentFailureV1.missingEvidence
        }
        planRevision = surface.planRevision
        orderedPlacementIDs = surface.placements.map(\.placement.placementID)
        orderedPlacementLabelKeys = surface.placements.map(\.accessibilityLabelKey)
        readinessFindingCodes = readiness.findings.map(\.code).sorted { $0.rawValue < $1.rawValue }
        rebaseDisposition = review?.disposition
        viewportConveysPhysicalDirection = PlanViewportPresentationV1.conveysPhysicalDirection
        stateUsesColorAlone = false
        try validate()
    }

    func validate() throws {
        try planRevision.validate()
        guard orderedPlacementIDs.count == orderedPlacementLabelKeys.count,
              Set(orderedPlacementIDs).count == orderedPlacementIDs.count,
              orderedPlacementLabelKeys.allSatisfy({
                  $0 == PlanLocalizationKeyV1.placementItem.rawValue
              }),
              !viewportConveysPhysicalDirection, !stateUsesColorAlone else {
            throw AccessibleDocumentFailureV1.invalidValue
        }
    }
}

struct C19HistoricPlanRevisionOpenRequestV1: Codable, Equatable, Sendable {
    let workspaceID: UUID
    let originalRevision: PlanRevisionReferenceV1
    let originalProjectionSHA256: String
    let allowsLatestRevisionFallback: Bool

    init(report: PlanReportProjectionV1) throws {
        try report.validate()
        workspaceID = report.workspaceID
        originalRevision = report.revisionReference
        originalProjectionSHA256 = report.projectionSHA256
        allowsLatestRevisionFallback = false
    }

    func validate(report: PlanReportProjectionV1) throws {
        try report.validate()
        guard workspaceID == report.workspaceID,
              originalRevision == report.revisionReference,
              originalProjectionSHA256 == report.projectionSHA256,
              !allowsLatestRevisionFallback else {
            throw AccessibleDocumentFailureV1.digestMismatch
        }
    }

    func resolve(report: PlanReportProjectionV1,
                 from revisions: [PlanRevisionV1]) throws -> PlanRevisionV1 {
        try validate(report: report)
        guard !allowsLatestRevisionFallback,
              let exact = revisions.first(where: {
                  $0.workspaceID.rawValue == workspaceID
                      && $0.planRevisionID == originalRevision.planRevisionID
                      && $0.revision == originalRevision.revision
                      && $0.revisionSHA256 == originalRevision.revisionSHA256
              }),
              revisions.filter({ $0.planRevisionID == originalRevision.planRevisionID
                  && $0.revision == originalRevision.revision
                  && $0.revisionSHA256 == originalRevision.revisionSHA256 }).count == 1 else {
            throw AccessibleDocumentFailureV1.missingEvidence
        }
        try exact.validateIntrinsic()
        return exact
    }
}

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

// MARK: - C25 survey-definition accessibility semantics

enum SurveyDefinitionAccessibilityIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case screen = "survey.definition.screen"
    case heading = "survey.definition.heading"
    case definition = "survey.definition.definition"
    case release = "survey.definition.release"
    case activityKind = "survey.definition.activity_kind"
    case lifecycle = "survey.definition.lifecycle"
    case sections = "survey.definition.sections"
    case facts = "survey.definition.facts"
    case claimBoundary = "survey.definition.claim_boundary"
    case notObserved = "survey.definition.not_observed"
    case nextStep = "survey.definition.next_step"

    var localizationKey: SurveyDefinitionLocalizationKeyV1 {
        switch self {
        case .screen, .heading: return .reportHeading
        case .definition: return .reportDefinition
        case .release: return .reportRelease
        case .activityKind: return .reportActivityKind
        case .lifecycle: return .reportLifecycle
        case .sections: return .reportSections
        case .facts: return .reportFacts
        case .claimBoundary: return .reportClaimBoundary
        case .notObserved: return .reportNotObserved
        case .nextStep: return .nextStepReviewRecordedFacts
        }
    }
}

enum SurveyDefinitionAccessibilityPolicyV1 {
    static let semanticNamespace = "survey.definition"
    static let stateSemanticIDs: Set<String> = [
        SurveyDefinitionAccessibilityIDV1.lifecycle.rawValue,
        SurveyDefinitionAccessibilityIDV1.notObserved.rawValue,
        SurveyDefinitionAccessibilityIDV1.claimBoundary.rawValue,
    ]
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresNonColorStateText = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesAnswers = true
    static let excludesPromptText = true
    static let excludesActorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesEvidenceBytes = true

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        semanticID == SurveyDefinitionAccessibilityIDV1.nextStep.rawValue
    }

    static func validate() throws {
        guard Set(SurveyDefinitionAccessibilityIDV1.allCases.map(\.rawValue)).count
                == SurveyDefinitionAccessibilityIDV1.allCases.count,
              requiresTextAndIconForIndeterminateStates,
              requiresNonColorStateText,
              requiresActionableNextStep,
              !allowsColorOnlyState, !allowsIconOnlyState, !allowsMotionOnlyState,
              excludesAnswers, excludesPromptText, excludesActorIdentity,
              excludesPrivateLocators, excludesEvidenceBytes else {
            throw SurveyDefinitionConsumerFailureV1.privacyViolation
        }
    }
}

enum C47ActivityContractConformance_FieldEvidenceApp_Domain_Reporting_AccessibleDocumentContractsV1_swift {
    static let integrationRole = "ACCESSIBLE_STATE_LIMITATIONS"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let createsSecondRouteOrInspectionAlias = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

enum C48PortableReviewAccessibleDocumentBoundaryV1 {
    static let spokenProjectionIsDerivedMetadataOnly = true
    static let capabilityBytesSpoken = false
    static let capabilityProofSpoken = false
    static let rawResponseBytesSpoken = false
    static let responseBodySpoken = false
    static let verifiedIdentitySpoken = false
    static let selfAssertedOriginMayBeSpoken = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }
}

// MARK: - C49 work-resource accessible projection

struct C49WorkResourceAccessibleDocumentProjectionV1: Codable, Equatable, Sendable {
    let lines: [String]
    let claims: String

    init(projection: C49WorkResourceReportProjectionV1) throws {
        try C49WorkResourceProjectionSupportV1.validate(projection)
        var values = ["Duration: \(projection.durationMinutes) minutes"]
        values.append(contentsOf: projection.materials.map {
            "Material: \($0.description), unit \($0.unit ?? "unspecified"), quantity \($0.quantity.mantissa) scale \($0.quantity.scale)"
        })
        if projection.directCostPreview.included {
            values.append(contentsOf: projection.directCostPreview.totalsByCurrency.map {
                "Direct cost total: \($0.currencyCode) \($0.mantissa) minor units at scale \($0.minorUnitScale)"
            })
        }
        lines = values
        claims = C49FormulaSafeCSVV1.sourceClaims
    }

    func validate() throws {
        guard !lines.isEmpty, claims == C49FormulaSafeCSVV1.sourceClaims else {
            throw C49WorkResourceProjectionFailureV1.nonCanonical
        }
    }
}

enum C49WorkResourceAccessibleDocumentBoundaryV1 {
    static let semanticLinesAreDerived = true
    static let sourceBytesSpoken = false
    static let liveInventoryClaimsSpoken = false

    static func lines(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> [String] {
        let document = try C49WorkResourceAccessibleDocumentProjectionV1(projection: projection)
        try document.validate()
        return document.lines
    }
}

// MARK: - C50 incumbent file-exchange cross-contract boundary

/// C50 may feed only a quarantined, allowlisted, derived presentation into
/// accessibility. Profile/selection evidence remains immutable configuration;
/// source/session bytes, provider state, and external availability never enter
/// the semantic tree or its evidence links.
enum C50AccessibleDocumentIncumbentExchangeBoundaryV1 {
    static let adapterContract: Any.Type = IncumbentFileAdapterV1.self
    static let registryContract: Any.Type = ClosedIncumbentAdapterRegistryV1.self
    static let profileReleaseContract: Any.Type = IncumbentFileProfileReleaseV1.self
    static let selectionReceiptContract: Any.Type = IncumbentSelectionReceiptV1.self
    static let exchangeScopeContract: Any.Type = IncumbentExchangeScopeV1.self
    static let exportManifestContract: Any.Type = IncumbentFileExportManifestV1.self
    static let exchangeReceiptContract: Any.Type = IncumbentFileExchangeReceiptV1.self
    static let quarantineReceiptContract: Any.Type = IncumbentFileQuarantineReceiptV1.self

    static let crossContractTypes: [Any.Type] = [
        AccessibleDocumentSemanticTreeV1.self,
        AccessibleEvidenceLinkV1.self,
        InspectionReviewProjectionV1.self,
        PackageReleaseBindingV1.self,
    ]
    static let privacyAllowlistIsClosed = true
    static let quarantinePrecedesProjection = true
    static let sourceAndSessionBytesAreExcluded = true
    static let providerStateIsNotCanonical = true
    static let writerAndRendererAreDelegated = true
    static let lifecycleIsDerivedOnly = true
    static let conformanceClaimsAreNotInferred = true
    static let disabledProfileRemainsTruthful = true

    static func validateDerivedTree(_ tree: AccessibleDocumentSemanticTreeV1) throws {
        try tree.validate()
    }

    static func validateEvidenceLink(_ link: AccessibleEvidenceLinkV1) throws {
        try link.validate()
    }
}
enum C52ServiceRequestBoundary_AccessibleDocumentContractsV1 {
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

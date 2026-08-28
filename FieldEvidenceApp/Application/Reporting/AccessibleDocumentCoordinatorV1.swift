import Foundation

struct AccessibleDocumentRenderOutputV1: Equatable, Sendable {
    let bytes: Data
    let mediaType: String
    let rendererID: String
    let rendererVersion: String
    init(bytes:Data,mediaType:String,rendererID:String,rendererVersion:String)throws{guard !bytes.isEmpty else{throw AccessibleDocumentFailureV1.invalidValue};try [mediaType,rendererID,rendererVersion].forEach{try AccessibleDocumentValidationV1.text($0)};self.bytes=bytes;self.mediaType=mediaType;self.rendererID=rendererID;self.rendererVersion=rendererVersion}
    var sha256:String{KernelCanonicalHashV1.sha256(bytes)}
}

protocol AccessibleDocumentSemanticTreeBuildingV1:Sendable{
    func deriveTree()async throws->AccessibleDocumentSemanticTreeV1
}
protocol AccessibleDocumentExistingRendererV1:Sendable{
    func render(tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentRenderOutputV1
}
protocol AccessibleDocumentAssessmentWritingV1:Sendable{
    func acceptedReceipt(for assessment:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1?
    func append(_ assessment:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1
}
protocol AccessibleDocumentEvidenceResolvingV1:Sendable{
    func resolve(evidenceIDs:[String])async throws->[OutputScopedContentReferenceV1]
}

struct AccessibleDocumentAssessmentRequestV1:Sendable{
    let receiptID:UUID;let workspaceID:WorkspaceID;let assessor:ActorSnapshotV1
    let state:AccessibleDocumentAssessmentStateV1;let externalProof:[AccessibleEvidenceLinkV1];let limitations:[String]
    let assessmentToolID:String;let assessmentToolVersion:String;let assessedAt:Date
    let supersedesReceiptID:UUID?;let revision:UInt64;let mutationID:MutationIDV1
}

actor AccessibleDocumentCoordinatorV1{
    private let treeBuilder:any AccessibleDocumentSemanticTreeBuildingV1
    private let renderer:any AccessibleDocumentExistingRendererV1
    private let writer:any AccessibleDocumentAssessmentWritingV1
    private let evidenceResolver:(any AccessibleDocumentEvidenceResolvingV1)?
    init(treeBuilder:any AccessibleDocumentSemanticTreeBuildingV1,renderer:any AccessibleDocumentExistingRendererV1,writer:any AccessibleDocumentAssessmentWritingV1,evidenceResolver:(any AccessibleDocumentEvidenceResolvingV1)?=nil){self.treeBuilder=treeBuilder;self.renderer=renderer;self.writer=writer;self.evidenceResolver=evidenceResolver}

    func deriveAndRender()async throws->(AccessibleDocumentSemanticTreeV1,AccessibleDocumentRenderOutputV1){let tree=try await treeBuilder.deriveTree();try tree.validate();let output=try await renderer.render(tree:tree);guard output.sha256==KernelCanonicalHashV1.sha256(output.bytes)else{throw AccessibleDocumentFailureV1.digestMismatch};return(tree,output)}

    func assess(_ request:AccessibleDocumentAssessmentRequestV1)async throws->AccessibleDocumentAssessmentReceiptV1{
        let(tree,output)=try await deriveAndRender();let value=try AccessibleDocumentAssessmentReceiptV1(receiptID:request.receiptID,workspaceID:request.workspaceID,tree:tree,outputSHA256:output.sha256,outputByteCount:Int64(output.bytes.count),outputMediaType:output.mediaType,rendererID:output.rendererID,rendererVersion:output.rendererVersion,assessmentToolID:request.assessmentToolID,assessmentToolVersion:request.assessmentToolVersion,assessor:request.assessor,state:request.state,externalProof:request.externalProof,limitations:request.limitations,assessedAt:request.assessedAt,supersedesReceiptID:request.supersedesReceiptID,revision:request.revision,mutationID:request.mutationID);try value.validateOutput(output.bytes)
        if !request.externalProof.isEmpty{guard let evidenceResolver else{throw AccessibleDocumentFailureV1.missingEvidence};let proof=request.externalProof.sorted{$0.evidenceID<$1.evidenceID};guard Set(proof.map(\.evidenceID)).count==proof.count else{throw AccessibleDocumentFailureV1.duplicateIdentity};let resolved=try await evidenceResolver.resolve(evidenceIDs:proof.map(\.evidenceID));try resolved.forEach{$0.validate()};guard resolved.count==proof.count,Set(resolved.map(\.outputReferenceID)).count==resolved.count else{throw AccessibleDocumentFailureV1.duplicateIdentity};let links=try resolved.map{try AccessibleEvidenceLinkV1(outputReference:$0)}.sorted{$0.evidenceID<$1.evidenceID};guard links==proof else{throw AccessibleDocumentFailureV1.missingEvidence}}
        if let accepted=try await writer.acceptedReceipt(for:value,tree:tree){guard accepted==value else{throw AccessibleDocumentFailureV1.staleAssessment};return accepted}
        let receipt=try await writer.append(value,tree:tree);guard receipt==value else{throw AccessibleDocumentFailureV1.staleAssessment};return receipt
    }
}

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

// MARK: - C48 portable-review accessible projection boundary

extension AccessibleDocumentCoordinatorV1 {
    /// The accessibility coordinator can consume the safe projection for a
    /// spoken status summary, but never receives the capability, proof, or
    /// canonical response bytes.
    nonisolated static func validatePortableReviewDerivedHistory(
        _ projection: C48PortableReviewDerivedHistoryProjectionV1
    ) throws -> C48PortableReviewDerivedHistoryProjectionV1 {
        try C48PortableReviewAccessibleDocumentBoundaryV1.validate(projection)
        return projection
    }
}

enum C48PortableReviewAccessibleDocumentCoordinatorBoundaryV1 {
    static let consumesDerivedMetadataOnly = true
    static let capabilityBytesConsumed = false
    static let capabilityProofBytesConsumed = false
    static let responseBodyConsumed = false
    static let rawRequestResponseBytesConsumed = false
    static let verifiedIdentityConsumed = false
    static let existingAccessibleRendererRemainsSoleRenderer = true
}

// MARK: - C49 work-resource accessible projection coordinator

extension AccessibleDocumentCoordinatorV1 {
    nonisolated static func workResourceLines(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> [String] {
        try C49WorkResourceAccessibleDocumentBoundaryV1.lines(projection)
    }
}

enum C49WorkResourceAccessibleCoordinatorBoundaryV1 {
    static let consumesSnapshotProjectionOnly = true
    static let sourceBytesConsumed = false
    static let liveInventoryClaimsConsumed = false
}

// MARK: - C50 incumbent file-exchange coordinator boundary

/// Accessibility consumes only the already validated projection. C50's
/// preview, mapping, quarantine, and external-file work remain delegated to
/// their owning seams and cannot append an assessment or persist source data.
enum C50AccessibleDocumentIncumbentCoordinatorBoundaryV1 {
    static let adapterContract: Any.Type = IncumbentFileAdapterV1.self
    static let selectionReceiptContract: Any.Type = IncumbentSelectionReceiptV1.self
    static let exchangeReceiptContract: Any.Type = IncumbentFileExchangeReceiptV1.self
    static let quarantineReceiptContract: Any.Type = IncumbentFileQuarantineReceiptV1.self
    static let previewIsZeroWrite = true
    static let allowlistIsRequiredBeforeAccessibility = true
    static let quarantineIsRequiredBeforeAccessibility = true
    static let sourceBytesConsumed = false
    static let sessionBytesConsumed = false
    static let providerStateConsumed = false
    static let accessibilityCoordinatorIsNotAnImportWriter = true
    static let existingAssessmentWriterRemainsSoleMutationRoute = true
    static let existingReportRendererRemainsSoleRenderer = true
    static let disabledProfileHasNoIntegrationClaim = true

    static func validateProjection(_ tree: AccessibleDocumentSemanticTreeV1) throws {
        try tree.validate()
    }
}

// MARK: - C52 service-request status accessibility boundary

/// Accessible output may consume only the derived request-state artifact. The
/// self-asserted requester/contact fields and accepted source bytes remain out
/// of the report tree, and rendering cannot be presented as delivery.
enum C52AccessibleServiceRequestStatusBoundaryV1 {
    static let statusArtifactContract: Any.Type = ServiceRequestStatusArtifactHandoffV1.self
    static let stateProjectionContract: Any.Type = ServiceRequestStateProjectionV1.self
    static let consumesDerivedStateOnly = true
    static let requesterOrContactAssertionConsumed = false
    static let acceptedSourceBytesConsumed = false
    static let deliveryClaimPermitted = false
    static let existingAccessibleRendererRemainsSoleRenderer = true

    static func validate(_ artifact: ServiceRequestStatusArtifactHandoffV1) throws {
        guard !artifact.requesterIdentityVerified,
              !artifact.deliveryClaimed,
              artifact.handoffIntent.target.kind == .serviceContactPoint else {
            throw AccessibleDocumentFailureV1.invalidValue
        }
    }
}

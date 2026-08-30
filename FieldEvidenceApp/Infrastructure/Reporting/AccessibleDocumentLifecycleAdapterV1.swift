import Foundation

enum AccessibleDocumentInterruptionPointV1:String,Codable,Sendable{case afterTreeBeforeRender="AFTER_TREE_BEFORE_RENDER",afterRenderBeforeAssessment="AFTER_RENDER_BEFORE_ASSESSMENT",afterAssessmentBeforeReturn="AFTER_ASSESSMENT_BEFORE_RETURN"}
struct AccessibleDocumentLifecycleOperationsV1:Sendable{
    let derive:@Sendable()async throws->AccessibleDocumentSemanticTreeV1
    let render:@Sendable(AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentRenderOutputV1
    let accepted:@Sendable(AccessibleDocumentAssessmentReceiptV1,AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1?
    let append:@Sendable(AccessibleDocumentAssessmentReceiptV1,AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1
    let interrupt:@Sendable(AccessibleDocumentInterruptionPointV1)async throws->Void
    init(derive:@escaping @Sendable()async throws->AccessibleDocumentSemanticTreeV1,render:@escaping @Sendable(AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentRenderOutputV1,accepted:@escaping @Sendable(AccessibleDocumentAssessmentReceiptV1,AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1?,append:@escaping @Sendable(AccessibleDocumentAssessmentReceiptV1,AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1,interrupt:@escaping @Sendable(AccessibleDocumentInterruptionPointV1)async throws->Void={_ in}){self.derive=derive;self.render=render;self.accepted=accepted;self.append=append;self.interrupt=interrupt}
}
actor AccessibleDocumentLifecycleAdapterV1:AccessibleDocumentSemanticTreeBuildingV1,AccessibleDocumentExistingRendererV1,AccessibleDocumentAssessmentWritingV1{
    private let operations:AccessibleDocumentLifecycleOperationsV1
    init(operations:AccessibleDocumentLifecycleOperationsV1){self.operations=operations}
    func deriveTree()async throws->AccessibleDocumentSemanticTreeV1{let value=try await operations.derive();try value.validate();try await operations.interrupt(.afterTreeBeforeRender);return value}
    func render(tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentRenderOutputV1{try tree.validate();let value=try await operations.render(tree);try await operations.interrupt(.afterRenderBeforeAssessment);return value}
    func acceptedReceipt(for assessment:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1?{guard let value=try await operations.accepted(assessment,tree)else{return nil};try value.validate(tree:tree);guard value==assessment else{throw AccessibleDocumentFailureV1.staleAssessment};return value}
    func append(_ assessment:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1{try assessment.validate(tree:tree);let value=try await operations.append(assessment,tree);try value.validate(tree:tree);try await operations.interrupt(.afterAssessmentBeforeReturn);return value}
}

enum AccessibleDocumentRecoveryV1{static func disposition(hasAcceptedAssessment:Bool,hasDerivedTree:Bool)->String{hasAcceptedAssessment ? "REBUILD_DERIVED_TREE_FROM_SNAPSHOT_AND_ACCEPTED_RECEIPT":(hasDerivedTree ? "DROP_UNACCEPTED_DERIVED_TREE":"NO_EFFECT")}}

struct AccessibleDocumentRestoreTreeResolverV1:AccessibleDocumentSemanticTreeResolvingV1{
    let operation:@Sendable(AccessibleDocumentSemanticTreeResolutionRequestV1)async throws->AccessibleDocumentSemanticTreeV1
    init(operation:@escaping @Sendable(AccessibleDocumentSemanticTreeResolutionRequestV1)async throws->AccessibleDocumentSemanticTreeV1){self.operation=operation}
    func resolve(_ request:AccessibleDocumentSemanticTreeResolutionRequestV1)async throws->AccessibleDocumentSemanticTreeV1{let tree=try await operation(request);try request.validate(tree);return tree}
}

struct AccessibleDocumentLocalEvidenceResolverV1:AccessibleDocumentEvidenceResolvingV1{
    let operation:@Sendable([String])async throws->[OutputScopedContentReferenceV1]
    init(operation:@escaping @Sendable([String])async throws->[OutputScopedContentReferenceV1]){self.operation=operation}
    func resolve(evidenceIDs:[String])async throws->[OutputScopedContentReferenceV1]{guard evidenceIDs==evidenceIDs.sorted(),Set(evidenceIDs).count==evidenceIDs.count else{throw AccessibleDocumentFailureV1.duplicateIdentity};let values=try await operation(evidenceIDs);try values.forEach{$0.validate()};guard values.map(\.outputReferenceID).sorted()==evidenceIDs else{throw AccessibleDocumentFailureV1.missingEvidence};return values.sorted()}
}

/// Sole-writer bridge. The transient tree is validated before the receipt-only
/// mutation is formed and is never encoded into the journal command.
@MainActor final class WorkspaceWriterAccessibleDocumentAssessmentBridgeV1:AccessibleDocumentAssessmentWritingV1{
    private let writer:WorkspaceWriterV1;private let journalStore:MutationJournalStoreV1
    init(writer:WorkspaceWriterV1,journalStore:MutationJournalStoreV1){self.writer=writer;self.journalStore=journalStore}
    func acceptedReceipt(for assessment:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1?{try assessment.validate(tree:tree);let mutation=AccessibleDocumentMutationV1(receipt:assessment);guard let canonical=try journalStore.receipt(mutationID:assessment.mutationID)else{return nil};_ = try AccessibleDocumentMutationReceiptV1(mutation:mutation,mutationReceipt:canonical);return assessment}
    func append(_ assessment:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1{try assessment.validate(tree:tree);let mutation=AccessibleDocumentMutationV1(receipt:assessment);let canonical=try writer.commitAccessibleDocumentAssessment(mutation,validatedAgainst:tree);_ = try AccessibleDocumentMutationReceiptV1(mutation:mutation,mutationReceipt:canonical);return assessment}
}

// C48 accessible-document lifecycle consumes only a validated derived
// projection; it never persists or speaks exchange secrets or response bytes.
enum C48PortableReviewAccessibleDocumentLifecycleBoundaryV1 {
    static let usesExistingAccessibleDocumentLifecycle = true
    static let capabilityBytesAccepted = false
    static let capabilityProofBytesAccepted = false
    static let responseBodyAccepted = false
    static let rawRequestResponseBytesAccepted = false
    static let externalReviewCannotWriteAssessment = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try C48PortableReviewAccessibleDocumentBoundaryV1.validate(projection)
    }
}

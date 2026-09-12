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
    private let globalizedRenderer:(any AccessibleDocumentGlobalizedRenderingV1)?
    init(operations:AccessibleDocumentLifecycleOperationsV1,globalizedRenderer:(any AccessibleDocumentGlobalizedRenderingV1)?=nil){self.operations=operations;self.globalizedRenderer=globalizedRenderer}
    func deriveTree()async throws->AccessibleDocumentSemanticTreeV1{let value=try await operations.derive();try value.validate();try await operations.interrupt(.afterTreeBeforeRender);return value}
    func render(tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentRenderOutputV1{try tree.validate();let value=try await operations.render(tree);try await operations.interrupt(.afterRenderBeforeAssessment);return value}
    func acceptedReceipt(for assessment:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1?{guard let value=try await operations.accepted(assessment,tree)else{return nil};try value.validate(tree:tree);guard value==assessment else{throw AccessibleDocumentFailureV1.staleAssessment};return value}
    func append(_ assessment:AccessibleDocumentAssessmentReceiptV1,tree:AccessibleDocumentSemanticTreeV1)async throws->AccessibleDocumentAssessmentReceiptV1{try assessment.validate(tree:tree);let value=try await operations.append(assessment,tree);try value.validate(tree:tree);try await operations.interrupt(.afterAssessmentBeforeReturn);return value}

    func renderGlobalized(tree: AccessibleDocumentSemanticTreeV1, request: AccessibleDocumentGlobalizedRenderRequestV1) async throws -> AccessibleDocumentGlobalizedRenderOutputV1 {
        try tree.validate()
        guard let globalizedRenderer else { throw AccessibleDocumentFailureV1.invalidValue }
        let value = try await globalizedRenderer.renderGlobalized(tree: tree, request: request)
        try await operations.interrupt(.afterRenderBeforeAssessment)
        return value
    }
}

extension AccessibleDocumentLifecycleAdapterV1: AccessibleDocumentGlobalizedRenderingV1 {}

/// Projects an already validated semantic tree into the V30 renderer's
/// source-bound element sequence. Asset bytes are accepted only when their
/// exact evidence link verifies them; a missing figure asset aborts output.
struct GlobalizedAccessibleDocumentTreeRendererV1: AccessibleDocumentGlobalizedRenderingV1 {
    private let renderer: GlobalizedAccessibleDocumentRendererV1

    init(renderer: GlobalizedAccessibleDocumentRendererV1 = .init()) {
        self.renderer = renderer
    }

    func renderGlobalized(
        tree: AccessibleDocumentSemanticTreeV1,
        request: AccessibleDocumentGlobalizedRenderRequestV1
    ) async throws -> AccessibleDocumentGlobalizedRenderOutputV1 {
        try tree.validate()
        let result = try renderer.render(
            elements: try GlobalizedAccessibleDocumentTreeProjectionV1.elements(tree: tree, imageDataByEvidenceID: request.imageDataByEvidenceID),
            sourceSHA256: tree.treeSHA256,
            sourceCreatedAt: request.sourceCreatedAt,
            request: request.documentRequest,
            expectedReplay: request.expectedReplay
        )
        return try AccessibleDocumentGlobalizedRenderOutputV1(
            output: AccessibleDocumentRenderOutputV1(
                bytes: result.pdf.data,
                mediaType: "application/pdf",
                rendererID: result.receipt.rendererID,
                rendererVersion: result.receipt.rendererVersion
            ),
            documentReceipt: result.receipt
        )
    }
}

enum GlobalizedAccessibleDocumentTreeProjectionV1 {
    static func elements(
        tree: AccessibleDocumentSemanticTreeV1,
        imageDataByEvidenceID: [String: Data]
    ) throws -> [GlobalizedDocumentElementV1] {
        try tree.validate()
        var elements: [GlobalizedDocumentElementV1] = []
        for node in try tree.depthFirstReadingOrder() {
            if node.role == .figure, node.evidenceLinks.count > 1 {
                // The source node remains the sole carrier of source text and
                // alt provenance. Each linked source asset is a concrete child
                // figure, so no image is silently selected or re-captioned.
                elements.append(try GlobalizedDocumentElementV1(
                    semanticID: node.nodeID,
                    role: node.role,
                    text: node.localizedText,
                    headingLevel: node.headingLevel,
                    alternateText: node.alternateText,
                    alternateTextProvenance: node.alternateTextProvenance,
                    keepWithNext: node.role == .heading,
                    parentSemanticID: node.parentNodeID,
                    tableHeaderScope: node.tableHeaderScope,
                    tableHeaderSemanticIDs: node.tableHeaderNodeIDs,
                    decorative: node.decorative
                ))
                for evidence in node.evidenceLinks {
                    guard let bytes = imageDataByEvidenceID[evidence.evidenceID],
                          KernelCanonicalHashV1.sha256(bytes) == evidence.evidenceSHA256 else {
                        throw GlobalizedAccessibleDocumentFailureV1.missingResource
                    }
                    elements.append(try GlobalizedDocumentElementV1(
                        semanticID: derivedImageSemanticID(parentSemanticID: node.nodeID, evidenceID: evidence.evidenceID),
                        role: .figure,
                        evidenceID: evidence.evidenceID,
                        evidenceSHA256: evidence.evidenceSHA256,
                        imageData: bytes,
                        alternateTextProvenance: node.decorative ? nil : .notProvided,
                        parentSemanticID: node.nodeID,
                        decorative: node.decorative
                    ))
                }
                continue
            }
            let figureEvidence: AccessibleEvidenceLinkV1?
            let imageData: Data?
            if node.role == .figure {
                guard node.evidenceLinks.count == 1,
                      let evidence = node.evidenceLinks.first,
                      let bytes = imageDataByEvidenceID[evidence.evidenceID],
                      KernelCanonicalHashV1.sha256(bytes) == evidence.evidenceSHA256 else {
                    throw GlobalizedAccessibleDocumentFailureV1.missingResource
                }
                figureEvidence = evidence
                imageData = bytes
            } else {
                figureEvidence = nil
                imageData = nil
            }
            elements.append(try GlobalizedDocumentElementV1(
                semanticID: node.nodeID,
                role: node.role,
                text: node.localizedText,
                headingLevel: node.headingLevel,
                evidenceID: figureEvidence?.evidenceID,
                evidenceSHA256: figureEvidence?.evidenceSHA256,
                imageData: imageData,
                alternateText: node.alternateText,
                alternateTextProvenance: node.alternateTextProvenance,
                keepWithNext: node.role == .heading,
                parentSemanticID: node.parentNodeID,
                tableHeaderScope: node.tableHeaderScope,
                tableHeaderSemanticIDs: node.tableHeaderNodeIDs,
                decorative: node.decorative
            ))
            if node.role != .figure {
                for evidence in node.evidenceLinks {
                    elements.append(try GlobalizedDocumentElementV1(
                        semanticID: derivedEvidenceSemanticID(parentSemanticID: node.nodeID, evidenceID: evidence.evidenceID),
                        role: .evidenceLink,
                        evidenceID: evidence.evidenceID,
                        evidenceSHA256: evidence.evidenceSHA256,
                        parentSemanticID: node.nodeID
                    ))
                }
            }
        }
        return elements
    }

    private static func derivedImageSemanticID(parentSemanticID: String, evidenceID: String) -> String {
        derivedSemanticID(prefix: "image", parentSemanticID: parentSemanticID, evidenceID: evidenceID)
    }

    private static func derivedEvidenceSemanticID(parentSemanticID: String, evidenceID: String) -> String {
        derivedSemanticID(prefix: "link", parentSemanticID: parentSemanticID, evidenceID: evidenceID)
    }

    private static func derivedSemanticID(prefix: String, parentSemanticID: String, evidenceID: String) -> String {
        let material = Data((parentSemanticID + "\u{0}" + evidenceID).utf8)
        return prefix + "." + String(KernelCanonicalHashV1.sha256(material).prefix(48))
    }
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

// MARK: - C49 work-resource accessible/report boundary

/// Reporting and accessibility consume the existing derived lifecycle. They
/// do not become a second writer, expose private cost by default, or query
/// live inventory while rendering a work-resource entry.
enum C49WorkResourceAccessibleDocumentLifecycleBoundaryV1 {
    static let consumesExistingAccessibleDocumentLifecycle = true
    static let reportUsesCanonicalWorkResourceProjection = true
    static let directCostDefaultVisibility = "INTERNAL_ONLY"
    static let customerSafeCostRequiresExplicitPreview = true
    static let rawContentBytesAccepted = false
    static let liveInventoryLookup = false
    static let createsSecondReportOrWriter = false
    static let formulaFieldsAccepted = false
}

// MARK: - C50 incumbent file-exchange lifecycle boundary

/// The existing accessibility lifecycle accepts only a derived tree or
/// assessment. C50 source leases and quarantine outcomes are external to this
/// lifecycle, and canonical assessment writes remain on the existing bridge.
enum C50AccessibleDocumentIncumbentLifecycleBoundaryV1 {
    static let adapterContract: Any.Type = IncumbentFileAdapterV1.self
    static let profileReleaseContract: Any.Type = IncumbentFileProfileReleaseV1.self
    static let exchangeScopeContract: Any.Type = IncumbentExchangeScopeV1.self
    static let quarantineReceiptContract: Any.Type = IncumbentFileQuarantineReceiptV1.self
    static let inputBytesAreLeasedScratch = true
    static let scratchIsExcludedFromBackup = true
    static let scratchIsDeletedAfterOutcome = true
    static let quarantineMustCompleteBeforeProjection = true
    static let lifecycleConsumesDerivedMetadataOnly = true
    static let lifecyclePersistsSourceBytes = false
    static let lifecyclePersistsSessionBytes = false
    static let lifecycleCreatesSecondWriter = false
    static let lifecycleCreatesSecondStore = false
    static let lifecycleClaimsProviderAvailability = false
    static let conformanceIsTypedAndNoncertifying = true

    static func validateAssessment(_ value: AccessibleDocumentAssessmentReceiptV1) throws {
        try value.validateIntrinsic()
    }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Reporting_AccessibleDocumentLifecycleAdapterV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

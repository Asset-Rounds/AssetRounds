import Foundation

/// C40 application adapter. Every operation is routed through the sole
/// WorkspaceWriterV1; retrying the same canonical value reuses its MutationID.
@MainActor
final class AuthorityCriterionLifecycleAdapterV1 {
    private let workspaceID: WorkspaceID
    private let writer: WorkspaceWriterV1
    private let assuranceReader: AuthorityCriterionAssuranceReaderV1?

    init(workspaceID: WorkspaceID, writer: WorkspaceWriterV1,
         assuranceReader: AuthorityCriterionAssuranceReaderV1? = nil) {
        self.workspaceID = workspaceID
        self.writer = writer
        self.assuranceReader = assuranceReader
    }

    func claimEvidenceLinkForCurrentRequirementBasis(
        criterionID: String,
        linkID: UUID,
        visibility: EvidenceVisibilityV1,
        audience: EvidenceAudienceV1,
        limitation: EvidenceLimitationV1? = nil,
        limitationNote: String? = nil,
        supersedesLinkID: UUID? = nil,
        revision: UInt64 = 1,
        mutationID: MutationIDV1
    ) throws -> ClaimEvidenceLinkV1 {
        guard let assuranceReader else { throw AuthorityCriterionAssuranceReadFailureV1.missingRecord }
        let source = try assuranceReader.currentRequirementBasisSource(criterionID: criterionID)
        guard source.workspaceID == workspaceID else { throw AuthorityCriterionAssuranceReadFailureV1.wrongWorkspace }
        return try AuthorityCriterionCoordinatorV1.claimEvidenceLink(
            source: source, linkID: linkID, visibility: visibility, audience: audience,
            limitation: limitation, limitationNote: limitationNote,
            supersedesLinkID: supersedesLinkID, revision: revision, mutationID: mutationID
        )
    }

    func claimEvidenceLinkForCurrentFindingClassification(
        findingID: UUID,
        criterionID: String,
        linkID: UUID,
        visibility: EvidenceVisibilityV1,
        audience: EvidenceAudienceV1,
        limitation: EvidenceLimitationV1? = nil,
        limitationNote: String? = nil,
        supersedesLinkID: UUID? = nil,
        revision: UInt64 = 1,
        mutationID: MutationIDV1
    ) throws -> ClaimEvidenceLinkV1 {
        guard let assuranceReader else { throw AuthorityCriterionAssuranceReadFailureV1.missingRecord }
        let source = try assuranceReader.currentFindingClassificationSource(
            findingID: findingID, criterionID: criterionID
        )
        guard source.workspaceID == workspaceID else { throw AuthorityCriterionAssuranceReadFailureV1.wrongWorkspace }
        return try AuthorityCriterionCoordinatorV1.claimEvidenceLink(
            source: source, linkID: linkID, visibility: visibility, audience: audience,
            limitation: limitation, limitationNote: limitationNote,
            supersedesLinkID: supersedesLinkID, revision: revision, mutationID: mutationID
        )
    }

    func assurancePreview(
        previewID: UUID,
        audience: EvidenceAudienceV1,
        snapshotSHA256: String,
        projectionVersion: String,
        links: [ClaimEvidenceLinkV1],
        createdAt: Date
    ) throws -> AssuranceProjectionPreviewV1 {
        try AuthorityCriterionCoordinatorV1.assurancePreview(
            previewID: previewID, workspaceID: workspaceID, audience: audience,
            snapshotSHA256: snapshotSHA256, projectionVersion: projectionVersion,
            links: links, createdAt: createdAt
        )
    }

    func admit(_ value: AuthoritySourceReleaseV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendAuthoritySource(value), expectedRevision) }
    func supersede(_ value: AuthoritySourceReleaseV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeAuthoritySource(value), expectedRevision) }
    func admit(_ value: RequirementBasisBindingV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendRequirementBasis(value), expectedRevision) }
    func supersede(_ value: RequirementBasisBindingV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeRequirementBasis(value), expectedRevision) }
    func admit(_ value: ApplicabilityContextSnapshotV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendApplicabilityContext(value), expectedRevision) }
    func supersede(_ value: ApplicabilityContextSnapshotV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeApplicabilityContext(value), expectedRevision) }
    func admit(_ value: AssessmentScopeSnapshotV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendAssessmentScope(value), expectedRevision) }
    func supersede(_ value: AssessmentScopeSnapshotV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeAssessmentScope(value), expectedRevision) }
    func admit(_ value: SeverityScaleReleaseV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendSeverityScale(value), expectedRevision) }
    func supersede(_ value: SeverityScaleReleaseV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeSeverityScale(value), expectedRevision) }
    func admit(_ value: FindingClassificationBindingV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendFindingClassification(value), expectedRevision) }
    func supersede(_ value: FindingClassificationBindingV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeFindingClassification(value), expectedRevision) }
    func admit(_ value: MeasurementProtocolReleaseV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendMeasurementProtocol(value), expectedRevision) }
    func supersede(_ value: MeasurementProtocolReleaseV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeMeasurementProtocol(value), expectedRevision) }
    func admit(_ value: DerivedFactEvaluatorDescriptorV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendEvaluatorDescriptor(value), expectedRevision) }
    func supersede(_ value: DerivedFactEvaluatorDescriptorV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeEvaluatorDescriptor(value), expectedRevision) }
    func admit(_ value: DerivedFactProvenanceV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.appendDerivedFact(value), expectedRevision) }
    func supersede(_ value: DerivedFactProvenanceV1, expectedRevision: UInt64) throws -> WorkspaceMutationOutcomeV1 { try commit(.supersedeDerivedFact(value), expectedRevision) }

    private func commit(
        _ payload: AuthorityCriterionMutationPayloadV1,
        _ expectedRevision: UInt64
    ) throws -> WorkspaceMutationOutcomeV1 {
        let prepared = try AuthorityCriterionCoordinatorV1.prepare(
            workspaceID: workspaceID,
            expectedRevision: expectedRevision,
            payload: payload
        )
        let outcome = try writer.execute(
            prepared.command,
            mutationID: prepared.mutation.mutationID
        )
        try AuthorityCriterionCoordinatorV1.validate(outcome: outcome, for: prepared)
        return outcome
    }
}

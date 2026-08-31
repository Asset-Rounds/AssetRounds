import Foundation

protocol EvidenceCurationContentResolvingV1: Sendable {
    func resolve(_ reference: ContentReferenceV1) async throws -> ContentReferenceV1?
}

struct EvidenceCurationCoordinatorV1: Sendable {
    let contentResolver: any EvidenceCurationContentResolvingV1

    init(contentResolver: any EvidenceCurationContentResolvingV1) {
        self.contentResolver = contentResolver
    }

    func eligibleSelection(
        selectionID: String,
        workspaceID: WorkspaceID,
        currentSequence: EvidenceSequenceV1,
        associations: [EvidenceAssociationV1],
        references: [ContentReferenceV1],
        originalProvenance: [ContentOriginalProvenanceV1]
    ) throws -> EvidenceCurationSelectionV1 {
        guard associations.count <= ContentContractLimitsV1.maximumAssociations,
              references.count <= EvidenceCurationLimitsV1.maximumSelectionCount,
              originalProvenance.count <= EvidenceCurationLimitsV1.maximumSelectionCount else {
            throw EvidenceCurationFailureV1.limitExceeded
        }
        try EvidenceAssociationLedgerV1.validateOrphanFree(events: associations, references: references)
        try currentSequence.validate()
        guard currentSequence.workspaceID == workspaceID else { throw EvidenceCurationFailureV1.wrongWorkspace }
        guard Set(references.map(\.contentID)).count == references.count,
              Set(originalProvenance.map(\.contentID)).count == originalProvenance.count,
              Set(originalProvenance.map(\.provenanceID)).count == originalProvenance.count else {
            throw EvidenceCurationFailureV1.duplicateReference
        }
        guard references.allSatisfy({ $0.workspaceID == workspaceID.rawValue.uuidString.lowercased() }),
              originalProvenance.allSatisfy({ $0.workspaceID == workspaceID.rawValue.uuidString.lowercased() }) else {
            throw EvidenceCurationFailureV1.wrongWorkspace
        }
        let referenceByID = Dictionary(uniqueKeysWithValues: references.map { ($0.contentID, $0) })
        let provenanceByID = Dictionary(uniqueKeysWithValues: originalProvenance.map { ($0.contentID, $0) })
        var terminalByEvidence: [String: EvidenceAssociationV1] = [:]
        for association in associations { terminalByEvidence[association.evidenceID] = association }
        let activeForTarget = terminalByEvidence.values.filter { $0.action != .removed && $0.target == currentSequence.target }
        guard Set(activeForTarget.map(\.evidenceID)) == Set(currentSequence.orderedItems.map(\.evidenceID)) else {
            throw EvidenceCurationFailureV1.staleReference
        }
        let candidates = try currentSequence.orderedItems.map { item -> EvidenceCurationCandidateV1 in
            guard let association = terminalByEvidence[item.evidenceID],
                  try association.associationSHA256 == item.associationBinding.associationSHA256 else {
                throw EvidenceCurationFailureV1.staleReference
            }
            guard let contentID = association.contentID, let reference = referenceByID[contentID],
                  let provenance = provenanceByID[contentID] else { throw EvidenceCurationFailureV1.missingContent }
            return try EvidenceCurationCandidateV1(evidenceID: association.evidenceID, association: association,
                reference: reference, originalProvenance: provenance, sequenceItem: item)
        }
        return try EvidenceCurationSelectionV1(selectionID: selectionID, workspaceID: workspaceID,
            orderedCandidates: candidates)
    }

    func previews(for selection: EvidenceCurationSelectionV1,
                  detailBundles: [String: EvidenceDetailPreviewBundleV1] = [:],
                  missingFallbackText: String) async throws -> [EvidenceVersionPinnedPreviewV1] {
        let selectedIDs = Set(selection.orderedCandidates.map(\.evidenceID))
        guard detailBundles.count <= EvidenceCurationLimitsV1.maximumSelectionCount,
              Set(detailBundles.keys).isSubset(of: selectedIDs) else {
            throw EvidenceCurationFailureV1.limitExceeded
        }
        var result: [EvidenceVersionPinnedPreviewV1] = []
        result.reserveCapacity(selection.orderedCandidates.count)
        for candidate in selection.orderedCandidates {
            if let current = try await contentResolver.resolve(candidate.reference) {
                guard current == candidate.reference else { throw EvidenceCurationFailureV1.staleReference }
                result.append(try EvidenceVersionPinnedPreviewV1(candidate: candidate, availability: .available,
                    availableBundle: detailBundles[candidate.evidenceID]))
            } else {
                guard detailBundles[candidate.evidenceID] == nil else {
                    throw EvidenceCurationFailureV1.staleReference
                }
                result.append(try EvidenceVersionPinnedPreviewV1(candidate: candidate, availability: .missing,
                    missingFallbackText: missingFallbackText))
            }
        }
        return result
    }

    func comparison(comparisonID: String, workspaceID: WorkspaceID, mode: EvidenceComparisonModeV1,
                    orderedPreviews: [EvidenceVersionPinnedPreviewV1], advisoryKey: EvidenceComparisonAdvisoryKeyV1 = .comparisonIsNotProof) throws -> EvidenceComparisonProjectionV1 {
        try EvidenceComparisonProjectionV1(comparisonID: comparisonID, workspaceID: workspaceID,
            mode: mode, orderedPreviews: orderedPreviews, advisoryKey: advisoryKey)
    }

    func reviewedMarkup(markupID: String, workspaceID: WorkspaceID, source: ContentReferenceV1,
                        privacyPolicy: PrivacyTransformPolicyV1, privacyManifest: PrivacyTransformManifestV1,
                        privacyReview: PrivacyReviewReceiptV1,
                        orderedAnnotations: [EvidenceAnnotationV1], orderedReferenceLabels: [String] = []) throws -> EvidenceReviewedMarkupPlanV1 {
        try EvidenceReviewedMarkupPlanV1(markupID: markupID, workspaceID: workspaceID, source: source,
            privacyPolicy: privacyPolicy, privacyManifest: privacyManifest, privacyReview: privacyReview,
            orderedAnnotations: orderedAnnotations, orderedReferenceLabels: orderedReferenceLabels)
    }

    func sequence(metadataSequence: EvidenceSequenceV1, kind: EvidenceSequenceKindV1,
                  orderedSources: [ContentReferenceV1], frameDurationMilliseconds: Int? = nil,
                  contactSheetColumns: Int? = nil, assemblerID: String, assemblerVersion: String) throws -> EvidenceSequencePlanV1 {
        try EvidenceSequencePlanV1(metadataSequence: metadataSequence, kind: kind,
            orderedSources: orderedSources, frameDurationMilliseconds: frameDurationMilliseconds,
            contactSheetColumns: contactSheetColumns, assemblerID: assemblerID, assemblerVersion: assemblerVersion)
    }

    func publicationMutation(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1,
        expectedSequenceRevision: UInt64,
        associationEvent: EvidenceAssociationV1,
        sequenceSuccessor: EvidenceSequenceV1
    ) throws -> EvidenceMetadataMutationV1 {
        try EvidenceMetadataMutationV1(workspaceID: workspaceID, mutationID: mutationID,
            expectedSequenceRevision: expectedSequenceRevision,
            associationEvent: associationEvent, sequenceSuccessor: sequenceSuccessor)
    }

    func replay(_ receipt: EvidenceCurationOperationReceiptV1, requestSHA256: String) throws -> EvidenceCurationOperationReceiptV1 {
        try receipt.replaying(requestSHA256: requestSHA256)
    }
}

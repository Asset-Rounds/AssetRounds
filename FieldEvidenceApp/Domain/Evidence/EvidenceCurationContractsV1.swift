import Foundation

enum EvidenceCurationFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case limitExceeded
    case wrongWorkspace
    case duplicateReference
    case ineligibleReference
    case staleReference
    case missingContent
    case privacyReviewRequired
    case invalidLineage
    case interrupted
    case replayDiverged
    case incompatibleVersion
}

enum EvidenceCurationLimitsV1 {
    static let maximumSelectionCount = 32
    static let maximumComparisonCount = 2
    static let maximumAnnotations = 64
    static let maximumAnnotationTextBytes = 1_024
    static let maximumSequenceFrames = 16
    static let maximumContactSheetColumns = 4
    static let maximumSourceBytes: Int64 = 1_073_741_824
    static let maximumTotalSourceBytes: Int64 = 2_147_483_648
}

enum EvidenceCurationLifecycleV1 {
    static let persistence = "CONTENT_ONLY"
    static let plansAndProjectionsAreNonpersistent = true
    static let schema = "INCUMBENT_CONTENT_AUTHORITY_AND_C05_V43_METADATA"
    static let migration = "C05_METADATA_AUTHORITY"
    static let backupRestore = "REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES"
    static let cloneFork = "INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES"
    static let journalReplay = "C05_METADATA_WRITER_REPLAY_AND_DETERMINISTIC_REPROJECTION"
    static let searchRebuild = "NOT_APPLICABLE"
    static let deleteErase = "REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES"
    static let exportReport = "REQUIRED_VIA_INCUMBENT_CONTENT_C05_METADATA_AND_REPORT_AUTHORITIES"
    static let comparisonIsProof = false
    static let createsContentStore = false
}

private enum EvidenceCurationValidationV1 {
    static func id(_ value: String) -> Bool { ContentContractValidationV1.validID(value) }
    static func digest(_ value: String) -> Bool { KernelCanonicalHashV1.validSHA256(value) }
    static func text(_ value: String, maximumBytes: Int = EvidenceCurationLimitsV1.maximumAnnotationTextBytes) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes
    }
    static func workspace(_ value: WorkspaceID, matches raw: String) -> Bool {
        value.rawValue.uuidString.lowercased() == raw
    }
    static func sourceBytes(_ references: [ContentReferenceV1]) throws {
        guard references.count <= EvidenceCurationLimitsV1.maximumSelectionCount else {
            throw EvidenceCurationFailureV1.limitExceeded
        }
        var total: Int64 = 0
        for reference in references {
            guard reference.byteLength <= EvidenceCurationLimitsV1.maximumSourceBytes else {
                throw EvidenceCurationFailureV1.limitExceeded
            }
            let (next, overflow) = total.addingReportingOverflow(reference.byteLength)
            guard !overflow, next <= EvidenceCurationLimitsV1.maximumTotalSourceBytes else {
                throw EvidenceCurationFailureV1.limitExceeded
            }
            total = next
        }
    }
}

enum EvidenceCurationEligibilityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case eligible = "ELIGIBLE"
    case removedAssociation = "REMOVED_ASSOCIATION"
    case missingContent = "MISSING_CONTENT"
    case wrongWorkspace = "WRONG_WORKSPACE"
    case mutableOrDerivativeSource = "MUTABLE_OR_DERIVATIVE_SOURCE"
    case digestMismatch = "DIGEST_MISMATCH"
}

struct EvidenceCurationCandidateV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let evidenceID: String
    let associationRevision: Int
    let associationEventID: String
    let reference: ContentReferenceV1
    let originalProvenance: ContentOriginalProvenanceV1
    let sequenceItem: EvidenceSequenceItemV1
    let eligibility: EvidenceCurationEligibilityV1

    init(
        evidenceID: String,
        association: EvidenceAssociationV1,
        reference: ContentReferenceV1,
        originalProvenance: ContentOriginalProvenanceV1,
        sequenceItem: EvidenceSequenceItemV1,
        eligibility: EvidenceCurationEligibilityV1 = .eligible
    ) throws {
        guard EvidenceCurationValidationV1.id(evidenceID), evidenceID == association.evidenceID,
              association.action != .removed, association.contentID == reference.contentID,
              association.workspaceID == reference.workspaceID,
              originalProvenance.workspaceID == reference.workspaceID,
              originalProvenance.contentID == reference.contentID,
              originalProvenance.contentDigest == reference.digests.digest(for: .sha256),
              sequenceItem.evidenceID == evidenceID,
              sequenceItem.contentID == reference.contentID,
              sequenceItem.associationBinding == (try EvidenceAssociationBindingV1(association)),
              reference.byteRole == .immutableOriginal,
              eligibility == .eligible else { throw EvidenceCurationFailureV1.ineligibleReference }
        try EvidenceCurationValidationV1.sourceBytes([reference])
        schemaVersion = Self.schemaVersion
        self.evidenceID = evidenceID
        associationRevision = association.resultingEvidenceRevision
        associationEventID = association.associationEventID
        self.reference = reference
        self.originalProvenance = originalProvenance
        self.sequenceItem = sequenceItem
        self.eligibility = eligibility
    }
}

struct EvidenceCurationSelectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let selectionID: String
    let workspaceID: WorkspaceID
    let orderedCandidates: [EvidenceCurationCandidateV1]
    let selectionSHA256: String

    init(selectionID: String, workspaceID: WorkspaceID, orderedCandidates: [EvidenceCurationCandidateV1]) throws {
        guard EvidenceCurationValidationV1.id(selectionID), !orderedCandidates.isEmpty,
              orderedCandidates.count <= EvidenceCurationLimitsV1.maximumSelectionCount else {
            throw EvidenceCurationFailureV1.limitExceeded
        }
        let references = orderedCandidates.map(\.reference)
        try EvidenceCurationValidationV1.sourceBytes(references)
        guard Set(orderedCandidates.map(\.evidenceID)).count == orderedCandidates.count,
              Set(references.map(\.contentID)).count == references.count else {
            throw EvidenceCurationFailureV1.duplicateReference
        }
        for index in orderedCandidates.indices.dropFirst() {
            let prior = orderedCandidates[orderedCandidates.index(before: index)]
            let current = orderedCandidates[index]
            guard prior.sequenceItem.ordinal < current.sequenceItem.ordinal else {
                throw EvidenceCurationFailureV1.invalidValue
            }
        }
        guard references.allSatisfy({ EvidenceCurationValidationV1.workspace(workspaceID, matches: $0.workspaceID) }) else {
            throw EvidenceCurationFailureV1.wrongWorkspace
        }
        schemaVersion = Self.schemaVersion
        self.selectionID = selectionID
        self.workspaceID = workspaceID
        self.orderedCandidates = orderedCandidates
        selectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            selectionID: selectionID,
            workspaceID: workspaceID,
            orderedCandidates: orderedCandidates
        ))
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let selectionID: String
        let workspaceID: WorkspaceID
        let orderedCandidates: [EvidenceCurationCandidateV1]
    }
}

enum EvidencePreviewAvailabilityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case available = "AVAILABLE"
    case missing = "MISSING"
}

struct EvidenceVersionPinnedPreviewV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let evidenceID: String
    let associationRevision: Int
    let reference: ContentReferenceV1
    let availability: EvidencePreviewAvailabilityV1
    let missingFallbackText: String?
    let availableBundle: EvidenceDetailPreviewBundleV1?
    var detailCard: EvidenceDetailCardV1? { availableBundle?.card }

    init(candidate: EvidenceCurationCandidateV1, availability: EvidencePreviewAvailabilityV1,
         missingFallbackText: String? = nil, availableBundle: EvidenceDetailPreviewBundleV1? = nil) throws {
        switch availability {
        case .available:
            guard missingFallbackText == nil,
                  let availableBundle,
                  availableBundle.card.workspaceID == candidate.reference.workspaceID,
                  availableBundle.card.evidenceID == candidate.evidenceID else {
                throw EvidenceCurationFailureV1.invalidValue
            }
        case .missing:
            guard availableBundle == nil, let missingFallbackText,
                  EvidenceCurationValidationV1.text(missingFallbackText) else {
                throw EvidenceCurationFailureV1.missingContent
            }
        }
        schemaVersion = Self.schemaVersion
        evidenceID = candidate.evidenceID
        associationRevision = candidate.associationRevision
        reference = candidate.reference
        self.availability = availability
        self.missingFallbackText = missingFallbackText
        self.availableBundle = availableBundle
    }
}

struct EvidenceDetailPreviewBundleV1: Codable, Equatable, Sendable {
    let snapshot: CompletedActivitySnapshotV1
    let profile: EvidenceDetailCardProfileV1
    let card: EvidenceDetailCardV1
    let confirmation: FinalAudiencePrivacyConfirmationV1
    let renderReceipt: EvidenceDetailCardRenderReceiptV1
    let semanticTree: AccessibleDocumentSemanticTreeV1
    let accessibilityAssessment: AccessibleDocumentAssessmentReceiptV1

    init(snapshot: CompletedActivitySnapshotV1, profile: EvidenceDetailCardProfileV1,
         card: EvidenceDetailCardV1, confirmation: FinalAudiencePrivacyConfirmationV1,
         renderReceipt: EvidenceDetailCardRenderReceiptV1,
         semanticTree: AccessibleDocumentSemanticTreeV1,
         accessibilityAssessment: AccessibleDocumentAssessmentReceiptV1) throws {
        try snapshot.validate(); try card.validate(); try confirmation.validate(); try renderReceipt.validate()
        try snapshot.validateAccessibleDocumentTree(semanticTree)
        try AccessibleDocumentContentReferenceBoundaryV1.validateAssessment(accessibilityAssessment, for: semanticTree)
        guard card.profile == profile, confirmation.card == card, renderReceipt.confirmation == confirmation,
              renderReceipt.snapshotID == snapshot.payload.snapshotID,
              renderReceipt.sourceSnapshotSHA256 == snapshot.snapshotSHA256,
              confirmation.sourceSnapshotSHA256 == snapshot.snapshotSHA256,
              card.workspaceID == snapshot.payload.workspaceID,
              semanticTree.workspaceID == card.workspaceID else {
            throw EvidenceCurationFailureV1.invalidLineage
        }
        self.snapshot = snapshot; self.profile = profile; self.card = card
        self.confirmation = confirmation; self.renderReceipt = renderReceipt
        self.semanticTree = semanticTree; self.accessibilityAssessment = accessibilityAssessment
    }
}

enum EvidenceComparisonModeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case sideBySide = "SIDE_BY_SIDE"
    case advisoryOverlay = "ADVISORY_OVERLAY"
}

enum EvidenceComparisonAdvisoryKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case comparisonIsNotProof = "evidence.comparison.advisory.notProof"
}

struct EvidenceComparisonProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let comparisonID: String
    let workspaceID: WorkspaceID
    let mode: EvidenceComparisonModeV1
    let orderedPreviews: [EvidenceVersionPinnedPreviewV1]
    let advisoryKey: EvidenceComparisonAdvisoryKeyV1
    let comparisonIsProof: Bool
    let projectionSHA256: String

    init(comparisonID: String, workspaceID: WorkspaceID, mode: EvidenceComparisonModeV1,
         orderedPreviews: [EvidenceVersionPinnedPreviewV1], advisoryKey: EvidenceComparisonAdvisoryKeyV1 = .comparisonIsNotProof) throws {
        guard EvidenceCurationValidationV1.id(comparisonID),
              orderedPreviews.count == EvidenceCurationLimitsV1.maximumComparisonCount,
              Set(orderedPreviews.map(\.evidenceID)).count == orderedPreviews.count,
              orderedPreviews.allSatisfy({ EvidenceCurationValidationV1.workspace(workspaceID, matches: $0.reference.workspaceID) }),
              advisoryKey == .comparisonIsNotProof else {
            throw EvidenceCurationFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.comparisonID = comparisonID
        self.workspaceID = workspaceID
        self.mode = mode
        self.orderedPreviews = orderedPreviews
        self.advisoryKey = advisoryKey
        comparisonIsProof = false
        projectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, comparisonID: comparisonID, workspaceID: workspaceID,
            mode: mode, orderedPreviews: orderedPreviews, advisoryKey: advisoryKey, comparisonIsProof: false
        ))
    }
    private struct Basis: Codable { let schemaVersion: Int; let comparisonID: String; let workspaceID: WorkspaceID; let mode: EvidenceComparisonModeV1; let orderedPreviews: [EvidenceVersionPinnedPreviewV1]; let advisoryKey: EvidenceComparisonAdvisoryKeyV1; let comparisonIsProof: Bool }
}

enum EvidenceAnnotationActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case add = "ADD"
    case remove = "REMOVE"
}

struct EvidenceAnnotationV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let annotationID: String
    let action: EvidenceAnnotationActionV1
    let text: String
    let supersedesAnnotationID: String?

    init(annotationID: String, action: EvidenceAnnotationActionV1, text: String,
         supersedesAnnotationID: String? = nil) throws {
        guard EvidenceCurationValidationV1.id(annotationID), EvidenceCurationValidationV1.text(text),
              supersedesAnnotationID.map(EvidenceCurationValidationV1.id) ?? true,
              (action == .remove) == (supersedesAnnotationID != nil) else {
            throw EvidenceCurationFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.annotationID = annotationID
        self.action = action
        self.text = text
        self.supersedesAnnotationID = supersedesAnnotationID
    }
}

struct EvidenceReviewedMarkupPlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let markupID: String
    let workspaceID: WorkspaceID
    let source: ContentReferenceV1
    let privacyPolicy: PrivacyTransformPolicyV1
    let privacyManifest: PrivacyTransformManifestV1
    let privacyReview: PrivacyReviewReceiptV1
    let orderedAnnotations: [EvidenceAnnotationV1]
    let reviewedMarkup: ReviewedEvidenceMarkupV1
    let planSHA256: String

    init(markupID: String, workspaceID: WorkspaceID, source: ContentReferenceV1,
         privacyPolicy: PrivacyTransformPolicyV1, privacyManifest: PrivacyTransformManifestV1,
         privacyReview: PrivacyReviewReceiptV1,
         orderedAnnotations: [EvidenceAnnotationV1], orderedReferenceLabels: [String] = []) throws {
        let privacyClosure = PrivacyTransformLifecycleClosureV1(
            policy: privacyPolicy,
            regions: privacyManifest.orderedRegions,
            manifest: privacyManifest,
            review: privacyReview
        )
        try privacyClosure.validate()
        try privacyReview.validate(manifest: privacyManifest, policy: privacyPolicy)
        guard EvidenceCurationValidationV1.id(markupID), orderedAnnotations.count <= EvidenceCurationLimitsV1.maximumAnnotations,
              Set(orderedAnnotations.map(\.annotationID)).count == orderedAnnotations.count,
              privacyReview.decision == .approved,
              privacyReview.workspaceID == workspaceID, privacyManifest.workspaceID == workspaceID,
              privacyPolicy.workspaceID == workspaceID,
              privacyReview.manifestID == privacyManifest.manifestID,
              privacyReview.manifestRevision == privacyManifest.revision,
              privacyReview.manifestSHA256 == privacyManifest.manifestSHA256,
              privacyManifest.original == source,
              privacyManifest.staleState == .current else {
            throw EvidenceCurationFailureV1.privacyReviewRequired
        }
        var active = Set<String>()
        for annotation in orderedAnnotations {
            switch annotation.action {
            case .add: guard active.insert(annotation.annotationID).inserted else { throw EvidenceCurationFailureV1.invalidLineage }
            case .remove:
                guard let predecessor = annotation.supersedesAnnotationID, active.remove(predecessor) != nil else {
                    throw EvidenceCurationFailureV1.invalidLineage
                }
            }
        }
        let visible = orderedAnnotations.filter { active.contains($0.annotationID) }.map(\.text)
        let markup = try ReviewedEvidenceMarkupV1(markupID: markupID,
            sourcePrivacyDigest: privacyManifest.derivativeSHA256,
            orderedAnnotations: visible, orderedReferenceLabels: orderedReferenceLabels)
        schemaVersion = Self.schemaVersion
        self.markupID = markupID; self.workspaceID = workspaceID; self.source = source
        self.privacyPolicy = privacyPolicy
        self.privacyManifest = privacyManifest; self.privacyReview = privacyReview
        self.orderedAnnotations = orderedAnnotations; reviewedMarkup = markup
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            markupID: markupID, workspaceID: workspaceID, source: source,
            privacyPolicy: privacyPolicy,
            privacyManifestSHA256: privacyManifest.manifestSHA256,
            privacyReviewSHA256: privacyReview.receiptSHA256, orderedAnnotations: orderedAnnotations,
            reviewedMarkup: markup))
    }
    private struct Basis: Codable { let schemaVersion: Int; let markupID: String; let workspaceID: WorkspaceID; let source: ContentReferenceV1; let privacyPolicy: PrivacyTransformPolicyV1; let privacyManifestSHA256: String; let privacyReviewSHA256: String; let orderedAnnotations: [EvidenceAnnotationV1]; let reviewedMarkup: ReviewedEvidenceMarkupV1 }

    func validate() throws {
        let rebuilt = try Self(markupID: markupID, workspaceID: workspaceID, source: source,
            privacyPolicy: privacyPolicy, privacyManifest: privacyManifest, privacyReview: privacyReview,
            orderedAnnotations: orderedAnnotations, orderedReferenceLabels: reviewedMarkup.orderedReferenceLabels)
        guard rebuilt == self else { throw EvidenceCurationFailureV1.replayDiverged }
    }
}

enum EvidenceSequenceKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case flicker = "FLICKER"
    case contactSheet = "CONTACT_SHEET"
}

struct EvidenceSequencePlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let metadataSequence: EvidenceSequenceV1
    let kind: EvidenceSequenceKindV1
    let orderedSources: [ContentReferenceV1]
    let frameDurationMilliseconds: Int?
    let contactSheetColumns: Int?
    let assemblerID: String
    let assemblerVersion: String
    let planSHA256: String
    var sequenceID: UUID { metadataSequence.sequenceID }
    var workspaceID: WorkspaceID { metadataSequence.workspaceID }

    init(metadataSequence: EvidenceSequenceV1, kind: EvidenceSequenceKindV1,
         orderedSources: [ContentReferenceV1], frameDurationMilliseconds: Int? = nil,
         contactSheetColumns: Int? = nil, assemblerID: String, assemblerVersion: String) throws {
        try metadataSequence.validate()
        guard EvidenceCurationValidationV1.id(assemblerID),
              ContentContractValidationV1.validVersion(assemblerVersion),
              (2...EvidenceCurationLimitsV1.maximumSequenceFrames).contains(orderedSources.count),
              Set(orderedSources.map(\.contentID)).count == orderedSources.count,
              orderedSources.map(\.contentID) == metadataSequence.orderedItems.map(\.contentID),
              orderedSources.allSatisfy({ EvidenceCurationValidationV1.workspace(metadataSequence.workspaceID, matches: $0.workspaceID) }) else {
            throw EvidenceCurationFailureV1.invalidValue
        }
        try EvidenceCurationValidationV1.sourceBytes(orderedSources)
        switch kind {
        case .flicker:
            guard let frameDurationMilliseconds, (100...5_000).contains(frameDurationMilliseconds), contactSheetColumns == nil else {
                throw EvidenceCurationFailureV1.invalidValue
            }
        case .contactSheet:
            guard frameDurationMilliseconds == nil, let contactSheetColumns,
                  (1...EvidenceCurationLimitsV1.maximumContactSheetColumns).contains(contactSheetColumns) else {
                throw EvidenceCurationFailureV1.invalidValue
            }
        }
        schemaVersion = Self.schemaVersion; self.metadataSequence = metadataSequence; self.kind = kind
        self.orderedSources = orderedSources; self.frameDurationMilliseconds = frameDurationMilliseconds
        self.contactSheetColumns = contactSheetColumns; self.assemblerID = assemblerID; self.assemblerVersion = assemblerVersion
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, metadataSequence: metadataSequence,
            kind: kind, orderedSources: orderedSources,
            frameDurationMilliseconds: frameDurationMilliseconds, contactSheetColumns: contactSheetColumns,
            assemblerID: assemblerID, assemblerVersion: assemblerVersion))
    }
    private struct Basis: Codable { let schemaVersion: Int; let metadataSequence: EvidenceSequenceV1; let kind: EvidenceSequenceKindV1; let orderedSources: [ContentReferenceV1]; let frameDurationMilliseconds: Int?; let contactSheetColumns: Int?; let assemblerID: String; let assemblerVersion: String }

    func validate() throws {
        let rebuilt = try Self(metadataSequence: metadataSequence, kind: kind,
            orderedSources: orderedSources, frameDurationMilliseconds: frameDurationMilliseconds,
            contactSheetColumns: contactSheetColumns, assemblerID: assemblerID, assemblerVersion: assemblerVersion)
        guard rebuilt == self else { throw EvidenceCurationFailureV1.replayDiverged }
    }
}

struct EvidenceCurationDerivativeResultV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let requestSHA256: String
    let derivative: ContentReferenceV1
    let provenance: ContentDerivativeProvenanceV1
    let orderedSources: [ContentReferenceV1]

    init(requestSHA256: String, derivative: ContentReferenceV1,
         provenance: ContentDerivativeProvenanceV1,
         orderedSources: [ContentReferenceV1]) throws {
        var expectedSources: [ContentSourceBindingV1] = []
        expectedSources.reserveCapacity(orderedSources.count)
        for source in orderedSources {
            guard let digest = source.digests.digest(for: .sha256) else {
                throw EvidenceCurationFailureV1.invalidLineage
            }
            expectedSources.append(try ContentSourceBindingV1(contentID: source.contentID, digest: digest))
        }
        guard EvidenceCurationValidationV1.digest(requestSHA256),
              derivative.byteRole == .derivative,
              provenance.workspaceID == derivative.workspaceID,
              provenance.derivativeContentID == derivative.contentID,
              provenance.derivativeDigest == derivative.digests.digest(for: .sha256),
              provenance.sources == expectedSources else { throw EvidenceCurationFailureV1.invalidLineage }
        switch provenance.transform {
        case .annotation(let transform):
            guard transform.annotationManifestSHA256 == requestSHA256, orderedSources.count == 1 else {
                throw EvidenceCurationFailureV1.invalidLineage
            }
        case .sequence(let transform):
            guard transform.orderedSourceCount == orderedSources.count else {
                throw EvidenceCurationFailureV1.invalidLineage
            }
        default:
            throw EvidenceCurationFailureV1.invalidLineage
        }
        schemaVersion = Self.schemaVersion
        self.requestSHA256 = requestSHA256
        self.derivative = derivative
        self.provenance = provenance
        self.orderedSources = orderedSources
    }
}

enum EvidenceCurationOperationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case planned = "PLANNED"
    case completed = "COMPLETED"
    case interrupted = "INTERRUPTED"
}

struct EvidenceCurationOperationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let operationID: String
    let workspaceID: WorkspaceID
    let requestSHA256: String
    let state: EvidenceCurationOperationStateV1
    let resultSHA256: String?
    let metadataReceipt: EvidenceMetadataMutationReceiptV1?
    let canonicalMutationReceiptSHA256: String?
    let recoveryState: RecoveryCenterStateV1

    init(operationID: String, workspaceID: WorkspaceID, requestSHA256: String,
         state: EvidenceCurationOperationStateV1, resultSHA256: String? = nil,
         metadataReceipt: EvidenceMetadataMutationReceiptV1? = nil) throws {
        try metadataReceipt?.validate()
        guard EvidenceCurationValidationV1.id(operationID), EvidenceCurationValidationV1.digest(requestSHA256),
              resultSHA256.map(EvidenceCurationValidationV1.digest) ?? true,
              (state == .completed) == (resultSHA256 != nil && metadataReceipt != nil),
              state == .completed || (resultSHA256 == nil && metadataReceipt == nil),
              metadataReceipt.map({ $0.mutationReceipt.identity.workspaceID == workspaceID }) ?? true else {
            throw EvidenceCurationFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion; self.operationID = operationID; self.workspaceID = workspaceID
        self.requestSHA256 = requestSHA256; self.state = state; self.resultSHA256 = resultSHA256
        self.metadataReceipt = metadataReceipt
        canonicalMutationReceiptSHA256 = try metadataReceipt.map { try WorkspaceMutationCanonicalV1.sha256($0) }
        switch state {
        case .planned: recoveryState = .checking
        case .completed: recoveryState = .complete
        case .interrupted: recoveryState = .interrupted
        }
    }

    func replaying(requestSHA256: String) throws -> Self {
        guard self.requestSHA256 == requestSHA256 else { throw EvidenceCurationFailureV1.replayDiverged }
        guard state != .interrupted else { throw EvidenceCurationFailureV1.interrupted }
        return self
    }
}

enum EvidenceCurationCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= ContentContractLimitsV1.maximumCanonicalBytes else { throw EvidenceCurationFailureV1.limitExceeded }
        return data
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty else { throw EvidenceCurationFailureV1.invalidValue }
        guard data.count <= ContentContractLimitsV1.maximumCanonicalBytes else { throw EvidenceCurationFailureV1.limitExceeded }
        let decoded = try JSONDecoder().decode(type, from: data)
        guard try encode(decoded) == data else {
            throw EvidenceCurationFailureV1.replayDiverged
        }
        return decoded
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String { KernelCanonicalHashV1.sha256(try encode(value)) }
}

// Closed decoding routes every released payload back through its validating constructor.
extension EvidenceCurationCandidateV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, evidenceID, associationRevision, associationEventID, reference, originalProvenance, sequenceItem, eligibility }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceCurationFailureV1.incompatibleVersion }
        let evidenceID = try c.decode(String.self, forKey: .evidenceID), revision = try c.decode(Int.self, forKey: .associationRevision)
        let eventID = try c.decode(String.self, forKey: .associationEventID), reference = try c.decode(ContentReferenceV1.self, forKey: .reference)
        let provenance = try c.decode(ContentOriginalProvenanceV1.self, forKey: .originalProvenance)
        let item = try c.decode(EvidenceSequenceItemV1.self, forKey: .sequenceItem)
        guard revision > 0, EvidenceCurationValidationV1.id(evidenceID), EvidenceCurationValidationV1.id(eventID),
              try c.decode(EvidenceCurationEligibilityV1.self, forKey: .eligibility) == .eligible,
              reference.byteRole == .immutableOriginal, provenance.workspaceID == reference.workspaceID,
              provenance.contentID == reference.contentID, provenance.contentDigest == reference.digests.digest(for: .sha256),
              item.evidenceID == evidenceID, item.contentID == reference.contentID,
              item.associationBinding.associationEventID == eventID,
              item.associationBinding.resultingEvidenceRevision == revision else {
            throw EvidenceCurationFailureV1.ineligibleReference
        }
        try EvidenceCurationValidationV1.sourceBytes([reference]); schemaVersion = Self.schemaVersion; self.evidenceID = evidenceID
        associationRevision = revision; associationEventID = eventID; self.reference = reference; originalProvenance = provenance; sequenceItem = item; eligibility = .eligible
    }
}

extension EvidenceCurationSelectionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, selectionID, workspaceID, orderedCandidates, selectionSHA256 }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceCurationFailureV1.incompatibleVersion }
        let rebuilt = try Self(selectionID: c.decode(String.self, forKey: .selectionID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), orderedCandidates: c.decode([EvidenceCurationCandidateV1].self, forKey: .orderedCandidates))
        guard rebuilt.selectionSHA256 == (try c.decode(String.self, forKey: .selectionSHA256)) else { throw EvidenceCurationFailureV1.replayDiverged }; self = rebuilt
    }
}

extension EvidenceVersionPinnedPreviewV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, evidenceID, associationRevision, reference, availability, missingFallbackText, availableBundle }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: ["schemaVersion","evidenceID","associationRevision","reference","availability"]); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceCurationFailureV1.incompatibleVersion }
        let availability = try c.decode(EvidencePreviewAvailabilityV1.self, forKey: .availability), fallback = try c.decodeIfPresent(String.self, forKey: .missingFallbackText), bundle = try c.decodeIfPresent(EvidenceDetailPreviewBundleV1.self, forKey: .availableBundle)
        let evidenceID = try c.decode(String.self, forKey: .evidenceID), revision = try c.decode(Int.self, forKey: .associationRevision), reference = try c.decode(ContentReferenceV1.self, forKey: .reference)
        guard EvidenceCurationValidationV1.id(evidenceID), revision > 0 else { throw EvidenceCurationFailureV1.invalidValue }
        switch availability { case .available: guard fallback == nil, let bundle, bundle.card.workspaceID == reference.workspaceID && bundle.card.evidenceID == evidenceID else { throw EvidenceCurationFailureV1.invalidValue }; case .missing: guard bundle == nil, fallback.map(EvidenceCurationValidationV1.text) == true else { throw EvidenceCurationFailureV1.missingContent } }
        schemaVersion = Self.schemaVersion; self.evidenceID = evidenceID; associationRevision = revision; self.reference = reference; self.availability = availability; missingFallbackText = fallback; availableBundle = bundle
    }
}

extension EvidenceDetailPreviewBundleV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case snapshot, profile, card, confirmation, renderReceipt, semanticTree, accessibilityAssessment }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(snapshot: c.decode(CompletedActivitySnapshotV1.self, forKey: .snapshot), profile: c.decode(EvidenceDetailCardProfileV1.self, forKey: .profile), card: c.decode(EvidenceDetailCardV1.self, forKey: .card), confirmation: c.decode(FinalAudiencePrivacyConfirmationV1.self, forKey: .confirmation), renderReceipt: c.decode(EvidenceDetailCardRenderReceiptV1.self, forKey: .renderReceipt), semanticTree: c.decode(AccessibleDocumentSemanticTreeV1.self, forKey: .semanticTree), accessibilityAssessment: c.decode(AccessibleDocumentAssessmentReceiptV1.self, forKey: .accessibilityAssessment))
    }
}

extension EvidenceComparisonProjectionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, comparisonID, workspaceID, mode, orderedPreviews, advisoryKey, comparisonIsProof, projectionSHA256 }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(Bool.self, forKey: .comparisonIsProof) == false else { throw EvidenceCurationFailureV1.incompatibleVersion }
        let rebuilt = try Self(comparisonID: c.decode(String.self, forKey: .comparisonID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), mode: c.decode(EvidenceComparisonModeV1.self, forKey: .mode), orderedPreviews: c.decode([EvidenceVersionPinnedPreviewV1].self, forKey: .orderedPreviews), advisoryKey: c.decode(EvidenceComparisonAdvisoryKeyV1.self, forKey: .advisoryKey))
        guard rebuilt.projectionSHA256 == (try c.decode(String.self, forKey: .projectionSHA256)) else { throw EvidenceCurationFailureV1.replayDiverged }; self = rebuilt
    }
}

extension EvidenceAnnotationV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, annotationID, action, text, supersedesAnnotationID }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: ["schemaVersion","annotationID","action","text"]); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceCurationFailureV1.incompatibleVersion }
        try self.init(annotationID: c.decode(String.self, forKey: .annotationID), action: c.decode(EvidenceAnnotationActionV1.self, forKey: .action), text: c.decode(String.self, forKey: .text), supersedesAnnotationID: c.decodeIfPresent(String.self, forKey: .supersedesAnnotationID))
    }
}

extension EvidenceReviewedMarkupPlanV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, markupID, workspaceID, source, privacyPolicy, privacyManifest, privacyReview, orderedAnnotations, reviewedMarkup, planSHA256 }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceCurationFailureV1.incompatibleVersion }
        let storedMarkup = try c.decode(ReviewedEvidenceMarkupV1.self, forKey: .reviewedMarkup)
        let rebuilt = try Self(markupID: c.decode(String.self, forKey: .markupID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), source: c.decode(ContentReferenceV1.self, forKey: .source), privacyPolicy: c.decode(PrivacyTransformPolicyV1.self, forKey: .privacyPolicy), privacyManifest: c.decode(PrivacyTransformManifestV1.self, forKey: .privacyManifest), privacyReview: c.decode(PrivacyReviewReceiptV1.self, forKey: .privacyReview), orderedAnnotations: c.decode([EvidenceAnnotationV1].self, forKey: .orderedAnnotations), orderedReferenceLabels: storedMarkup.orderedReferenceLabels)
        guard rebuilt.reviewedMarkup == storedMarkup, rebuilt.planSHA256 == (try c.decode(String.self, forKey: .planSHA256)) else { throw EvidenceCurationFailureV1.replayDiverged }; self = rebuilt
    }
}

extension EvidenceSequencePlanV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, metadataSequence, kind, orderedSources, frameDurationMilliseconds, contactSheetColumns, assemblerID, assemblerVersion, planSHA256 }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: ["schemaVersion","metadataSequence","kind","orderedSources","assemblerID","assemblerVersion","planSHA256"]); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceCurationFailureV1.incompatibleVersion }
        let rebuilt = try Self(metadataSequence: c.decode(EvidenceSequenceV1.self, forKey: .metadataSequence), kind: c.decode(EvidenceSequenceKindV1.self, forKey: .kind), orderedSources: c.decode([ContentReferenceV1].self, forKey: .orderedSources), frameDurationMilliseconds: c.decodeIfPresent(Int.self, forKey: .frameDurationMilliseconds), contactSheetColumns: c.decodeIfPresent(Int.self, forKey: .contactSheetColumns), assemblerID: c.decode(String.self, forKey: .assemblerID), assemblerVersion: c.decode(String.self, forKey: .assemblerVersion))
        guard rebuilt.planSHA256 == (try c.decode(String.self, forKey: .planSHA256)) else { throw EvidenceCurationFailureV1.replayDiverged }; self = rebuilt
    }
}

extension EvidenceCurationOperationReceiptV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, operationID, workspaceID, requestSHA256, state, resultSHA256, metadataReceipt, canonicalMutationReceiptSHA256, recoveryState }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: ["schemaVersion","operationID","workspaceID","requestSHA256","state","recoveryState"]); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceCurationFailureV1.incompatibleVersion }
        let state = try c.decode(EvidenceCurationOperationStateV1.self, forKey: .state)
        try self.init(operationID: c.decode(String.self, forKey: .operationID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), requestSHA256: c.decode(String.self, forKey: .requestSHA256), state: state, resultSHA256: c.decodeIfPresent(String.self, forKey: .resultSHA256), metadataReceipt: c.decodeIfPresent(EvidenceMetadataMutationReceiptV1.self, forKey: .metadataReceipt))
        guard recoveryState == (try c.decode(RecoveryCenterStateV1.self, forKey: .recoveryState)),
              canonicalMutationReceiptSHA256 == (try c.decodeIfPresent(String.self, forKey: .canonicalMutationReceiptSHA256)) else { throw EvidenceCurationFailureV1.replayDiverged }
    }
}

extension EvidenceCurationDerivativeResultV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, requestSHA256, derivative, provenance, orderedSources }
    init(from decoder: Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw EvidenceCurationFailureV1.incompatibleVersion }
        try self.init(requestSHA256: c.decode(String.self, forKey: .requestSHA256), derivative: c.decode(ContentReferenceV1.self, forKey: .derivative), provenance: c.decode(ContentDerivativeProvenanceV1.self, forKey: .provenance), orderedSources: c.decode([ContentReferenceV1].self, forKey: .orderedSources))
    }
}

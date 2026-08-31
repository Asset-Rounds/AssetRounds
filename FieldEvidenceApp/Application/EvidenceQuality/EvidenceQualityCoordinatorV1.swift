import Foundation
import SwiftData

/// The C10 coordinator is deliberately a deterministic, advisory-only engine.
/// It accepts canonical capture facts supplied by the media owner; it neither
/// reads a device, mutates original media bytes, nor determines compliance.
@MainActor
final class EvidenceQualityCoordinatorV1 {
    typealias Submit = (EvidenceQualityMutationCommandV1) throws -> EvidenceQualityMutationReceiptV1
    typealias Query = (EvidenceQualityQueryV1) throws -> EvidenceQualityQueryResultV1
    typealias ReceiptLookup = (MutationIDV1) throws -> EvidenceQualityMutationReceiptV1?
    /// Supplied by the C02/content-integrity owner. It verifies that these
    /// exact immutable bytes still belong to this evidence revision and digest.
    typealias ContentIntegrityVerifier = (EvidenceQualityEvidenceBindingV1, Data) throws -> Bool

    struct CanonicalCapture: Equatable, Sendable {
        let evidence: EvidenceQualityEvidenceBindingV1
        let canonicalBytes: Data
        let pixelWidth: Int
        let pixelHeight: Int
        let declaredLumaMillionths: Int64?
        let declaredLaplacianVarianceMillionths: Int64?
        let declaredPerceptualHash: UInt64?
        let declaredReferenceCoverageMillionths: Int64?
        let referenceSequenceSHA256: String?

        init(
            evidence: EvidenceQualityEvidenceBindingV1,
            canonicalBytes: Data,
            pixelWidth: Int,
            pixelHeight: Int,
            declaredLumaMillionths: Int64? = nil,
            declaredLaplacianVarianceMillionths: Int64? = nil,
            declaredPerceptualHash: UInt64? = nil,
            declaredReferenceCoverageMillionths: Int64? = nil,
            referenceSequenceSHA256: String? = nil
        ) {
            self.evidence = evidence
            self.canonicalBytes = canonicalBytes
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.declaredLumaMillionths = declaredLumaMillionths
            self.declaredLaplacianVarianceMillionths = declaredLaplacianVarianceMillionths
            self.declaredPerceptualHash = declaredPerceptualHash
            self.declaredReferenceCoverageMillionths = declaredReferenceCoverageMillionths
            self.referenceSequenceSHA256 = referenceSequenceSHA256
        }
    }

    struct AssessmentRequest: Sendable {
        let assessmentID: UUID
        let workspaceID: WorkspaceID
        let primary: CanonicalCapture
        let duplicateComparison: CanonicalCapture?
        /// Exact provenance-bound captures used by the required-count rule.
        let collection: [CanonicalCapture]
        let ruleSet: EvidenceQualityRuleSetV1
        let assessmentRevision: UInt64
        let mutationID: MutationIDV1
        let expectedRevision: WorkspaceExpectedRevisionV1
        let assessedAt: Date

        init(
            assessmentID: UUID,
            workspaceID: WorkspaceID,
            primary: CanonicalCapture,
            duplicateComparison: CanonicalCapture? = nil,
            collection: [CanonicalCapture],
            ruleSet: EvidenceQualityRuleSetV1,
            assessmentRevision: UInt64,
            mutationID: MutationIDV1,
            expectedRevision: WorkspaceExpectedRevisionV1,
            assessedAt: Date
        ) {
            self.assessmentID = assessmentID
            self.workspaceID = workspaceID
            self.primary = primary
            self.duplicateComparison = duplicateComparison
            self.collection = collection
            self.ruleSet = ruleSet
            self.assessmentRevision = assessmentRevision
            self.mutationID = mutationID
            self.expectedRevision = expectedRevision
            self.assessedAt = assessedAt
        }
    }

    struct WaiverRequest: Sendable {
        let waiverEventID: UUID
        let waiverID: UUID
        let assessment: EvidenceQualityAssessmentV1
        let selectedRuleIDs: [String]
        let reason: EvidenceQualityWaiverReasonV1
        let limitation: String?
        let actor: ActorSnapshotV1
        let recordedAt: Date
        let predecessor: EvidenceQualityWaiverV1?
        let revision: UInt64
        let mutationID: MutationIDV1
        let expectedRevision: WorkspaceExpectedRevisionV1
    }

    enum ActionResult: Equatable, Sendable {
        case preview(EvidenceQualityAssessmentV1)
        case assessed(EvidenceQualityAssessmentV1, EvidenceQualityMutationReceiptV1)
        case retaken(EvidenceQualityAssessmentV1, EvidenceQualityMutationReceiptV1)
        case acceptedWithReason(EvidenceQualityWaiverV1, EvidenceQualityMutationReceiptV1)
        case cancelled
        case rebuilt(EvidenceQualityAssessmentV1)
    }

    private let submit: Submit
    private let query: Query
    private let receiptLookup: ReceiptLookup
    private let contentIntegrityVerifier: ContentIntegrityVerifier

    init(submit: @escaping Submit, query: @escaping Query, receiptLookup: @escaping ReceiptLookup,
         contentIntegrityVerifier: @escaping ContentIntegrityVerifier) {
        self.submit = submit
        self.query = query
        self.receiptLookup = receiptLookup
        self.contentIntegrityVerifier = contentIntegrityVerifier
    }

    /// Production binding: C10 commands enter the existing WorkspaceWriterV1
    /// and its journal.  Querying remains read-only and is supplied by the
    /// incumbent projection owner; this initializer introduces no writer/store.
    convenience init(
        workspaceWriter: WorkspaceWriterV1,
        query: @escaping Query,
        contentIntegrityVerifier: @escaping ContentIntegrityVerifier
    ) {
        self.init(
            submit: { try workspaceWriter.commitEvidenceQuality($0) },
            query: query,
            receiptLookup: { try workspaceWriter.evidenceQualityReceipt(for: $0) },
            contentIntegrityVerifier: contentIntegrityVerifier
        )
    }

    convenience init(
        workspaceWriter: WorkspaceWriterV1,
        modelContext: ModelContext,
        workspaceID: WorkspaceID,
        contentIntegrityVerifier: @escaping ContentIntegrityVerifier
    ) {
        let source = EvidenceQualitySwiftDataQuerySourceV1(
            modelContext: modelContext, workspaceID: workspaceID
        )
        self.init(
            submit: { try workspaceWriter.commitEvidenceQuality($0) },
            query: { try source.result(for: $0) },
            receiptLookup: { mutationID in
                try source.snapshot().receipts.first { $0.mutationID == mutationID }
            },
            contentIntegrityVerifier: contentIntegrityVerifier
        )
    }

    func preview(_ request: AssessmentRequest) throws -> ActionResult {
        .preview(try makeAssessment(request))
    }

    func assess(_ request: AssessmentRequest) throws -> ActionResult {
        let assessment = try makeAssessment(request)
        let command = try command(
            workspaceID: request.workspaceID,
            expectedRevision: request.expectedRevision,
            mutationID: request.mutationID,
            payload: .recordAssessment(assessment),
            submittedAt: request.assessedAt
        )
        return .assessed(assessment, try submitOrRecover(command))
    }

    func retake(_ request: AssessmentRequest) throws -> ActionResult {
        let assessment = try makeAssessment(request)
        let command = try command(
            workspaceID: request.workspaceID,
            expectedRevision: request.expectedRevision,
            mutationID: request.mutationID,
            payload: .recordAssessment(assessment),
            submittedAt: request.assessedAt
        )
        return .retaken(assessment, try submitOrRecover(command))
    }

    func acceptWithReason(_ request: WaiverRequest) throws -> ActionResult {
        let waiver = try EvidenceQualityWaiverV1(
            waiverEventID: request.waiverEventID,
            waiverID: request.waiverID,
            assessment: request.assessment,
            selectedRuleIDs: request.selectedRuleIDs,
            reason: request.reason,
            limitation: request.limitation,
            actor: request.actor,
            recordedAt: request.recordedAt,
            predecessor: request.predecessor,
            revision: request.revision,
            mutationID: request.mutationID
        )
        let command = try command(
            workspaceID: request.assessment.workspaceID,
            expectedRevision: request.expectedRevision,
            mutationID: request.mutationID,
            payload: .recordWaiver(waiver),
            submittedAt: request.recordedAt
        )
        return .acceptedWithReason(waiver, try submitOrRecover(command))
    }

    func cancel() -> ActionResult { .cancelled }

    /// Rebuild is derived only: it never writes a waiver or changes original bytes.
    func rebuild(_ request: AssessmentRequest) throws -> ActionResult {
        .rebuilt(try makeAssessment(request))
    }

    func projection(_ query: EvidenceQualityQueryV1) throws -> EvidenceQualityQueryResultV1 {
        try self.query(query)
    }

    func isCurrent(_ assessment: EvidenceQualityAssessmentV1, for capture: CanonicalCapture,
                   ruleSet: EvidenceQualityRuleSetV1) throws -> Bool {
        try assessment.validateCurrentEvidence(capture.evidence)
        guard try contentIntegrityVerifier(capture.evidence, capture.canonicalBytes) else { return false }
        return assessment.evidence == capture.evidence &&
            assessment.ruleSetID == ruleSet.ruleSetID &&
            assessment.ruleSetRevision == ruleSet.revision &&
            assessment.ruleSetSHA256 == ruleSet.ruleSetSHA256
    }

    private func submitOrRecover(_ command: EvidenceQualityMutationCommandV1) throws -> EvidenceQualityMutationReceiptV1 {
        if let existing = try receiptLookup(command.mutationID) {
            try existing.validate(command: command)
            return existing
        }
        let receipt = try submit(command)
        try receipt.validate(command: command)
        return receipt
    }

    private func command(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        payload: EvidenceQualityMutationPayloadV1,
        submittedAt: Date
    ) throws -> EvidenceQualityMutationCommandV1 {
        try .init(commandID: UUID(), workspaceID: workspaceID, expectedRevision: expectedRevision,
                  mutationID: mutationID, payload: payload, submittedAt: submittedAt)
    }

    private func makeAssessment(_ request: AssessmentRequest) throws -> EvidenceQualityAssessmentV1 {
        try request.primary.evidence.validate()
        guard request.ruleSet.workspaceID == request.workspaceID,
              request.primary.evidence.workspaceID == request.workspaceID,
              request.collection.contains(where: { $0.evidence == request.primary.evidence }) else {
            throw EvidenceQualityFailureV1.wrongWorkspace
        }
        try validateCanonicalCaptures([request.primary], workspaceID: request.workspaceID)
        try validateCanonicalCaptures(request.collection, workspaceID: request.workspaceID)
        if let comparison = request.duplicateComparison {
            try validateCanonicalCaptures([comparison], workspaceID: request.workspaceID)
        }
        let findings = try request.ruleSet.orderedRules.map { rule in
            let measured = try measurement(for: rule, request: request)
            let input = try EvidenceQualityRuleInputV1(
                rule: rule,
                measuredValue: measured.value,
                subject: request.primary.evidence,
                comparison: measured.comparison,
                referenceSequenceSHA256: measured.referenceSequenceSHA256
            )
            let disposition: EvidenceQualityFindingDispositionV1 = rule.comparator.includes(measured.value, threshold: rule.threshold)
                ? .withinConfiguredBoundary : .attentionRecommended
            return try EvidenceQualityRuleFindingV1(rule: rule, input: input, disposition: disposition)
        }
        return try .init(assessmentID: request.assessmentID, workspaceID: request.workspaceID,
                         evidence: request.primary.evidence, ruleSet: request.ruleSet,
                         orderedFindings: findings, revision: request.assessmentRevision,
                         mutationID: request.mutationID, assessedAt: request.assessedAt)
    }

    private func measurement(for rule: EvidenceQualityRuleV1, request: AssessmentRequest) throws
        -> (value: Int64, comparison: EvidenceQualityEvidenceBindingV1?, referenceSequenceSHA256: String?) {
        switch rule.kind {
        case .darkness:
            return (try lumaMillionths(request.primary), nil, nil)
        case .blur:
            return (try laplacianVarianceMillionths(request.primary), nil, nil)
        case .resolution:
            return (try pixelCount(request.primary), nil, nil)
        case .duplicate:
            guard let comparison = request.duplicateComparison else { throw EvidenceQualityFailureV1.invalidValue }
            return (Int64((perceptualHash(request.primary) ^ perceptualHash(comparison)).nonzeroBitCount), comparison.evidence, nil)
        case .framingReferenceSequence:
            guard let coverage = request.primary.declaredReferenceCoverageMillionths,
                  let sequence = request.primary.referenceSequenceSHA256 else { throw EvidenceQualityFailureV1.invalidValue }
            return (coverage, nil, sequence)
        case .requiredCount:
            return (Int64(request.collection.count), nil, nil)
        }
    }

    private func lumaMillionths(_ capture: CanonicalCapture) throws -> Int64 {
        if let declared = capture.declaredLumaMillionths { return declared }
        guard !capture.canonicalBytes.isEmpty else { throw EvidenceQualityFailureV1.invalidValue }
        let total = capture.canonicalBytes.reduce(Int64.zero) { $0 + Int64($1) }
        return try scaled(total, denominator: Int64(capture.canonicalBytes.count) * 255)
    }

    private func laplacianVarianceMillionths(_ capture: CanonicalCapture) throws -> Int64 {
        if let declared = capture.declaredLaplacianVarianceMillionths { return declared }
        let values = capture.canonicalBytes.map(Int64.init)
        guard values.count >= 3 else { throw EvidenceQualityFailureV1.invalidValue }
        let laplacians = zip(zip(values, values.dropFirst()), values.dropFirst(2)).map { pair, next in
            pair.0 - (2 * pair.1) + next
        }
        let mean = laplacians.reduce(0, +) / Int64(laplacians.count)
        let squareSum = try laplacians.reduce(Int64.zero) { partial, value in
            let delta = value - mean
            let (next, overflow) = partial.addingReportingOverflow(delta * delta)
            guard !overflow else { throw EvidenceQualityFailureV1.arithmeticOverflow }
            return next
        }
        return try scaled(squareSum, denominator: Int64(laplacians.count) * 255 * 255)
    }

    private func pixelCount(_ capture: CanonicalCapture) throws -> Int64 {
        guard capture.pixelWidth > 0, capture.pixelHeight > 0 else { throw EvidenceQualityFailureV1.invalidValue }
        let (count, overflow) = Int64(capture.pixelWidth).multipliedReportingOverflow(by: Int64(capture.pixelHeight))
        guard !overflow else { throw EvidenceQualityFailureV1.arithmeticOverflow }
        return count
    }

    private func perceptualHash(_ capture: CanonicalCapture) -> UInt64 {
        if let declared = capture.declaredPerceptualHash { return declared }
        guard !capture.canonicalBytes.isEmpty else { return 0 }
        let mean = capture.canonicalBytes.reduce(Int.zero) { $0 + Int($1) } / capture.canonicalBytes.count
        var result: UInt64 = 0
        for bit in 0..<64 {
            let index = (bit * capture.canonicalBytes.count) / 64
            if Int(capture.canonicalBytes[index]) >= mean { result |= UInt64(1) << UInt64(bit) }
        }
        return result
    }

    private func scaled(_ numerator: Int64, denominator: Int64) throws -> Int64 {
        guard denominator > 0 else { throw EvidenceQualityFailureV1.invalidValue }
        let (scaled, overflow) = numerator.multipliedReportingOverflow(by: 1_000_000)
        guard !overflow, scaled >= 0 else { throw EvidenceQualityFailureV1.arithmeticOverflow }
        return scaled / denominator
    }

    private func validateCanonicalCaptures(_ captures: [CanonicalCapture], workspaceID: WorkspaceID) throws {
        guard !captures.isEmpty else { throw EvidenceQualityFailureV1.invalidValue }
        let bindings = captures.map(\.evidence)
        guard bindings.allSatisfy({ $0.workspaceID == workspaceID }),
              Set(bindings).count == bindings.count else { throw EvidenceQualityFailureV1.duplicateIdentity }
        for capture in captures {
            try capture.evidence.validate()
            guard try contentIntegrityVerifier(capture.evidence, capture.canonicalBytes) else {
                throw EvidenceQualityFailureV1.corruptDigest
            }
        }
    }
}

import CryptoKit
import Foundation

/// Noncanonical two-plane session authority. Implementations stage and retain
/// exact portable bytes, but can never write C14 rows or workspace receipts.
protocol PortableReviewSessionReconciliationV1: Sendable {
    func prepareAcceptAndApply(
        plan: ExternalReviewImportPlanV1,
        receipt: ExternalReviewImportReceiptV1
    ) async throws
    func finalizeAcceptAndApply(
        plan: ExternalReviewImportPlanV1,
        receipt: ExternalReviewImportReceiptV1,
        canonicalReceipt: PortableReviewMutationReceiptV1
    ) async throws
    func finalizeSessionOnly(
        plan: ExternalReviewImportPlanV1,
        receipt: ExternalReviewImportReceiptV1
    ) async throws
    func recoverAcceptAndApply(
        mutationID: MutationIDV1,
        canonicalReceipt: PortableReviewMutationReceiptV1?
    ) async throws
}

@MainActor
final class PortableReviewCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let sessions: any PortableReviewSessionReconciliationV1
    private let reviewLifecycle: InspectionReviewLifecycleAdapterV1

    init(
        writer: WorkspaceWriterV1,
        sessions: any PortableReviewSessionReconciliationV1,
        reviewLifecycle: InspectionReviewLifecycleAdapterV1
    ) {
        self.writer = writer
        self.sessions = sessions
        self.reviewLifecycle = reviewLifecycle
    }

    /// Pure, zero-write planning. The supplied response record already owns
    /// exact canonical bytes; this method only binds it to an exact C14 basis.
    func preview(
        responseRecord: ExternalReviewResponseRecordV1,
        mapping: ReviewRequestC14SubjectItemMappingV1,
        reviewID: UUID,
        basisWorkspaceRevision: UInt64,
        disposition: ExternalReviewImportDispositionV1,
        decision: ExternalReviewImportDecisionV1,
        mutationID: MutationIDV1
    ) throws -> ExternalReviewImportPlanV1 {
        try responseRecord.validate(); try mapping.validate()
        _ = try reviewLifecycle.portableReviewBasis(mapping: mapping, reviewID: reviewID)
        return try ExternalReviewImportPlanV1(
            workspaceID: responseRecord.workspaceID,
            requestPublicID: responseRecord.requestManifest.requestPublicID,
            basisWorkspaceRevision: basisWorkspaceRevision,
            responseRecord: responseRecord,
            c14Mapping: mapping,
            disposition: disposition,
            proofAssessment: responseRecord.proofAssessment,
            decision: decision,
            mutationID: mutationID
        )
    }

    /// Stages exact bytes first, commits one existing-C14 transaction, then
    /// finalizes identical session evidence. A crash between the last two
    /// steps is repaired by recoverAcceptAndApply without reapplying C14.
    func acceptAndApply(
        plan: ExternalReviewImportPlanV1,
        inspectionReviewMutation: InspectionReviewMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) async throws -> PortableReviewMutationReceiptV1 {
        guard plan.basisWorkspaceRevision < UInt64.max else {
            throw PortableReviewFailureV1.ineligibleApplication
        }
        let effectDigest = Data(SHA256.hash(
            data: try WorkspaceMutationCanonicalV1.data(inspectionReviewMutation)
        ))
        let receipt = try ExternalReviewImportReceiptV1(
            workspaceID: plan.workspaceID,
            basisWorkspaceRevision: plan.basisWorkspaceRevision,
            responseRecord: plan.responseRecord,
            decision: .acceptAndApply,
            mutationID: plan.mutationID,
            effectDigest: effectDigest,
            proofAssessment: plan.proofAssessment,
            resultingLifecycleState: .historyOnlyTerminal,
            appliedWorkspaceRevision: plan.basisWorkspaceRevision + 1
        )
        return try await acceptAndApply(
            plan: plan,
            importReceipt: receipt,
            inspectionReviewMutation: inspectionReviewMutation,
            expectedRevision: expectedRevision
        )
    }

    func acceptAndApply(
        plan: ExternalReviewImportPlanV1,
        importReceipt: ExternalReviewImportReceiptV1,
        inspectionReviewMutation: InspectionReviewMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) async throws -> PortableReviewMutationReceiptV1 {
        try plan.validate(); try importReceipt.validate(); try inspectionReviewMutation.validate()
        guard plan.decision == .acceptAndApply,
              plan.disposition == .exactPendingDecision,
              expectedRevision.workspaceID == plan.workspaceID,
              expectedRevision.workspaceRevision == plan.basisWorkspaceRevision,
              plan.mutationID == inspectionReviewMutation.mutationID else {
            throw PortableReviewFailureV1.ineligibleApplication
        }
        guard case let .applyReviewBundle(bundle) = inspectionReviewMutation.postImage else {
            throw PortableReviewFailureV1.ineligibleApplication
        }
        try PortableReviewC14ReconciliationV1.validate(plan: plan, bundle: bundle)
        let mutation = try PortableReviewMutationV1(
            workspaceID: plan.workspaceID,
            mutationID: plan.mutationID,
            plan: plan,
            importReceipt: importReceipt,
            inspectionReviewMutation: inspectionReviewMutation
        )
        try await sessions.prepareAcceptAndApply(plan: plan, receipt: importReceipt)
        let canonical = try writer.commitPortableReview(mutation, expectedRevision: expectedRevision)
        try await sessions.finalizeAcceptAndApply(
            plan: plan,
            receipt: importReceipt,
            canonicalReceipt: canonical
        )
        return canonical
    }

    /// History-only, discard, and quarantine are explicitly outside the
    /// canonical workspace writer and therefore have no MutationReceiptV1.
    func finalizeSessionOnly(
        plan: ExternalReviewImportPlanV1,
        receipt: ExternalReviewImportReceiptV1
    ) async throws -> ExternalReviewImportReceiptV1 {
        try plan.validate(); try receipt.validate()
        guard plan.decision != .acceptAndApply,
              receipt.decision == plan.decision,
              receipt.mutationID == plan.mutationID,
              receipt.workspaceID == plan.workspaceID,
              receipt.appliedWorkspaceRevision == nil else {
            throw PortableReviewFailureV1.invalidValue
        }
        try await sessions.finalizeSessionOnly(plan: plan, receipt: receipt)
        return receipt
    }

    func recoverAcceptAndApply(mutationID: MutationIDV1) async throws {
        let receipt = try writer.portableReviewReceipt(mutationID: mutationID)
        try await sessions.recoverAcceptAndApply(mutationID: mutationID, canonicalReceipt: receipt)
    }
}

// MARK: - C49 work-resource review exchange projection

extension PortableReviewCoordinatorV1 {
    nonisolated static func workResourcePreview(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> C49WorkResourceProjectionEnvelopeV1 {
        try C49WorkResourceReviewExchangeBoundaryV1.customerSafePreview(projection)
    }
}

enum C49WorkResourcePortableReviewCoordinatorBoundaryV1 {
    static let exchangeConsumesCustomerSafePreview = true
    static let directCostRequiresExplicitOptIn = true
    static let canonicalWriterIsNotReplaced = true
}

// MARK: - C52 portable service-request exchange delegation

/// C52 may reuse the existing protected operation/session lifecycle, but its
/// capability, proof, artifact kinds, and receipts stay type-separated from
/// portable review request/response authority.
enum C52PortableReviewServiceRequestExchangeBoundaryV1 {
    static let serviceReleaseContract: Any.Type = PortableServiceRequestProtocolReleaseV1.self
    static let serviceProofContract: Any.Type = ServiceRequestCapabilityProofV1.self
    static let serviceImportReceiptContract: Any.Type = ServiceRequestImportReceiptV1.self
    static let exchangeSessionStoreContract: Any.Type = PortableExchangeSessionStoreV2.self
    static let serviceProofCanBeReplacedByReviewProof = false
    static let serviceSubmissionCanBecomeReviewResponse = false
    static let canonicalWriterIsNotReplaced = true
    static let exchangeCreatesPortalOrNetwork = false
}

extension PortableReviewCoordinatorV1 {
    nonisolated static func c50AdapterProjection(
        _ source: ReviewRequestStateProjectionV1,
        privacyApproval: C50PrivacyPreviewApprovalReferenceV1
    ) throws -> C50PortableReviewAdapterProjectionV1 {
        let projection = try C50PortableReviewAdapterProjectionV1(
            source,
            privacyApproval: privacyApproval
        )
        try C50PortableReviewAdapterDelegationV1.validate(projection)
        return projection
    }
}

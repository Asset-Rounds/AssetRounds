import Foundation

@MainActor
protocol AssistanceProposalLifecycleV1: AnyObject {
    func obtainReviewSnapshot(
        for proposal: AssistanceProposalV1
    ) async throws -> AssistanceProposalEvaluationContextV1
    func present(
        _ proposal: AssistanceProposalV1,
        context: AssistanceProposalEvaluationContextV1
    ) async throws
    func proposal(proposalID: UUID) async -> AssistanceProposalV1?
    func activeProposals(workspaceID: WorkspaceID) async -> [AssistanceProposalV1]
    func review(
        proposalID: UUID,
        context: AssistanceProposalEvaluationContextV1
    ) async throws -> AssistanceReviewDecisionV1
    func accept(
        proposalID: UUID,
        targetMutation: AssistanceCanonicalTargetMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        acceptedBy: ActorSnapshotV1,
        acceptedAt: Date,
        context: AssistanceProposalEvaluationContextV1
    ) async throws -> AssistanceAcceptanceReceiptV1
    func remove(
        proposalID: UUID,
        kind: AssistanceRemovalKindV1,
        expiryReason: AssistanceProposalExpiryReasonV1?
    ) async throws -> AssistanceRemovalDispositionV1
    func expireAll(
        contextByProposal: [UUID: AssistanceProposalEvaluationContextV1]
    ) async throws -> [AssistanceExpiryDispositionV1]
    func recoverAfterInterruption() async throws
}

/// The shared entry point for OCR, speech, one-shot location, and closed
/// deterministic helper providers. Providers can create proposals, but only
/// this explicit-review path can ask the canonical workspace writer to accept.
@MainActor
final class AssistanceCoordinatorV1 {
    private let lifecycle: any AssistanceProposalLifecycleV1

    init(lifecycle: any AssistanceProposalLifecycleV1) {
        self.lifecycle = lifecycle
    }

    func obtainReviewSnapshot(
        for proposal: AssistanceProposalV1
    ) async throws -> AssistanceProposalEvaluationContextV1 {
        try await lifecycle.obtainReviewSnapshot(for: proposal)
    }

    func present(
        _ proposal: AssistanceProposalV1,
        context: AssistanceProposalEvaluationContextV1
    ) async throws {
        try await lifecycle.present(proposal, context: context)
    }

    func proposal(proposalID: UUID) async -> AssistanceProposalV1? {
        await lifecycle.proposal(proposalID: proposalID)
    }

    func activeProposals(workspaceID: WorkspaceID) async -> [AssistanceProposalV1] {
        await lifecycle.activeProposals(workspaceID: workspaceID)
    }

    func review(
        proposalID: UUID,
        context: AssistanceProposalEvaluationContextV1
    ) async throws -> AssistanceReviewDecisionV1 {
        try await lifecycle.review(proposalID: proposalID, context: context)
    }

    func accept(
        proposalID: UUID,
        targetMutation: AssistanceCanonicalTargetMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        acceptedBy: ActorSnapshotV1,
        acceptedAt: Date,
        context: AssistanceProposalEvaluationContextV1
    ) async throws -> AssistanceAcceptanceReceiptV1 {
        try await lifecycle.accept(
            proposalID: proposalID,
            targetMutation: targetMutation,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            acceptedBy: acceptedBy,
            acceptedAt: acceptedAt,
            context: context
        )
    }

    func reject(proposalID: UUID) async throws -> AssistanceRemovalDispositionV1 {
        try await lifecycle.remove(proposalID: proposalID, kind: .rejected, expiryReason: nil)
    }

    func cancel(proposalID: UUID) async throws -> AssistanceRemovalDispositionV1 {
        try await lifecycle.remove(proposalID: proposalID, kind: .cancelled, expiryReason: nil)
    }

    func expire(
        proposalID: UUID,
        reason: AssistanceProposalExpiryReasonV1
    ) async throws -> AssistanceRemovalDispositionV1 {
        try await lifecycle.remove(proposalID: proposalID, kind: .expired, expiryReason: reason)
    }

    func expireAll(
        contextByProposal: [UUID: AssistanceProposalEvaluationContextV1]
    ) async throws -> [AssistanceExpiryDispositionV1] {
        try await lifecycle.expireAll(contextByProposal: contextByProposal)
    }

    func recoverAfterInterruption() async throws {
        try await lifecycle.recoverAfterInterruption()
    }
}

enum C33TemporalEvidenceBoundary_Application_Assistance_AssistanceCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row180 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_Assistance_AssistanceCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

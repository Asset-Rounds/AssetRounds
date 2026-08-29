import Foundation

@MainActor
protocol PlanRebaseWorkspaceWritingV1: AnyObject {
    func commitPlan(_ mutation: PlanMutationV1) throws -> MutationReceiptV1
    func commitPlan(_ mutation: PlanMutationV1,
                    validatedAgainst preview: RebasePreviewV1) throws -> MutationReceiptV1
}

struct PlanRebaseApprovalOutcomeV1: Sendable {
    let preview: RebasePreviewV1
    let planReceipt: RebaseReceiptV1
    let mutationReceipt: MutationReceiptV1
}

struct PlanRebaseRejectionOutcomeV1: Sendable {
    let preview: RebasePreviewV1
    let planReceipt: RebaseReceiptV1
    let mutationReceipt: MutationReceiptV1
}

@MainActor
final class PlanRebaseCoordinatorV1 {
    private let registry: PlanRebaseComponentRegistryV1
    private let writer: any PlanRebaseWorkspaceWritingV1

    init(registry: PlanRebaseComponentRegistryV1,
         writer: any PlanRebaseWorkspaceWritingV1) {
        self.registry = registry
        self.writer = writer
    }

    func appendDocument(_ value: PlanDocumentV1, predecessor: PlanDocumentV1?) throws -> MutationReceiptV1 {
        try writer.commitPlan(.init(workspaceID: value.workspaceID, mutationID: value.mutationID,
                                    payload: .appendDocument(value, predecessor: predecessor)))
    }

    func appendRevision(_ value: PlanRevisionV1, predecessor: PlanRevisionV1?,
                        document: PlanDocumentV1,
                        prerequisites: PlanPrerequisiteClosureV1) throws -> MutationReceiptV1 {
        try prerequisites.validate(revision: value, placements: [])
        try writer.commitPlan(.init(workspaceID: value.workspaceID, mutationID: value.mutationID,
                                    payload: .appendRevision(value, predecessor: predecessor,
                                                             document: document)))
    }

    func appendPlacement(_ value: PlanPlacementV1, predecessor: PlanPlacementV1?,
                         planRevision: PlanRevisionV1,
                         prerequisites: PlanPrerequisiteClosureV1) throws -> MutationReceiptV1 {
        try prerequisites.validate(revision: planRevision, placements: [value])
        try writer.commitPlan(.init(workspaceID: value.workspaceID, mutationID: value.mutationID,
                                    payload: .appendPlacement(value, predecessor: predecessor,
                                                              planRevision: planRevision)))
    }

    func preview(previewID: UUID, workspaceID: WorkspaceID,
                 oldRevision: PlanRevisionV1, newRevision: PlanRevisionV1,
                 transform: PlanAffineTransformV1, placements: [PlanPlacementV1],
                 oldPrerequisites: PlanPrerequisiteClosureV1,
                 newPrerequisites: PlanPrerequisiteClosureV1,
                 expectedRevision: UInt64, generatedAt: Date) throws -> RebasePreviewV1 {
        try oldPrerequisites.validate(revision: oldRevision, placements: placements)
        try newPrerequisites.validate(revision: newRevision, placements: [])
        try PlanRebasePreviewBuilderV1.build(previewID: previewID, workspaceID: workspaceID,
                                             oldRevision: oldRevision, newRevision: newRevision,
                                             transform: transform, placements: placements,
                                             registry: registry, expectedRevision: expectedRevision,
                                             generatedAt: generatedAt)
    }

    func approve(preview: RebasePreviewV1, newRevision: PlanRevisionV1,
                 predecessorRevision: PlanRevisionV1, placements: [PlanPlacementV1],
                 predecessorPlacements: [PlanPlacementV1], receiptID: UUID,
                 prerequisites: PlanPrerequisiteClosureV1,
                 predecessorReceipt: RebaseReceiptV1?, mutationID: MutationIDV1,
                 reviewedBy: ActorSnapshotV1, recordedAt: Date,
                 poseEffects: PlacementPoseMutationV1? = nil) throws -> PlanRebaseApprovalOutcomeV1 {
        try preview.validate()
        try prerequisites.validate(revision: newRevision, placements: placements)
        let poseContribution = preview.contributions.first {
            $0.componentID == "C37_POSE_FRAME_REBASE" && $0.mutationIntentSHA256 != nil
        }
        guard (poseEffects != nil) == (poseContribution != nil) else {
            throw PlanContractFailureV1.componentConflict
        }
        guard reviewedBy.responsibility == .reviewedBy else {
            throw PlanContractFailureV1.reviewRequired
        }
        let commandBasis = try PlanRebaseCommandBasisV1(
            workspaceID: preview.workspaceID, mutationID: mutationID, preview: preview,
            newRevision: newRevision, predecessorRevision: predecessorRevision,
            placements: placements, predecessorPlacements: predecessorPlacements,
            receiptID: receiptID, predecessorReceipt: predecessorReceipt,
            reviewedBy: reviewedBy, recordedAt: recordedAt, poseEffects: poseEffects
        )
        let receiptRevision: UInt64
        if let predecessorReceipt {
            guard predecessorReceipt.revision < UInt64.max else { throw PlanContractFailureV1.invalidSuccessor }
            receiptRevision = predecessorReceipt.revision + 1
        } else {
            receiptRevision = 1
        }
        let planReceipt = try RebaseReceiptV1(
            receiptID: receiptID, preview: preview, decision: .approved,
            resultingRevision: newRevision.reference,
            resultingPlacementsSHA256: PlanRebasePreviewBuilderV1.placementSetSHA256(placements),
            canonicalPlanMutationSHA256: commandBasis.canonicalSHA256,
            reviewedBy: reviewedBy, recordedAt: recordedAt, predecessor: predecessorReceipt,
            revision: receiptRevision, mutationID: mutationID
        )
        try planReceipt.validate(preview: preview, commandBasis: commandBasis,
                                 predecessor: predecessorReceipt)
        let mutation = try PlanMutationV1(
            workspaceID: preview.workspaceID, mutationID: mutationID,
            payload: .applyRebase(newRevision: newRevision,
                                  predecessorRevision: predecessorRevision,
                                  placements: placements,
                                  predecessorPlacements: predecessorPlacements,
                                  receipt: planReceipt,
                                  predecessorReceipt: predecessorReceipt,
                                  poseEffects: poseEffects)
        )
        let mutationReceipt = try writer.commitPlan(mutation, validatedAgainst: preview)
        return PlanRebaseApprovalOutcomeV1(preview: preview, planReceipt: planReceipt,
                                           mutationReceipt: mutationReceipt)
    }

    /// Produces the exact reviewed rejection post-image. Publication remains
    /// the sole writer's responsibility through the closed rejection command;
    /// this method never mutates plan state.
    func rejectionReceipt(preview: RebasePreviewV1, receiptID: UUID,
                          predecessorReceipt: RebaseReceiptV1?, mutationID: MutationIDV1,
                          reviewedBy: ActorSnapshotV1, recordedAt: Date) throws -> RebaseReceiptV1 {
        let revision: UInt64
        if let predecessorReceipt {
            guard predecessorReceipt.revision < UInt64.max else { throw PlanContractFailureV1.invalidSuccessor }
            revision = predecessorReceipt.revision + 1
        } else { revision = 1 }
        return try RebaseReceiptV1(receiptID: receiptID, preview: preview, decision: .rejected,
                                   resultingRevision: nil, resultingPlacementsSHA256: nil,
                                   canonicalPlanMutationSHA256: nil, reviewedBy: reviewedBy,
                                   recordedAt: recordedAt, predecessor: predecessorReceipt,
                                   revision: revision, mutationID: mutationID)
    }

    func reject(preview: RebasePreviewV1, receiptID: UUID,
                predecessorReceipt: RebaseReceiptV1?, mutationID: MutationIDV1,
                reviewedBy: ActorSnapshotV1, recordedAt: Date) throws -> PlanRebaseRejectionOutcomeV1 {
        let planReceipt = try rejectionReceipt(preview: preview, receiptID: receiptID,
                                               predecessorReceipt: predecessorReceipt,
                                               mutationID: mutationID, reviewedBy: reviewedBy,
                                               recordedAt: recordedAt)
        let mutation = try PlanMutationV1(workspaceID: preview.workspaceID,
                                          mutationID: mutationID,
                                          payload: .recordRebaseRejection(
                                            receipt: planReceipt,
                                            predecessorReceipt: predecessorReceipt
                                          ))
        let mutationReceipt = try writer.commitPlan(mutation, validatedAgainst: preview)
        return .init(preview: preview, planReceipt: planReceipt, mutationReceipt: mutationReceipt)
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_Plans_PlanRebaseCoordinatorV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Application_Plans_PlanRebaseCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Plans/PlanRebaseCoordinatorV1.swift", role: .plan)
}

enum C31LightingConsumerBoundary_Application_Plans_PlanRebaseCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/plan-rebase-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}
// MARK: - C32 assistance plan rebase boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_Plans_PlanRebaseCoordinatorV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let planRebaseDoesNotAcceptProposalDirectly = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceBoundary_Application_Plans_PlanRebaseCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row158 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

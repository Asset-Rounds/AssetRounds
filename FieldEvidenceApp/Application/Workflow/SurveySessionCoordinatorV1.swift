import Foundation

enum SurveySessionScheduleCoordinatorBoundaryV1 { static let scheduledStartUsesExplicitAtomicLink = true }

/// Application boundary for C26 survey-session writes. Implementations must
/// route every value through the sole workspace writer and its durable journal;
/// this protocol does not authorize a second store or receipt stream.
@MainActor protocol SurveySessionWritingV1: AnyObject {
    func acceptedSurveySessionMutation(
        _ mutation: SurveySessionMutationV1
    ) throws -> SurveySessionMutationReceiptV1?

    func applySurveySession(
        _ mutation: SurveySessionMutationV1
    ) throws -> SurveySessionMutationReceiptV1
}

@MainActor final class SurveySessionCoordinatorV1 {
    private let writer: any SurveySessionWritingV1

    init(writer: any SurveySessionWritingV1) {
        self.writer = writer
    }

    func apply(
        session: SurveySessionV1,
        definition: SurveyDefinitionReleaseV1,
        packageRelease: InspectionPackageReleaseV1
    ) throws -> SurveySessionMutationReceiptV1 {
        try session.authority.validate(
            definition: definition,
            packageRelease: packageRelease
        )
        try commit(.init(
            workspaceID: session.workspaceID,
            mutationID: session.mutationID,
            payload: .applySession(session, definition: definition, publication: nil)
        ))
    }

    func capture(
        _ capture: FactCaptureV1,
        session: SurveySessionV1,
        definition: SurveyDefinitionReleaseV1,
        packageRelease: InspectionPackageReleaseV1,
        predecessors: [FactCaptureV1]
    ) throws -> SurveySessionMutationReceiptV1 {
        try session.authority.validate(
            definition: definition,
            packageRelease: packageRelease
        )
        try commit(.init(
            workspaceID: capture.workspaceID,
            mutationID: capture.mutationID,
            payload: .captureFact(
                capture,
                session: session,
                definition: definition,
                predecessors: predecessors
            )
        ))
    }

    func apply(
        provisionalSubject: ProvisionalSubjectV1
    ) throws -> SurveySessionMutationReceiptV1 {
        try commit(.init(
            workspaceID: provisionalSubject.workspaceID,
            mutationID: provisionalSubject.mutationID,
            payload: .applyProvisionalSubject(provisionalSubject)
        ))
    }

    func promote(
        provisionalSubject: ProvisionalSubjectV1,
        receipt: SubjectPromotionReceiptV1,
        preview: SubjectPromotionPreviewV1,
        predecessor: SubjectPromotionReceiptV1?
    ) throws -> SurveySessionMutationReceiptV1 {
        try commit(.init(
            workspaceID: provisionalSubject.workspaceID,
            mutationID: provisionalSubject.mutationID,
            payload: .promoteSubject(
                provisionalSubject,
                receipt: receipt,
                preview: preview,
                predecessor: predecessor
            )
        ))
    }

    /// Publication is atomic with the completing/amending session version.
    /// The immutable snapshot captures the exact subject and fact projection;
    /// later promotion or reconciliation cannot rewrite it.
    func publish(
        session: SurveySessionV1,
        snapshot: SurveyPublicationSnapshotV1,
        definition: SurveyDefinitionReleaseV1,
        packageRelease: InspectionPackageReleaseV1,
        captures: [FactCaptureV1]
    ) throws -> SurveySessionMutationReceiptV1 {
        try session.authority.validate(
            definition: definition,
            packageRelease: packageRelease
        )
        try commit(.init(
            workspaceID: session.workspaceID,
            mutationID: session.mutationID,
            payload: .publish(
                session,
                snapshot: snapshot,
                definition: definition,
                captures: captures
            )
        ))
    }

    private func commit(
        _ mutation: SurveySessionMutationV1
    ) throws -> SurveySessionMutationReceiptV1 {
        try mutation.validate()
        if let accepted = try writer.acceptedSurveySessionMutation(mutation) {
            guard accepted.mutationSHA256 == (try WorkspaceMutationCanonicalV1.sha256(mutation)) else {
                throw WorkspaceMutationFailureV1.invalidReceipt
            }
            return accepted
        }
        let receipt = try writer.applySurveySession(mutation)
        guard receipt.mutationSHA256 == (try WorkspaceMutationCanonicalV1.sha256(mutation)) else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        return receipt
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_Workflow_SurveySessionCoordinatorV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_Workflow_SurveySessionCoordinatorV1_swift {
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
enum C30ConsumerBoundaryV1_Application_Workflow_SurveySessionCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Workflow/SurveySessionCoordinatorV1.swift", role: .survey)
}

enum C31LightingConsumerBoundary_Application_Workflow_SurveySessionCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/survey-session-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

// MARK: - C32 accepted survey-fact boundary

extension SurveySessionCoordinatorV1 {
    /// Rebinds an accepted C32 value to the existing survey definition only
    /// after the canonical assistance receipt exists. This method is a
    /// validator, not a writer: the acceptance transaction remains owned by
    /// AssistanceCanonicalWorkspaceWritingV1 and its exact expected revision.
    func acceptedAssistanceFactValue(
        _ receipt: AssistanceAcceptanceReceiptV1,
        for session: SurveySessionV1,
        definition: SurveyDefinitionReleaseV1,
        packageRelease: InspectionPackageReleaseV1
    ) throws -> ResponseValueV1 {
        try receipt.validate()
        try session.authority.validate(
            definition: definition,
            packageRelease: packageRelease
        )
        guard receipt.workspaceID == session.workspaceID,
              receipt.target.entity.kind == .surveySession,
              receipt.target.entity.id == session.sessionID,
              receipt.target.revision == session.revision,
              let field = definition.sections.flatMap(\.facts).first(where: {
                  $0.factID == receipt.target.fieldID
              }),
              SurveyDefinitionStaticValidationV1.response(
                  receipt.acceptedValue,
                  isCompatibleWith: field
              ) else {
            throw AssistanceContractFailureV1.staleTarget
        }
        return receipt.acceptedValue
    }
}

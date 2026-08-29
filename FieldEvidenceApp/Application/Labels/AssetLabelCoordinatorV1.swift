import Foundation

@MainActor protocol AssetLabelAuthoritativePlanValidatingV1: AnyObject {
    /// Re-reads the current locator state, binding receipt, asset revision and frozen release.
    func validateCurrent(_ plan: AssetLabelGenerationPlanV1) async throws
}

@MainActor protocol AssetLabelProjectionRenderingV1: AnyObject {
    /// Produces scratch projection bytes. The accepted snapshot stores only their immutable manifest.
    func project(_ plan: AssetLabelGenerationPlanV1) async throws -> LabelProjectionResultV1
}

@MainActor protocol AssetLabelCanonicalWorkspaceWritingV1: AnyObject {
    func acceptedReceipt(for mutation: AssetLabelMutationV1) async throws -> AssetLabelAcceptanceReceiptV1?
    func commitAssetLabel(_ mutation: AssetLabelMutationV1) async throws -> AssetLabelAcceptanceReceiptV1
}

@MainActor protocol AcceptedLabelGenerationSnapshotQueryingV1: AnyObject {
    func acceptedLabelSnapshot(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> AcceptedLabelGenerationSnapshotV1?

    func acceptedLabelSnapshot(
        workspaceID: WorkspaceID,
        snapshotID: UUID
    ) async throws -> AcceptedLabelGenerationSnapshotV1?
}

@MainActor final class AssetLabelCoordinatorV1 {
    private let authority: any AssetLabelAuthoritativePlanValidatingV1
    private let renderer: any AssetLabelProjectionRenderingV1
    private let writer: any AssetLabelCanonicalWorkspaceWritingV1
    private let query: any AcceptedLabelGenerationSnapshotQueryingV1

    init(
        authority: any AssetLabelAuthoritativePlanValidatingV1,
        renderer: any AssetLabelProjectionRenderingV1,
        writer: any AssetLabelCanonicalWorkspaceWritingV1,
        query: any AcceptedLabelGenerationSnapshotQueryingV1
    ) {
        self.authority = authority
        self.renderer = renderer
        self.writer = writer
        self.query = query
    }

    func projectValidatedPlan(_ plan: AssetLabelGenerationPlanV1) async throws -> LabelProjectionResultV1 {
        try plan.validate()
        try await authority.validateCurrent(plan)
        let result = try await renderer.project(plan)
        try result.validate(plan: plan)
        return result
    }

    func makeAcceptanceRequest(
        snapshotID: UUID,
        plan: AssetLabelGenerationPlanV1,
        projection: LabelProjectionResultV1,
        outputReceipt: LabelOutputReceiptV1,
        activationDecision: LabelOutputActivationDecisionV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        recordedBy: ActorSnapshotV1,
        recordedAt: Date
    ) async throws -> AssetLabelAcceptanceRequestV1 {
        try plan.validate()
        try projection.validate(plan: plan)
        try outputReceipt.validate()
        try await authority.validateCurrent(plan)
        let snapshot = try AcceptedLabelGenerationSnapshotV1(
            snapshotID: snapshotID,
            plan: plan,
            result: projection,
            outputReceipt: outputReceipt,
            activationDecision: activationDecision,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            recordedBy: recordedBy,
            recordedAt: recordedAt
        )
        return try AssetLabelAcceptanceRequestV1(snapshot: snapshot)
    }

    func accept(_ request: AssetLabelAcceptanceRequestV1) async throws -> AssetLabelAcceptanceReceiptV1 {
        try request.validate()
        try await authority.validateCurrent(request.snapshot.plan)
        if let receipt = try await writer.acceptedReceipt(for: request.mutation) {
            try receipt.validate(snapshot: request.snapshot)
            return receipt
        }
        let receipt = try await writer.commitAssetLabel(request.mutation)
        try receipt.validate(snapshot: request.snapshot)
        return receipt
    }

    func acceptedSnapshot(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> AcceptedLabelGenerationSnapshotV1? {
        let snapshot = try await query.acceptedLabelSnapshot(workspaceID: workspaceID, mutationID: mutationID)
        try snapshot?.validate()
        return snapshot
    }

    func acceptedSnapshot(
        workspaceID: WorkspaceID,
        snapshotID: UUID
    ) async throws -> AcceptedLabelGenerationSnapshotV1? {
        let snapshot = try await query.acceptedLabelSnapshot(workspaceID: workspaceID, snapshotID: snapshotID)
        try snapshot?.validate()
        return snapshot
    }

    func reprintEligibility(
        for snapshot: AcceptedLabelGenerationSnapshotV1,
        context: AssetLabelReprintContextV1
    ) throws -> LabelReprintEligibilityV1 {
        try snapshot.reprintEligibility(in: context)
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_Labels_AssetLabelCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

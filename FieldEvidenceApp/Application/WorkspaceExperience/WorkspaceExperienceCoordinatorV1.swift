import Foundation

struct WorkspaceExperienceCoordinatorV1: Sendable {
    private let access: any AppAccessGatePortV1

    init(access: any AppAccessGatePortV1) { self.access = access }

    func withAuthorizedPrivateProjection<T: Sendable>(
        _ projection: @Sendable () async throws -> T
    ) async throws -> T {
        try await access.requireContentAccess()
        return try await projection()
    }

    func installPlan(
        planID: UUID,
        workspaceID: WorkspaceID,
        template: StarterWorkspaceTemplateReleaseV1,
        mutationID: MutationIDV1,
        requestedAt: Date,
        destinationWasEmpty: Bool
    ) throws -> StarterWorkspaceInstallPlanV1 {
        try StarterWorkspaceInstallPlanV1(
            planID: planID,
            workspaceID: workspaceID,
            template: template,
            mutationID: mutationID,
            requestedAt: requestedAt,
            explicitUserRequest: true,
            destinationWasEmpty: destinationWasEmpty
        )
    }

    func profile(
        workspaceID: WorkspaceID,
        provenance: PracticeWorkspaceProvenanceV1?,
        policy: UXSimplicityPolicyV1
    ) throws -> WorkspaceExperienceProfileV1 {
        try WorkspaceExperienceProfileV1(workspaceID: workspaceID, provenance: provenance, policy: policy)
    }

    func resumeProjection(from value: DraftRecoveryProjectionV1) throws -> WorkspaceResumeProjectionV1 {
        let disposition: WorkspaceResumeDispositionV1
        switch value.status {
        case .resumable: disposition = .resume
        case .conflict, .missingMedia, .lowStorage, .protectedData, .unsupportedCodec,
             .partialStage, .staleTarget, .recoveryRequired: disposition = .reviewRequired
        }
        return try WorkspaceResumeProjectionV1(
            workspaceID: value.workspaceID,
            draftID: value.draftID,
            disposition: disposition,
            routeToken: "draft:\(value.draftID.uuidString.lowercased())",
            restoredWorkMustNotRestart: true,
            updatedAt: value.updatedAt
        )
    }

    func contextualGuidance(
        workspaceID: WorkspaceID,
        contextKey: String,
        catalog: ContextualGuidanceCatalogV1,
        generatedAt: Date
    ) throws -> ContextualGuidanceProjectionV1 {
        try catalog.validate()
        return try ContextualGuidanceProjectionV1(
            workspaceID: workspaceID,
            contextKey: contextKey,
            entries: catalog.entries.filter { $0.contextKey == contextKey },
            generatedAt: generatedAt
        )
    }

    func todayUpdates(
        workspaceID: WorkspaceID,
        values: [TodayUpdateProjectionV1]
    ) throws -> [TodayUpdateProjectionV1] {
        guard values.count <= WorkspaceExperienceLimitsV1.maximumItems,
              values.allSatisfy({ $0.workspaceID == workspaceID }),
              Set(values.map(\.updateID)).count == values.count else {
            throw WorkspaceExperienceFailureV1.wrongWorkspace
        }
        return values.sorted()
    }

    func conductor(
        profile: WorkspaceExperienceProfileV1,
        stage: FirstRealJobStageV1,
        nextAction: NextRequiredActionProjectionV1,
        budget: TechnicianWorkflowBudgetV1,
        evaluatedAt: Date
    ) throws -> FirstRealJobConductorProjectionV1 {
        try FirstRealJobConductorProjectionV1(
            workspaceID: profile.workspaceID,
            workspaceKind: profile.kind,
            stage: stage,
            nextAction: nextAction,
            budget: budget,
            evaluatedAt: evaluatedAt
        )
    }

    func availability(
        featureKey: String,
        policyEnabled: Bool,
        accessState: AppAccessStateV1,
        protectedDataAvailable: Bool,
        workspaceKind: WorkspaceExperienceWorkspaceKindV1?,
        requiresRealWorkspace: Bool = false
    ) throws -> FeatureAvailabilityPresentationV1 {
        let reason: WorkspaceExperienceAvailabilityReasonV1
        if !policyEnabled { reason = .disabledByPolicy }
        else if !accessState.permitsContentAccess { reason = .appLocked }
        else if !protectedDataAvailable { reason = .protectedDataUnavailable }
        else if requiresRealWorkspace && workspaceKind != .real { reason = .realWorkspaceRequired }
        else if workspaceKind == nil { reason = .sourceUnavailable }
        else { reason = .available }
        return try FeatureAvailabilityPresentationV1(
            featureKey: featureKey,
            isAvailable: reason == .available,
            reason: reason,
            explanationKey: "workspace.experience.availability.\(reason.rawValue.lowercased())"
        )
    }
}

import Foundation

enum AssetSemanticsScheduleCoordinatorBoundaryV1 { static let scheduleProjectionIsReadOnly = true }

enum C51AssetSemanticsScheduleCoordinatorBoundaryV1 {
    static let closureReferenceIsDerivedMetadataOnly = true
    static let canonicalOccurrenceWriterIsNotCalled = true

    static func validate(_ reference: C51ScheduleClosureReferenceV1) throws {
        try reference.validate()
    }
}

extension AssetSemanticsCoordinatorV1 {
    /// Resolution is deliberately read-only and shares no semantic mutation
    /// plan with the C39 coordinator.
    func resolveLocator(
        _ input: LocatorResolutionInputV1,
        workspaceID: WorkspaceID,
        evaluatedAt: Date,
        using resolver: OfflineAssetLocatorResolverV1
    ) async throws -> LocatorResolutionV1 {
        try await resolver.resolve(input, workspaceID: workspaceID, evaluatedAt: evaluatedAt)
    }
}

enum AssetSemanticsCoordinatorFailureV1: Error, Equatable, Sendable {
    case invalidPlan
    case staleRevision
    case missingDurableReceipt
    case receiptMismatch
}

/// Read/validation-only seam for C39.  Implementations may inspect the
/// durable semantic rows, but all writes still go through WorkspaceWriterV1.
@MainActor
protocol AssetSemanticLifecyclePortV1: AnyObject {
    func validate(_ mutation: AssetSemanticsMutationV1) throws
    func functionalRelationshipProjection(
        boundary: FunctionalRelationshipReadinessBoundaryV1?
    ) throws -> CurrentFunctionalRelationshipProjectionV1
    func functionalRelationshipPreview(
        change: FunctionalRelationshipEndpointChangeV1,
        relationshipID: UUID,
        currentSiteID: UUID,
        proposedSiteID: UUID?
    ) throws -> FunctionalRelationshipDispositionPreviewV1
    func validate(
        _ scope: WorkSubjectScopeSnapshotV1,
        against snapshot: CompletedFunctionalRelationshipSnapshotV1
    ) throws
}

struct AssetSemanticsPreviewBasisV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutation: AssetSemanticsMutationV1

    init(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutation: AssetSemanticsMutationV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.mutation = mutation
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              expectedRevision.workspaceID == workspaceID,
              mutation.workspaceID == workspaceID else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        try mutation.validate()
        let target = try mutation.affectedIdentity
        let expectedByIdentity = Dictionary(
            uniqueKeysWithValues: expectedRevision.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        guard expectedRevision.generationID != Self.zeroUUID,
              expectedRevision.workspaceRevision < UInt64.max,
              expectedByIdentity[target] == mutation.expectedAssetRevision else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// A C39 preview is immutable.  The operation ID identifies this plan while
/// the embedded MutationIDV1 is the idempotency identity consumed by the
/// canonical writer and journal.
struct AssetSemanticsChangePlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let mutationID: MutationIDV1
    let basis: AssetSemanticsPreviewBasisV1
    let planSHA256: String

    init(
        operationID: UUID,
        mutationID: MutationIDV1,
        basis: AssetSemanticsPreviewBasisV1
    ) throws {
        guard operationID != Self.zeroUUID else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        try basis.validate()
        guard basis.mutation.mutationID == mutationID else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.mutationID = mutationID
        self.basis = basis
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                operationID: operationID,
                mutationID: mutationID,
                basis: basis
            )
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              operationID != Self.zeroUUID,
              basis.mutation.mutationID == mutationID,
              MutationEnvelopeV1.isSHA256(planSHA256) else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        try basis.validate()
        guard planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: schemaVersion,
                operationID: operationID,
                mutationID: mutationID,
                basis: basis
            )
        )) else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let operationID: UUID
        let mutationID: MutationIDV1
        let basis: AssetSemanticsPreviewBasisV1
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// The only application writer seam for C39 asset-semantic mutations.
@MainActor
final class AssetSemanticsCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let idSource: any ApplicationIDSource
    private let lifecycle: (any AssetSemanticLifecyclePortV1)?

    init(
        writer: WorkspaceWriterV1,
        idSource: any ApplicationIDSource,
        lifecycle: (any AssetSemanticLifecyclePortV1)? = nil
    ) {
        self.writer = writer
        self.idSource = idSource
        self.lifecycle = lifecycle
    }

    func makeMutationID() throws -> MutationIDV1 {
        try writer.makeMutationID()
    }

    func preview(
        _ basis: AssetSemanticsPreviewBasisV1
    ) throws -> AssetSemanticsChangePlanV1 {
        try basis.validate()
        let observed = try writer.currentRevision()
        guard try Self.revision(from: basis.expectedRevision) == observed else {
            throw AssetSemanticsCoordinatorFailureV1.staleRevision
        }
        try lifecycle?.validate(basis.mutation)
        guard try writer.currentRevision() == observed else {
            throw AssetSemanticsCoordinatorFailureV1.staleRevision
        }
        let plan = try AssetSemanticsChangePlanV1(
            operationID: idSource.makeID(),
            mutationID: basis.mutation.mutationID,
            basis: basis
        )
        guard try writer.currentRevision() == observed else {
            throw AssetSemanticsCoordinatorFailureV1.staleRevision
        }
        return plan
    }

    func preview(
        mutation: AssetSemanticsMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        workspaceID: WorkspaceID
    ) throws -> AssetSemanticsChangePlanV1 {
        try preview(
            AssetSemanticsPreviewBasisV1(
                workspaceID: workspaceID,
                expectedRevision: expectedRevision,
                mutation: mutation
            )
        )
    }

    func commit(
        _ plan: AssetSemanticsChangePlanV1
    ) throws -> AssetSemanticsChangeReceiptV1 {
        try plan.validate()
        try lifecycle?.validate(plan.basis.mutation)
        _ = try writer.execute(WorkspaceMutationRequestV1(
            mutationID: plan.mutationID,
            expectedRevision: plan.basis.expectedRevision,
            command: .applyAssetSemantics(plan.basis.mutation)
        ))
        guard let durableReceipt = try writer.durableReceipt(
            mutationID: plan.mutationID
        ) else {
            throw AssetSemanticsCoordinatorFailureV1.missingDurableReceipt
        }
        do {
            return try AssetSemanticsChangeReceiptV1(
                plan: plan,
                mutationReceipt: durableReceipt
            )
        } catch let failure as AssetSemanticsCoordinatorFailureV1 {
            throw failure
        } catch {
            throw AssetSemanticsCoordinatorFailureV1.receiptMismatch
        }
    }

    /// Read-only C39/C41 bridge. The current graph remains event-derived in the
    /// lifecycle adapter and this coordinator never writes a projection.
    func functionalRelationshipProjection(
        boundary: FunctionalRelationshipReadinessBoundaryV1? = nil
    ) throws -> CurrentFunctionalRelationshipProjectionV1 {
        guard let lifecycle else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        return try lifecycle.functionalRelationshipProjection(boundary: boundary)
    }

    func functionalRelationshipPreview(
        change: FunctionalRelationshipEndpointChangeV1,
        relationshipID: UUID,
        currentSiteID: UUID,
        proposedSiteID: UUID? = nil
    ) throws -> FunctionalRelationshipDispositionPreviewV1 {
        guard let lifecycle else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        return try lifecycle.functionalRelationshipPreview(
            change: change,
            relationshipID: relationshipID,
            currentSiteID: currentSiteID,
            proposedSiteID: proposedSiteID
        )
    }

    func validateFrozenWorkSubjectScope(
        _ scope: WorkSubjectScopeSnapshotV1,
        against snapshot: CompletedFunctionalRelationshipSnapshotV1
    ) throws {
        guard let lifecycle else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        try lifecycle.validate(scope, against: snapshot)
    }

    func commit(
        mutation: AssetSemanticsMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        workspaceID: WorkspaceID
    ) throws -> AssetSemanticsChangeReceiptV1 {
        try commit(preview(
            mutation: mutation,
            expectedRevision: expectedRevision,
            workspaceID: workspaceID
        ))
    }

    private static func revision(
        from expected: WorkspaceExpectedRevisionV1
    ) throws -> WorkspaceRevisionV1 {
        try WorkspaceRevisionV1(
            workspaceID: expected.workspaceID,
            generationID: expected.generationID,
            writerInstanceID: expected.writerInstanceID,
            revision: expected.workspaceRevision,
            entityRevisions: expected.entityRevisions
        )
    }
}

typealias AssetSemanticsPlanV1 = AssetSemanticsChangePlanV1
typealias AssetSemanticsReceiptV1 = AssetSemanticsChangeReceiptV1

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_AssetSemantics_AssetSemanticsCoordinatorV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_AssetSemantics_AssetSemanticsCoordinatorV1_swift {
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
enum C30ConsumerBoundaryV1_Application_AssetSemantics_AssetSemanticsCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/AssetSemantics/AssetSemanticsCoordinatorV1.swift", role: .asset)
}

enum C31LightingConsumerBoundary_Application_AssetSemantics_AssetSemanticsCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/asset-semantics-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}
// MARK: - C32 assistance asset-semantics boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_AssetSemantics_AssetSemanticsCoordinatorV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptedEffectRebindsToExistingAssetSemantics = true

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

enum C33TemporalEvidenceBoundary_Application_AssetSemantics_AssetSemanticsCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

/// C45 label preview consumes exact current semantic state before explicit Start.
enum C45AssetLabelBoundary_AssetSemanticsCoordinatorV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let previewRequiresExplicitStart = true
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_AssetSemantics_AssetSemanticsCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

enum C34AssetSemanticRouteAdapterV1 {
    static let routeStoresDisplayCopy = false

    static func semanticID(_ value: String) throws -> String {
        try RouteContractValidationV1.semanticID(value)
        return value
    }
}

enum C34RouteAdoptionBoundary_AssetSemanticsCoordinatorV1 {
    static let canonicalTargetType = NavigationTargetV1.self
    static let semanticIDAdapter = C34AssetSemanticRouteAdapterV1.self
    static let restorationIsReadOnly = true
}

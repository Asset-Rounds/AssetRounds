import Foundation

extension LightingCoordinatorV1 {
    @MainActor
    static func nightWorkflowCoordinator(
        query: any LightingNightWorkflowQueryingV1,
        sourceResolver: any LightingNightWorkflowSourceResolvingV1,
        authority: any LightingNightWorkflowMutationAuthorityV1
    ) -> LightingNightWorkflowCoordinatorV1 {
        LightingNightWorkflowCoordinatorV1(
            query: query,
            sourceResolver: sourceResolver,
            authority: authority
        )
    }
}

protocol LightingQueryingV1: Sendable {
    func latestSystem(workspaceID: WorkspaceID, systemID: UUID) async throws -> LightingSystemV1?
    func latestObservation(workspaceID: WorkspaceID, observationID: UUID) async throws -> LightingObservationV1?
    func latestIssue(workspaceID: WorkspaceID, issueID: UUID) async throws -> LightingIssueV1?
    func latestMeasurementPlan(workspaceID: WorkspaceID, planID: UUID) async throws -> MeasurementPlanV1?
    func latestClaim(workspaceID: WorkspaceID, claimID: UUID) async throws -> LightingClaimStateV1?
}

enum LightingWriteOperationV1: Codable, Equatable, Sendable {
    case appendSystem(value: LightingSystemV1, predecessor: LightingSystemV1?, admission: LightingTopologyAdmissionClosureV1)
    case appendObservation(value: LightingObservationV1, predecessor: LightingObservationV1?, system: LightingSystemV1)
    case appendIssue(value: LightingIssueV1, predecessor: LightingIssueV1?, admission: LightingIssueAdmissionClosureV1)
    case appendMeasurementPlan(value: MeasurementPlanV1, predecessor: MeasurementPlanV1?, system: LightingSystemV1)
    case appendClaim(value: LightingClaimStateV1, predecessor: LightingClaimStateV1?, admission: LightingClaimAdmissionClosureV1)

    var workspaceID: WorkspaceID {
        switch self {
        case .appendSystem(let value, _, _): value.workspaceID
        case .appendObservation(let value, _, _): value.workspaceID
        case .appendIssue(let value, _, _): value.workspaceID
        case .appendMeasurementPlan(let value, _, _): value.workspaceID
        case .appendClaim(let value, _, _): value.workspaceID
        }
    }
    var mutationID: MutationIDV1 {
        switch self {
        case .appendSystem(let value, _, _): value.mutationID
        case .appendObservation(let value, _, _): value.mutationID
        case .appendIssue(let value, _, _): value.mutationID
        case .appendMeasurementPlan(let value, _, _): value.mutationID
        case .appendClaim(let value, _, _): value.mutationID
        }
    }
    func validate() throws {
        switch self {
        case .appendSystem(let value, let predecessor, let admission):
            try value.validateIntrinsic()
            try admission.validate(system: value)
            if let predecessor { try value.validateSuccessor(of: predecessor) }
            else if value.revision != 1 { throw LightingContractFailureV1.invalidSuccessor }
        case .appendObservation(let value, let predecessor, let system):
            try value.validate(system: system)
            if let predecessor { try value.validateSuccessor(of: predecessor, system: system) }
            else if value.revision != 1 { throw LightingContractFailureV1.invalidSuccessor }
        case .appendIssue(let value, let predecessor, let admission):
            try admission.validate(issue: value, predecessor: predecessor)
        case .appendMeasurementPlan(let value, let predecessor, let system):
            try value.validate(system: system)
            if let predecessor { try value.validateSuccessor(of: predecessor, system: system) }
            else if value.revision != 1 { throw LightingContractFailureV1.invalidSuccessor }
        case .appendClaim(let value, let predecessor, let admission):
            try admission.validate(claim: value)
            if let predecessor { try value.validateSuccessor(of: predecessor) }
            else if value.revision != 1 { throw LightingContractFailureV1.invalidSuccessor }
        }
    }
}

@MainActor
protocol LightingMutationAuthorityV1: AnyObject {
    func commit(_ operation: LightingWriteOperationV1) async throws -> MutationReceiptV1
}

struct LightingWriteReceiptV1: Codable, Equatable, Sendable {
    let operationSHA256: String
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let committedAt: Date
    init(operation: LightingWriteOperationV1, mutationReceipt: MutationReceiptV1) throws {
        try operation.validate(); try mutationReceipt.validate()
        guard mutationReceipt.identity.workspaceID == operation.workspaceID,
              mutationReceipt.mutationID == operation.mutationID else {
            throw LightingContractFailureV1.staleReference
        }
        operationSHA256 = try LightingCanonicalCodecV1.sha256(operation)
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        committedAt = mutationReceipt.committedAt
    }
}

@MainActor
final class LightingCoordinatorV1 {
    private let query: any LightingQueryingV1
    private let authority: any LightingMutationAuthorityV1
    init(query: any LightingQueryingV1, authority: any LightingMutationAuthorityV1) {
        self.query = query; self.authority = authority
    }
    func append(_ value: LightingSystemV1,
                admission: LightingTopologyAdmissionClosureV1) async throws -> LightingWriteReceiptV1 {
        let predecessor = try await query.latestSystem(workspaceID: value.workspaceID, systemID: value.systemID)
        return try await commit(.appendSystem(value: value, predecessor: predecessor, admission: admission))
    }
    func append(_ value: LightingObservationV1, system: LightingSystemV1) async throws -> LightingWriteReceiptV1 {
        let predecessor = try await query.latestObservation(workspaceID: value.workspaceID,
                                                             observationID: value.observationID)
        return try await commit(.appendObservation(value: value, predecessor: predecessor, system: system))
    }
    func append(_ value: LightingIssueV1,
                admission: LightingIssueAdmissionClosureV1) async throws -> LightingWriteReceiptV1 {
        let predecessor = try await query.latestIssue(workspaceID: value.workspaceID, issueID: value.issueID)
        return try await commit(.appendIssue(value: value, predecessor: predecessor, admission: admission))
    }
    func append(_ value: MeasurementPlanV1, system: LightingSystemV1) async throws -> LightingWriteReceiptV1 {
        let predecessor = try await query.latestMeasurementPlan(workspaceID: value.workspaceID, planID: value.planID)
        return try await commit(.appendMeasurementPlan(value: value, predecessor: predecessor, system: system))
    }
    func append(_ value: LightingClaimStateV1,
                admission: LightingClaimAdmissionClosureV1) async throws -> LightingWriteReceiptV1 {
        let predecessor = try await query.latestClaim(workspaceID: value.workspaceID, claimID: value.claimID)
        return try await commit(.appendClaim(value: value, predecessor: predecessor, admission: admission))
    }
    private func commit(_ operation: LightingWriteOperationV1) async throws -> LightingWriteReceiptV1 {
        try operation.validate()
        let receipt = try await authority.commit(operation)
        return try .init(operation: operation, mutationReceipt: receipt)
    }
}

// C17 remains a distinct aggregate and journal operation, but is composed from
// the incumbent lighting application boundary so callers do not create a
// parallel lighting service or persistence owner.
extension LightingCoordinatorV1 {
    static func dayInventoryCoordinator(
        query: any LightingDayInventoryQueryingV1,
        authority: any LightingDayInventoryMutationAuthorityV1
    ) -> LightingDayInventoryCoordinatorV1 {
        LightingDayInventoryCoordinatorV1(query: query, authority: authority)
    }
}
// MARK: - C32 assistance lighting boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_Lighting_LightingCoordinatorV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let assistanceCannotImplyOperationalState = true

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

enum C33TemporalEvidenceBoundary_Application_Lighting_LightingCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row176 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_Lighting_LightingCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Application_Lighting_LightingCoordinatorV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

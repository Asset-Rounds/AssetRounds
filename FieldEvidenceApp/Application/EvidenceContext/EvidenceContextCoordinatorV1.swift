import Foundation

protocol EvidenceContextQueryingV1: Sendable {
    func latestContext(workspaceID: WorkspaceID, evidenceID: String) async throws -> EvidenceContextV1?
    func latestPair(workspaceID: WorkspaceID,
                    firstEvidenceID: String,
                    secondEvidenceID: String) async throws -> PairedObservationLinkV1?
}

enum EvidenceContextWriteOperationV1: Codable, Equatable, Sendable {
    case appendContext(value: EvidenceContextV1, predecessor: EvidenceContextV1?)
    case appendPair(value: PairedObservationLinkV1, predecessor: PairedObservationLinkV1?)

    var workspaceID: WorkspaceID {
        switch self {
        case .appendContext(let value, _): value.workspaceID
        case .appendPair(let value, _): value.workspaceID
        }
    }
    var mutationID: MutationIDV1 {
        switch self {
        case .appendContext(let value, _): value.mutationID
        case .appendPair(let value, _): value.mutationID
        }
    }
    func validate() throws {
        switch self {
        case .appendContext(let value, let predecessor):
            try value.validateIntrinsic()
            if let predecessor { try value.validateSuccessor(of: predecessor) }
            else if value.revision != 1 { throw EvidenceContextFailureV1.predecessorMismatch }
        case .appendPair(let value, let predecessor):
            try value.validateCompatiblePair()
            if let predecessor { try value.validateSuccessor(of: predecessor) }
            else if value.revision != 1 { throw EvidenceContextFailureV1.predecessorMismatch }
        }
    }
}

@MainActor
protocol EvidenceContextMutationAuthorityV1: AnyObject {
    func commit(_ operation: EvidenceContextWriteOperationV1) async throws -> MutationReceiptV1
}

struct EvidenceContextWriteReceiptV1: Codable, Equatable, Sendable {
    let operationSHA256: String
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let committedAt: Date

    init(operation: EvidenceContextWriteOperationV1,
         mutationReceipt: MutationReceiptV1) throws {
        try operation.validate(); try mutationReceipt.validate()
        guard mutationReceipt.identity.workspaceID == operation.workspaceID,
              mutationReceipt.mutationID == operation.mutationID else {
            throw EvidenceContextFailureV1.referenceMismatch
        }
        operationSHA256 = try EvidenceContextCanonicalCodecV1.sha256(operation)
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        committedAt = mutationReceipt.committedAt
    }
}

@MainActor
final class EvidenceContextCoordinatorV1 {
    private let query: any EvidenceContextQueryingV1
    private let authority: any EvidenceContextMutationAuthorityV1

    init(query: any EvidenceContextQueryingV1,
         authority: any EvidenceContextMutationAuthorityV1) {
        self.query = query; self.authority = authority
    }

    func append(_ value: EvidenceContextV1) async throws -> EvidenceContextWriteReceiptV1 {
        try value.validateIntrinsic()
        let predecessor = try await query.latestContext(workspaceID: value.workspaceID,
                                                         evidenceID: value.evidenceID)
        let operation = EvidenceContextWriteOperationV1.appendContext(
            value: value, predecessor: predecessor)
        try operation.validate()
        let receipt = try await authority.commit(operation)
        return try .init(operation: operation, mutationReceipt: receipt)
    }

    func append(_ value: PairedObservationLinkV1) async throws -> EvidenceContextWriteReceiptV1 {
        try value.validateCompatiblePair()
        let predecessor = try await query.latestPair(workspaceID: value.workspaceID,
            firstEvidenceID: value.first.evidenceID,
            secondEvidenceID: value.second.evidenceID)
        let operation = EvidenceContextWriteOperationV1.appendPair(
            value: value, predecessor: predecessor)
        try operation.validate()
        let receipt = try await authority.commit(operation)
        return try .init(operation: operation, mutationReceipt: receipt)
    }

    func mismatchPreview(first: PairedObservationReferenceV1,
                         second: PairedObservationReferenceV1)
        -> [PairedObservationMismatchReasonV1] {
        PairedObservationLinkV1.mismatches(first, second)
    }
}

enum C31LightingConsumerBoundary_Application_EvidenceContext_EvidenceContextCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/evidence-context-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}
// MARK: - C32 assistance evidence context boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_EvidenceContext_EvidenceContextCoordinatorV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let sourceReferenceRemainsNonCanonicalUntilAcceptance = true

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

enum C33TemporalEvidenceBoundary_Application_EvidenceContext_EvidenceContextCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row172 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_EvidenceContext_EvidenceContextCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Application_EvidenceContext_EvidenceContextCoordinatorV1_swift {
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

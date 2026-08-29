import Foundation

enum ScheduleLocalJobBoundaryV1 { static let derivedProjectionsAreRebuildable = true }

/// Narrow application boundary for the device-local operational job ledger.
///
/// The ledger is not canonical workspace truth. Callers enqueue work only
/// after its canonical intent exists and reconcile terminal jobs back to that
/// intent through the owning feature service.
protocol ResumableLocalJobPortV1: Sendable {
    @discardableResult
    func enqueue(_ job: ResumableLocalJobV1) async throws -> ResumableLocalJobV1
    func job(id: LocalJobIDV1) async throws -> ResumableLocalJobV1?
    func jobs(workspaceID: UUID?) async throws -> [ResumableLocalJobV1]
    @discardableResult
    func requestCancellation(id: LocalJobIDV1) async throws -> ResumableLocalJobV1
    func resumePending() async throws
    func removeTerminal(id: LocalJobIDV1) async throws
    func removeJobs(workspaceID: UUID) async throws
    func eraseAll() async throws
}

/// Exact durable phases for C45 output generation. Each phase is a bounded
/// cancellation boundary; the final phase means bytes are staged, not printed.
enum AssetLabelRenderCheckpointV1: Int, Codable, CaseIterable, Sendable {
    case validatedPlan = 1
    case renderedPDF = 2
    case renderedFormulaSafeCSV = 3
    case renderedStructuredText = 4
    case sealedManifest = 5

    static let totalUnitCount = 5
    var completedUnitCount: Int { rawValue }

    func localJobCheckpoint(
        jobID: LocalJobIDV1,
        rollingSHA256: String
    ) -> LocalJobCheckpointV1 {
        LocalJobCheckpointV1(
            nextChunkIndex: rawValue,
            completedUnitCount: rawValue,
            totalUnitCount: Self.totalUnitCount,
            lastChunkID: .deterministic(jobID: jobID, index: rawValue - 1),
            rollingOutputSHA256: rollingSHA256
        )
    }
}

enum AssetLabelRenderJobBoundaryV1 {
    static let kind: ResumableLocalJobKindV1 = .render
    static let publishesLocallyOrAdoptsExactManifest = true
    static let receiptClaimsPhysicalPrintOrDelivery = false
}

enum C33TemporalEvidenceJobBoundaryV1 { static let canonicalMediaCaptureIsResumableBackgroundWork=false;static let derivativeJobsMayBeRebuilt=true;static let immutableOriginalJobsMayOverwrite=false;static let canonicalMutationKind:WorkspaceCommandKindV1 = .applyTemporalEvidence }

/// Narrow C36 adapter for bounded attachment-processing work.  The request
/// and result are job metadata only; bytes remain owned by the draft staging
/// adapter and are never returned through this port.
protocol DraftAttachmentJobPortV1: Sendable {
    @discardableResult
    func enqueueDraftAttachment(
        _ request: DraftAttachmentJobRequestV1
    ) async throws -> ResumableLocalJobV1

    func draftAttachmentJob(
        workspaceID: WorkspaceID,
        stageID: UUID
    ) async throws -> ResumableLocalJobV1?
}

struct DraftAttachmentJobProgressV1: Codable, Equatable, Sendable {
    let stageID: UUID
    let state: LocalJobStateV1
    let completedUnitCount: Int
    let totalUnitCount: Int
    let retryClassification: LocalJobRetryClassificationV1?

    init(job: ResumableLocalJobV1, stageID: UUID) throws {
        guard job.kind == .draftAttachmentProcessing,
              job.workspaceID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                               0, 0, 0, 0, 0, 0, 0, 0)),
              stageID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                      0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw LocalJobValidationFailureV1.invalidContract
        }
        try job.validate()
        self.stageID = stageID
        state = job.state
        completedUnitCount = job.checkpoint.completedUnitCount
        totalUnitCount = job.checkpoint.totalUnitCount
        retryClassification = job.retryClassification
    }
}

enum LocalJobLifecycleSuspensionReasonV1: String, Equatable, Hashable, Sendable {
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case sceneBackground = "SCENE_BACKGROUND"
}

/// Provisional kernel boundary. Lifecycle suspension preserves durable
/// checkpoints, attempt-owned staging, and awaiting-publication uncertainty;
/// it is never equivalent to user cancellation.
protocol ResumableLocalJobLifecyclePortV1: Sendable {
    func suspendForLifecycle(
        _ reason: LocalJobLifecycleSuspensionReasonV1
    ) async throws
    func resumeAfterLifecycle(
        _ reason: LocalJobLifecycleSuspensionReasonV1
    ) async throws
}

enum ResumableLocalJobLifecycleHookPointV1: Equatable, Sendable {
    case beforeSuspensionPersistence
}

typealias ResumableLocalJobLifecycleHookV1 = @Sendable (
    LocalJobIDV1,
    ResumableLocalJobLifecycleHookPointV1
) async -> Void

/// A unit of resumable work. Implementations must check cancellation before
/// and after every checkpoint or output-publication boundary.
typealias ResumableLocalJobOperationV1 = @Sendable (
    ResumableLocalJobExecutionContextV1
) async throws -> ResumableLocalJobResultV1

/// Idempotent publication adapter contract. `publishOrAdopt` may perform the
/// one atomic effect or adopt an exact readback. `adoptOnly` must never create
/// an effect; it returns `.absent` when no exact readback exists.
typealias ResumableLocalJobPublisherV1 = @Sendable (
    ResumableLocalJobPublicationContextV1
) throws -> LocalJobPublicationOutcomeV1

/// Idempotent customer-data scratch cleanup invoked before a terminal job row
/// is recorded or removed. Throwing keeps the job recoverable/nonterminal.
typealias ResumableLocalJobTerminalCleanupV1 = @Sendable (
    ResumableLocalJobV1
) async throws -> Void

/// For a generation-bound job this wrapper is mandatory. It validates the
/// accepted/current epoch and retains publication authority across the entire
/// publisher atomic-effect plus readback closure.
typealias ResumableLocalJobPublicationAuthorityV1 = @Sendable (
    GenerationEpochV1,
    @escaping @Sendable () throws -> LocalJobPublicationOutcomeV1
) throws -> LocalJobPublicationOutcomeV1

enum GenerationLocalJobPublicationFailureV1: Error, Equatable, Sendable {
    case generationEpochRequired
    case staleGeneration
}

/// Generation publication adapter for the narrow atomic effect/readback
/// boundary. `withAuthorizedCommit` must hold the matching generation's
/// stale-writer commit authority for the complete synchronous closure.
struct GenerationLocalJobPublicationAdapterV1: Sendable {
    private let currentGenerationEpoch: @Sendable () throws -> GenerationEpochV1
    private let withAuthorizedCommit: ResumableLocalJobPublicationAuthorityV1

    init(
        currentGenerationEpoch: @escaping @Sendable () throws -> GenerationEpochV1,
        withAuthorizedCommit: @escaping ResumableLocalJobPublicationAuthorityV1
    ) {
        self.currentGenerationEpoch = currentGenerationEpoch
        self.withAuthorizedCommit = withAuthorizedCommit
    }

    func publish(
        job: ResumableLocalJobV1,
        effectAndReadback: @escaping @Sendable () throws -> LocalJobPublicationOutcomeV1
    ) throws -> LocalJobPublicationOutcomeV1 {
        guard let expectedEpoch = job.generationEpoch else {
            throw GenerationLocalJobPublicationFailureV1.generationEpochRequired
        }
        try expectedEpoch.validate()
        guard try currentGenerationEpoch() == expectedEpoch else {
            throw GenerationLocalJobPublicationFailureV1.staleGeneration
        }
        return try withAuthorizedCommit(expectedEpoch) {
            guard try currentGenerationEpoch() == expectedEpoch else {
                throw GenerationLocalJobPublicationFailureV1.staleGeneration
            }
            let outcome = try effectAndReadback()
            guard try currentGenerationEpoch() == expectedEpoch else {
                throw GenerationLocalJobPublicationFailureV1.staleGeneration
            }
            return outcome
        }
    }
}

struct ResumableLocalJobExecutionContextV1: Sendable {
    let job: ResumableLocalJobV1
    let checkpoint: @Sendable (LocalJobCheckpointV1) async throws -> Void
    let cancellationBoundary: @Sendable () async throws -> Void
    /// Source-compatible pre-staging validation boundary. This never grants
    /// escaped publication authority; only the registered publisher may do so.
    let publicationBoundary: @Sendable () async throws -> Void
    let validateGenerationLease: @Sendable () throws -> Void
}

struct ResumableLocalJobResultV1: Codable, Equatable, Sendable {
    let outputSHA256: String
    let completedUnitCount: Int

    init(outputSHA256: String, completedUnitCount: Int) {
        self.outputSHA256 = outputSHA256
        self.completedUnitCount = completedUnitCount
    }
}

struct ResumableLocalJobPublicationContextV1: Sendable {
    let job: ResumableLocalJobV1
    let pending: LocalJobPendingPublicationV1
    let mode: LocalJobPublicationModeV1
}

enum LocalJobPublicationOutcomeV1: Equatable, Sendable {
    case completed(LocalJobPublicationReceiptV1)
    case absent
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_Ports_ResumableLocalJobPortV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_Ports_ResumableLocalJobPortV1_swift {
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
enum C30ConsumerBoundaryV1_Application_Ports_ResumableLocalJobPortV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Ports/ResumableLocalJobPortV1.swift", role: .port)
}

enum C31LightingProjectionJobBoundaryV1 {
    static let rebuildIsDeterministicAndIdempotent = true
    static let incompleteProjectionIsNotAClaim = true
    static let originalEvidenceRemainsOutsideTheProjection = true
}
// MARK: - C32 assistance interruption recovery boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_Ports_ResumableLocalJobPortV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let interruptionRecoveryDoesNotPersistProposal = true

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

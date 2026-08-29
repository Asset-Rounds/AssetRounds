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

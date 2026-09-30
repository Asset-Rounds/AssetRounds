import Combine
import Foundation

enum MyDayPlanningEditingSessionFailureV1: Error, Equatable {
    case invalidLifecycle
    case changedEditingContext
    case saveAlreadyInFlight
    case staleCompletion
}

enum MyDayPlanningEditingFlushReasonV1: Equatable, Sendable {
    case automatic
    case navigation
    case background
    case handoff
    case promotion
    case share
    case save
}

typealias MyDayPlanningEditingSessionV1 = MyDayPlanningEditingSessionCoreV1<MyDayPlanningPlanSaveRequestV1>
typealias MyDayPlanningCarryoverEditingSessionV1 = MyDayPlanningEditingSessionCoreV1<MyDayPlanningCarryoverRequestV1>

/// One presentation-bound owner for a typed My Day planning edit.
///
/// The session deliberately keeps the prepared write, rather than just the
/// current form values, until the exact checkpoint and mutation receipt have
/// both been read back. A later edit can therefore never replace bytes whose
/// acknowledgement was interrupted.
@MainActor
final class MyDayPlanningEditingSessionCoreV1<Request: MyDayPlanningEditingRequestV1>: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private struct Pending: Equatable {
        let generation: UInt64
        let write: MyDayPlanningEditingWriteV1
    }

    private let access: AppAccessPresentationV1.MyDayAccess
    private let policy: DraftAutosavePolicyV1
    private let autosaveClock: any DraftAutosaveClockV1
    private let confirmedContext: MyDayPlanningConfirmedContextV1
    private let originalRequest: Request
    private let draftIDValue: UUID

    private var requestValue: Request
    private var resumeAnchorValue: DraftResumeAnchorV1
    private var pending: Pending?
    private var dirtyGeneration: UInt64
    private var durableGeneration: UInt64
    private var lifecycleGeneration: UInt64 = 1
    private var started = false
    private var invalidated = false
    private var commitInFlight = false
    private var requestedFlushReason: MyDayPlanningEditingFlushReasonV1?
    private var flushSequence: UInt64 = 0
    private var activeFlushSequence: UInt64?
    private var activeFlushTask: Task<Void, Error>?

    private(set) var checkpoint: FieldDraftCheckpointV1?
    private(set) var acknowledgement: MyDayPlanningCheckpointAcknowledgementV1?
    private(set) var commitOutcome: MyDayPlanningCommitOutcomeV1?
    private(set) var durabilityState: DraftDurabilityPresentationStateV1
    private(set) var lastFlushReason: MyDayPlanningEditingFlushReasonV1?

    var request: Request { requestValue }
    var resumeAnchor: DraftResumeAnchorV1 { resumeAnchorValue }
    var draftID: UUID { draftIDValue }
    var hasDirtyChanges: Bool { pending != nil || dirtyGeneration != durableGeneration }
    var isCommitInFlight: Bool { commitInFlight }

    #if DEBUG
    /// Runs after durable readback but before presentation publication. Tests
    /// use the suspension point to prove newer edits and revoked publications
    /// cannot be overwritten by an older completion.
    var afterAcknowledgementReadyForTesting:
        (@MainActor @Sendable (MyDayPlanningCheckpointAcknowledgementV1) async throws -> Void)?
    #endif

    private lazy var scheduler = DraftAutosaveSchedulerV1(
        policy: policy,
        clock: autosaveClock,
        flush: { [weak self] draftID in
            guard let self else { return }
            try await self.performSerializedFlush(draftID: draftID)
        }
    )

    init(
        request: Request,
        resumeAnchor: DraftResumeAnchorV1,
        access: AppAccessPresentationV1.MyDayAccess,
        policy: DraftAutosavePolicyV1,
        clock: any DraftAutosaveClockV1 = ContinuousDraftAutosaveClockV1()
    ) throws {
        try resumeAnchor.validate()
        let write = try access.preparePlanningEditingWrite(
            request,
            replacing: nil,
            resumeAnchor: resumeAnchor
        )
        self.access = access
        self.policy = policy
        autosaveClock = clock
        confirmedContext = request.confirmedContext
        originalRequest = request
        draftIDValue = write.checkpoint.draftID
        requestValue = request
        resumeAnchorValue = resumeAnchor
        pending = Pending(generation: 1, write: write)
        dirtyGeneration = 1
        durableGeneration = 0
        checkpoint = nil
        acknowledgement = nil
        commitOutcome = nil
        durabilityState = .unsavedChanges
        lastFlushReason = nil
    }

    convenience init(
        request: Request,
        resumeAnchor: DraftResumeAnchorV1,
        access: AppAccessPresentationV1.MyDayAccess,
        clock: any DraftAutosaveClockV1 = ContinuousDraftAutosaveClockV1()
    ) throws {
        try self.init(
            request: request,
            resumeAnchor: resumeAnchor,
            access: access,
            policy: DraftAutosavePolicyV1(),
            clock: clock
        )
    }

    init(
        resumingDraftID draftID: UUID,
        access: AppAccessPresentationV1.MyDayAccess,
        policy: DraftAutosavePolicyV1,
        clock: any DraftAutosaveClockV1 = ContinuousDraftAutosaveClockV1()
    ) throws {
        let durableCheckpoint = try access.loadPlanningCheckpoint(draftID: draftID)
        let durableAcknowledgement = try access.editingAcknowledgement(draftID: draftID)
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(durableCheckpoint)
        guard durableAcknowledgement.checkpoint == durableCheckpoint,
              payload.phase == .editing,
              let context = payload.confirmedContext,
              let intent = payload.editingIntent else {
            throw MyDayPlanningExecutionFailureV1.unsupportedState
        }
        let request = try Request(confirmedContext: context, editingIntent: intent)
        self.access = access
        self.policy = policy
        autosaveClock = clock
        confirmedContext = context
        originalRequest = request
        draftIDValue = durableCheckpoint.draftID
        requestValue = request
        resumeAnchorValue = durableCheckpoint.resumeAnchor
        pending = nil
        dirtyGeneration = 1
        durableGeneration = 1
        checkpoint = durableCheckpoint
        acknowledgement = durableAcknowledgement
        commitOutcome = nil
        durabilityState = .savedOnThisIPhone
        lastFlushReason = nil
    }

    convenience init(
        resumingDraftID draftID: UUID,
        access: AppAccessPresentationV1.MyDayAccess,
        clock: any DraftAutosaveClockV1 = ContinuousDraftAutosaveClockV1()
    ) throws {
        try self.init(
            resumingDraftID: draftID,
            access: access,
            policy: DraftAutosavePolicyV1(),
            clock: clock
        )
    }

    /// Begins the incumbent trailing/max-dirty autosave policy. Construction is
    /// effect-free so a destination can be prepared without creating a row.
    func start() async throws {
        try requireEditable()
        guard !started else { return }
        started = true
        if hasDirtyChanges {
            await scheduler.meaningfulEdit(draftID: draftID)
        }
    }

    func meaningfulEdit(
        _ request: Request,
        resumeAnchor: DraftResumeAnchorV1
    ) async throws {
        try requireEditable()
        try resumeAnchor.validate()
        guard request.confirmedContext == confirmedContext,
              request.matchesEditingBase(of: originalRequest),
              request.editingIntent.targetKey == confirmedContext.key else {
            throw MyDayPlanningEditingSessionFailureV1.changedEditingContext
        }

        let next = nextGeneration(after: dirtyGeneration)
        var prepared: MyDayPlanningEditingWriteV1?
        if pending == nil {
            guard let checkpoint else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            prepared = try access.preparePlanningEditingWrite(
                request,
                replacing: checkpoint,
                resumeAnchor: resumeAnchor
            )
        }

        objectWillChange.send()
        try access.withCurrentPresentation {
            guard !invalidated, !commitInFlight, commitOutcome == nil,
                  dirtyGeneration < next else {
                throw MyDayPlanningEditingSessionFailureV1.staleCompletion
            }
            requestValue = request
            resumeAnchorValue = resumeAnchor
            dirtyGeneration = next
            if let prepared { pending = Pending(generation: next, write: prepared) }
            durabilityState = .unsavedChanges
        }
        started = true
        await scheduler.meaningfulEdit(draftID: draftID)
    }

    func forceFlush(reason: MyDayPlanningEditingFlushReasonV1) async throws {
        try requireEditable()
        guard hasDirtyChanges else { return }
        started = true
        requestedFlushReason = reason
        await scheduler.meaningfulEdit(draftID: draftID)
        do {
            try await scheduler.forceFlush(draftID: draftID)
        } catch {
            if requestedFlushReason == reason { requestedFlushReason = nil }
            throw error
        }
        if requestedFlushReason == reason { requestedFlushReason = nil }
    }

    @discardableResult
    func save() async throws -> MyDayPlanningCommitOutcomeV1 {
        try requireEditable()
        try await forceFlush(reason: .save)
        let expectedLifecycle = lifecycleGeneration
        let expectedGeneration = dirtyGeneration

        objectWillChange.send()
        try access.withCurrentPresentation {
            guard !invalidated, !commitInFlight, commitOutcome == nil,
                  lifecycleGeneration == expectedLifecycle,
                  dirtyGeneration == expectedGeneration,
                  durableGeneration == expectedGeneration,
                  pending == nil else {
                throw MyDayPlanningEditingSessionFailureV1.staleCompletion
            }
            commitInFlight = true
            durabilityState = .committing
        }

        do {
            let outcome = try await access.retryPlanningCommit(draftID: draftID)
            objectWillChange.send()
            try access.withCurrentPresentation {
                guard !invalidated, commitInFlight, commitOutcome == nil,
                      lifecycleGeneration == expectedLifecycle,
                      dirtyGeneration == expectedGeneration,
                      durableGeneration == expectedGeneration,
                      pending == nil else {
                    throw MyDayPlanningEditingSessionFailureV1.staleCompletion
                }
                checkpoint = outcome.checkpoint
                commitOutcome = outcome
                commitInFlight = false
                durabilityState = .committed
            }
            await scheduler.cancel(draftID: draftID)
            return outcome
        } catch {
            objectWillChange.send()
            try? access.withCurrentPresentation {
                guard lifecycleGeneration == expectedLifecycle,
                      dirtyGeneration == expectedGeneration,
                      commitInFlight else { return }
                commitInFlight = false
                durabilityState = .saveBlocked
            }
            throw error
        }
    }

    func invalidate() async {
        guard !invalidated else { return }
        objectWillChange.send()
        invalidated = true
        lifecycleGeneration = nextGeneration(after: lifecycleGeneration)
        commitInFlight = false
        activeFlushTask?.cancel()
        await scheduler.cancel(draftID: draftID)
    }

    /// A timer that has already awakened can overlap a boundary force-flush.
    /// Both callers join one operation so an idempotent receipt replay cannot
    /// still produce a stale second presentation completion.
    private func performSerializedFlush(draftID: UUID) async throws {
        if let activeFlushTask {
            return try await activeFlushTask.value
        }
        flushSequence = nextGeneration(after: flushSequence)
        let sequence = flushSequence
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.flushPendingWrite(draftID: draftID)
        }
        activeFlushSequence = sequence
        activeFlushTask = task
        do {
            try await task.value
            if activeFlushSequence == sequence {
                activeFlushSequence = nil
                activeFlushTask = nil
            }
        } catch {
            if activeFlushSequence == sequence {
                activeFlushSequence = nil
                activeFlushTask = nil
            }
            throw error
        }
    }

    private func flushPendingWrite(draftID: UUID) async throws {
        guard !invalidated, commitOutcome == nil, self.draftID == draftID else {
            throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
        }
        let reason = requestedFlushReason ?? .automatic

        while true {
            if pending == nil, dirtyGeneration != durableGeneration {
                guard let predecessorCheckpoint = checkpoint else {
                    throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
                }
                let successorGeneration = dirtyGeneration
                let successorRequest = requestValue
                let successorAnchor = resumeAnchorValue
                do {
                    let successor = try access.preparePlanningEditingWrite(
                        successorRequest,
                        replacing: predecessorCheckpoint,
                        resumeAnchor: successorAnchor
                    )
                    objectWillChange.send()
                    try access.withCurrentPresentation {
                        guard !invalidated, pending == nil,
                              dirtyGeneration == successorGeneration,
                              checkpoint == predecessorCheckpoint else {
                            throw MyDayPlanningEditingSessionFailureV1.staleCompletion
                        }
                        pending = Pending(generation: successorGeneration, write: successor)
                        durabilityState = .unsavedChanges
                    }
                } catch {
                    objectWillChange.send()
                    try? access.withCurrentPresentation {
                        guard !invalidated, pending == nil,
                              dirtyGeneration == successorGeneration,
                              checkpoint == predecessorCheckpoint else { return }
                        durabilityState = .saveBlocked
                    }
                    throw error
                }
            }
            guard let candidate = pending else { return }
            let expectedLifecycle = lifecycleGeneration
            objectWillChange.send()
            try access.withCurrentPresentation {
                guard !invalidated, lifecycleGeneration == expectedLifecycle,
                      pending == candidate else {
                    throw MyDayPlanningEditingSessionFailureV1.staleCompletion
                }
                durabilityState = .savingOnThisIPhone
            }

            let durable: MyDayPlanningCheckpointAcknowledgementV1
            do {
                durable = try access.persistEditingWrite(candidate.write)
                #if DEBUG
                try await afterAcknowledgementReadyForTesting?(durable)
                #endif
            } catch {
                objectWillChange.send()
                try? access.withCurrentPresentation {
                    guard !invalidated, lifecycleGeneration == expectedLifecycle,
                          pending == candidate else { return }
                    durabilityState = .saveBlocked
                }
                throw error
            }

            objectWillChange.send()
            try access.withCurrentPresentation {
                guard !invalidated, lifecycleGeneration == expectedLifecycle,
                      pending == candidate,
                      durable.checkpoint == candidate.write.checkpoint else {
                    throw MyDayPlanningEditingSessionFailureV1.staleCompletion
                }
                acknowledgement = durable
                checkpoint = durable.checkpoint
                durableGeneration = candidate.generation
                pending = nil
                lastFlushReason = reason
                durabilityState = dirtyGeneration == durableGeneration
                    ? .savedOnThisIPhone : .unsavedChanges
            }

        }
    }

    private func requireEditable() throws {
        guard !invalidated, commitOutcome == nil else {
            throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
        }
        guard !commitInFlight else {
            throw MyDayPlanningEditingSessionFailureV1.saveAlreadyInFlight
        }
        try access.withCurrentPresentation {}
    }

    private func nextGeneration(after value: UInt64) -> UInt64 {
        let next = value.addingReportingOverflow(1)
        return next.overflow ? 1 : next.partialValue
    }
}

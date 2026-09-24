import Combine
import Foundation

enum CheckRunnerFieldFlushReasonV1: Equatable, Sendable {
    case begin, back, rootChange, leave, camera, photos, settings
    case keepOpen, deferItem, complete, sceneInactive, sceneBackground
    case photoPromotion, finalization, share
}

enum CheckRunnerItemEditingSessionFailureV1: Error, Equatable {
    case retired, changedCheckpoint, staleReadback, generationExhausted
}

@MainActor
fileprivate final class CheckRunnerFieldFlushOwnerV1 {}

/// Observational proof for exactly one acknowledged edit generation. The host
/// must validate it again at its actual transition boundary.
@MainActor
final class CheckRunnerFieldFlushReadbackV1 {
    let parent: CheckRunnerFieldReadbackV1
    fileprivate let owner: CheckRunnerFieldFlushOwnerV1
    fileprivate let generation: UInt64

    fileprivate init(parent: CheckRunnerFieldReadbackV1,
                     owner: CheckRunnerFieldFlushOwnerV1, generation: UInt64) {
        self.parent = parent
        self.owner = owner
        self.generation = generation
    }
}

/// A scene-owned RAM buffer, composed with the incumbent autosave scheduler.
/// Only the parent service writes. A frozen attempt survives failed or lost
/// acknowledgement, and must resolve before a newer buffer can be persisted.
@MainActor
final class CheckRunnerItemEditingSessionV1: @MainActor ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private struct Pending {
        let generation: UInt64
        let attempt: CheckRunnerFieldEditAttemptV1
    }

    private let service: ProductionCheckRunnerItemDraftServiceV1
    private let clock: any DraftAutosaveClockV1
    private let policy: DraftAutosavePolicyV1
    private let validateIntent: @MainActor () throws -> Void
    private let owner = CheckRunnerFieldFlushOwnerV1()
    private let draftID: UUID
    private var desiredGeneration: UInt64 = 0
    private var acknowledgedGeneration: UInt64 = 0
    private var pending: Pending?
    private var registration: Task<Void, Never>?
    private var flushTask: Task<Void, Error>?
    private var retired = false

    private(set) var values: CheckRunnerEditableItemValuesV1
    private(set) var acknowledgement: CheckRunnerFieldReadbackV1
    private(set) var durabilityState: DraftDurabilityPresentationStateV1 = .savedOnThisIPhone

    var hasUnacknowledgedEdits: Bool {
        pending != nil || desiredGeneration != acknowledgedGeneration
    }

    #if DEBUG
    var afterAcknowledgementReadyForTesting:
        (@MainActor @Sendable (CheckRunnerFieldReadbackV1) async throws -> Void)?

    func autosaveFailureStateForTesting() async -> DraftAutosaveFailureStateV1? {
        await scheduler.failureState(draftID: draftID)
    }
    #endif

    private lazy var scheduler = DraftAutosaveSchedulerV1(
        policy: policy, clock: clock,
        flush: { [weak self] draftID in
            guard let self else { throw CancellationError() }
            try await self.flushFromScheduler(draftID: draftID)
        }
    )

    init(service: ProductionCheckRunnerItemDraftServiceV1,
         initialRead: CheckRunnerFieldReadbackV1,
         clock: any DraftAutosaveClockV1 = ContinuousDraftAutosaveClockV1(),
         validateIntent: @escaping @MainActor () throws -> Void) throws {
        try validateIntent()
        try service.validateForPublication(initialRead)
        self.service = service
        self.clock = clock
        self.policy = try DraftAutosavePolicyV1()
        self.validateIntent = validateIntent
        self.draftID = initialRead.checkpoint.draftID
        self.values = initialRead.values
        self.acknowledgement = initialRead
    }

    func replaceEditableValues(_ next: CheckRunnerEditableItemValuesV1) throws {
        try requireCurrentIntent()
        guard next != values else { return }
        let increment = desiredGeneration.addingReportingOverflow(1)
        guard !increment.overflow else {
            throw CheckRunnerItemEditingSessionFailureV1.generationExhausted
        }
        objectWillChange.send()
        values = next
        desiredGeneration = increment.partialValue
        durabilityState = .unsavedChanges

        // Register in edit order even when UI callers do not await. Flush also
        // drains the buffer directly, so a pending registration cannot falsely
        // turn scheduler.forceFlush's no-dirty fast path into saved evidence.
        let previous = registration
        registration = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !self.retired else { return }
            await self.scheduler.meaningfulEdit(draftID: self.draftID)
        }
    }

    func forceFlushAndReadBack(reason: CheckRunnerFieldFlushReasonV1) async throws
        -> CheckRunnerFieldFlushReadbackV1 {
        try requireCurrentIntent()
        await registration?.value
        try requireCurrentIntent()
        try await scheduler.forceFlush(draftID: draftID)
        try requireCurrentIntent()
        // The scheduler may have seen an older dirty generation. Explicitly
        // authenticate the latest buffer after its suspension boundary.
        while true {
            try await performSerializedFlush()
            try requireCurrentIntent()
            guard !hasUnacknowledgedEdits else { continue }
            let proof = CheckRunnerFieldFlushReadbackV1(
                parent: acknowledgement, owner: owner, generation: desiredGeneration
            )
            try validateForPublication(proof)
            return proof
        }
    }

    func validateForPublication(_ read: CheckRunnerFieldFlushReadbackV1) throws {
        try requireCurrentIntent()
        guard read.owner === owner, read.generation == desiredGeneration,
              read.generation == acknowledgedGeneration, pending == nil,
              read.parent.checkpoint == acknowledgement.checkpoint,
              read.parent.receipt == acknowledgement.receipt, read.parent.values == values else {
            throw CheckRunnerItemEditingSessionFailureV1.staleReadback
        }
        try service.validateForPublication(read.parent)
    }

    /// Retirement stops automatic work, but never marks pending RAM edits saved.
    func retire() async {
        objectWillChange.send()
        retired = true
        await registration?.value
        await scheduler.cancel(draftID: draftID)
    }

    private func flushFromScheduler(draftID: UUID) async throws {
        guard draftID == self.draftID else {
            throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint
        }
        try await performSerializedFlush()
    }

    private func performSerializedFlush() async throws {
        try requireCurrentIntent()
        if let flushTask {
            try await flushTask.value
            try requireCurrentIntent()
            return
        }
        let task = Task { @MainActor in try await self.drain() }
        flushTask = task
        defer { flushTask = nil }
        do {
            try await task.value
            try requireCurrentIntent()
        } catch {
            objectWillChange.send()
            durabilityState = .saveBlocked
            throw error
        }
    }

    private func drain() async throws {
        while true {
            try requireCurrentIntent()
            if pending == nil {
                let current = try service.readEditableFields(draftID: draftID)
                guard current.checkpoint == acknowledgement.checkpoint else {
                    throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint
                }
                let generation = desiredGeneration
                let attempt = try service.prepareFieldEdit(
                    draftID: draftID,
                    expectedCheckpointSHA256: current.checkpoint.checkpointSHA256,
                    values: values, validateIntent: validateIntent
                )
                if let attempt {
                    pending = Pending(generation: generation, attempt: attempt)
                } else {
                    guard current.values == values else {
                        throw CheckRunnerItemEditingSessionFailureV1.staleReadback
                    }
                    try service.validateForPublication(current)
                    objectWillChange.send()
                    acknowledgement = current
                    acknowledgedGeneration = generation
                    durabilityState = .savedOnThisIPhone
                    return
                }
            }
            guard let frozen = pending else {
                throw CheckRunnerItemEditingSessionFailureV1.staleReadback
            }
            objectWillChange.send()
            durabilityState = .savingOnThisIPhone
            let read = try service.persistFieldEdit(frozen.attempt, validateIntent: validateIntent)
            #if DEBUG
            try await afterAcknowledgementReadyForTesting?(read)
            #endif
            try requireCurrentIntent()
            try service.validateForPublication(read)
            guard pending?.attempt === frozen.attempt else {
                throw CheckRunnerItemEditingSessionFailureV1.staleReadback
            }
            objectWillChange.send()
            acknowledgement = read
            acknowledgedGeneration = frozen.generation
            pending = nil
            durabilityState = hasUnacknowledgedEdits ? .unsavedChanges : .savedOnThisIPhone
            // Re-read even when apparently clean: this confirms exact current
            // row/receipt ownership, and drains any edit received during await.
        }
    }

    private func requireCurrentIntent() throws {
        try Task.checkCancellation()
        guard !retired else { throw CheckRunnerItemEditingSessionFailureV1.retired }
        try validateIntent()
    }
}

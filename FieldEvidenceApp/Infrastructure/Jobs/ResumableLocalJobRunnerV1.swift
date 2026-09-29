import Darwin
import Foundation

enum C52ServiceRequestLocalJobRunnerBoundaryV1 {
    static let mayReplayImmutableReceipt = true
    static let mayInventCanonicalServiceRequestEffect = false
    static let mayTransmitServiceRequest = false
}

enum ScheduleGenerationRunnerBoundaryV1 { static let retriesAreIdempotent = true }

enum C51ScheduleReconciliationRunnerBoundaryV1 {
    static let exactSourceFrontierIsRequired = true
    static let partialCompletionClaimAllowed = false
    static let reconciliationRemainsLocalOnly = true

    static func validate(
        job: ResumableLocalJobV1,
        input: C51ScheduleReconciliationJobInputV1
    ) throws {
        try C51ScheduleReconciliationJobBoundaryV1.validate(job: job, input: input)
    }
}

enum ResumableLocalJobRunnerFailureV1: Error, Equatable, Sendable {
    case operationNotRegistered
    case publisherNotRegistered
    case publicationAuthorityUnavailable
    case publicationAbsentWithoutCancellation
    case generationLeaseUnavailable
    case generationLeaseLost
    case invalidResult
    case unsafeStagingPath
    case stagingCleanupFailed
    case lifecycleGenerationExhausted
    case destructiveScopeBusy
}

private enum PendingLifecycleCancellationV1: Equatable, Sendable {
    case suspend(LocalJobLifecycleSuspensionReasonV1)
    /// The matching resume edge completed its durable readback while the old
    /// task was still unwinding. That task must queue its own attempt.
    case resumeAfterReadback
}

/// Bounded structured executor for durable local jobs.
///
/// The actor owns every child task, retains a reader generation lease for the
/// full duration of long reads, and serializes exactly one terminal store
/// transition per claimed attempt. Operations never run on the UI actor.
private final class LocalJobCleanupCheckedIOV1 {
    private var owned: [Int32] = []
    private(set) var uncertainDescriptors: [Int32] = []
    private(set) var uncertainDirectories: [UnsafeMutablePointer<DIR>] = []

    func retain(_ descriptor: Int32) {
        owned.append(descriptor)
    }

    func close(_ descriptor: Int32) throws {
        guard let index = owned.firstIndex(of: descriptor) else {
            throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
        }
        owned.remove(at: index)
        guard Darwin.close(descriptor) == 0 else {
            uncertainDescriptors.append(descriptor)
            throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
        }
    }

    func closeRemaining() throws {
        var failed = false
        for descriptor in Array(owned.reversed()) {
            do { try close(descriptor) } catch { failed = true }
        }
        guard !failed, uncertainDescriptors.isEmpty,
              uncertainDirectories.isEmpty else {
            throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
        }
    }

    /// A separate file description avoids `dup` sharing a consumed directory
    /// offset with the owner. A failed `closedir` is retained and never retried.
    func names(in parent: Int32) throws -> [String] {
        let descriptor = Darwin.openat(parent, ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
        }
        guard let directory = Darwin.fdopendir(descriptor) else {
            retain(descriptor)
            try close(descriptor)
            throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
        }
        var closeAttempted = false
        do {
            var names = [String]()
            errno = 0
            while let entry = Darwin.readdir(directory) {
                guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                    throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
                }
                if name != "." && name != ".." {
                    guard names.count
                        < JobScaleBudgetPolicyV1.maximumStagingCleanupEntryCount else {
                        throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
                    }
                    names.append(name)
                }
                errno = 0
            }
            guard errno == 0 else {
                throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
            }
            closeAttempted = true
            guard Darwin.closedir(directory) == 0 else {
                uncertainDirectories.append(directory)
                throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
            }
            return names.sorted()
        } catch {
            if !closeAttempted, Darwin.closedir(directory) != 0 {
                uncertainDirectories.append(directory)
            }
            throw error
        }
    }
}

actor ResumableLocalJobRunnerV1:
    ResumableLocalJobPortV1,
    ResumableLocalJobLifecyclePortV1,
    DraftAttachmentJobPortV1 {
    private let store: LocalJobStoreV1
    private let stagingRootURL: URL
    private let generationLeaseRegistry: GenerationLeaseRegistryV1?
    private var generationPublicationAdapter: GenerationLocalJobPublicationAdapterV1?
    private let lifecycleHook: ResumableLocalJobLifecycleHookV1
    private let maximumConcurrency: Int

    private var operations: [
        ResumableLocalJobKindV1: ResumableLocalJobOperationV1
    ] = [:]
    private var publishers: [
        ResumableLocalJobKindV1: ResumableLocalJobPublisherV1
    ] = [:]
    private var terminalCleanups: [
        ResumableLocalJobKindV1: ResumableLocalJobTerminalCleanupV1
    ] = [:]
    private var activeTasks: [LocalJobIDV1: Task<Void, Never>] = [:]
    private var suppressedPublicationRetries: Set<LocalJobIDV1> = []
    private var lifecycleSuspensions: Set<LocalJobLifecycleSuspensionReasonV1> = []
    private var lifecycleGenerations: [
        LocalJobLifecycleSuspensionReasonV1: UInt64
    ] = [:]
    private var exhaustedLifecycleGenerations: Set<
        LocalJobLifecycleSuspensionReasonV1
    > = []
    private var lifecycleCancellationReasons: [
        LocalJobIDV1: PendingLifecycleCancellationV1
    ] = [:]
    private var userCancellationRequests: Set<LocalJobIDV1> = []
    private var globalDestructiveGate = false
    private enum OriginalEraseFencePhase: Equatable {
        case settling(UUID)
        case observing(UUID)
        case draining(UUID)
        case storeEmpty(UUID)
        case rootRemoved(UUID)
        case retired(UUID)
        case uncertain(UUID)

        var operationID: UUID {
            switch self {
            case .settling(let id), .observing(let id), .draining(let id),
                 .storeEmpty(let id), .rootRemoved(let id),
                 .retired(let id), .uncertain(let id): return id
            }
        }
    }
    private var originalEraseFencePhase: OriginalEraseFencePhase?
    private var originalEraseNoRepairBaseline:
        LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1?
    private enum ColdEraseFencePhase: Equatable {
        case opening(UUID)
        case observing(UUID)
        case draining(UUID)
        case storeEmpty(UUID)
        case uncertain(UUID)

        var operationID: UUID {
            switch self {
            case .opening(let id), .observing(let id), .draining(let id),
                 .storeEmpty(let id), .uncertain(let id): return id
            }
        }
    }
    private var coldEraseFencePhase: ColdEraseFencePhase?
    private var coldEraseNoRepairBaseline:
        LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1?
    private var workspaceDestructiveGates: Set<UUID> = []
    private var globalMutationCount = 0
    private var workspaceMutationCounts: [UUID: Int] = [:]
    private var lastInfrastructureFailureCode: String?
    private var originalEraseCleanupUncertainIO: LocalJobCleanupCheckedIOV1?

    init(
        store: LocalJobStoreV1,
        stagingRootURL: URL,
        generationLeaseRegistry: GenerationLeaseRegistryV1? = nil,
        generationPublicationAdapter: GenerationLocalJobPublicationAdapterV1? = nil,
        maximumConcurrency: Int = JobScaleBudgetPolicyV1.maximumRunnerConcurrency,
        initialLifecycleGenerations: [
            LocalJobLifecycleSuspensionReasonV1: UInt64
        ] = [:],
        lifecycleHook: @escaping ResumableLocalJobLifecycleHookV1 = { _, _ in }
    ) throws {
        guard stagingRootURL.isFileURL,
              (1...JobScaleBudgetPolicyV1.maximumRunnerConcurrency)
                .contains(maximumConcurrency) else {
            throw LocalJobValidationFailureV1.invalidContract
        }
        self.store = store
        self.stagingRootURL = stagingRootURL.standardizedFileURL
        self.generationLeaseRegistry = generationLeaseRegistry
        self.generationPublicationAdapter = generationPublicationAdapter
        self.maximumConcurrency = maximumConcurrency
        lifecycleGenerations = initialLifecycleGenerations
        self.lifecycleHook = lifecycleHook
    }

    func register(
        _ kind: ResumableLocalJobKindV1,
        operation: @escaping ResumableLocalJobOperationV1
    ) {
        guard originalEraseFencePhase == nil, coldEraseFencePhase == nil else {
            rejectFencedRegistration()
            return
        }
        operations[kind] = operation
    }

    func unregister(_ kind: ResumableLocalJobKindV1) {
        guard coldEraseFencePhase == nil else {
            rejectFencedRegistration()
            return
        }
        operations.removeValue(forKey: kind)
    }

    func registerPublisher(
        _ kind: ResumableLocalJobKindV1,
        publisher: @escaping ResumableLocalJobPublisherV1
    ) {
        guard originalEraseFencePhase == nil, coldEraseFencePhase == nil else {
            rejectFencedRegistration()
            return
        }
        publishers[kind] = publisher
    }

    func unregisterPublisher(_ kind: ResumableLocalJobKindV1) {
        guard coldEraseFencePhase == nil else {
            rejectFencedRegistration()
            return
        }
        publishers.removeValue(forKey: kind)
    }

    func registerTerminalCleanup(
        _ kind: ResumableLocalJobKindV1,
        cleanup: @escaping ResumableLocalJobTerminalCleanupV1
    ) {
        guard originalEraseFencePhase == nil, coldEraseFencePhase == nil else {
            rejectFencedRegistration()
            return
        }
        terminalCleanups[kind] = cleanup
    }

    private func rejectFencedRegistration() {
        if let phase = originalEraseFencePhase {
            if case .retired = phase { return }
            originalEraseFencePhase = .uncertain(phase.operationID)
        }
        if let phase = coldEraseFencePhase {
            coldEraseFencePhase = .uncertain(phase.operationID)
        }
    }

    @discardableResult
    func enqueue(_ job: ResumableLocalJobV1) async throws -> ResumableLocalJobV1 {
        try beginMutation(workspaceID: job.workspaceID)
        defer { endMutation(workspaceID: job.workspaceID) }
        if job.generationEpoch != nil, generationPublicationAdapter == nil {
            throw ResumableLocalJobRunnerFailureV1
                .publicationAuthorityUnavailable
        }
        let stored = try await store.enqueue(job)
        try await scheduleAvailableWork()
        return stored
    }

    func job(id: LocalJobIDV1) async throws -> ResumableLocalJobV1? {
        try await store.job(id: id)
    }

    func jobs(workspaceID: UUID? = nil) async throws -> [ResumableLocalJobV1] {
        try await store.jobs(workspaceID: workspaceID)
    }

    @discardableResult
    func requestCancellation(id: LocalJobIDV1) async throws -> ResumableLocalJobV1 {
        guard let existing = try await store.job(id: id) else {
            throw LocalJobStoreFailureV1.jobNotFound
        }
        try beginMutation(workspaceID: existing.workspaceID)
        defer { endMutation(workspaceID: existing.workspaceID) }
        let requested = try await store.requestCancellation(id: id)
        suppressedPublicationRetries.remove(id)
        if let task = activeTasks[id] {
            userCancellationRequests.insert(id)
            task.cancel()
            return requested
        }
        if requested.state == .awaitingPublication {
            try await scheduleAvailableWork()
            return requested
        }
        try await performRegisteredTerminalCleanup(for: requested)
        try cleanupStaging(for: requested)
        return try await store.markCancelled(
            id: requested.id,
            expectedAttemptCount: requested.attemptCount
        )
    }

    func resumePending() async throws {
        try beginMutation(workspaceID: nil)
        defer { endMutation(workspaceID: nil) }
        try await store.resumePending()
        suppressedPublicationRetries.removeAll()
        let resumedJobs = try await store.jobs(workspaceID: nil)
        let interrupted = resumedJobs.filter {
            $0.state == .cancellationRequested
        }
        for job in interrupted {
            try await performRegisteredTerminalCleanup(for: job)
            try cleanupStaging(for: job)
            _ = try await store.markCancelled(
                id: job.id,
                expectedAttemptCount: job.attemptCount
            )
        }
        try await scheduleAvailableWork()
    }

    func removeTerminal(id: LocalJobIDV1) async throws {
        guard activeTasks[id] == nil else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        guard let job = try await store.job(id: id) else { return }
        try beginMutation(workspaceID: job.workspaceID)
        defer { endMutation(workspaceID: job.workspaceID) }
        try await performRegisteredTerminalCleanup(for: job)
        try cleanupStaging(for: job)
        try await store.removeTerminal(id: id)
    }

    func removeJobs(workspaceID: UUID) async throws {
        try beginDestructiveRemoval(workspaceID: workspaceID)
        defer { endDestructiveRemoval(workspaceID: workspaceID) }
        let scoped = try await store.jobs(workspaceID: workspaceID)
        for job in scoped where !job.state.isTerminal {
            _ = try await store.requestCancellation(id: job.id)
        }
        let tasks = scoped.compactMap { activeTasks[$0.id] }
        tasks.forEach { $0.cancel() }
        for task in tasks { await task.value }
        try await reconcileForDestructiveRemoval(workspaceID: workspaceID)
        let terminal = try await store.jobs(workspaceID: workspaceID)
        guard terminal.allSatisfy({ $0.state.isTerminal }) else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        for job in terminal {
            try await performRegisteredTerminalCleanup(for: job)
            try cleanupStaging(for: job)
        }
        try await store.removeJobs(workspaceID: workspaceID)
    }

    func eraseAll() async throws {
        try beginDestructiveRemoval(workspaceID: nil)
        defer { endDestructiveRemoval(workspaceID: nil) }
        try await eraseAllUnderDestructiveGate()
    }

    /// Closes new producer admission without changing C05 durable bytes or
    /// cancelling existing tasks. Waits for real producer tails before a
    /// read-only source/job witness can be frozen. Any uncertain tail leaves
    /// the exact owner fenced instead of reopening admission.
    func beginOriginalEraseObservationFence(
        _ operationID: UUID,
        expectedSupportIdentity: StoreApplicationSupportIdentity
    ) async throws {
        guard originalEraseFencePhase == nil else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        try beginDestructiveRemoval(workspaceID: nil)
        originalEraseFencePhase = .settling(operationID)
        let tasks = Array(activeTasks.values)
        for task in tasks { await task.value }
        guard originalEraseFencePhase == .settling(operationID),
              activeTasks.isEmpty,
              globalMutationCount == 0,
              workspaceMutationCounts.isEmpty,
              lastInfrastructureFailureCode == nil else {
            originalEraseFencePhase = .uncertain(operationID)
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        do {
            originalEraseNoRepairBaseline = try await store
                .beginOriginalEraseNoRepairObservation(
                    operationID: operationID,
                    expectedSupportIdentity: expectedSupportIdentity)
        } catch {
            originalEraseFencePhase = .uncertain(operationID)
            throw error
        }
        originalEraseFencePhase = .observing(operationID)
    }

    /// Only a proven no-effect abort may reopen the producer gate. A pending
    /// durable preparation or any drain attempt makes this transition stale.
    func releaseOriginalEraseObservationFence(_ operationID: UUID) async throws {
        guard originalEraseFencePhase == .observing(operationID),
              globalDestructiveGate,
              activeTasks.isEmpty,
              globalMutationCount == 0,
              workspaceMutationCounts.isEmpty else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        try await store.releaseOriginalEraseNoRepairObservation(
            operationID: operationID)
        originalEraseNoRepairBaseline = nil
        originalEraseFencePhase = nil
        endDestructiveRemoval(workspaceID: nil)
    }

    func requireOriginalEraseObservationFence(_ operationID: UUID) async throws
        -> LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1? {
        guard originalEraseFencePhase == .observing(operationID),
              globalDestructiveGate,
              activeTasks.isEmpty,
              globalMutationCount == 0,
              workspaceMutationCounts.isEmpty,
              lastInfrastructureFailureCode == nil else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        let observed = try await store.requireOriginalEraseNoRepairBaseline(
            operationID: operationID)
        guard observed == originalEraseNoRepairBaseline else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        return observed
    }

    /// The Router may call this only after genuine AppLock admission and the
    /// versioned pending preparation have become durable. No helper here can
    /// manufacture that authority from the UUID alone.
    func eraseAllForOriginalOperation(
        _ operationID: UUID,
        authority: OriginalC05PendingDrainAuthorityV1
    ) async throws {
        guard authority.operationID == operationID else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        guard try await requireOriginalEraseObservationFence(operationID) != nil else {
            // The proven absent-C05 path retains schema-2/no-effect abort.
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        originalEraseFencePhase = .draining(operationID)
        do {
            try await eraseAllUnderDestructiveGate()
            guard activeTasks.isEmpty,
                  lastInfrastructureFailureCode == nil,
                  try await store.jobs(workspaceID: nil).isEmpty else {
                throw ResumableLocalJobRunnerFailureV1.generationLeaseLost
            }
            originalEraseFencePhase = .storeEmpty(operationID)
        } catch {
            originalEraseFencePhase = .uncertain(operationID)
            throw error
        }
    }

    /// This is only the store-empty phase. Checked physical scratch-parent
    /// absence and durable witness publication are proved by Erase itself.
    func requireOriginalEraseStoreEmpty(_ operationID: UUID) async throws
        -> LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1 {
        guard originalEraseFencePhase == .storeEmpty(operationID),
              globalDestructiveGate,
              activeTasks.isEmpty,
              lastInfrastructureFailureCode == nil else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        let empty = try await store.requireOriginalEraseEmptySnapshot(
            operationID: operationID)
        guard originalEraseFencePhase == .storeEmpty(operationID),
              globalDestructiveGate,
              activeTasks.isEmpty,
              lastInfrastructureFailureCode == nil else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        return empty
    }

    /// The same retained producer remains fenced while the exact DRAINED
    /// record authorizes forward-only removal of its own empty C05 root.
    func removeOriginalEraseDrainedRoot(
        _ drain: EraseC05JobDrainV3,
        operationID: UUID
    ) async throws {
        guard originalEraseFencePhase == .storeEmpty(operationID),
              globalDestructiveGate,
              activeTasks.isEmpty,
              lastInfrastructureFailureCode == nil else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        do {
            try await store.removeOriginalEraseDrainedRoot(drain)
        } catch {
            originalEraseFencePhase = .uncertain(operationID)
            throw error
        }
        guard originalEraseFencePhase == .storeEmpty(operationID),
              globalDestructiveGate,
              activeTasks.isEmpty else {
            originalEraseFencePhase = .uncertain(operationID)
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        originalEraseFencePhase = .rootRemoved(operationID)
    }

    /// Terminally revoke every retained effect callback and the publication
    /// adapter's captured writer handle after the ROOT_REMOVED CAS. The global
    /// producer fence remains closed for this original actor's lifetime.
    func retireOriginalEraseEffects(_ operationID: UUID) throws {
        guard originalEraseFencePhase == .rootRemoved(operationID),
              globalDestructiveGate,
              activeTasks.isEmpty,
              globalMutationCount == 0,
              workspaceMutationCounts.isEmpty else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        originalEraseFencePhase = .retired(operationID)
        operations.removeAll()
        publishers.removeAll()
        terminalCleanups.removeAll()
        generationPublicationAdapter = nil
    }

    /// A cold relaunch has no original producer actor or callback authority.
    /// The actual startup operation retains this actor and its one store
    /// before the first no-repair read. The global gate never reopens here.
    func beginColdEraseObservationFence(
        operation: EraseColdPreparationOperationV1,
        pending: EraseC05JobDrainV3,
        expectedSupportIdentity: StoreApplicationSupportIdentity
    ) async throws -> LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1 {
        guard let generationLeaseRegistry else {
            throw ResumableLocalJobRunnerFailureV1.generationLeaseUnavailable
        }
        try await operation.requireC05ColdRunner(self, store: store,
            registry: generationLeaseRegistry)
        let operationID = try await operation.requireC05ColdPending(pending)
        try await operation.requireC05ColdPredecessorCheckedCompletion(
            registry: generationLeaseRegistry)
        guard originalEraseFencePhase == nil,
              coldEraseFencePhase == nil else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        try beginDestructiveRemoval(workspaceID: nil)
        coldEraseFencePhase = .opening(operationID)
        do {
            guard activeTasks.isEmpty,
                  globalMutationCount == 0,
                  workspaceMutationCounts.isEmpty,
                  lastInfrastructureFailureCode == nil else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            let observed = try await store.beginColdEraseNoRepairObservation(
                operation: operation, pending: pending,
                expectedSupportIdentity: expectedSupportIdentity)
            try await operation.requireC05ColdRunner(self, store: store,
                registry: generationLeaseRegistry)
            try await operation.requireC05ColdPredecessorCheckedCompletion(
                registry: generationLeaseRegistry)
            guard try await operation.requireC05ColdPending(pending)
                    == operationID,
                  coldEraseFencePhase == .opening(operationID),
                  globalDestructiveGate,
                  activeTasks.isEmpty,
                  globalMutationCount == 0,
                  workspaceMutationCounts.isEmpty,
                  lastInfrastructureFailureCode == nil else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            coldEraseNoRepairBaseline = observed
            coldEraseFencePhase = .observing(operationID)
            return observed
        } catch {
            coldEraseFencePhase = .uncertain(operationID)
            throw error
        }
    }

    /// This is the sole cold mutation entry. Before the first mutation it
    /// refuses awaiting-publication rows until a separate genuine cold
    /// adopt-only readback can be bound, and refuses jobs lacking the real
    /// terminal-cleanup callback from the reconstructed source workflow.
    func drainColdEraseAfterPendingPreparation(
        operation: EraseColdPreparationOperationV1,
        pending: EraseC05JobDrainV3
    ) async throws {
        guard let generationLeaseRegistry else {
            throw ResumableLocalJobRunnerFailureV1.generationLeaseUnavailable
        }
        try await operation.requireC05ColdRunner(self, store: store,
            registry: generationLeaseRegistry)
        let operationID = try await operation.requireC05ColdPending(pending)
        try await operation.requireC05ColdPredecessorCheckedCompletion(
            registry: generationLeaseRegistry)
        guard coldEraseFencePhase == .observing(operationID),
              globalDestructiveGate,
              activeTasks.isEmpty,
              globalMutationCount == 0,
              workspaceMutationCounts.isEmpty,
              lastInfrastructureFailureCode == nil,
              let coldEraseNoRepairBaseline else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        do {
            guard try await store.requireOriginalEraseNoRepairBaseline(
                operationID: operationID) == coldEraseNoRepairBaseline else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            let jobs = try await store.jobs(workspaceID: nil)
            for job in jobs {
                guard terminalCleanups[job.kind] != nil else {
                    throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
                }
                if job.state == .awaitingPublication {
                    throw ResumableLocalJobRunnerFailureV1
                        .publicationAuthorityUnavailable
                }
            }
            try await operation.requireC05ColdRunner(self, store: store,
                registry: generationLeaseRegistry)
            try await operation.requireC05ColdPredecessorCheckedCompletion(
                registry: generationLeaseRegistry)
            guard try await operation.requireC05ColdPending(pending)
                    == operationID,
                  coldEraseFencePhase == .observing(operationID),
                  globalDestructiveGate,
                  activeTasks.isEmpty,
                  globalMutationCount == 0,
                  workspaceMutationCounts.isEmpty,
                  lastInfrastructureFailureCode == nil else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            // This is the final actor hop before the first effect. The store
            // rechecks exact canonical bytes/rows and seals every generic
            // mutation; only operation-bound transitions can now write.
            try await store.beginColdEraseDrain(
                operationID: operationID,
                expected: coldEraseNoRepairBaseline,
                expectedJobs: jobs)
            coldEraseFencePhase = .draining(operationID)
            try await eraseAllUnderDestructiveGate(
                coldOperationID: operationID)
            guard coldEraseFencePhase == .draining(operationID),
                  globalDestructiveGate,
                  activeTasks.isEmpty,
                  globalMutationCount == 0,
                  workspaceMutationCounts.isEmpty,
                  lastInfrastructureFailureCode == nil,
                  try await store.jobs(workspaceID: nil).isEmpty else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            coldEraseFencePhase = .storeEmpty(operationID)
        } catch {
            coldEraseFencePhase = .uncertain(operationID)
            throw error
        }
    }

    func requireColdEraseStoreEmpty(
        operation: EraseColdPreparationOperationV1,
        pending: EraseC05JobDrainV3
    ) async throws -> LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1 {
        guard let generationLeaseRegistry else {
            throw ResumableLocalJobRunnerFailureV1.generationLeaseUnavailable
        }
        try await operation.requireC05ColdRunner(self, store: store,
            registry: generationLeaseRegistry)
        let operationID = try await operation.requireC05ColdPending(pending)
        guard coldEraseFencePhase == .storeEmpty(operationID),
              globalDestructiveGate, activeTasks.isEmpty,
              lastInfrastructureFailureCode == nil else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        let empty = try await store.requireOriginalEraseEmptySnapshot(
            operationID: operationID)
        guard coldEraseFencePhase == .storeEmpty(operationID),
              globalDestructiveGate, activeTasks.isEmpty,
              lastInfrastructureFailureCode == nil else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        return empty
    }

    private func eraseAllUnderDestructiveGate(
        coldOperationID: UUID? = nil
    ) async throws {
        let allJobs = try await store.jobs(workspaceID: nil)
        for job in allJobs where !job.state.isTerminal {
            if let coldOperationID {
                _ = try await store.requestCancellationForColdErase(
                    id: job.id, expected: job,
                    operationID: coldOperationID)
            } else {
                _ = try await store.requestCancellation(id: job.id)
            }
        }
        let tasks = Array(activeTasks.values)
        tasks.forEach { $0.cancel() }
        for task in tasks { await task.value }
        try await reconcileForDestructiveRemoval(
            workspaceID: nil, coldOperationID: coldOperationID)
        let terminal = try await store.jobs(workspaceID: nil)
        guard terminal.allSatisfy({ $0.state.isTerminal }) else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        for job in terminal {
            try await performRegisteredTerminalCleanup(for: job)
            try cleanupStaging(for: job)
        }
        if let coldOperationID {
            try await store.eraseAllForColdErase(operationID: coldOperationID)
        } else {
            try await store.eraseAll()
        }
    }

    func waitUntilIdle() async {
        while let task = activeTasks.values.first {
            await task.value
        }
    }

    func activeJobCount() -> Int {
        activeTasks.count
    }

    func infrastructureFailureCode() -> String? {
        lastInfrastructureFailureCode
    }

    func suspendForLifecycle(
        _ reason: LocalJobLifecycleSuspensionReasonV1
    ) async throws {
        lifecycleSuspensions.insert(reason)
        let currentGeneration = lifecycleGenerations[reason] ?? 0
        let generationExhausted = exhaustedLifecycleGenerations.contains(reason)
            || currentGeneration == UInt64.max
        if generationExhausted {
            exhaustedLifecycleGenerations.insert(reason)
        } else {
            lifecycleGenerations[reason] = currentGeneration + 1
        }
        let active = activeTasks
        for id in active.keys {
            if lifecycleCancellationReasons[id]
                != .suspend(.protectedDataUnavailable) {
                lifecycleCancellationReasons[id] = .suspend(reason)
            }
        }
        active.values.forEach { $0.cancel() }
        // Suspension itself is bounded. Durable RUNNING/checkpoint state is
        // already sufficient for termination recovery; owned tasks converge
        // when they next reach their mandatory cancellation boundary.
        if generationExhausted {
            throw ResumableLocalJobRunnerFailureV1.lifecycleGenerationExhausted
        }
    }

    func resumeAfterLifecycle(
        _ reason: LocalJobLifecycleSuspensionReasonV1
    ) async throws {
        try beginMutation(workspaceID: nil)
        defer { endMutation(workspaceID: nil) }
        guard !exhaustedLifecycleGenerations.contains(reason),
              lifecycleSuspensions.contains(reason),
              let expectedGeneration = lifecycleGenerations[reason] else {
            if exhaustedLifecycleGenerations.contains(reason) {
                throw ResumableLocalJobRunnerFailureV1
                    .lifecycleGenerationExhausted
            }
            return
        }
        let activeIDs = Set(activeTasks.keys)
        switch reason {
        case .protectedDataUnavailable:
            // This forces a descriptor-pinned disk reload before any blocked
            // job becomes eligible to run again.
            try await store.resumeAfterProtectedDataAvailable()
        case .sceneBackground:
            try await store.resumePending()
        }
        guard lifecycleGenerations[reason] == expectedGeneration,
              lifecycleSuspensions.contains(reason),
              !exhaustedLifecycleGenerations.contains(reason) else {
            // A newer observation won while readback was suspended. Any rows
            // safely requeued by the stale readback remain queued, but the
            // newer global suspension prevents their scheduling.
            return
        }
        // Readback requeued RUNNING rows, including active attempts. Their
        // task slot remains the successor-exclusion fence until unwind.
        for id in activeIDs {
            if lifecycleCancellationReasons[id] == .suspend(reason) {
                lifecycleCancellationReasons[id] = .resumeAfterReadback
            }
        }
        lifecycleSuspensions.remove(reason)
        suppressedPublicationRetries.removeAll()
        try await scheduleAvailableWork()
    }

    func isLifecycleSuspended(
        _ reason: LocalJobLifecycleSuspensionReasonV1
    ) -> Bool {
        lifecycleSuspensions.contains(reason)
    }

    func lifecycleGeneration(
        _ reason: LocalJobLifecycleSuspensionReasonV1
    ) -> UInt64? {
        lifecycleGenerations[reason]
    }

    func isDestructiveOperationGated(workspaceID: UUID?) -> Bool {
        if globalDestructiveGate { return true }
        guard let workspaceID else {
            return !workspaceDestructiveGates.isEmpty
        }
        return workspaceDestructiveGates.contains(workspaceID)
    }

    func retry(id: LocalJobIDV1) async throws {
        guard let existing = try await store.job(id: id) else {
            throw LocalJobStoreFailureV1.jobNotFound
        }
        try beginMutation(workspaceID: existing.workspaceID)
        defer { endMutation(workspaceID: existing.workspaceID) }
        suppressedPublicationRetries.remove(id)
        if existing.state != .awaitingPublication {
            _ = try await store.requeue(id: id)
        }
        try await scheduleAvailableWork()
    }
}

// MARK: - C36 attachment jobs

extension ResumableLocalJobRunnerV1 {
    @discardableResult
    func enqueueDraftAttachment(
        _ request: DraftAttachmentJobRequestV1
    ) async throws -> ResumableLocalJobV1 {
        try await enqueue(ResumableLocalJobV1.draftAttachmentProcessing(request))
    }

    func draftAttachmentJob(
        workspaceID: WorkspaceID,
        stageID: UUID
    ) async throws -> ResumableLocalJobV1? {
        let jobs = try await jobs(workspaceID: workspaceID.rawValue)
        return jobs.first {
            $0.kind == .draftAttachmentProcessing
                && $0.stagingRelativePath.contains(stageID.uuidString.lowercased())
        }
    }

    /// Registers a bounded processing operation without allowing callers to
    /// change the runner's global concurrency budget.
    func registerDraftAttachmentOperation(
        _ operation: @escaping ResumableLocalJobOperationV1
    ) {
        register(.draftAttachmentProcessing, operation: operation)
    }

    func registerDraftAttachmentPublisher(
        _ publisher: @escaping ResumableLocalJobPublisherV1
    ) {
        registerPublisher(.draftAttachmentProcessing, publisher: publisher)
    }
}

extension ResumableLocalJobRunnerV1 {
    func registerAssetLabelRenderOperation(
        _ operation: @escaping ResumableLocalJobOperationV1
    ) {
        register(.render, operation: operation)
    }

    func registerAssetLabelRenderPublisher(
        _ publisher: @escaping ResumableLocalJobPublisherV1
    ) {
        registerPublisher(.render, publisher: publisher)
    }
}

private extension ResumableLocalJobRunnerV1 {
    func beginMutation(workspaceID: UUID?) throws {
        guard !globalDestructiveGate else {
            throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
        }
        if let workspaceID {
            guard !workspaceDestructiveGates.contains(workspaceID) else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            let current = workspaceMutationCounts[workspaceID] ?? 0
            guard current < Int.max else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            workspaceMutationCounts[workspaceID] = current + 1
        } else {
            guard workspaceDestructiveGates.isEmpty,
                  globalMutationCount < Int.max else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            globalMutationCount += 1
        }
    }

    func endMutation(workspaceID: UUID?) {
        if let workspaceID {
            guard let current = workspaceMutationCounts[workspaceID] else {
                return
            }
            if current == 1 {
                workspaceMutationCounts.removeValue(forKey: workspaceID)
            } else {
                workspaceMutationCounts[workspaceID] = current - 1
            }
        } else if globalMutationCount > 0 {
            globalMutationCount -= 1
        }
    }

    func beginDestructiveRemoval(workspaceID: UUID?) throws {
        if let workspaceID {
            guard !globalDestructiveGate,
                  !workspaceDestructiveGates.contains(workspaceID),
                  globalMutationCount == 0,
                  workspaceMutationCounts[workspaceID] == nil else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            workspaceDestructiveGates.insert(workspaceID)
        } else {
            guard !globalDestructiveGate,
                  workspaceDestructiveGates.isEmpty,
                  globalMutationCount == 0,
                  workspaceMutationCounts.isEmpty else {
                throw ResumableLocalJobRunnerFailureV1.destructiveScopeBusy
            }
            globalDestructiveGate = true
        }
    }

    func endDestructiveRemoval(workspaceID: UUID?) {
        if let workspaceID {
            workspaceDestructiveGates.remove(workspaceID)
        } else if originalEraseFencePhase == nil,
                  coldEraseFencePhase == nil {
            globalDestructiveGate = false
        }
    }

    func isDestructivelyGated(workspaceID: UUID) -> Bool {
        globalDestructiveGate
            || workspaceDestructiveGates.contains(workspaceID)
    }

    func reconcileForDestructiveRemoval(
        workspaceID: UUID?, coldOperationID: UUID? = nil
    ) async throws {
        let pending = try await store.jobs(workspaceID: workspaceID)
        for job in pending where job.state == .cancellationRequested {
            try cleanupStaging(for: job)
            if let coldOperationID {
                _ = try await store.markCancelledForColdErase(
                    id: job.id, expected: job,
                    expectedAttemptCount: job.attemptCount,
                    operationID: coldOperationID)
            } else {
                _ = try await store.markCancelled(
                    id: job.id,
                    expectedAttemptCount: job.attemptCount)
            }
        }
        let afterCancellation = try await store.jobs(workspaceID: workspaceID)
        let awaiting = afterCancellation.filter {
            $0.state == .awaitingPublication
        }
        for job in awaiting {
            guard coldOperationID == nil else {
                throw ResumableLocalJobRunnerFailureV1
                    .publicationAuthorityUnavailable
            }
            // requestCancellation persistently selected adopt-only. A failed
            // or ambiguous readback leaves the row intact and blocks removal.
            await reconcilePublication(job, ownsTaskSlot: false)
        }
    }

    func scheduleAvailableWork() async throws {
        guard lifecycleSuspensions.isEmpty else { return }
        guard !globalDestructiveGate else { return }
        guard activeTasks.count < maximumConcurrency else { return }
        let storedJobs = try await store.jobs(workspaceID: nil)
        let candidates = storedJobs.filter {
            ($0.state == .queued || $0.state == .awaitingPublication)
                && activeTasks[$0.id] == nil
                && !suppressedPublicationRetries.contains($0.id)
                && !isDestructivelyGated(workspaceID: $0.workspaceID)
        }
        for candidate in candidates.prefix(maximumConcurrency - activeTasks.count) {
            guard !isDestructivelyGated(workspaceID: candidate.workspaceID) else {
                continue
            }
            let isQueued = candidate.state == .queued
            let scheduled: ResumableLocalJobV1
            let operation: ResumableLocalJobOperationV1?
            if isQueued {
                try beginMutation(workspaceID: candidate.workspaceID)
                do {
                    scheduled = try await store.claimForExecution(id: candidate.id)
                    endMutation(workspaceID: candidate.workspaceID)
                } catch {
                    endMutation(workspaceID: candidate.workspaceID)
                    throw error
                }
                operation = operations[scheduled.kind]
            } else {
                scheduled = candidate
                operation = nil
            }
            let task: Task<Void, Never> = Task { [weak self] in
                guard let self else { return }
                if isQueued {
                    await self.execute(scheduled, operation: operation)
                } else {
                    await self.reconcilePublication(scheduled)
                }
            }
            activeTasks[scheduled.id] = task
        }
    }

    func execute(
        _ job: ResumableLocalJobV1,
        operation: ResumableLocalJobOperationV1?
    ) async {
        let attempt = job.attemptCount
        var leaseHandle: GenerationLeaseHandleV1?
        var awaitingPublication: ResumableLocalJobV1?
        var operationFailure: Error?
        do {
            if let epoch = job.generationEpoch {
                guard let generationLeaseRegistry else {
                    throw ResumableLocalJobRunnerFailureV1.generationLeaseUnavailable
                }
                leaseHandle = try generationLeaseRegistry.acquireHandle(
                    epoch: epoch,
                    role: .reader
                )
            }
            guard let operation else {
                throw ResumableLocalJobRunnerFailureV1.operationNotRegistered
            }
            let registry = generationLeaseRegistry
            let token = leaseHandle?.token
            let boundary: @Sendable () async throws -> Void = { [store] in
                try Task.checkCancellation()
                if (try await store.job(id: job.id))?.state
                    == .cancellationRequested {
                    throw CancellationError()
                }
                if let registry, let token {
                    try registry.validateActive(token, requiredRole: .reader)
                }
            }
            let context = ResumableLocalJobExecutionContextV1(
                job: job,
                checkpoint: { [store] checkpoint in
                    try Task.checkCancellation()
                    if let registry, let token {
                        try registry.validateActive(token, requiredRole: .reader)
                    }
                    _ = try await store.saveCheckpoint(
                        id: job.id,
                        expectedAttemptCount: attempt,
                        checkpoint: checkpoint
                    )
                    try Task.checkCancellation()
                },
                cancellationBoundary: boundary,
                publicationBoundary: boundary,
                validateGenerationLease: {
                    if let registry, let token {
                        try registry.validateActive(token, requiredRole: .reader)
                    }
                }
            )
            try await context.cancellationBoundary()
            let result = try await operation(context)
            // Operation output remains attempt-owned staging. Persisting this
            // boundary precedes every escaped publication attempt.
            try context.validateGenerationLease()
            guard ResumableLocalJobV1.isSHA256(result.outputSHA256),
                  result.completedUnitCount == job.checkpoint.totalUnitCount else {
                throw ResumableLocalJobRunnerFailureV1.invalidResult
            }
            awaitingPublication = try await store.markAwaitingPublication(
                id: job.id,
                expectedAttemptCount: attempt,
                result: result
            )
        } catch {
            operationFailure = error
        }

        // There is exactly one close invocation for every acquired handle.
        // A release failure is surfaced as the job failure when no earlier
        // operation failure exists, and otherwise retained as runner evidence.
        if let leaseHandle, awaitingPublication == nil {
            do {
                try leaseHandle.close()
            } catch {
                lastInfrastructureFailureCode = "generation_lease_release_failed"
                if operationFailure == nil, awaitingPublication == nil {
                    operationFailure = ResumableLocalJobRunnerFailureV1
                        .generationLeaseLost
                }
            }
        }

        if let awaitingPublication {
            await reconcilePublication(
                awaitingPublication,
                retainedLeaseHandle: leaseHandle,
                ownsTaskSlot: true
            )
            return
        } else if operationFailure is CancellationError,
                  userCancellationRequests.remove(job.id) != nil {
            do {
                try await performRegisteredTerminalCleanup(for: job)
                try cleanupStaging(for: job)
                _ = try await store.markCancelled(
                    id: job.id,
                    expectedAttemptCount: attempt
                )
            } catch {
                await recordTerminalFailure(
                    job: job,
                    attempt: attempt,
                    classification: .retryable,
                    code: "staging_cleanup_failed"
                )
            }
        } else if operationFailure is CancellationError,
                  let lifecycleCancellation = lifecycleCancellationReasons.removeValue(
                      forKey: job.id
                  ) {
            do {
                await lifecycleHook(
                    job.id,
                    .beforeSuspensionPersistence
                )
                switch lifecycleCancellation {
                case .suspend(let lifecycleReason):
                    _ = try await store.markLifecycleSuspended(
                        id: job.id,
                        expectedAttemptCount: attempt,
                        reason: lifecycleReason
                    )
                case .resumeAfterReadback:
                    _ = try await store.markLifecycleRecoveryQueued(
                        id: job.id,
                        expectedAttemptCount: attempt
                    )
                }
            } catch let failure as LocalJobStoreFailureV1
                where failure == .protectedDataUnavailable {
                // The already-durable RUNNING checkpoint remains recovery
                // authority while protected files cannot be opened.
                lastInfrastructureFailureCode = "protected_data_unavailable"
            } catch let failure as LocalJobStoreFailureV1
                where failure == .staleJob {
                do {
                    let converged = try await store.job(id: job.id)
                    if converged?.attemptCount != attempt
                        || converged?.state != .queued {
                        lastInfrastructureFailureCode = normalizedCode(failure)
                    }
                    // Matching readback already queued this exact attempt.
                    // The old suspension write is an expected idempotent no-op.
                } catch {
                    lastInfrastructureFailureCode = normalizedCode(error)
                }
            } catch {
                lastInfrastructureFailureCode = normalizedCode(error)
            }
        } else if operationFailure is CancellationError {
            do {
                try await performRegisteredTerminalCleanup(for: job)
                try cleanupStaging(for: job)
                _ = try await store.markCancelled(
                    id: job.id,
                    expectedAttemptCount: attempt
                )
            } catch {
                await recordTerminalFailure(
                    job: job,
                    attempt: attempt,
                    classification: .retryable,
                    code: "staging_cleanup_failed"
                )
            }
        } else if let operationFailure {
            let mapped = classify(operationFailure)
            if mapped.classification == .protectedDataUnavailable {
                do {
                    _ = try await store.markLifecycleSuspended(
                        id: job.id,
                        expectedAttemptCount: attempt,
                        reason: .protectedDataUnavailable
                    )
                } catch let failure as LocalJobStoreFailureV1
                    where failure == .protectedDataUnavailable {
                    // Durable RUNNING plus its last checkpoint is the relaunch
                    // recovery state when the store itself is locked.
                    lastInfrastructureFailureCode = mapped.code
                } catch {
                    lastInfrastructureFailureCode = normalizedCode(error)
                }
            } else {
                await recordTerminalFailure(
                    job: job,
                    attempt: attempt,
                    classification: mapped.classification,
                    code: mapped.code
                )
            }
        } else {
            await recordTerminalFailure(
                job: job,
                attempt: attempt,
                classification: .permanent,
                code: "missing_operation_result"
            )
        }
        lifecycleCancellationReasons.removeValue(forKey: job.id)
        userCancellationRequests.remove(job.id)
        activeTasks.removeValue(forKey: job.id)
        do { try await scheduleAvailableWork() }
        catch { lastInfrastructureFailureCode = normalizedCode(error) }
    }

    func reconcilePublication(
        _ scheduledJob: ResumableLocalJobV1,
        retainedLeaseHandle: GenerationLeaseHandleV1? = nil,
        ownsTaskSlot: Bool = true
    ) async {
        var leaseHandle = retainedLeaseHandle
        var completedTerminalTransition = false
        do {
            guard let current = try await store.job(id: scheduledJob.id),
                  current.state == .awaitingPublication,
                  let pending = current.pendingPublication else {
                throw LocalJobStoreFailureV1.staleJob
            }
            guard let publisher = publishers[current.kind] else {
                throw ResumableLocalJobRunnerFailureV1.publisherNotRegistered
            }
            if let epoch = current.generationEpoch, leaseHandle == nil {
                guard let generationLeaseRegistry else {
                    throw ResumableLocalJobRunnerFailureV1
                        .generationLeaseUnavailable
                }
                leaseHandle = try generationLeaseRegistry.acquireHandle(
                    epoch: epoch,
                    role: .reader
                )
            }
            if let leaseHandle, let generationLeaseRegistry {
                try generationLeaseRegistry.validateActive(
                    leaseHandle.token,
                    requiredRole: .reader
                )
            }
            let mode: LocalJobPublicationModeV1 = pending.cancellationRequested
                ? .adoptOnly
                : .publishOrAdopt
            let context = ResumableLocalJobPublicationContextV1(
                job: current,
                pending: pending,
                mode: mode
            )
            try Task.checkCancellation()
            guard lifecycleSuspensions.isEmpty else {
                throw CancellationError()
            }
            let invoke: @Sendable () throws -> LocalJobPublicationOutcomeV1 = {
                try publisher(context)
            }
            let outcome: LocalJobPublicationOutcomeV1
            if current.generationEpoch != nil {
                guard let generationPublicationAdapter else {
                    throw ResumableLocalJobRunnerFailureV1
                        .publicationAuthorityUnavailable
                }
                // No suspension is permitted from the authority entry until
                // the atomic effect and exact readback have both completed.
                outcome = try generationPublicationAdapter.publish(
                    job: current,
                    effectAndReadback: invoke
                )
            } else {
                outcome = try invoke()
            }
            switch outcome {
            case .completed(let receipt):
                // Publication/adoption readback is already complete. Remove
                // attempt scratch before recording SUCCEEDED so no terminal
                // job can strand customer-data output. If interruption lands
                // here, the awaiting-publication replay adopts the exact
                // external effect and retries this cleanup.
                try await performRegisteredTerminalCleanup(for: current)
                try cleanupStaging(for: current)
                _ = try await store.markPublicationSucceeded(
                    id: current.id,
                    expectedAttemptCount: current.attemptCount,
                    receipt: receipt
                )
                completedTerminalTransition = true
            case .absent:
                guard mode == .adoptOnly else {
                    throw ResumableLocalJobRunnerFailureV1
                        .publicationAbsentWithoutCancellation
                }
                // Cleanup is proved before the durable CANCELLED transition.
                try await performRegisteredTerminalCleanup(for: current)
                try cleanupStaging(for: current)
                _ = try await store.markPublicationAbsentAndCancelled(
                    id: current.id,
                    expectedAttemptCount: current.attemptCount
                )
                completedTerminalTransition = true
            }
        } catch {
            // Awaiting publication is intentionally nonterminal. Relaunch or
            // retry re-invokes the idempotent adapter and adopts exact readback.
            lastInfrastructureFailureCode = normalizedCode(error)
            if error is CancellationError {
                let userRequested = userCancellationRequests.remove(
                    scheduledJob.id
                ) != nil
                let lifecycleResumed = lifecycleCancellationReasons[
                    scheduledJob.id
                ] == .resumeAfterReadback
                if userRequested || lifecycleResumed {
                    suppressedPublicationRetries.remove(scheduledJob.id)
                } else {
                    suppressedPublicationRetries.insert(scheduledJob.id)
                }
            } else {
                suppressedPublicationRetries.insert(scheduledJob.id)
            }
        }
        if let leaseHandle {
            do { try leaseHandle.close() }
            catch {
                // Publication outcome/readback remains authoritative. Lease
                // release failure is operational evidence, never a false job
                // failure after an effect may have escaped.
                lastInfrastructureFailureCode = "generation_lease_release_failed"
            }
        }
        if completedTerminalTransition {
            suppressedPublicationRetries.remove(scheduledJob.id)
        }
        lifecycleCancellationReasons.removeValue(forKey: scheduledJob.id)
        if ownsTaskSlot {
            activeTasks.removeValue(forKey: scheduledJob.id)
            do { try await scheduleAvailableWork() }
            catch { recordInfrastructureFailure(error) }
        }
    }

    func recordInfrastructureFailure(_ error: Error) {
        lastInfrastructureFailureCode = normalizedCode(error)
    }

    func recordTerminalFailure(
        job: ResumableLocalJobV1,
        attempt: Int,
        classification: LocalJobRetryClassificationV1,
        code: String
    ) async {
        do {
            try await performRegisteredTerminalCleanup(for: job)
            try cleanupStaging(for: job)
        } catch {
            // Keep the durable RUNNING/checkpoint row as relaunch authority.
            // A terminal FAILED row must never coexist with undeleted
            // customer-data scratch.
            lastInfrastructureFailureCode = "staging_cleanup_failed"
            return
        }
        do {
            _ = try await store.markFailed(
                id: job.id,
                expectedAttemptCount: attempt,
                classification: classification,
                failureCode: code
            )
        } catch {
            lastInfrastructureFailureCode = normalizedCode(error)
        }
    }

    func performRegisteredTerminalCleanup(
        for job: ResumableLocalJobV1
    ) async throws {
        if let cleanup = terminalCleanups[job.kind] {
            try await cleanup(job)
        }
    }

    func classify(_ error: Error) -> (
        classification: LocalJobRetryClassificationV1,
        code: String
    ) {
        if let failure = error as? GenerationLeaseRegistryFailureV1 {
            switch failure {
            case .protectedDataUnavailable:
                return (.protectedDataUnavailable, "protected_data_unavailable")
            default:
                return (.generationLeaseLost, "generation_lease_lost")
            }
        }
        if let failure = error as? LocalJobStoreFailureV1,
           failure == .protectedDataUnavailable {
            return (.protectedDataUnavailable, "protected_data_unavailable")
        }
        if let failure = error as? ResumableLocalJobRunnerFailureV1 {
            switch failure {
            case .operationNotRegistered:
                return (.permanent, "operation_not_registered")
            case .publisherNotRegistered:
                return (.permanent, "publisher_not_registered")
            case .publicationAuthorityUnavailable:
                return (.generationLeaseLost, "publication_authority_unavailable")
            case .publicationAbsentWithoutCancellation:
                return (.retryable, "publication_readback_absent")
            case .generationLeaseUnavailable, .generationLeaseLost:
                return (.generationLeaseLost, "generation_lease_lost")
            case .invalidResult:
                return (.permanent, "invalid_result")
            case .unsafeStagingPath, .stagingCleanupFailed:
                return (.retryable, "staging_cleanup_failed")
            case .lifecycleGenerationExhausted:
                return (.permanent, "lifecycle_generation_exhausted")
            case .destructiveScopeBusy:
                return (.retryable, "destructive_scope_busy")
            }
        }
        return (.retryable, "operation_failed")
    }

    func normalizedCode(_ error: Error) -> String {
        if let failure = error as? LocalJobStoreFailureV1 {
            return "local_job_store_\(String(describing: failure))"
                .lowercased()
        }
        if let failure = error as? ResumableLocalJobRunnerFailureV1 {
            return "local_job_runner_\(String(describing: failure))"
                .lowercased()
        }
        return "local_job_infrastructure_failure"
    }

    func cleanupStaging(for job: ResumableLocalJobV1) throws {
        guard originalEraseCleanupUncertainIO == nil else {
            throw cleanupFailure()
        }
        let io = LocalJobCleanupCheckedIOV1()
        var operationFailure: Error?
        do {
            try cleanupStagingBody(for: job, io: io)
        } catch {
            operationFailure = error
        }
        do {
            try io.closeRemaining()
        } catch {
            originalEraseCleanupUncertainIO = io
            throw error
        }
        if let operationFailure { throw operationFailure }
    }

    private func cleanupStagingBody(
        for job: ResumableLocalJobV1,
        io: LocalJobCleanupCheckedIOV1
    ) throws {
        let components = job.stagingRelativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.isEmpty,
              components.count <= JobScaleBudgetPolicyV1.maximumStagingPathDepth,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
                      && !$0.contains("\\")
              }) else {
            throw ResumableLocalJobRunnerFailureV1.unsafeStagingPath
        }
        let rootDescriptor = Darwin.open(
            stagingRootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if rootDescriptor < 0, errno == ENOENT { return }
        guard rootDescriptor >= 0 else { throw cleanupFailure() }
        io.retain(rootDescriptor)
        var opened = [OpenedCleanupDirectory(
            descriptor: rootDescriptor,
            parentDescriptor: nil,
            name: nil,
            identity: try cleanupIdentity(rootDescriptor, directory: true)
        )]

        for component in components.dropLast() {
            let parent = opened[opened.count - 1].descriptor
            let descriptor = Darwin.openat(
                parent,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if descriptor < 0, errno == ENOENT { return }
            guard descriptor >= 0 else { throw cleanupFailure() }
            io.retain(descriptor)
            do {
                let identity = try cleanupIdentity(descriptor, directory: true)
                guard try cleanupNamedIdentity(parent, component)
                        .hasSameStableIdentity(as: identity) else {
                    throw cleanupFailure()
                }
                opened.append(OpenedCleanupDirectory(
                    descriptor: descriptor,
                    parentDescriptor: parent,
                    name: component,
                    identity: identity
                ))
            } catch {
                throw error
            }
        }

        let parent = opened[opened.count - 1].descriptor
        guard let leafName = components.last else { throw cleanupFailure() }
        let quarantineName = ".cleanup-"
            + job.id.rawValue.uuidString.lowercased()
        let leafExists = try cleanupEntryExists(parent, leafName)
        let quarantineExists = try cleanupEntryExists(parent, quarantineName)
        guard !(leafExists && quarantineExists) else { throw cleanupFailure() }
        if leafExists {
            let leafDescriptor = Darwin.openat(
                parent,
                leafName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard leafDescriptor >= 0 else { throw cleanupFailure() }
            io.retain(leafDescriptor)
            let leafIdentity: CleanupIdentity
            do {
                leafIdentity = try cleanupIdentity(
                    leafDescriptor,
                    directory: true
                )
                guard try cleanupNamedIdentity(parent, leafName)
                        .hasSameStableIdentity(as: leafIdentity) else {
                    throw cleanupFailure()
                }
            } catch {
                throw error
            }
            guard Darwin.renameat(
                parent,
                leafName,
                parent,
                quarantineName
            ) == 0 else {
                throw cleanupFailure()
            }
            guard Darwin.fsync(parent) == 0,
                  try cleanupNamedIdentity(parent, quarantineName)
                    .hasSameStableIdentity(as: leafIdentity),
                  try cleanupIdentity(leafDescriptor, directory: true)
                    .hasSameStableIdentity(as: leafIdentity) else {
                throw cleanupFailure()
            }
            try io.close(leafDescriptor)
        } else if !quarantineExists {
            return
        }

        var quarantineDescriptor = Darwin.openat(
            parent,
            quarantineName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard quarantineDescriptor >= 0 else { throw cleanupFailure() }
        io.retain(quarantineDescriptor)
        let quarantineIdentity = try cleanupIdentity(
            quarantineDescriptor,
            directory: true
        )
        guard try cleanupNamedIdentity(parent, quarantineName)
                .hasSameStableIdentity(as: quarantineIdentity) else {
            throw cleanupFailure()
        }
        var removedEntryCount = 0
        do {
            try removeCleanupContents(
                descriptor: quarantineDescriptor,
                depth: 0,
                removedEntryCount: &removedEntryCount,
                io: io
            )
            guard try cleanupIdentity(quarantineDescriptor, directory: true)
                    .hasSameStableIdentity(as: quarantineIdentity),
                  try cleanupNamedIdentity(parent, quarantineName)
                    .hasSameStableIdentity(as: quarantineIdentity) else {
                throw cleanupFailure()
            }
        } catch {
            throw error
        }
        try io.close(quarantineDescriptor)
        quarantineDescriptor = -1
        guard Darwin.unlinkat(parent, quarantineName, AT_REMOVEDIR) == 0,
              Darwin.fsync(parent) == 0 else {
            throw cleanupFailure()
        }
        // The quarantined cleanup root is no longer named after unlinkat.
        // Only still-linked staging ancestors are revalidated below.
        for directory in opened {
            guard try cleanupIdentity(directory.descriptor, directory: true)
                    .hasSameStableIdentity(as: directory.identity) else {
                throw cleanupFailure()
            }
            if let parentDescriptor = directory.parentDescriptor,
               let name = directory.name {
                guard try cleanupNamedIdentity(parentDescriptor, name)
                        .hasSameStableIdentity(as: directory.identity) else {
                    throw cleanupFailure()
                }
            }
        }
    }

    struct CleanupIdentity {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
        let kind: mode_t

        func hasSameStableIdentity(as other: CleanupIdentity) -> Bool {
            device == other.device
                && inode == other.inode
                && kind == other.kind
        }
    }

    struct OpenedCleanupDirectory {
        let descriptor: Int32
        let parentDescriptor: Int32?
        let name: String?
        let identity: CleanupIdentity
    }

    private func removeCleanupContents(
        descriptor: Int32,
        depth: Int,
        removedEntryCount: inout Int,
        io: LocalJobCleanupCheckedIOV1
    ) throws {
        guard depth < JobScaleBudgetPolicyV1.maximumStagingPathDepth else {
            throw cleanupFailure()
        }
        let names = try io.names(in: descriptor)
        for name in names {
            guard removedEntryCount
                    < JobScaleBudgetPolicyV1.maximumStagingCleanupEntryCount else {
                throw cleanupFailure()
            }
            removedEntryCount += 1
            let identity = try cleanupNamedIdentity(descriptor, name)
            if identity.kind == mode_t(S_IFDIR) {
                let child = Darwin.openat(
                    descriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else { throw cleanupFailure() }
                io.retain(child)
                do {
                    guard try cleanupIdentity(child, directory: true)
                            .hasSameStableIdentity(as: identity),
                          try cleanupNamedIdentity(descriptor, name)
                            .hasSameStableIdentity(as: identity) else {
                        throw cleanupFailure()
                    }
                    try removeCleanupContents(
                        descriptor: child,
                        depth: depth + 1,
                        removedEntryCount: &removedEntryCount,
                        io: io
                    )
                    guard try cleanupIdentity(child, directory: true)
                            .hasSameStableIdentity(as: identity),
                          try cleanupNamedIdentity(descriptor, name)
                            .hasSameStableIdentity(as: identity) else {
                        throw cleanupFailure()
                    }
                } catch {
                    throw error
                }
                try io.close(child)
                guard Darwin.unlinkat(descriptor, name, AT_REMOVEDIR) == 0 else {
                    throw cleanupFailure()
                }
            } else if identity.kind == mode_t(S_IFREG) {
                guard identity.linkCount == 1 else { throw cleanupFailure() }
                let file = Darwin.openat(descriptor, name, O_RDONLY | O_NOFOLLOW)
                guard file >= 0 else { throw cleanupFailure() }
                io.retain(file)
                let pinned = try cleanupIdentity(file, directory: false)
                try io.close(file)
                guard pinned.hasSameStableIdentity(as: identity),
                      pinned.linkCount == 1,
                      identity.linkCount == 1,
                      try cleanupNamedIdentity(descriptor, name)
                        .hasSameStableIdentity(as: identity),
                      Darwin.unlinkat(descriptor, name, 0) == 0 else {
                    throw cleanupFailure()
                }
            } else if identity.kind == mode_t(S_IFLNK) {
                guard try cleanupNamedIdentity(descriptor, name)
                        .hasSameStableIdentity(as: identity),
                      Darwin.unlinkat(descriptor, name, 0) == 0 else {
                    throw cleanupFailure()
                }
            } else {
                throw cleanupFailure()
            }
        }
        guard Darwin.fsync(descriptor) == 0 else { throw cleanupFailure() }
    }

    func cleanupIdentity(
        _ descriptor: Int32,
        directory: Bool
    ) throws -> CleanupIdentity {
        var information = stat()
        let expected = directory ? mode_t(S_IFDIR) : mode_t(S_IFREG)
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == expected,
              directory || information.st_nlink == 1 else {
            throw cleanupFailure()
        }
        return CleanupIdentity(
            device: information.st_dev,
            inode: information.st_ino,
            linkCount: information.st_nlink,
            kind: information.st_mode & S_IFMT
        )
    }

    func cleanupNamedIdentity(
        _ parentDescriptor: Int32,
        _ name: String
    ) throws -> CleanupIdentity {
        var information = stat()
        guard Darwin.fstatat(
            parentDescriptor,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            throw cleanupFailure()
        }
        return CleanupIdentity(
            device: information.st_dev,
            inode: information.st_ino,
            linkCount: information.st_nlink,
            kind: information.st_mode & S_IFMT
        )
    }

    func cleanupEntryExists(_ parentDescriptor: Int32, _ name: String) throws -> Bool {
        var information = stat()
        if Darwin.fstatat(
            parentDescriptor,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            return true
        }
        if errno == ENOENT { return false }
        throw cleanupFailure()
    }

    func cleanupFailure() -> ResumableLocalJobRunnerFailureV1 {
        .stagingCleanupFailed
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Jobs_ResumableLocalJobRunnerV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Jobs_ResumableLocalJobRunnerV1_swift {
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
enum C30ConsumerBoundaryV1_Infrastructure_Jobs_ResumableLocalJobRunnerV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobRunnerV1.swift", role: .job)
}

enum C31LightingConsumerBoundary_Infrastructure_Jobs_ResumableLocalJobRunnerV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/resumable-local-job-runner"
    static let compatibility = C31LightingCompatibilityPolicyV1()

    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Jobs_ResumableLocalJobRunnerV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Jobs_ResumableLocalJobRunnerV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Jobs_ResumableLocalJobRunnerV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

enum C34SceneRestorationJobRunnerBoundaryV1 {
    static let dispatchesJob = false
    static let resumesLifecycleJob = false
    static func validate(anchor: DraftResumeAnchorV1) -> Bool { !dispatchesJob && !resumesLifecycleJob && C34SceneRestorationJobPortBoundaryV1.validate(anchor: anchor) }
}

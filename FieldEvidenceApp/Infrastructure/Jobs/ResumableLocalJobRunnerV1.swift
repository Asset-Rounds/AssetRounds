import Darwin
import Foundation

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
}

/// Bounded structured executor for durable local jobs.
///
/// The actor owns every child task, retains a reader generation lease for the
/// full duration of long reads, and serializes exactly one terminal store
/// transition per claimed attempt. Operations never run on the UI actor.
actor ResumableLocalJobRunnerV1: ResumableLocalJobPortV1 {
    private let store: LocalJobStoreV1
    private let stagingRootURL: URL
    private let generationLeaseRegistry: GenerationLeaseRegistryV1?
    private let generationPublicationAdapter: GenerationLocalJobPublicationAdapterV1?
    private let maximumConcurrency: Int

    private var operations: [
        ResumableLocalJobKindV1: ResumableLocalJobOperationV1
    ] = [:]
    private var publishers: [
        ResumableLocalJobKindV1: ResumableLocalJobPublisherV1
    ] = [:]
    private var activeTasks: [LocalJobIDV1: Task<Void, Never>] = [:]
    private var suppressedPublicationRetries: Set<LocalJobIDV1> = []
    private var lastInfrastructureFailureCode: String?

    init(
        store: LocalJobStoreV1,
        stagingRootURL: URL,
        generationLeaseRegistry: GenerationLeaseRegistryV1? = nil,
        generationPublicationAdapter: GenerationLocalJobPublicationAdapterV1? = nil,
        maximumConcurrency: Int = JobScaleBudgetPolicyV1.maximumRunnerConcurrency
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
    }

    func register(
        _ kind: ResumableLocalJobKindV1,
        operation: @escaping ResumableLocalJobOperationV1
    ) {
        operations[kind] = operation
    }

    func unregister(_ kind: ResumableLocalJobKindV1) {
        operations.removeValue(forKey: kind)
    }

    func registerPublisher(
        _ kind: ResumableLocalJobKindV1,
        publisher: @escaping ResumableLocalJobPublisherV1
    ) {
        publishers[kind] = publisher
    }

    func unregisterPublisher(_ kind: ResumableLocalJobKindV1) {
        publishers.removeValue(forKey: kind)
    }

    @discardableResult
    func enqueue(_ job: ResumableLocalJobV1) async throws -> ResumableLocalJobV1 {
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
        let requested = try await store.requestCancellation(id: id)
        suppressedPublicationRetries.remove(id)
        if let task = activeTasks[id] {
            task.cancel()
            return requested
        }
        if requested.state == .awaitingPublication {
            try await scheduleAvailableWork()
            return requested
        }
        try cleanupStaging(for: requested)
        return try await store.markCancelled(
            id: requested.id,
            expectedAttemptCount: requested.attemptCount
        )
    }

    func resumePending() async throws {
        try await store.resumePending()
        suppressedPublicationRetries.removeAll()
        let resumedJobs = try await store.jobs(workspaceID: nil)
        let interrupted = resumedJobs.filter {
            $0.state == .cancellationRequested
        }
        for job in interrupted {
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
        if let job = try await store.job(id: id) {
            try cleanupStaging(for: job)
        }
        try await store.removeTerminal(id: id)
    }

    func removeJobs(workspaceID: UUID) async throws {
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
            try cleanupStaging(for: job)
        }
        try await store.removeJobs(workspaceID: workspaceID)
    }

    func eraseAll() async throws {
        let allJobs = try await store.jobs(workspaceID: nil)
        for job in allJobs where !job.state.isTerminal {
            _ = try await store.requestCancellation(id: job.id)
        }
        let tasks = Array(activeTasks.values)
        tasks.forEach { $0.cancel() }
        for task in tasks { await task.value }
        try await reconcileForDestructiveRemoval(workspaceID: nil)
        let terminal = try await store.jobs(workspaceID: nil)
        guard terminal.allSatisfy({ $0.state.isTerminal }) else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        for job in terminal {
            try cleanupStaging(for: job)
        }
        try await store.eraseAll()
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

    func retry(id: LocalJobIDV1) async throws {
        suppressedPublicationRetries.remove(id)
        if (try await store.job(id: id))?.state != .awaitingPublication {
            _ = try await store.requeue(id: id)
        }
        try await scheduleAvailableWork()
    }
}

private extension ResumableLocalJobRunnerV1 {
    func reconcileForDestructiveRemoval(workspaceID: UUID?) async throws {
        let pending = try await store.jobs(workspaceID: workspaceID)
        for job in pending where job.state == .cancellationRequested {
            try cleanupStaging(for: job)
            _ = try await store.markCancelled(
                id: job.id,
                expectedAttemptCount: job.attemptCount
            )
        }
        let afterCancellation = try await store.jobs(workspaceID: workspaceID)
        let awaiting = afterCancellation.filter {
            $0.state == .awaitingPublication
        }
        for job in awaiting {
            // requestCancellation persistently selected adopt-only. A failed
            // or ambiguous readback leaves the row intact and blocks removal.
            await reconcilePublication(job, ownsTaskSlot: false)
        }
    }

    func scheduleAvailableWork() async throws {
        guard activeTasks.count < maximumConcurrency else { return }
        let storedJobs = try await store.jobs(workspaceID: nil)
        let candidates = storedJobs.filter {
            ($0.state == .queued || $0.state == .awaitingPublication)
                && activeTasks[$0.id] == nil
                && !suppressedPublicationRetries.contains($0.id)
        }
        for candidate in candidates.prefix(maximumConcurrency - activeTasks.count) {
            let isQueued = candidate.state == .queued
            let scheduled: ResumableLocalJobV1
            let operation: ResumableLocalJobOperationV1?
            if isQueued {
                scheduled = try await store.claimForExecution(id: candidate.id)
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
        } else if operationFailure is CancellationError {
            do {
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
            await recordTerminalFailure(
                job: job,
                attempt: attempt,
                classification: mapped.classification,
                code: mapped.code
            )
        } else {
            await recordTerminalFailure(
                job: job,
                attempt: attempt,
                classification: .permanent,
                code: "missing_operation_result"
            )
        }
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
                _ = try await store.markPublicationSucceeded(
                    id: current.id,
                    expectedAttemptCount: current.attemptCount,
                    receipt: receipt
                )
                completedTerminalTransition = true
                do { try cleanupStaging(for: current) }
                catch {
                    lastInfrastructureFailureCode = "staging_cleanup_failed"
                }
            case .absent:
                guard mode == .adoptOnly else {
                    throw ResumableLocalJobRunnerFailureV1
                        .publicationAbsentWithoutCancellation
                }
                // Cleanup is proved before the durable CANCELLED transition.
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
            suppressedPublicationRetries.insert(scheduledJob.id)
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
        var finalClassification = classification
        var finalCode = code
        do { try cleanupStaging(for: job) }
        catch {
            finalClassification = .retryable
            finalCode = "staging_cleanup_failed"
        }
        do {
            _ = try await store.markFailed(
                id: job.id,
                expectedAttemptCount: attempt,
                classification: finalClassification,
                failureCode: finalCode
            )
        } catch {
            lastInfrastructureFailureCode = normalizedCode(error)
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
        var opened = [OpenedCleanupDirectory(
            descriptor: rootDescriptor,
            parentDescriptor: nil,
            name: nil,
            identity: try cleanupIdentity(rootDescriptor, directory: true)
        )]
        defer { opened.reversed().forEach { _ = Darwin.close($0.descriptor) } }

        for component in components.dropLast() {
            let parent = opened[opened.count - 1].descriptor
            let descriptor = Darwin.openat(
                parent,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if descriptor < 0, errno == ENOENT { return }
            guard descriptor >= 0 else { throw cleanupFailure() }
            do {
                let identity = try cleanupIdentity(descriptor, directory: true)
                guard try cleanupNamedIdentity(parent, component)
                        .hasSameStableIdentity(as: identity) else {
                    _ = Darwin.close(descriptor)
                    throw cleanupFailure()
                }
                opened.append(OpenedCleanupDirectory(
                    descriptor: descriptor,
                    parentDescriptor: parent,
                    name: component,
                    identity: identity
                ))
            } catch {
                _ = Darwin.close(descriptor)
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
                _ = Darwin.close(leafDescriptor)
                throw error
            }
            guard Darwin.renameat(
                parent,
                leafName,
                parent,
                quarantineName
            ) == 0 else {
                _ = Darwin.close(leafDescriptor)
                throw cleanupFailure()
            }
            guard Darwin.fsync(parent) == 0,
                  try cleanupNamedIdentity(parent, quarantineName)
                    .hasSameStableIdentity(as: leafIdentity),
                  try cleanupIdentity(leafDescriptor, directory: true)
                    .hasSameStableIdentity(as: leafIdentity) else {
                _ = Darwin.close(leafDescriptor)
                throw cleanupFailure()
            }
            guard Darwin.close(leafDescriptor) == 0 else {
                throw cleanupFailure()
            }
        } else if !quarantineExists {
            return
        }

        var quarantineDescriptor = Darwin.openat(
            parent,
            quarantineName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard quarantineDescriptor >= 0 else { throw cleanupFailure() }
        let quarantineIdentity = try cleanupIdentity(
            quarantineDescriptor,
            directory: true
        )
        guard try cleanupNamedIdentity(parent, quarantineName)
                .hasSameStableIdentity(as: quarantineIdentity) else {
            _ = Darwin.close(quarantineDescriptor)
            throw cleanupFailure()
        }
        var removedEntryCount = 0
        do {
            try removeCleanupContents(
                descriptor: quarantineDescriptor,
                depth: 0,
                removedEntryCount: &removedEntryCount
            )
            guard try cleanupIdentity(quarantineDescriptor, directory: true)
                    .hasSameStableIdentity(as: quarantineIdentity),
                  try cleanupNamedIdentity(parent, quarantineName)
                    .hasSameStableIdentity(as: quarantineIdentity) else {
                throw cleanupFailure()
            }
        } catch {
            _ = Darwin.close(quarantineDescriptor)
            quarantineDescriptor = -1
            throw error
        }
        guard Darwin.close(quarantineDescriptor) == 0 else {
            throw cleanupFailure()
        }
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

    func removeCleanupContents(
        descriptor: Int32,
        depth: Int,
        removedEntryCount: inout Int
    ) throws {
        guard depth < JobScaleBudgetPolicyV1.maximumStagingPathDepth else {
            throw cleanupFailure()
        }
        let names = try cleanupNames(descriptor)
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
                        removedEntryCount: &removedEntryCount
                    )
                    guard try cleanupIdentity(child, directory: true)
                            .hasSameStableIdentity(as: identity),
                          try cleanupNamedIdentity(descriptor, name)
                            .hasSameStableIdentity(as: identity) else {
                        throw cleanupFailure()
                    }
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                guard Darwin.close(child) == 0,
                      Darwin.unlinkat(descriptor, name, AT_REMOVEDIR) == 0 else {
                    throw cleanupFailure()
                }
            } else if identity.kind == mode_t(S_IFREG) {
                guard identity.linkCount == 1 else { throw cleanupFailure() }
                let file = Darwin.openat(descriptor, name, O_RDONLY | O_NOFOLLOW)
                guard file >= 0 else { throw cleanupFailure() }
                let pinned = try cleanupIdentity(file, directory: false)
                let closeResult = Darwin.close(file)
                guard pinned.hasSameStableIdentity(as: identity),
                      pinned.linkCount == 1,
                      identity.linkCount == 1,
                      closeResult == 0,
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

    func cleanupNames(_ descriptor: Int32) throws -> [String] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 { _ = Darwin.close(duplicate) }
            throw cleanupFailure()
        }
        defer { _ = Darwin.closedir(directory) }
        var names = [String]()
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." {
                guard names.count
                        < JobScaleBudgetPolicyV1.maximumStagingCleanupEntryCount else {
                    throw cleanupFailure()
                }
                names.append(name)
            }
            errno = 0
        }
        guard errno == 0 else { throw cleanupFailure() }
        return names.sorted()
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

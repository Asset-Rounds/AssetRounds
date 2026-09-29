import Darwin
import Foundation

actor LocalJobStoreV1: ResumableLocalJobPortV1, DraftAttachmentJobPortV1 {
    private let rootURL: URL
    private let storeURL: URL
    private let receiptURL: URL
    private let quarantineURL: URL
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let fileManager: FileManager
    private let protectedDataFailureHook: LocalJobStoreProtectedDataFailureHookV1

    private var envelope: LocalJobStoreEnvelopeV1?
    private var receipt: LocalJobStoreMigrationReceiptV1?
    struct OriginalEraseNoRepairSnapshotV1: Equatable, Sendable {
        let rootDevice: UInt64
        let rootInode: UInt64
        let envelopeBytes: Data
        let receiptBytes: Data

        func authenticatedJobs() throws -> [ResumableLocalJobV1] {
            let envelope = try LocalJobStoreV1.makeDecoder().decode(
                LocalJobStoreEnvelopeV1.self, from: envelopeBytes)
            try envelope.validate()
            guard try LocalJobStoreV1.makeEncoder().encode(envelope)
                    == envelopeBytes else {
                throw LocalJobStoreFailureV1.corruptStore
            }
            return envelope.jobs
        }
    }
    private var originalEraseNoRepairOperationID: UUID?
    private var originalEraseExpectedSupportIdentity:
        StoreApplicationSupportIdentity?
    private var originalEraseNoRepairBaseline: OriginalEraseNoRepairSnapshotV1?
    private var coldEraseDrainOperationID: UUID?
    private var coldEraseDrainStarted = false
    private var coldEraseMutationPermitted = false
    private var coldEraseDrainUncertain = false
    private var coldEraseExpectedEnvelopeBytes: Data?
    private var coldEraseExpectedRows: [ResumableLocalJobV1]?
    private var originalEraseUncertainDescriptors: [Int32] = []
    private var originalEraseUncertainStreams: [UnsafeMutablePointer<DIR>] = []
    private var coldEraseWriteOwners: [ColdEraseCheckedWriteOwnerV1] = []

    /// A relaunch enters through the already durable C05 PENDING preparation,
    /// never through `ensureLoaded`'s create/migrate/quarantine branch. This
    /// observation installs the existing no-repair mode before any Runner may
    /// ask for jobs. It is not a drain or lease-release witness.
    func beginColdEraseNoRepairObservation(
        operation: EraseColdPreparationOperationV1,
        pending: EraseC05JobDrainV3,
        expectedSupportIdentity: StoreApplicationSupportIdentity
    ) async throws -> OriginalEraseNoRepairSnapshotV1 {
        let operationID = try await operation.requireC05ColdPending(pending)
        try await operation.requireC05ColdJobStore(self)
        try pending.validate()
        guard pending.phase == .pending,
              originalEraseNoRepairOperationID == nil,
              UInt64(expectedSupportIdentity.device) == pending.supportDevice,
              UInt64(expectedSupportIdentity.inode) == pending.supportInode,
              let observed = try readOriginalEraseNoRepairSnapshot(
                expectedSupportIdentity: expectedSupportIdentity),
              observed.rootDevice == pending.sourceStoreDevice,
              observed.rootInode == pending.sourceStoreInode,
              observed.receiptBytes == pending.sourceReceiptBytes else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        let source = try Self.makeDecoder().decode(
            LocalJobStoreEnvelopeV1.self, from: pending.sourceEnvelopeBytes)
        try source.validate()
        guard try Self.makeEncoder().encode(source)
                == pending.sourceEnvelopeBytes else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        let sourceByID = Dictionary(uniqueKeysWithValues:
            source.jobs.map { ($0.id, $0) })
        for current in try observed.authenticatedJobs() {
            guard let original = sourceByID[current.id],
                  current.schemaVersion == original.schemaVersion,
                  current.workspaceID == original.workspaceID,
                  current.kind == original.kind,
                  current.immutableInputSHA256 == original.immutableInputSHA256,
                  current.stagingRelativePath == original.stagingRelativePath,
                  current.generationEpoch == original.generationEpoch,
                  current.createdAt == original.createdAt else {
                throw LocalJobStoreFailureV1.corruptStore
            }
        }
        originalEraseNoRepairOperationID = operationID
        originalEraseExpectedSupportIdentity = expectedSupportIdentity
        originalEraseNoRepairBaseline = observed
        coldEraseDrainOperationID = operationID
        return observed
    }

    /// The store actor atomically binds its first cold mutation to the exact
    /// no-repair snapshot and row set. All ordinary writes are sealed from
    /// cold observation onward; only the three typed transitions below may
    /// change those rows while the operation ID remains retained.
    func beginColdEraseDrain(
        operationID: UUID,
        expected: OriginalEraseNoRepairSnapshotV1,
        expectedJobs: [ResumableLocalJobV1]
    ) throws {
        guard coldEraseDrainOperationID == operationID,
              !coldEraseDrainStarted,
              !coldEraseDrainUncertain,
              let actual = try requireOriginalEraseNoRepairBaseline(
                operationID: operationID),
              actual == expected,
              try actual.authenticatedJobs() == expectedJobs,
              !expectedJobs.contains(where: { $0.state == .awaitingPublication }) else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        coldEraseExpectedEnvelopeBytes = actual.envelopeBytes
        coldEraseExpectedRows = expectedJobs
        coldEraseDrainStarted = true
    }

    @discardableResult
    func requestCancellationForColdErase(
        id: LocalJobIDV1,
        expected: ResumableLocalJobV1,
        operationID: UUID
    ) throws -> ResumableLocalJobV1 {
        guard expected.id == id else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try requireColdEraseMutableRow(expected, operationID: operationID)
        guard expected.state != .awaitingPublication else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        return try withColdEraseMutation(operationID: operationID) {
            try requestCancellation(id: id)
        }
    }

    @discardableResult
    func markCancelledForColdErase(
        id: LocalJobIDV1,
        expected: ResumableLocalJobV1,
        expectedAttemptCount: Int,
        operationID: UUID
    ) throws -> ResumableLocalJobV1 {
        guard expected.id == id,
              expected.attemptCount == expectedAttemptCount else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try requireColdEraseMutableRow(expected, operationID: operationID)
        guard expected.state == .cancellationRequested else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        return try withColdEraseMutation(operationID: operationID) {
            try markCancelled(id: id,
                expectedAttemptCount: expectedAttemptCount)
        }
    }

    func eraseAllForColdErase(operationID: UUID) throws {
        guard coldEraseDrainOperationID == operationID,
              coldEraseDrainStarted else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try ensureLoaded()
        try requireColdEraseExpectedPhysicalState()
        guard envelope?.jobs.allSatisfy({ $0.state.isTerminal }) == true else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try withColdEraseMutation(operationID: operationID) {
            try eraseAll()
        }
    }

    private func requireColdEraseMutableRow(
        _ expected: ResumableLocalJobV1,
        operationID: UUID
    ) throws {
        guard coldEraseDrainOperationID == operationID,
              coldEraseDrainStarted else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try ensureLoaded()
        try requireColdEraseExpectedPhysicalState()
        guard envelope?.jobs.first(where: { $0.id == expected.id })
                == expected else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
    }

    private func requireColdEraseExpectedPhysicalState() throws {
        guard !coldEraseDrainUncertain,
              let originalEraseExpectedSupportIdentity,
              let originalEraseNoRepairBaseline,
              let coldEraseExpectedEnvelopeBytes,
              let coldEraseExpectedRows,
              let observed = try readOriginalEraseNoRepairSnapshot(
                expectedSupportIdentity: originalEraseExpectedSupportIdentity),
              observed.rootDevice == originalEraseNoRepairBaseline.rootDevice,
              observed.rootInode == originalEraseNoRepairBaseline.rootInode,
              observed.receiptBytes == originalEraseNoRepairBaseline.receiptBytes,
              observed.envelopeBytes == coldEraseExpectedEnvelopeBytes,
              try observed.authenticatedJobs() == coldEraseExpectedRows,
              envelope?.jobs == coldEraseExpectedRows else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
    }

    private func withColdEraseMutation<T>(
        operationID: UUID,
        _ body: () throws -> T
    ) throws -> T {
        guard coldEraseDrainOperationID == operationID,
              coldEraseDrainStarted,
              !coldEraseMutationPermitted,
              !coldEraseDrainUncertain else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try requireColdEraseExpectedPhysicalState()
        coldEraseMutationPermitted = true
        do {
            let result = try body()
            coldEraseMutationPermitted = false
            guard let originalEraseExpectedSupportIdentity,
                  let originalEraseNoRepairBaseline,
                  let envelope,
                  let observed = try readOriginalEraseNoRepairSnapshot(
                    expectedSupportIdentity: originalEraseExpectedSupportIdentity),
                  observed.rootDevice == originalEraseNoRepairBaseline.rootDevice,
                  observed.rootInode == originalEraseNoRepairBaseline.rootInode,
                  observed.receiptBytes == originalEraseNoRepairBaseline.receiptBytes,
                  observed.envelopeBytes == (try Self.makeEncoder().encode(envelope)),
                  try observed.authenticatedJobs() == envelope.jobs else {
                throw LocalJobStoreFailureV1.corruptStore
            }
            coldEraseExpectedEnvelopeBytes = observed.envelopeBytes
            coldEraseExpectedRows = envelope.jobs
            return result
        } catch {
            coldEraseMutationPermitted = false
            coldEraseDrainUncertain = true
            throw error
        }
    }

    /// Pure observation before Erase admission. An absent store stays absent;
    /// no directory, envelope, receipt or quarantine is created here.
    func beginOriginalEraseNoRepairObservation(
        operationID: UUID,
        expectedSupportIdentity: StoreApplicationSupportIdentity
    ) throws -> OriginalEraseNoRepairSnapshotV1? {
        guard originalEraseNoRepairOperationID == nil else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        let observed = try readOriginalEraseNoRepairSnapshot(
            expectedSupportIdentity: expectedSupportIdentity)
        originalEraseNoRepairOperationID = operationID
        originalEraseExpectedSupportIdentity = expectedSupportIdentity
        originalEraseNoRepairBaseline = observed
        return observed
    }

    /// The producer actor gate remains held across both observations. Any
    /// drift refuses; it never adopts a newer store as the V3 pending basis.
    func requireOriginalEraseNoRepairBaseline(
        operationID: UUID
    ) throws -> OriginalEraseNoRepairSnapshotV1? {
        guard originalEraseNoRepairOperationID == operationID else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        guard let originalEraseExpectedSupportIdentity else {
            throw LocalJobStoreFailureV1.invalidRoot
        }
        let observed = try readOriginalEraseNoRepairSnapshot(
            expectedSupportIdentity: originalEraseExpectedSupportIdentity)
        guard observed == originalEraseNoRepairBaseline else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        return observed
    }

    /// Used only by the Router's genuine pre-marker, no-effect abort path.
    func releaseOriginalEraseNoRepairObservation(
        operationID: UUID
    ) throws {
        _ = try requireOriginalEraseNoRepairBaseline(operationID: operationID)
        originalEraseNoRepairOperationID = nil
        originalEraseExpectedSupportIdentity = nil
        originalEraseNoRepairBaseline = nil
    }

    /// The genuine post-drain store bytes for the V3 completed marker. This
    /// rereads the actual retained root after `eraseAll` has published, and
    /// checks that the C05 receipt and directory identity did not change.
    func requireOriginalEraseEmptySnapshot(operationID: UUID) throws
        -> OriginalEraseNoRepairSnapshotV1 {
        guard originalEraseNoRepairOperationID == operationID,
              let originalEraseExpectedSupportIdentity,
              let originalEraseNoRepairBaseline,
              let current = try readOriginalEraseNoRepairSnapshot(
                expectedSupportIdentity: originalEraseExpectedSupportIdentity),
              current.rootDevice == originalEraseNoRepairBaseline.rootDevice,
              current.rootInode == originalEraseNoRepairBaseline.rootInode,
              current.receiptBytes == originalEraseNoRepairBaseline.receiptBytes else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        let envelope = try Self.makeDecoder().decode(
            LocalJobStoreEnvelopeV1.self, from: current.envelopeBytes)
        guard try Self.makeEncoder().encode(envelope) == current.envelopeBytes,
              envelope.jobs.isEmpty else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        return current
    }

    /// Forward-only continuation after the durable DRAINED preparation has
    /// authenticated the empty envelope, receipt and absent generation scratch.
    /// A partially removed root is accepted only for these exact two leaves;
    /// existing leaves must still equal the recorded bytes. No store is loaded,
    /// repaired or created. The caller retains this actor on any uncertain close.
    func removeOriginalEraseDrainedRoot(
        _ drain: EraseC05JobDrainV3
    ) throws {
        try drain.validate()
        guard drain.phase == .drained,
              let empty = drain.completedEnvelopeBytes,
              let receipt = drain.completedReceiptBytes,
              originalEraseUncertainDescriptors.isEmpty,
              originalEraseUncertainStreams.isEmpty else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        let decoded = try Self.makeDecoder().decode(
            LocalJobStoreEnvelopeV1.self, from: empty)
        let decodedReceipt = try Self.makeDecoder().decode(
            LocalJobStoreMigrationReceiptV1.self, from: receipt)
        try decoded.validate()
        try decodedReceipt.validate()
        guard decoded.jobs.isEmpty,
              try Self.makeEncoder().encode(decoded) == empty,
              try Self.makeEncoder().encode(decodedReceipt) == receipt,
              receipt == drain.sourceReceiptBytes else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        let support = Darwin.open(rootURL.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard support >= 0 else { throw LocalJobStoreFailureV1.invalidRoot }
        try withCheckedOriginalEraseDescriptor(support) { supportFD in
            var supportStat = stat()
            guard Darwin.fstat(supportFD, &supportStat) == 0,
                  UInt64(supportStat.st_dev) == drain.supportDevice,
                  UInt64(supportStat.st_ino) == drain.supportInode else {
                throw LocalJobStoreFailureV1.invalidRoot
            }
            var rootStat = stat()
            if Darwin.fstatat(supportFD, LocalJobStoreSchemaV1.directoryName,
                              &rootStat, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw LocalJobStoreFailureV1.invalidRoot }
                guard Darwin.fsync(supportFD) == 0 else {
                    throw LocalJobStoreFailureV1.cleanupFailed
                }
                return
            }
            guard rootStat.st_mode & S_IFMT == S_IFDIR,
                  UInt64(rootStat.st_dev) == drain.sourceStoreDevice,
                  UInt64(rootStat.st_ino) == drain.sourceStoreInode else {
                throw LocalJobStoreFailureV1.invalidRoot
            }
            let opened = Darwin.openat(supportFD,
                LocalJobStoreSchemaV1.directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard opened >= 0 else { throw LocalJobStoreFailureV1.invalidRoot }
            try withCheckedOriginalEraseDescriptor(opened) { rootFD in
                var held = stat()
                guard Darwin.fstat(rootFD, &held) == 0,
                      held.st_dev == rootStat.st_dev,
                      held.st_ino == rootStat.st_ino else {
                    throw LocalJobStoreFailureV1.invalidRoot
                }
                let expected: [String: Data] = [
                    LocalJobStoreSchemaV1.storeFileName: empty,
                    LocalJobStoreSchemaV1.migrationReceiptFileName: receipt,
                ]
                let names = try originalEraseNoRepairNames(in: rootFD)
                guard names.isSubset(of: Set(expected.keys)) else {
                    throw LocalJobStoreFailureV1.corruptStore
                }
                for name in names.sorted() {
                    guard let bytes = expected[name],
                          try readOriginalEraseNoRepairFile(
                              name, parentDescriptor: rootFD) == bytes,
                          Darwin.unlinkat(rootFD, name, 0) == 0 else {
                        throw LocalJobStoreFailureV1.corruptStore
                    }
                }
                guard try originalEraseNoRepairNames(in: rootFD).isEmpty,
                      Darwin.fsync(rootFD) == 0 else {
                    throw LocalJobStoreFailureV1.cleanupFailed
                }
            }
            guard Darwin.unlinkat(supportFD,
                    LocalJobStoreSchemaV1.directoryName, AT_REMOVEDIR) == 0,
                  Darwin.fsync(supportFD) == 0 else {
                throw LocalJobStoreFailureV1.cleanupFailed
            }
            var after = stat()
            guard Darwin.fstatat(supportFD,
                    LocalJobStoreSchemaV1.directoryName,
                    &after, AT_SYMLINK_NOFOLLOW) != 0,
                  errno == ENOENT else {
                throw LocalJobStoreFailureV1.invalidRoot
            }
        }
    }

    init(
        applicationSupportURL: URL,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileManager: FileManager = .default,
        protectedDataFailureHook: @escaping LocalJobStoreProtectedDataFailureHookV1 = { _ in false }
    ) throws {
        guard applicationSupportURL.isFileURL else {
            throw LocalJobStoreFailureV1.invalidRoot
        }
        let support = applicationSupportURL.standardizedFileURL
        rootURL = support.appendingPathComponent(
            LocalJobStoreSchemaV1.directoryName,
            isDirectory: true
        )
        storeURL = rootURL.appendingPathComponent(
            LocalJobStoreSchemaV1.storeFileName,
            isDirectory: false
        )
        receiptURL = rootURL.appendingPathComponent(
            LocalJobStoreSchemaV1.migrationReceiptFileName,
            isDirectory: false
        )
        quarantineURL = rootURL.appendingPathComponent(
            LocalJobStoreSchemaV1.quarantineDirectoryName,
            isDirectory: true
        )
        self.clock = clock
        self.idSource = idSource
        self.fileManager = fileManager
        self.protectedDataFailureHook = protectedDataFailureHook
    }

    @discardableResult
    func enqueue(_ job: ResumableLocalJobV1) throws -> ResumableLocalJobV1 {
        try ensureLoaded()
        try job.validate()
        guard job.state == .queued,
              envelope?.jobs.contains(where: { $0.id == job.id }) == false else {
            throw LocalJobStoreFailureV1.jobAlreadyExists
        }
        var jobs = envelope?.jobs ?? []
        guard jobs.count < LocalJobStoreSchemaV1.maximumJobCount else {
            throw LocalJobStoreFailureV1.storeLimitExceeded
        }
        jobs.append(job)
        try replace(jobs: jobs)
        return job
    }

    func job(id: LocalJobIDV1) throws -> ResumableLocalJobV1? {
        try ensureLoaded()
        return envelope?.jobs.first { $0.id == id }
    }

    func jobs(workspaceID: UUID? = nil) throws -> [ResumableLocalJobV1] {
        try ensureLoaded()
        let jobs = envelope?.jobs ?? []
        guard let workspaceID else { return jobs }
        return jobs.filter { $0.workspaceID == workspaceID }
    }

    @discardableResult
    func requestCancellation(id: LocalJobIDV1) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            if job.state == .cancelled || job.state == .cancellationRequested {
                return
            }
            if job.state == .awaitingPublication {
                guard var pending = job.pendingPublication else {
                    throw LocalJobStoreFailureV1.invalidTransition
                }
                pending.cancellationRequested = true
                job.pendingPublication = pending
                job.updatedAt = clock.now()
                return
            }
            guard !job.state.isTerminal,
                  job.permitsTransition(to: .cancellationRequested) else {
                throw LocalJobStoreFailureV1.invalidTransition
            }
            job.state = .cancellationRequested
            job.updatedAt = clock.now()
            job.retryClassification = nil
            job.failureCode = nil
        }
    }

    /// Converts interrupted RUNNING rows into resumable QUEUED rows. A
    /// Cancellation-requested rows remain durable until the runner proves
    /// exact staging cleanup. Awaiting-publication rows are reconciled by their
    /// idempotent publisher before any terminal state is recorded.
    func resumePending() throws {
        try ensureLoaded()
        var changed = false
        let now = clock.now()
        var jobs = envelope?.jobs ?? []
        for index in jobs.indices {
            switch jobs[index].state {
            case .running:
                jobs[index].state = .queued
                jobs[index].retryClassification = .retryable
                jobs[index].failureCode = nil
                jobs[index].updatedAt = now
                changed = true
            default:
                break
            }
        }
        if changed { try replace(jobs: jobs) }
    }

    /// Records an interruption without applying user-cancellation cleanup.
    /// Awaiting-publication rows are intentionally not eligible here.
    @discardableResult
    func markLifecycleSuspended(
        id: LocalJobIDV1,
        expectedAttemptCount: Int,
        reason: LocalJobLifecycleSuspensionReasonV1
    ) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.attemptCount == expectedAttemptCount else {
                throw LocalJobStoreFailureV1.staleJob
            }
            // Matching resume may already have requeued this exact attempt.
            // An older task unwind can never overwrite QUEUED with BLOCKED.
            if job.state == .queued { return }
            guard job.state == .running else {
                throw LocalJobStoreFailureV1.staleJob
            }
            switch reason {
            case .protectedDataUnavailable:
                guard job.permitsTransition(to: .blockedProtectedData) else {
                    throw LocalJobStoreFailureV1.invalidTransition
                }
                job.state = .blockedProtectedData
                job.retryClassification = .protectedDataUnavailable
            case .sceneBackground:
                guard job.permitsTransition(to: .queued) else {
                    throw LocalJobStoreFailureV1.invalidTransition
                }
                job.state = .queued
                job.retryClassification = .retryable
            }
            job.outputSHA256 = nil
            job.failureCode = nil
            job.updatedAt = clock.now()
        }
    }

    /// Completes an already-cancelled lifecycle attempt after its matching
    /// resume edge has durably read the store. The old task alone performs
    /// this transition, preventing a successor attempt from overlapping it.
    @discardableResult
    func markLifecycleRecoveryQueued(
        id: LocalJobIDV1,
        expectedAttemptCount: Int
    ) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.attemptCount == expectedAttemptCount else {
                throw LocalJobStoreFailureV1.staleJob
            }
            if job.state == .queued { return }
            guard job.state == .running,
                  job.permitsTransition(to: .queued) else {
                throw LocalJobStoreFailureV1.staleJob
            }
            job.state = .queued
            job.outputSHA256 = nil
            job.failureCode = nil
            job.retryClassification = .retryable
            job.updatedAt = clock.now()
        }
    }

    /// Unlock recovery first discards the actor cache and proves an exact
    /// descriptor-pinned durable read. Only then are blocked/interrupted rows
    /// requeued and durably read back by `replace`.
    func resumeAfterProtectedDataAvailable() throws {
        envelope = nil
        receipt = nil
        try ensureLoaded()
        let now = clock.now()
        var jobs = envelope?.jobs ?? []
        var changed = false
        for index in jobs.indices {
            switch jobs[index].state {
            case .blockedProtectedData:
                jobs[index].state = .queued
                jobs[index].retryClassification = .retryable
                jobs[index].failureCode = nil
                jobs[index].updatedAt = now
                changed = true
            case .running:
                jobs[index].state = .queued
                jobs[index].retryClassification = .retryable
                jobs[index].failureCode = nil
                jobs[index].updatedAt = now
                changed = true
            default:
                break
            }
        }
        if changed { try replace(jobs: jobs) }
    }

    func removeTerminal(id: LocalJobIDV1) throws {
        try ensureLoaded()
        guard let current = envelope?.jobs.first(where: { $0.id == id }) else {
            return
        }
        guard current.state.isTerminal else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try replace(jobs: envelope!.jobs.filter { $0.id != id })
    }

    func removeJobs(workspaceID: UUID) throws {
        try ensureLoaded()
        guard let current = envelope else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        let scoped = current.jobs.filter { $0.workspaceID == workspaceID }
        guard scoped.allSatisfy({ $0.state.isTerminal }) else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try replace(jobs: current.jobs.filter { $0.workspaceID != workspaceID })
    }

    func eraseAll() throws {
        try ensureLoaded()
        guard let current = envelope else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        guard current.jobs.allSatisfy({ $0.state.isTerminal }) else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try replace(jobs: [])
    }

    @discardableResult
    func removeExpired(before cutoff: Date) throws -> Int {
        try ensureLoaded()
        let existing = envelope!.jobs
        let retained = existing.filter {
            !$0.state.isTerminal || $0.updatedAt >= cutoff
        }
        if retained.count != existing.count { try replace(jobs: retained) }
        return existing.count - retained.count
    }

    func migrationReceipt() throws -> LocalJobStoreMigrationReceiptV1 {
        try ensureLoaded()
        return receipt!
    }

    @discardableResult
    func claimForExecution(id: LocalJobIDV1) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.state == .queued,
                  job.permitsTransition(to: .running) else {
                throw LocalJobStoreFailureV1.invalidTransition
            }
            job.state = .running
            job.attemptCount += 1
            job.updatedAt = clock.now()
            job.retryClassification = nil
            job.failureCode = nil
        }
    }

    @discardableResult
    func saveCheckpoint(
        id: LocalJobIDV1,
        expectedAttemptCount: Int,
        checkpoint: LocalJobCheckpointV1
    ) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.state == .running,
                  job.attemptCount == expectedAttemptCount,
                  checkpoint.completedUnitCount >= job.checkpoint.completedUnitCount,
                  checkpoint.nextChunkIndex >= job.checkpoint.nextChunkIndex else {
                throw LocalJobStoreFailureV1.staleJob
            }
            try checkpoint.validate(for: id)
            job.checkpoint = checkpoint
            job.updatedAt = clock.now()
        }
    }

    @discardableResult
    func markSucceeded(
        id: LocalJobIDV1,
        expectedAttemptCount: Int,
        result: ResumableLocalJobResultV1
    ) throws -> ResumableLocalJobV1 {
        // Direct success bypasses publication/readback authority and is no
        // longer a valid transition. Retained as a fail-closed source-compatible
        // boundary for callers migrating to markAwaitingPublication.
        _ = id
        _ = expectedAttemptCount
        _ = result
        throw LocalJobStoreFailureV1.invalidTransition
    }

    @discardableResult
    func markAwaitingPublication(
        id: LocalJobIDV1,
        expectedAttemptCount: Int,
        result: ResumableLocalJobResultV1
    ) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.state == .running || job.state == .cancellationRequested,
                  job.attemptCount == expectedAttemptCount,
                  job.permitsTransition(to: .awaitingPublication),
                  ResumableLocalJobV1.isSHA256(result.outputSHA256),
                  result.completedUnitCount == job.checkpoint.totalUnitCount else {
                throw LocalJobStoreFailureV1.staleJob
            }
            job.checkpoint = LocalJobCheckpointV1(
                nextChunkIndex: job.checkpoint.nextChunkIndex,
                completedUnitCount: result.completedUnitCount,
                totalUnitCount: job.checkpoint.totalUnitCount,
                lastChunkID: job.checkpoint.lastChunkID,
                rollingOutputSHA256: result.outputSHA256
            )
            job.pendingPublication = LocalJobPendingPublicationV1(
                attemptCount: expectedAttemptCount,
                result: result,
                persistedAt: clock.now(),
                cancellationRequested: job.state == .cancellationRequested
            )
            job.state = .awaitingPublication
            job.outputSHA256 = nil
            job.retryClassification = nil
            job.failureCode = nil
            job.updatedAt = clock.now()
        }
    }

    @discardableResult
    func markPublicationSucceeded(
        id: LocalJobIDV1,
        expectedAttemptCount: Int,
        receipt: LocalJobPublicationReceiptV1
    ) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.state == .awaitingPublication,
                  job.attemptCount == expectedAttemptCount,
                  job.permitsTransition(to: .succeeded),
                  let pending = job.pendingPublication,
                  pending.attemptCount == expectedAttemptCount else {
                throw LocalJobStoreFailureV1.staleJob
            }
            try receipt.validate(job: job)
            job.state = .succeeded
            job.outputSHA256 = pending.result.outputSHA256
            job.publicationReceipt = receipt
            job.retryClassification = nil
            job.failureCode = nil
            job.updatedAt = clock.now()
        }
    }

    @discardableResult
    func markPublicationAbsentAndCancelled(
        id: LocalJobIDV1,
        expectedAttemptCount: Int
    ) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.state == .awaitingPublication,
                  job.attemptCount == expectedAttemptCount,
                  job.pendingPublication?.cancellationRequested == true,
                  job.permitsTransition(to: .cancelled) else {
                throw LocalJobStoreFailureV1.staleJob
            }
            job.state = .cancelled
            job.pendingPublication = nil
            job.publicationReceipt = nil
            job.outputSHA256 = nil
            job.retryClassification = nil
            job.failureCode = nil
            job.updatedAt = clock.now()
        }
    }

    @discardableResult
    func markCancelled(
        id: LocalJobIDV1,
        expectedAttemptCount: Int
    ) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.attemptCount == expectedAttemptCount,
                  job.state == .running || job.state == .cancellationRequested else {
                throw LocalJobStoreFailureV1.staleJob
            }
            job.state = .cancelled
            job.pendingPublication = nil
            job.publicationReceipt = nil
            job.outputSHA256 = nil
            job.retryClassification = nil
            job.failureCode = nil
            job.updatedAt = clock.now()
        }
    }

    @discardableResult
    func markFailed(
        id: LocalJobIDV1,
        expectedAttemptCount: Int,
        classification: LocalJobRetryClassificationV1,
        failureCode: String
    ) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.attemptCount == expectedAttemptCount,
                  job.state == .running else {
                throw LocalJobStoreFailureV1.staleJob
            }
            let next: LocalJobStateV1 = classification == .protectedDataUnavailable
                ? .blockedProtectedData
                : .failed
            guard job.permitsTransition(to: next) else {
                throw LocalJobStoreFailureV1.invalidTransition
            }
            job.state = next
            job.outputSHA256 = nil
            job.retryClassification = classification
            job.failureCode = next == .failed ? failureCode : nil
            job.updatedAt = clock.now()
        }
    }

    @discardableResult
    func requeue(id: LocalJobIDV1) throws -> ResumableLocalJobV1 {
        try mutate(id: id) { job in
            guard job.permitsTransition(to: .queued),
                  job.retryClassification != .permanent else {
                throw LocalJobStoreFailureV1.invalidTransition
            }
            job.state = .queued
            job.outputSHA256 = nil
            job.failureCode = nil
            job.updatedAt = clock.now()
        }
    }
}

// MARK: - C36 attachment jobs

extension LocalJobStoreV1 {
    @discardableResult
    func enqueueDraftAttachment(
        _ request: DraftAttachmentJobRequestV1
    ) async throws -> ResumableLocalJobV1 {
        try enqueue(ResumableLocalJobV1.draftAttachmentProcessing(request))
    }

    func draftAttachmentJob(
        workspaceID: WorkspaceID,
        stageID: UUID
    ) async throws -> ResumableLocalJobV1? {
        let jobs = try jobs(workspaceID: workspaceID.rawValue)
        return jobs.first {
            guard $0.kind == .draftAttachmentProcessing else { return false }
            return $0.stagingRelativePath.contains(stageID.uuidString.lowercased())
        }
    }
}

private extension LocalJobStoreV1 {
    func withCheckedOriginalEraseDescriptor<Value>(
        _ descriptor: Int32, _ body: (Int32) throws -> Value
    ) throws -> Value {
        var didAttemptClose = false
        do {
            let result = try body(descriptor)
            didAttemptClose = true
            guard Darwin.close(descriptor) == 0 else {
                originalEraseUncertainDescriptors.append(descriptor)
                throw LocalJobStoreFailureV1.cleanupFailed
            }
            return result
        } catch {
            if !didAttemptClose {
                didAttemptClose = true
                guard Darwin.close(descriptor) == 0 else {
                    originalEraseUncertainDescriptors.append(descriptor)
                    throw LocalJobStoreFailureV1.cleanupFailed
                }
            }
            throw error
        }
    }

    func readOriginalEraseNoRepairSnapshot(
        expectedSupportIdentity: StoreApplicationSupportIdentity
    ) throws
        -> OriginalEraseNoRepairSnapshotV1? {
        guard originalEraseUncertainDescriptors.isEmpty,
              originalEraseUncertainStreams.isEmpty else {
            throw LocalJobStoreFailureV1.cleanupFailed
        }
        let supportURL = rootURL.deletingLastPathComponent()
        let supportDescriptor = Darwin.open(
            supportURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard supportDescriptor >= 0 else {
            throw Self.mappedPOSIXFailure(errno)
        }
        let observed: OriginalEraseNoRepairSnapshotV1? = try
            withCheckedOriginalEraseDescriptor(supportDescriptor) { support in
            var supportBefore = stat(), supportAfter = stat()
            guard Darwin.fstat(support, &supportBefore) == 0 else {
                throw LocalJobStoreFailureV1.invalidRoot
            }
            guard supportBefore.st_dev == expectedSupportIdentity.device,
                  supportBefore.st_ino == expectedSupportIdentity.inode else {
                throw LocalJobStoreFailureV1.invalidRoot
            }
            var namedRoot = stat()
            guard Darwin.fstatat(support, LocalJobStoreSchemaV1.directoryName,
                &namedRoot, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno == ENOENT { return nil }
                throw LocalJobStoreFailureV1.invalidRoot
            }
            guard namedRoot.st_mode & S_IFMT == S_IFDIR else {
                throw LocalJobStoreFailureV1.invalidRoot
            }
            let rootDescriptor = Darwin.openat(support,
                LocalJobStoreSchemaV1.directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard rootDescriptor >= 0 else {
                throw LocalJobStoreFailureV1.invalidRoot
            }
            let observed = try withCheckedOriginalEraseDescriptor(rootDescriptor) { root in
                var rootBefore = stat(), rootAfter = stat(), namedAfter = stat()
                guard Darwin.fstat(root, &rootBefore) == 0,
                      rootBefore.st_dev == namedRoot.st_dev,
                      rootBefore.st_ino == namedRoot.st_ino else {
                    throw LocalJobStoreFailureV1.invalidRoot
                }
                let expectedNames: Set<String> = [
                    LocalJobStoreSchemaV1.storeFileName,
                    LocalJobStoreSchemaV1.migrationReceiptFileName,
                ]
                guard try originalEraseNoRepairNames(in: root) == expectedNames else {
                    throw LocalJobStoreFailureV1.corruptStore
                }
                let envelopeBytes = try readOriginalEraseNoRepairFile(
                    LocalJobStoreSchemaV1.storeFileName,
                    parentDescriptor: root)
                let receiptBytes = try readOriginalEraseNoRepairFile(
                    LocalJobStoreSchemaV1.migrationReceiptFileName,
                    parentDescriptor: root)
                guard Darwin.fstat(root, &rootAfter) == 0,
                      Darwin.fstatat(support,
                        LocalJobStoreSchemaV1.directoryName,
                        &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
                      rootBefore.st_dev == rootAfter.st_dev,
                      rootBefore.st_ino == rootAfter.st_ino,
                      rootBefore.st_mtimespec.tv_sec == rootAfter.st_mtimespec.tv_sec,
                      rootBefore.st_mtimespec.tv_nsec == rootAfter.st_mtimespec.tv_nsec,
                      rootBefore.st_ctimespec.tv_sec == rootAfter.st_ctimespec.tv_sec,
                      rootBefore.st_ctimespec.tv_nsec == rootAfter.st_ctimespec.tv_nsec,
                      namedAfter.st_dev == rootBefore.st_dev,
                      namedAfter.st_ino == rootBefore.st_ino,
                      namedAfter.st_mode & S_IFMT == S_IFDIR,
                      try originalEraseNoRepairNames(in: root) == expectedNames else {
                    throw LocalJobStoreFailureV1.invalidRoot
                }
                return OriginalEraseNoRepairSnapshotV1(
                    rootDevice: UInt64(rootBefore.st_dev),
                    rootInode: UInt64(rootBefore.st_ino),
                    envelopeBytes: envelopeBytes,
                    receiptBytes: receiptBytes)
            }
            guard Darwin.fstat(support, &supportAfter) == 0,
                  supportBefore.st_dev == supportAfter.st_dev,
                  supportBefore.st_ino == supportAfter.st_ino else {
                throw LocalJobStoreFailureV1.invalidRoot
            }
            return observed
        }
        if let observed {
            let decoded = try Self.makeDecoder().decode(
                LocalJobStoreEnvelopeV1.self, from: observed.envelopeBytes)
            let migration = try Self.makeDecoder().decode(
                LocalJobStoreMigrationReceiptV1.self,
                from: observed.receiptBytes)
            guard try Self.makeEncoder().encode(decoded) == observed.envelopeBytes,
                  try Self.makeEncoder().encode(migration) == observed.receiptBytes else {
                throw LocalJobStoreFailureV1.corruptStore
            }
            try decoded.validate()
            try migration.validate()
        }
        return observed
    }

    /// A closed census of this actual directory, not a URL traversal. A
    /// quarantine, pending write or alien child needs separate recovery
    /// authority and cannot be silently treated as an empty C05 store.
    private func originalEraseNoRepairNames(in descriptor: Int32) throws
        -> Set<String> {
        // `dup` would share the directory offset with the held root, making
        // the second census vacuously empty. Open a distinct file description.
        let independent = Darwin.openat(descriptor, ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard independent >= 0 else { throw LocalJobStoreFailureV1.invalidRoot }
        guard let stream = Darwin.fdopendir(independent) else {
            return try withCheckedOriginalEraseDescriptor(independent) { _ in
                throw LocalJobStoreFailureV1.invalidRoot
            }
        }
        var closeAttempted = false
        do {
            var names = Set<String>()
            // The only authorized C05 leaves are the envelope and receipt.
            // Bound the scan before accepting even a malformed large folder.
            for _ in 0..<5 {
                errno = 0
                guard let entry = Darwin.readdir(stream) else {
                    guard errno == 0 else {
                        throw LocalJobStoreFailureV1.invalidRoot
                    }
                    closeAttempted = true
                    guard Darwin.closedir(stream) == 0 else {
                        originalEraseUncertainStreams.append(stream)
                        throw LocalJobStoreFailureV1.cleanupFailed
                    }
                    return names
                }
                guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                    throw LocalJobStoreFailureV1.invalidRoot
                }
                if name != "." && name != ".." {
                    guard names.insert(name).inserted else {
                        throw LocalJobStoreFailureV1.corruptStore
                    }
                }
            }
            throw LocalJobStoreFailureV1.corruptStore
        } catch {
            if !closeAttempted {
                closeAttempted = true
                guard Darwin.closedir(stream) == 0 else {
                    originalEraseUncertainStreams.append(stream)
                    throw LocalJobStoreFailureV1.cleanupFailed
                }
            }
            throw error
        }
    }

    func readOriginalEraseNoRepairFile(
        _ name: String, parentDescriptor: Int32
    ) throws -> Data {
        let descriptor = Darwin.openat(parentDescriptor, name,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        return try withCheckedOriginalEraseDescriptor(descriptor) { file in
            var before = stat(), after = stat(), named = stat()
            guard Darwin.fstat(file, &before) == 0,
                  before.st_mode & S_IFMT == S_IFREG,
                  before.st_nlink == 1,
                  before.st_size >= 0,
                  before.st_size <= off_t(LocalJobStoreSchemaV1.maximumStoreBytes) else {
                throw LocalJobStoreFailureV1.corruptStore
            }
            let bytes = try Self.readAll(from: file,
                maximumByteCount: LocalJobStoreSchemaV1.maximumStoreBytes)
            guard Darwin.fstat(file, &after) == 0,
                  Darwin.fstatat(parentDescriptor, name,
                    &named, AT_SYMLINK_NOFOLLOW) == 0,
                  before.st_dev == after.st_dev,
                  before.st_ino == after.st_ino,
                  before.st_size == after.st_size,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                  before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
                  before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
                  named.st_dev == before.st_dev,
                  named.st_ino == before.st_ino,
                  named.st_mode & S_IFMT == S_IFREG,
                  named.st_nlink == 1,
                  bytes.count == Int(after.st_size) else {
                throw LocalJobStoreFailureV1.corruptStore
            }
            return bytes
        }
    }

    func ensureLoaded() throws {
        if originalEraseNoRepairOperationID != nil {
            guard let originalEraseExpectedSupportIdentity,
                  let snapshot = try readOriginalEraseNoRepairSnapshot(
                    expectedSupportIdentity: originalEraseExpectedSupportIdentity) else {
                throw LocalJobStoreFailureV1.corruptStore
            }
            let decoded = try Self.makeDecoder().decode(
                LocalJobStoreEnvelopeV1.self, from: snapshot.envelopeBytes)
            let migration = try Self.makeDecoder().decode(
                LocalJobStoreMigrationReceiptV1.self,
                from: snapshot.receiptBytes)
            guard try Self.makeEncoder().encode(decoded) == snapshot.envelopeBytes,
                  try Self.makeEncoder().encode(migration) == snapshot.receiptBytes else {
                throw LocalJobStoreFailureV1.corruptStore
            }
            try decoded.validate()
            try migration.validate()
            envelope = decoded
            receipt = migration
            return
        }
        guard envelope == nil else { return }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = rootURL
        do { try mutableRoot.setResourceValues(values) }
        catch { throw LocalJobStoreFailureV1.writeFailed }

        guard fileManager.fileExists(atPath: storeURL.path) else {
            let empty = try LocalJobStoreEnvelopeV1(jobs: [])
            let migration = LocalJobStoreMigrationReceiptV1(
                source: .absent,
                disposition: .createdEmpty,
                sourceStoreVersion: nil,
                migratedJobCount: 0,
                occurredAt: clock.now()
            )
            try persist(envelope: empty, receipt: migration)
            self.envelope = empty
            receipt = migration
            return
        }

        do {
            let data = try boundedData(at: storeURL)
            let decoded: LocalJobStoreEnvelopeV1
            let migration: LocalJobStoreMigrationReceiptV1
            if try Self.storeVersion(in: data) == 0 {
                let legacy = try Self.makeDecoder().decode(
                    LegacyLocalJobStoreEnvelopeV0.self,
                    from: data
                )
                decoded = try LocalJobStoreEnvelopeV1(jobs: legacy.jobs)
                migration = LocalJobStoreMigrationReceiptV1(
                    source: .olderVersion,
                    disposition: .migrated,
                    sourceStoreVersion: 0,
                    migratedJobCount: decoded.jobs.count,
                    occurredAt: clock.now()
                )
                try persist(envelope: decoded, receipt: migration)
            } else {
                decoded = try Self.makeDecoder().decode(
                    LocalJobStoreEnvelopeV1.self,
                    from: data
                )
                guard try Self.makeEncoder().encode(decoded) == data else {
                    throw LocalJobStoreFailureV1.corruptStore
                }
                migration = try loadReceipt() ?? LocalJobStoreMigrationReceiptV1(
                    source: .version1,
                    disposition: .openedCurrent,
                    sourceStoreVersion: LocalJobStoreSchemaV1.currentVersion,
                    migratedJobCount: decoded.jobs.count,
                    occurredAt: clock.now()
                )
            }
            try decoded.validate()
            try migration.validate()
            if !fileManager.fileExists(atPath: receiptURL.path) {
                try write(migration, to: receiptURL)
            }
            envelope = decoded
            receipt = migration
        } catch let error where Self.isProtectedDataFailure(error) {
            throw LocalJobStoreFailureV1.protectedDataUnavailable
        } catch {
            try quarantineAndRebuild()
        }
    }

    func quarantineAndRebuild() throws {
        try injectProtectedDataFailure(at: .cleanup)
        try fileManager.createDirectory(
            at: quarantineURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if fileManager.fileExists(atPath: storeURL.path) {
            let suffix = idSource.makeID().uuidString.lowercased()
            let destination = quarantineURL.appendingPathComponent(
                "jobs-\(suffix).invalid",
                isDirectory: false
            )
            do { try fileManager.moveItem(at: storeURL, to: destination) }
            catch { throw LocalJobStoreFailureV1.cleanupFailed }
        }
        if fileManager.fileExists(atPath: receiptURL.path) {
            do { try fileManager.removeItem(at: receiptURL) }
            catch { throw LocalJobStoreFailureV1.cleanupFailed }
        }
        let empty = try LocalJobStoreEnvelopeV1(jobs: [])
        let migration = LocalJobStoreMigrationReceiptV1(
            source: .unknownOrCorrupt,
            disposition: .quarantinedAndRebuilt,
            sourceStoreVersion: nil,
            migratedJobCount: 0,
            occurredAt: clock.now()
        )
        try persist(envelope: empty, receipt: migration)
        envelope = empty
        receipt = migration
    }

    func mutate(
        id: LocalJobIDV1,
        _ body: (inout ResumableLocalJobV1) throws -> Void
    ) throws -> ResumableLocalJobV1 {
        try ensureLoaded()
        var jobs = envelope!.jobs
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            throw LocalJobStoreFailureV1.jobNotFound
        }
        try body(&jobs[index])
        do { try jobs[index].validate() }
        catch { throw LocalJobStoreFailureV1.invalidTransition }
        let result = jobs[index]
        try replace(jobs: jobs)
        return result
    }

    func replace(jobs: [ResumableLocalJobV1]) throws {
        guard coldEraseDrainOperationID == nil
                || coldEraseMutationPermitted else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        if coldEraseMutationPermitted {
            // The ordinary mutator may have reloaded disk since its caller's
            // check. Reprove all expected bytes at the immediate write edge.
            try requireColdEraseExpectedPhysicalState()
        }
        let replacement = try LocalJobStoreEnvelopeV1(jobs: jobs)
        try write(replacement, to: storeURL)
        envelope = replacement
    }

    func persist(
        envelope: LocalJobStoreEnvelopeV1,
        receipt: LocalJobStoreMigrationReceiptV1
    ) throws {
        guard coldEraseDrainOperationID == nil else {
            throw LocalJobStoreFailureV1.invalidTransition
        }
        try envelope.validate()
        try receipt.validate()
        try write(envelope, to: storeURL)
        do { try write(receipt, to: receiptURL) }
        catch {
            // The store rename may already be durable. Force the next access
            // to reconcile disk rather than retaining an older actor snapshot.
            self.envelope = nil
            self.receipt = nil
            throw error
        }
    }

    func loadReceipt() throws -> LocalJobStoreMigrationReceiptV1? {
        guard fileManager.fileExists(atPath: receiptURL.path) else { return nil }
        let data = try boundedData(at: receiptURL)
        let decoded = try Self.makeDecoder().decode(
            LocalJobStoreMigrationReceiptV1.self,
            from: data
        )
        guard try Self.makeEncoder().encode(decoded) == data else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        return decoded
    }

    func boundedData(at url: URL) throws -> Data {
        try injectProtectedDataFailure(at: .read)
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent == rootURL,
              !url.lastPathComponent.isEmpty,
              !url.lastPathComponent.contains("/") else {
            throw LocalJobStoreFailureV1.invalidRoot
        }
        let parentDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else {
            throw Self.mappedPOSIXFailure(errno)
        }
        defer { _ = Darwin.close(parentDescriptor) }
        do {
            return try Self.readNamedFile(
                url.lastPathComponent,
                parentDescriptor: parentDescriptor,
                maximumByteCount: LocalJobStoreSchemaV1.maximumStoreBytes
            )
        } catch let error where Self.isProtectedDataFailure(error) {
            throw LocalJobStoreFailureV1.protectedDataUnavailable
        }
    }

    func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        guard coldEraseMutationPermitted else {
            try writeBody(value, to: url, checkedOwner: nil)
            return
        }
        // Retain the owner before the first fallible open. A failed close is
        // terminal: its numeric descriptor may already have been recycled.
        let owner = ColdEraseCheckedWriteOwnerV1()
        coldEraseWriteOwners.append(owner)
        do {
            try writeBody(value, to: url, checkedOwner: owner)
            try owner.closeChecked()
            coldEraseWriteOwners.removeAll { $0 === owner }
        } catch {
            let primaryFailure = error
            if !owner.closeAttempted {
                do {
                    try owner.closeChecked()
                    coldEraseWriteOwners.removeAll { $0 === owner }
                } catch {
                    coldEraseDrainUncertain = true
                    throw LocalJobStoreFailureV1.cleanupFailed
                }
            }
            coldEraseDrainUncertain = true
            throw primaryFailure
        }
    }

    private func writeBody<Value: Encodable>(
        _ value: Value,
        to url: URL,
        checkedOwner: ColdEraseCheckedWriteOwnerV1?
    ) throws {
        try injectProtectedDataFailure(at: .write)
        // Descriptor-pinned replacement provides the required .atomic and
        // .completeFileProtection durability semantics without publishing a
        // Foundation-managed temporary before its metadata is verified.
        let data: Data
        do { data = try Self.makeEncoder().encode(value) }
        catch { throw LocalJobStoreFailureV1.corruptStore }
        guard data.count <= LocalJobStoreSchemaV1.maximumStoreBytes else {
            throw LocalJobStoreFailureV1.storeLimitExceeded
        }

        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent == rootURL,
              !url.lastPathComponent.isEmpty,
              !url.lastPathComponent.contains("/") else {
            throw LocalJobStoreFailureV1.invalidRoot
        }
        let parentDescriptor = Darwin.open(
            parent.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else {
            throw Self.mappedPOSIXFailure(errno)
        }
        checkedOwner?.retainParent(parentDescriptor)
        defer {
            if checkedOwner == nil { _ = Darwin.close(parentDescriptor) }
        }

        let temporaryName = url.lastPathComponent
            + ".attempt-"
            + idSource.makeID().uuidString.lowercased()
            + ".tmp"
        let temporaryURL = parent.appendingPathComponent(
            temporaryName,
            isDirectory: false
        )
        let temporaryDescriptor = Darwin.openat(
            parentDescriptor,
            temporaryName,
            O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard temporaryDescriptor >= 0 else {
            throw Self.mappedPOSIXFailure(errno)
        }
        checkedOwner?.retainTemporary(temporaryDescriptor)
        var temporaryExists = true
        var didPublish = false
        defer {
            if checkedOwner == nil { _ = Darwin.close(temporaryDescriptor) }
        }

        do {
            let identity = try Self.regularFileIdentity(temporaryDescriptor)
            try Self.writeAll(data, to: temporaryDescriptor)
            guard Darwin.fsync(temporaryDescriptor) == 0 else {
                throw Self.mappedPOSIXFailure(errno)
            }
            do {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: temporaryURL.path
                )
            } catch {
                throw Self.mappedFoundationFailure(error)
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableTemporaryURL = temporaryURL
            do { try mutableTemporaryURL.setResourceValues(values) }
            catch { throw Self.mappedFoundationFailure(error) }
            let verifiedValues = try temporaryURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            )
            guard verifiedValues.isExcludedFromBackup == true,
                  try Self.regularFileIdentity(temporaryDescriptor) == identity,
                  try Self.namedIdentity(
                      temporaryName,
                      parentDescriptor: parentDescriptor
                  ) == identity,
                  try Self.readAll(
                      from: temporaryDescriptor,
                      maximumByteCount: LocalJobStoreSchemaV1.maximumStoreBytes
                  ) == data,
                  Darwin.fsync(temporaryDescriptor) == 0 else {
                throw LocalJobStoreFailureV1.writeFailed
            }
            guard Darwin.renameat(
                parentDescriptor,
                temporaryName,
                parentDescriptor,
                url.lastPathComponent
            ) == 0 else {
                throw Self.mappedPOSIXFailure(errno)
            }
            temporaryExists = false
            didPublish = true
            guard Darwin.fsync(parentDescriptor) == 0 else {
                throw Self.mappedPOSIXFailure(errno)
            }
            if checkedOwner != nil {
                // The renamed temporary descriptor is still the exact held
                // published inode. Avoid an additional readback descriptor
                // whose ordinary helper has an unchecked defer-close.
                guard try Self.regularFileIdentity(temporaryDescriptor) == identity,
                      try Self.namedIdentity(
                          url.lastPathComponent,
                          parentDescriptor: parentDescriptor
                      ) == identity,
                      try Self.readAll(
                          from: temporaryDescriptor,
                          maximumByteCount: LocalJobStoreSchemaV1.maximumStoreBytes
                      ) == data else {
                    throw LocalJobStoreFailureV1.writeFailed
                }
            } else {
                guard try Self.readNamedFile(
                    url.lastPathComponent,
                    parentDescriptor: parentDescriptor,
                    expectedIdentity: identity,
                    maximumByteCount: LocalJobStoreSchemaV1.maximumStoreBytes
                ) == data else {
                    throw LocalJobStoreFailureV1.writeFailed
                }
            }
        } catch {
            let primaryFailure = Self.normalizedStoreFailure(error)
            if temporaryExists {
                let unlinkResult = Darwin.unlinkat(
                    parentDescriptor,
                    temporaryName,
                    0
                )
                let syncResult = Darwin.fsync(parentDescriptor)
                guard unlinkResult == 0, syncResult == 0 else {
                    throw LocalJobStoreFailureV1.cleanupFailed
                }
            }
            if didPublish {
                envelope = nil
                receipt = nil
            }
            throw primaryFailure
        }
    }

    struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
    }

    static func regularFileIdentity(_ descriptor: Int32) throws -> FileIdentity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1 else {
            throw mappedPOSIXFailure(errno)
        }
        return FileIdentity(
            device: information.st_dev,
            inode: information.st_ino,
            linkCount: information.st_nlink
        )
    }

    static func namedIdentity(
        _ name: String,
        parentDescriptor: Int32
    ) throws -> FileIdentity {
        var information = stat()
        guard Darwin.fstatat(
            parentDescriptor,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1 else {
            throw mappedPOSIXFailure(errno)
        }
        return FileIdentity(
            device: information.st_dev,
            inode: information.st_ino,
            linkCount: information.st_nlink
        )
    }

    static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw mappedPOSIXFailure(errno)
                }
            }
        }
    }

    static func readAll(
        from descriptor: Int32,
        maximumByteCount: Int
    ) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw mappedPOSIXFailure(errno)
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                guard result.count <= maximumByteCount - count else {
                    throw LocalJobStoreFailureV1.storeLimitExceeded
                }
                result.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                return result
            } else if errno != EINTR {
                throw mappedPOSIXFailure(errno)
            }
        }
    }

    static func readNamedFile(
        _ name: String,
        parentDescriptor: Int32,
        maximumByteCount: Int
    ) throws -> Data {
        let descriptor = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw mappedPOSIXFailure(errno) }
        defer { _ = Darwin.close(descriptor) }
        let identity = try regularFileIdentity(descriptor)
        let data = try readAll(
            from: descriptor,
            maximumByteCount: maximumByteCount
        )
        guard try regularFileIdentity(descriptor) == identity,
              try namedIdentity(
                  name,
                  parentDescriptor: parentDescriptor
              ) == identity else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        return data
    }

    static func readNamedFile(
        _ name: String,
        parentDescriptor: Int32,
        expectedIdentity: FileIdentity,
        maximumByteCount: Int
    ) throws -> Data {
        let descriptor = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw mappedPOSIXFailure(errno) }
        defer { _ = Darwin.close(descriptor) }
        guard try regularFileIdentity(descriptor) == expectedIdentity else {
            throw LocalJobStoreFailureV1.writeFailed
        }
        let data = try readAll(
            from: descriptor,
            maximumByteCount: maximumByteCount
        )
        guard try regularFileIdentity(descriptor) == expectedIdentity,
              try namedIdentity(
                  name,
                  parentDescriptor: parentDescriptor
              ) == expectedIdentity else {
            throw LocalJobStoreFailureV1.writeFailed
        }
        return data
    }

    static func normalizedStoreFailure(_ error: Error) -> LocalJobStoreFailureV1 {
        if let failure = error as? LocalJobStoreFailureV1 { return failure }
        return mappedFoundationFailure(error)
    }

    func injectProtectedDataFailure(
        at access: LocalJobStoreProtectedDataAccessV1
    ) throws {
        if protectedDataFailureHook(access) {
            throw LocalJobStoreFailureV1.protectedDataUnavailable
        }
    }

    static func mappedFoundationFailure(_ error: Error) -> LocalJobStoreFailureV1 {
        let cocoa = error as NSError
        guard cocoa.domain == NSCocoaErrorDomain else { return .writeFailed }
        switch cocoa.code {
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return .protectedDataUnavailable
        case NSFileWriteOutOfSpaceError, NSFileWriteVolumeReadOnlyError:
            return .storageUnavailable
        default:
            return .writeFailed
        }
    }

    static func mappedPOSIXFailure(_ code: Int32) -> LocalJobStoreFailureV1 {
        switch code {
        case EACCES, EPERM:
            return .protectedDataUnavailable
        case ENOSPC, EDQUOT, EROFS:
            return .storageUnavailable
        default:
            return .writeFailed
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    static func storeVersion(in data: Data) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let version = dictionary["storeVersion"] as? Int else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        return version
    }

    static func isProtectedDataFailure(_ error: Error) -> Bool {
        if let failure = error as? LocalJobStoreFailureV1 {
            return failure == .protectedDataUnavailable
        }
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain
            && (cocoa.code == NSFileReadNoPermissionError
                || cocoa.code == NSFileWriteNoPermissionError)
    }
}

/// The cold writer owns both descriptors until a single checked close attempt.
/// A failed close leaves this object retained by LocalJobStoreV1; it never
/// retries a descriptor number whose ownership is now ambiguous.
private final class ColdEraseCheckedWriteOwnerV1 {
    private var parentDescriptor: Int32?
    private var temporaryDescriptor: Int32?
    private(set) var parentOpenedDescriptor: Int32?
    private(set) var temporaryOpenedDescriptor: Int32?
    private(set) var closeAttempted = false

    func retainParent(_ descriptor: Int32) {
        precondition(parentDescriptor == nil && !closeAttempted)
        parentDescriptor = descriptor
        parentOpenedDescriptor = descriptor
    }

    func retainTemporary(_ descriptor: Int32) {
        precondition(temporaryDescriptor == nil && !closeAttempted)
        temporaryDescriptor = descriptor
        temporaryOpenedDescriptor = descriptor
    }

    func closeChecked() throws {
        guard !closeAttempted else {
            throw LocalJobStoreFailureV1.cleanupFailed
        }
        closeAttempted = true
        let temporary = temporaryDescriptor
        let parent = parentDescriptor
        temporaryDescriptor = nil
        parentDescriptor = nil
        var failed = false
        if let temporary, Darwin.close(temporary) != 0 { failed = true }
        if let parent, Darwin.close(parent) != 0 { failed = true }
        if failed { throw LocalJobStoreFailureV1.cleanupFailed }
    }
}

private struct LegacyLocalJobStoreEnvelopeV0: Decodable {
    let storeVersion: Int
    let jobs: [ResumableLocalJobV1]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storeVersion = try container.decode(Int.self, forKey: .storeVersion)
        guard storeVersion == 0 else {
            throw LocalJobStoreFailureV1.unsupportedSchemaVersion
        }
        jobs = try container.decode([ResumableLocalJobV1].self, forKey: .jobs)
    }

    private enum CodingKeys: String, CodingKey {
        case storeVersion
        case jobs
    }
}

enum C34SceneRestorationLocalJobStoreBoundaryV1 {
    static let insertsJob = false
    static let resumesStoredJob = false
    static let ownsSceneState = false
    static func validate(anchor: DraftResumeAnchorV1) -> Bool { !insertsJob && !resumesStoredJob && !ownsSceneState && C34SceneRestorationLocalJobSchemaBoundaryV1.validate(anchor: anchor) }
}

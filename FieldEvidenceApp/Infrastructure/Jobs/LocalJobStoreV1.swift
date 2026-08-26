import Darwin
import Foundation

actor LocalJobStoreV1: ResumableLocalJobPortV1 {
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

private extension LocalJobStoreV1 {
    func ensureLoaded() throws {
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
        let replacement = try LocalJobStoreEnvelopeV1(jobs: jobs)
        try write(replacement, to: storeURL)
        envelope = replacement
    }

    func persist(
        envelope: LocalJobStoreEnvelopeV1,
        receipt: LocalJobStoreMigrationReceiptV1
    ) throws {
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
        defer { _ = Darwin.close(parentDescriptor) }

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
        var temporaryExists = true
        var didPublish = false
        defer { _ = Darwin.close(temporaryDescriptor) }

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
            guard try Self.readNamedFile(
                url.lastPathComponent,
                parentDescriptor: parentDescriptor,
                expectedIdentity: identity,
                maximumByteCount: LocalJobStoreSchemaV1.maximumStoreBytes
            ) == data else {
                throw LocalJobStoreFailureV1.writeFailed
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

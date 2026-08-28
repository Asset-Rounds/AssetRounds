import Foundation
import Darwin
import XCTest

@testable import FieldEvidenceApp

final class V9_09ConcurrencyScaleTests: XCTestCase {
    private let fileManager = FileManager.default

    func testV9_09G01OffMainWorkersAndDeterministicIdentifiers() async throws {
        let root = try makeRoot("g01")
        defer { try? fileManager.removeItem(at: root) }
        let store = try LocalJobStoreV1(applicationSupportURL: root)
        let runner = try ResumableLocalJobRunnerV1(
            store: store,
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true),
            maximumConcurrency: 2
        )
        let gate = V909Gate()
        let probe = V909ExecutionProbe()
        await runner.register(.hash) { context in
            await probe.enter(onMainThread: pthread_main_np() != 0)
            await gate.wait()
            try await context.publicationBoundary()
            let chunkID = LocalJobChunkIDV1.deterministic(
                jobID: context.job.id,
                index: 0
            )
            try await context.checkpoint(LocalJobCheckpointV1(
                nextChunkIndex: 1,
                completedUnitCount: 1,
                totalUnitCount: 1,
                lastChunkID: chunkID,
                rollingOutputSHA256: Self.digest("b")
            ))
            await probe.leave()
            return ResumableLocalJobResultV1(
                outputSHA256: Self.digest("b"),
                completedUnitCount: 1
            )
        }
        await runner.registerPublisher(.hash) { context in
            .completed(Self.publicationReceipt(context, disposition: .published))
        }

        let workspaceID = uuid(1)
        let jobs = try (1...3).map { index in
            try makeJob(
                workspaceID: workspaceID,
                kind: .hash,
                digest: Self.digest(String(index)),
                stagingPath: "g01/job-\(index)",
                units: 1
            )
        }
        XCTAssertEqual(
            jobs[0].id,
            LocalJobIDV1.deterministic(
                kind: .hash,
                workspaceID: workspaceID,
                immutableInputSHA256: Self.digest("1")
            )
        )
        XCTAssertEqual(
            LocalJobChunkIDV1.deterministic(jobID: jobs[0].id, index: 7),
            LocalJobChunkIDV1.deterministic(jobID: jobs[0].id, index: 7)
        )
        for job in jobs { _ = try await runner.enqueue(job) }
        await probe.waitForActiveCount(2)
        let activeBeforeRelease = await runner.activeJobCount()
        let maximumBeforeRelease = await probe.maximumActive
        XCTAssertEqual(activeBeforeRelease, 2)
        XCTAssertEqual(maximumBeforeRelease, 2)
        await gate.open()
        await runner.waitUntilIdle()

        let observedMainThread = await probe.observedMainThread
        let completionCount = await probe.completionCount
        XCTAssertFalse(observedMainThread)
        XCTAssertEqual(completionCount, 3)
        for job in jobs {
            let loaded = try await runner.job(id: job.id)
            let stored = try XCTUnwrap(loaded)
            XCTAssertEqual(stored.state, .succeeded)
            XCTAssertEqual(stored.attemptCount, 1)
            XCTAssertEqual(stored.outputSHA256, Self.digest("b"))
        }
    }

    func testV9_09A01DurableBoundedCheckpointsResumeAfterRelaunch() async throws {
        let root = try makeRoot("a01")
        defer { try? fileManager.removeItem(at: root) }
        let clock = V909Clock(Date(timeIntervalSinceReferenceDate: 230_205))
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let publishedURL = root.appendingPathComponent("archive-output.bin")
        let publicationCount = V909Counter()
        let job = try makeJob(
            workspaceID: uuid(10),
            kind: .archive,
            digest: Self.digest("a"),
            stagingPath: "a01/archive",
            units: 4
        )

        let firstStore = try LocalJobStoreV1(
            applicationSupportURL: root,
            clock: clock
        )
        let firstRunner = try ResumableLocalJobRunnerV1(
            store: firstStore,
            stagingRootURL: stagingRoot,
            maximumConcurrency: 1
        )
        await firstRunner.register(.archive) { context in
            try await context.checkpoint(LocalJobCheckpointV1(
                nextChunkIndex: 2,
                completedUnitCount: 2,
                totalUnitCount: 4,
                lastChunkID: .deterministic(jobID: context.job.id, index: 1),
                rollingOutputSHA256: Self.digest("c")
            ))
            try await context.checkpoint(LocalJobCheckpointV1(
                nextChunkIndex: 4,
                completedUnitCount: 4,
                totalUnitCount: 4,
                lastChunkID: .deterministic(jobID: context.job.id, index: 3),
                rollingOutputSHA256: Self.digest("d")
            ))
            return .init(outputSHA256: Self.digest("d"), completedUnitCount: 4)
        }
        await firstRunner.registerPublisher(.archive) { _ in
            try Data("durable-effect".utf8).write(to: publishedURL, options: .atomic)
            publicationCount.increment()
            throw V909InjectedFailure.effectBeforeReceipt
        }
        _ = try await firstRunner.enqueue(job)
        await firstRunner.waitUntilIdle()

        let interruptedLoaded = try await firstRunner.job(id: job.id)
        let interrupted = try XCTUnwrap(interruptedLoaded)
        XCTAssertEqual(interrupted.state, .awaitingPublication)
        XCTAssertEqual(interrupted.checkpoint.nextChunkIndex, 4)
        XCTAssertEqual(interrupted.checkpoint.completedUnitCount, 4)
        XCTAssertEqual(interrupted.attemptCount, 1)
        XCTAssertNotNil(interrupted.pendingPublication)
        XCTAssertNil(interrupted.publicationReceipt)
        XCTAssertEqual(try Data(contentsOf: publishedURL), Data("durable-effect".utf8))

        let reopenedStore = try LocalJobStoreV1(
            applicationSupportURL: root,
            clock: clock
        )
        let relaunchedRunner = try ResumableLocalJobRunnerV1(
            store: reopenedStore,
            stagingRootURL: stagingRoot,
            maximumConcurrency: 1
        )
        await relaunchedRunner.registerPublisher(.archive) { context in
            XCTAssertEqual(context.mode, .publishOrAdopt)
            guard try Data(contentsOf: publishedURL) == Data("durable-effect".utf8) else {
                return .absent
            }
            return .completed(Self.publicationReceipt(context, disposition: .adopted))
        }
        try await relaunchedRunner.resumePending()
        await relaunchedRunner.waitUntilIdle()

        let loadedCompleted = try await relaunchedRunner.job(id: job.id)
        let completed = try XCTUnwrap(loadedCompleted)
        XCTAssertEqual(completed.state, .succeeded)
        XCTAssertEqual(completed.attemptCount, 1)
        XCTAssertEqual(completed.outputSHA256, Self.digest("d"))
        XCTAssertEqual(completed.publicationReceipt?.disposition, .adopted)
        let escapedEffectCount = publicationCount.value
        XCTAssertEqual(escapedEffectCount, 1)

        let storeURL = root.appendingPathComponent("local-jobs-v1/jobs.json")
        let firstBytes = try Data(contentsOf: storeURL)
        let finalReopen = try LocalJobStoreV1(applicationSupportURL: root)
        let finalJobs = try await finalReopen.jobs(workspaceID: nil)
        XCTAssertEqual(finalJobs, [completed])
        XCTAssertEqual(try Data(contentsOf: storeURL), firstBytes)
        XCTAssertLessThan(firstBytes.count, LocalJobStoreSchemaV1.maximumStoreBytes)

        let protectedRoot = root.appendingPathComponent("protected-data", isDirectory: true)
        let protectedSeedStore = try LocalJobStoreV1(applicationSupportURL: protectedRoot)
        _ = try await protectedSeedStore.jobs(workspaceID: nil)
        let protectedStore = try LocalJobStoreV1(
            applicationSupportURL: protectedRoot,
            protectedDataFailureHook: { $0 == .read }
        )
        do {
            _ = try await protectedStore.jobs(workspaceID: nil)
            XCTFail("injected protected-data read must fail closed")
        } catch let failure as LocalJobStoreFailureV1 {
            XCTAssertEqual(failure, .protectedDataUnavailable)
        }

        let corruptRoot = root.appendingPathComponent("corrupt-store", isDirectory: true)
        let corruptDirectory = corruptRoot.appendingPathComponent(
            LocalJobStoreSchemaV1.directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: corruptDirectory,
            withIntermediateDirectories: true
        )
        let corruptBytes = Data("{unknown-and-corrupt".utf8)
        try corruptBytes.write(
            to: corruptDirectory.appendingPathComponent(LocalJobStoreSchemaV1.storeFileName)
        )
        let corruptStore = try LocalJobStoreV1(
            applicationSupportURL: corruptRoot,
            clock: clock,
            idSource: V909IDSource(uuid(11))
        )
        let rebuiltJobs = try await corruptStore.jobs(workspaceID: nil)
        XCTAssertTrue(rebuiltJobs.isEmpty)
        let rebuildReceipt = try await corruptStore.migrationReceipt()
        XCTAssertEqual(rebuildReceipt.source, .unknownOrCorrupt)
        XCTAssertEqual(rebuildReceipt.disposition, .quarantinedAndRebuilt)
        XCTAssertEqual(rebuildReceipt.migratedJobCount, 0)
        let quarantinedURL = corruptDirectory
            .appendingPathComponent(LocalJobStoreSchemaV1.quarantineDirectoryName)
            .appendingPathComponent("jobs-\(uuid(11).uuidString.lowercased()).invalid")
        XCTAssertEqual(try Data(contentsOf: quarantinedURL), corruptBytes)

        let destructiveStore = try LocalJobStoreV1(
            applicationSupportURL: root.appendingPathComponent("destructive", isDirectory: true)
        )
        let destructiveRunner = try ResumableLocalJobRunnerV1(
            store: destructiveStore,
            stagingRootURL: root.appendingPathComponent("destructive-staging", isDirectory: true),
            maximumConcurrency: 1
        )
        let destructiveOutput = root.appendingPathComponent("destructive-output", isDirectory: true)
        try fileManager.createDirectory(at: destructiveOutput, withIntermediateDirectories: true)
        await destructiveRunner.register(.archive) { context in
            .init(
                outputSHA256: context.job.immutableInputSHA256,
                completedUnitCount: context.job.checkpoint.totalUnitCount
            )
        }
        await destructiveRunner.registerPublisher(.archive) { context in
            let effectURL = destructiveOutput.appendingPathComponent(
                context.job.id.rawValue.uuidString.lowercased()
            )
            if context.mode == .publishOrAdopt {
                try Data(context.pending.result.outputSHA256.utf8).write(
                    to: effectURL,
                    options: .atomic
                )
                throw V909InjectedFailure.effectBeforeReceipt
            }
            guard (try? Data(contentsOf: effectURL))
                    == Data(context.pending.result.outputSHA256.utf8) else {
                return .absent
            }
            return .completed(Self.publicationReceipt(context, disposition: .adopted))
        }
        let removeWorkspace = uuid(12)
        let removeJob = try makeJob(
            workspaceID: removeWorkspace,
            kind: .archive,
            digest: Self.digest("2"),
            stagingPath: "remove/job",
            units: 1
        )
        _ = try await destructiveRunner.enqueue(removeJob)
        await destructiveRunner.waitUntilIdle()
        let awaitingRemove = try await destructiveRunner.job(id: removeJob.id)
        XCTAssertEqual(awaitingRemove?.state, .awaitingPublication)
        let removeEffectURL = destructiveOutput.appendingPathComponent(
            removeJob.id.rawValue.uuidString.lowercased()
        )
        XCTAssertEqual(
            try Data(contentsOf: removeEffectURL),
            Data(Self.digest("2").utf8)
        )
        try await destructiveRunner.removeJobs(workspaceID: removeWorkspace)
        let removedJob = try await destructiveRunner.job(id: removeJob.id)
        XCTAssertNil(removedJob)
        XCTAssertEqual(
            try Data(contentsOf: removeEffectURL),
            Data(Self.digest("2").utf8)
        )

        let eraseJob = try makeJob(
            workspaceID: uuid(13),
            kind: .archive,
            digest: Self.digest("3"),
            stagingPath: "erase/job",
            units: 1
        )
        _ = try await destructiveRunner.enqueue(eraseJob)
        await destructiveRunner.waitUntilIdle()
        let awaitingErase = try await destructiveRunner.job(id: eraseJob.id)
        XCTAssertEqual(awaitingErase?.state, .awaitingPublication)
        let eraseEffectURL = destructiveOutput.appendingPathComponent(
            eraseJob.id.rawValue.uuidString.lowercased()
        )
        try await destructiveRunner.eraseAll()
        let afterErase = try await destructiveRunner.jobs(workspaceID: nil)
        XCTAssertTrue(afterErase.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: eraseEffectURL),
            Data(Self.digest("3").utf8)
        )
    }

    func testV9_09H01StructuredCancellationCleansStagingWithoutPublishingPartialBytes() async throws {
        let root = try makeRoot("h01")
        defer { try? fileManager.removeItem(at: root) }
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let publishedURL = root.appendingPathComponent("published.bin")
        let store = try LocalJobStoreV1(applicationSupportURL: root)
        let runner = try ResumableLocalJobRunnerV1(
            store: store,
            stagingRootURL: stagingRoot,
            maximumConcurrency: 1
        )
        let gate = V909Gate()
        let probe = V909ExecutionProbe()
        await runner.register(.copy) { context in
            let directory = stagingRoot.appendingPathComponent(
                context.job.stagingRelativePath,
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Data("partial".utf8).write(
                to: directory.appendingPathComponent("partial.bin")
            )
            await probe.enter(onMainThread: pthread_main_np() != 0)
            await gate.wait()
            try await context.publicationBoundary()
            try Data("published".utf8).write(to: publishedURL, options: .atomic)
            await probe.leave()
            return .init(outputSHA256: Self.digest("e"), completedUnitCount: 1)
        }
        await runner.registerPublisher(.copy) { _ in
            XCTFail("pre-publication cancellation must not invoke publisher")
            return .absent
        }
        let job = try makeJob(
            workspaceID: uuid(20),
            kind: .copy,
            digest: Self.digest("e"),
            stagingPath: "h01/copy",
            units: 1
        )
        _ = try await runner.enqueue(job)
        await probe.waitForActiveCount(1)
        _ = try await runner.requestCancellation(id: job.id)
        await gate.open()
        await runner.waitUntilIdle()

        let loadedCancelled = try await runner.job(id: job.id)
        let cancelled = try XCTUnwrap(loadedCancelled)
        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertNil(cancelled.outputSHA256)
        XCTAssertFalse(fileManager.fileExists(atPath: publishedURL.path))
        XCTAssertFalse(fileManager.fileExists(
            atPath: stagingRoot.appendingPathComponent(job.stagingRelativePath).path
        ))
        let activeAfterCancellation = await runner.activeJobCount()
        XCTAssertEqual(activeAfterCancellation, 0)

        // Cancellation that arrives after the atomic publication boundary
        // cannot revoke escaped bytes or manufacture a false CANCELLED state.
        let latePublishedURL = root.appendingPathComponent("late-published.bin")
        let lateGate = V909SynchronousGate()
        let lateProbe = V909SynchronousProbe()
        await runner.register(.finalize) { context in
            try await context.publicationBoundary()
            return .init(
                outputSHA256: Self.digest("9"),
                completedUnitCount: 1
            )
        }
        await runner.registerPublisher(.finalize) { context in
            XCTAssertEqual(context.mode, .publishOrAdopt)
            try Data("durable-readback".utf8).write(
                to: latePublishedURL,
                options: .atomic
            )
            lateProbe.enter(onMainThread: pthread_main_np() != 0)
            lateGate.wait()
            lateProbe.leave()
            throw V909InjectedFailure.effectBeforeReceipt
        }
        let lateJob = try makeJob(
            workspaceID: uuid(21),
            kind: .finalize,
            digest: Self.digest("9"),
            stagingPath: "h01/late-finalize",
            units: 1
        )
        _ = try await runner.enqueue(lateJob)
        XCTAssertTrue(lateProbe.waitForActiveCount(1))
        XCTAssertEqual(
            try Data(contentsOf: latePublishedURL),
            Data("durable-readback".utf8)
        )

        _ = try await store.requestCancellation(id: lateJob.id)
        lateGate.open()
        await runner.waitUntilIdle()

        let loadedAwaitingAdoption = try await runner.job(id: lateJob.id)
        let awaitingAdoption = try XCTUnwrap(loadedAwaitingAdoption)
        XCTAssertEqual(awaitingAdoption.state, .awaitingPublication)
        XCTAssertTrue(awaitingAdoption.pendingPublication?.cancellationRequested == true)
        XCTAssertNil(awaitingAdoption.publicationReceipt)

        let adoptionStore = try LocalJobStoreV1(applicationSupportURL: root)
        let adoptionRunner = try ResumableLocalJobRunnerV1(
            store: adoptionStore,
            stagingRootURL: stagingRoot,
            maximumConcurrency: 1
        )
        await adoptionRunner.registerPublisher(.finalize) { context in
            XCTAssertEqual(context.mode, .adoptOnly)
            guard try Data(contentsOf: latePublishedURL)
                    == Data("durable-readback".utf8) else {
                return .absent
            }
            return .completed(Self.publicationReceipt(
                context,
                disposition: .adopted
            ))
        }
        try await adoptionRunner.resumePending()
        await adoptionRunner.waitUntilIdle()
        let loadedLateResult = try await adoptionRunner.job(id: lateJob.id)
        let lateResult = try XCTUnwrap(loadedLateResult)
        XCTAssertEqual(lateResult.state, .succeeded)
        XCTAssertEqual(lateResult.outputSHA256, Self.digest("9"))
        XCTAssertEqual(lateResult.publicationReceipt?.disposition, .adopted)
        XCTAssertEqual(
            try Data(contentsOf: latePublishedURL),
            Data("durable-readback".utf8)
        )

        let relaunchRoot = root.appendingPathComponent("relaunch-cancel", isDirectory: true)
        let relaunchStaging = root.appendingPathComponent("relaunch-cancel-staging", isDirectory: true)
        let interruptionStore = try LocalJobStoreV1(applicationSupportURL: relaunchRoot)
        let interruptedJob = try makeJob(
            workspaceID: uuid(22), kind: .copy, digest: Self.digest("7"),
            stagingPath: "interrupted/job", units: 1
        )
        _ = try await interruptionStore.enqueue(interruptedJob)
        _ = try await interruptionStore.claimForExecution(id: interruptedJob.id)
        let interruptedStagingURL = relaunchStaging.appendingPathComponent(
            interruptedJob.stagingRelativePath, isDirectory: true
        )
        try fileManager.createDirectory(at: interruptedStagingURL, withIntermediateDirectories: true)
        try Data("partial-before-kill".utf8).write(
            to: interruptedStagingURL.appendingPathComponent("partial.bin")
        )
        _ = try await interruptionStore.requestCancellation(id: interruptedJob.id)
        let relaunchedCancellationStore = try LocalJobStoreV1(applicationSupportURL: relaunchRoot)
        let relaunchedCancellationRunner = try ResumableLocalJobRunnerV1(
            store: relaunchedCancellationStore,
            stagingRootURL: relaunchStaging,
            maximumConcurrency: 1
        )
        try await relaunchedCancellationRunner.resumePending()
        let loadedInterruptedCancellation = try await relaunchedCancellationRunner.job(
            id: interruptedJob.id
        )
        XCTAssertEqual(loadedInterruptedCancellation?.state, .cancelled)
        XCTAssertFalse(fileManager.fileExists(atPath: interruptedStagingURL.path))

        let hostileRoot = root.appendingPathComponent("hostile-symlink", isDirectory: true)
        let hostileStaging = root.appendingPathComponent("hostile-symlink-staging", isDirectory: true)
        let outsideDirectory = root.appendingPathComponent("outside-target", isDirectory: true)
        try fileManager.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        let outsideSentinel = outsideDirectory.appendingPathComponent("must-survive.bin")
        let outsideBytes = Data("outside-must-survive".utf8)
        try outsideBytes.write(to: outsideSentinel)
        let hostileStore = try LocalJobStoreV1(applicationSupportURL: hostileRoot)
        let hostileJob = try makeJob(
            workspaceID: uuid(23), kind: .copy, digest: Self.digest("8"),
            stagingPath: "hostile/job", units: 1
        )
        _ = try await hostileStore.enqueue(hostileJob)
        _ = try await hostileStore.claimForExecution(id: hostileJob.id)
        _ = try await hostileStore.requestCancellation(id: hostileJob.id)
        let hostileParent = hostileStaging.appendingPathComponent("hostile", isDirectory: true)
        try fileManager.createDirectory(at: hostileParent, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: hostileParent.appendingPathComponent("job"),
            withDestinationURL: outsideDirectory
        )
        let hostileRelaunchStore = try LocalJobStoreV1(applicationSupportURL: hostileRoot)
        let hostileRunner = try ResumableLocalJobRunnerV1(
            store: hostileRelaunchStore,
            stagingRootURL: hostileStaging,
            maximumConcurrency: 1
        )
        do {
            try await hostileRunner.resumePending()
            XCTFail("symlink staging cleanup must fail closed")
        } catch {
            XCTAssertTrue(error is ResumableLocalJobRunnerFailureV1)
        }
        XCTAssertEqual(try Data(contentsOf: outsideSentinel), outsideBytes)
        let hostilePersisted = try await hostileRunner.job(id: hostileJob.id)
        XCTAssertEqual(hostilePersisted?.state, .cancellationRequested)
    }

    @MainActor
    func testV9_09I01GenerationLeaseFencesStalePublicationAndBalancesConcurrency() async throws {
        let root = try makeRoot("i01")
        defer { try? fileManager.removeItem(at: root) }
        let generationSupport = root.appendingPathComponent(
            "generation-support",
            isDirectory: true
        )
        try fileManager.createDirectory(at: generationSupport, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: generationSupport)
        var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let acceptedEpoch = try XCTUnwrap(session?.generationEpoch)
        let successorEpoch = try GenerationEpochV1(
            generationID: uuid(30),
            generationManifestSHA256: Self.digest("f")
        )
        let replacementEpoch = try GenerationEpochV1(
            generationID: uuid(32),
            generationManifestSHA256: Self.digest("e")
        )
        let acceptedAuthority = V909GenerationCommitAuthority(accepted: acceptedEpoch)
        let publicationGate = V909SynchronousGate()
        acceptedAuthority.blockNextCommit(on: publicationGate)
        let adapter = GenerationLocalJobPublicationAdapterV1(
            currentGenerationEpoch: { acceptedAuthority.currentEpoch() },
            withAuthorizedCommit: { epoch, effect in
                try acceptedAuthority.withAuthorizedCommit(
                    expected: epoch,
                    effect: effect
                )
            }
        )
        let leaseSupport = root.appendingPathComponent("lease-support", isDirectory: true)
        try fileManager.createDirectory(at: leaseSupport, withIntermediateDirectories: true)
        let registry = try GenerationLeaseRegistryV1(
            applicationSupportURL: leaseSupport,
            ownerID: uuid(31),
            makeLeaseID: { UUID(uuidString: "00000000-0000-0000-0000-000000000020")! },
            now: { Date(timeIntervalSinceReferenceDate: 230_205) }
        )
        let store = try LocalJobStoreV1(applicationSupportURL: root)
        let runner = try ResumableLocalJobRunnerV1(
            store: store,
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true),
            generationLeaseRegistry: registry,
            generationPublicationAdapter: adapter,
            maximumConcurrency: 1
        )
        let gate = V909Gate()
        let probe = V909ExecutionProbe()
        let publicationCount = V909Counter()
        let publishedURL = root.appendingPathComponent("accepted-output.bin")
        await runner.register(.render) { context in
            await probe.enter(onMainThread: pthread_main_np() != 0)
            await gate.wait()
            await probe.leave()
            return .init(
                outputSHA256: context.job.immutableInputSHA256,
                completedUnitCount: 1
            )
        }
        await runner.registerPublisher(.render) { context in
            if let epoch = context.job.generationEpoch {
                XCTAssertEqual(try registry.activeEpochs(), Set([epoch]))
            } else {
                XCTFail("generation-bound publication lost its epoch")
            }
            try Data(context.pending.result.outputSHA256.utf8).write(
                to: publishedURL,
                options: .atomic
            )
            publicationCount.increment()
            return .completed(Self.publicationReceipt(
                context,
                disposition: .published
            ))
        }
        let staleJob = try makeJob(
            workspaceID: uuid(33),
            kind: .render,
            digest: Self.digest("0"),
            stagingPath: "i01/render",
            units: 1,
            generationEpoch: acceptedEpoch
        )
        _ = try await runner.enqueue(staleJob)
        await probe.waitForActiveCount(1)
        XCTAssertEqual(try registry.activeEpochs(), Set([acceptedEpoch]))
        acceptedAuthority.replaceImmediately(with: successorEpoch)
        await gate.open()
        await runner.waitUntilIdle()

        let loadedFenced = try await runner.job(id: staleJob.id)
        let fenced = try XCTUnwrap(loadedFenced)
        XCTAssertEqual(fenced.state, .awaitingPublication)
        XCTAssertNotNil(fenced.pendingPublication)
        XCTAssertNil(fenced.publicationReceipt)
        XCTAssertNil(fenced.outputSHA256)
        XCTAssertFalse(fileManager.fileExists(atPath: publishedURL.path))
        XCTAssertTrue(try registry.activeEpochs().isEmpty)
        let stalePublicationCount = publicationCount.value
        XCTAssertEqual(stalePublicationCount, 0)

        let successorJob = try makeJob(
            workspaceID: uuid(33),
            kind: .render,
            digest: Self.digest("1"),
            stagingPath: "i01/render-successor",
            units: 1,
            generationEpoch: successorEpoch
        )
        XCTAssertNotEqual(successorJob.id, staleJob.id)
        _ = try await runner.enqueue(successorJob)
        XCTAssertTrue(acceptedAuthority.commitEntered.waitForOpen())
        let replacementWorker = V909GenerationReplacementWorker()
        async let replacement: Void = replacementWorker.replace(
            acceptedAuthority,
            with: replacementEpoch
        )
        XCTAssertTrue(acceptedAuthority.replacementAttempted.waitForOpen())
        XCTAssertFalse(acceptedAuthority.replacementCompleted.isOpen)
        XCTAssertEqual(acceptedAuthority.currentEpoch(), successorEpoch)
        XCTAssertEqual(try registry.activeEpochs(), Set([successorEpoch]))
        publicationGate.open()
        _ = await replacement
        await runner.waitUntilIdle()
        let loadedSuccessor = try await runner.job(id: successorJob.id)
        let successor = try XCTUnwrap(loadedSuccessor)
        XCTAssertEqual(successor.state, .succeeded)
        XCTAssertEqual(successor.generationEpoch, successorEpoch)
        XCTAssertEqual(successor.publicationReceipt?.disposition, .published)
        XCTAssertEqual(
            try Data(contentsOf: publishedURL),
            Data(Self.digest("1").utf8)
        )
        XCTAssertEqual(acceptedAuthority.currentEpoch(), replacementEpoch)
        XCTAssertTrue(acceptedAuthority.replacementCompleted.isOpen)
        XCTAssertTrue(try registry.activeEpochs().isEmpty)
        let activeAfterFence = await runner.activeJobCount()
        let maximumLeaseConcurrency = await probe.maximumActive
        let acceptedPublicationCount = publicationCount.value
        XCTAssertEqual(activeAfterFence, 0)
        XCTAssertLessThanOrEqual(maximumLeaseConcurrency, 1)
        XCTAssertEqual(acceptedPublicationCount, 1)
        session = nil
    }

    func testV9_09R01RepresentativeScaleMatrixMeetsBoundedConcurrencyMemoryAndLatencyBudgets() async throws {
        try JobScaleBudgetPolicyV1.validateFrozenPolicy()
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertTrue(corpus.synthetic)
        XCTAssertFalse(corpus.containsCustomerData)
        XCTAssertFalse(corpus.containsSecrets)
        XCTAssertEqual(corpus.generator.seed, 230_205)
        XCTAssertEqual(corpus.hostileCases.count, 5)
        XCTAssertEqual(corpus.interruptionBoundaries.count, 3)
        XCTAssertEqual(corpus.recoveryCases.count, 4)
        XCTAssertEqual(
            Set(corpus.scaleCases.map(\.fixture)),
            Set(JobScaleFixtureV1.allCases)
        )
        for (vectorIndex, vector) in corpus.scaleCases.enumerated() {
            let budget = JobScaleBudgetPolicyV1.budget(for: vector.fixture)
            XCTAssertEqual(vector.assetCount, budget.assetCount)
            XCTAssertEqual(vector.proxyByteCount, budget.proxyByteCount)
            let expectedChunks = vector.proxyByteCount > 0
                ? Int((vector.proxyByteCount + Int64(budget.chunkByteCount) - 1)
                    / Int64(budget.chunkByteCount))
                : max(1, (vector.assetCount + 511) / 512)
            XCTAssertGreaterThan(expectedChunks, 0)
            XCTAssertEqual(vector.expectedLogicalChunkCount, expectedChunks)
            XCTAssertEqual(vector.measurementRepetitions, 20)
            if vector.proxyByteCount > 0 {
                XCTAssertEqual(vector.proxyBacking, "FILE_BACKED_SPARSE")
            }
            let root = try makeRoot("r01-\(vectorIndex)")
            defer { try? fileManager.removeItem(at: root) }
            let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
            let sparseURL = root.appendingPathComponent("large-media-proxy.bin")
            if vector.proxyByteCount > 0 {
                XCTAssertTrue(fileManager.createFile(atPath: sparseURL.path, contents: nil))
                let sparse = try FileHandle(forWritingTo: sparseURL)
                try sparse.truncate(atOffset: UInt64(vector.proxyByteCount))
                try sparse.close()
                let sparseSize = (
                    try fileManager.attributesOfItem(atPath: sparseURL.path)[.size]
                        as? NSNumber
                )?.int64Value
                XCTAssertEqual(
                    sparseSize,
                    vector.proxyByteCount
                )
            }
            let baselineFootprint = try Self.processPhysicalFootprintBytes()
            let metrics = V909ScaleMetrics(baselineFootprint: baselineFootprint)
            let startBarrier = V909StartBarrier(
                participantCount: budget.maximumConcurrency
            )
            let store = try LocalJobStoreV1(applicationSupportURL: root)
            let runner = try ResumableLocalJobRunnerV1(
                store: store,
                stagingRootURL: stagingRoot,
                maximumConcurrency: budget.maximumConcurrency
            )
            await runner.register(.mediaProcessing) { context in
                metrics.begin(
                    jobID: context.job.id,
                    at: DispatchTime.now().uptimeNanoseconds,
                    onMainThread: pthread_main_np() != 0
                )
                await startBarrier.arriveAndWait()
                let totalUnits = context.job.checkpoint.totalUnitCount
                var completedUnits = 0
                var rolling = UInt64(0)
                let sparse: FileHandle? = vector.proxyByteCount > 0
                    ? try FileHandle(forReadingFrom: sparseURL)
                    : nil
                defer { try? sparse?.close() }
                for chunkIndex in 0..<expectedChunks {
                    try await context.cancellationBoundary()
                    let buffer: Data
                    if let sparse {
                        try sparse.seek(
                            toOffset: UInt64(chunkIndex * budget.chunkByteCount)
                        )
                        buffer = try sparse.read(upToCount: budget.chunkByteCount) ?? Data()
                        completedUnits += 1
                    } else {
                        let lower = chunkIndex * 512
                        let upper = min(vector.assetCount, lower + 512)
                        buffer = Data(repeating: UInt8(chunkIndex & 0xff), count: budget.chunkByteCount)
                        for assetIndex in lower..<upper {
                            rolling &+= UInt64(assetIndex) &* 1_099_511_628_211
                        }
                        completedUnits = upper
                    }
                    rolling ^= UInt64(buffer.count)
                    let footprint = try withExtendedLifetime(buffer) {
                        try Self.processPhysicalFootprintBytes()
                    }
                    metrics.sample(
                        jobID: context.job.id,
                        at: DispatchTime.now().uptimeNanoseconds,
                        physicalFootprint: footprint
                    )
                    try await context.checkpoint(LocalJobCheckpointV1(
                        nextChunkIndex: chunkIndex + 1,
                        completedUnitCount: completedUnits,
                        totalUnitCount: totalUnits,
                        lastChunkID: .deterministic(
                            jobID: context.job.id,
                            index: chunkIndex
                        ),
                        rollingOutputSHA256: context.job.immutableInputSHA256
                    ))
                }
                XCTAssertNotEqual(rolling, UInt64.max)
                return .init(
                    outputSHA256: context.job.immutableInputSHA256,
                    completedUnitCount: totalUnits
                )
            }
            await runner.registerPublisher(.mediaProcessing) { context in
                metrics.finish(
                    jobID: context.job.id,
                    at: DispatchTime.now().uptimeNanoseconds
                )
                return .completed(Self.publicationReceipt(
                    context,
                    disposition: .published
                ))
            }

            var jobIDs: [LocalJobIDV1] = []
            let repetitionCount = vector.measurementRepetitions
            for batchStart in stride(
                from: 0,
                to: repetitionCount,
                by: budget.maximumConcurrency
            ) {
                let batchEnd = min(
                    repetitionCount,
                    batchStart + budget.maximumConcurrency
                )
                for repetition in batchStart..<batchEnd {
                    let digest = scaleDigest((vectorIndex + 1) * 1_000 + repetition)
                    let job = try makeJob(
                        workspaceID: uuid(40 + vectorIndex),
                        kind: .mediaProcessing,
                        digest: digest,
                        stagingPath: "r01/\(vectorIndex)/\(repetition)",
                        units: vector.proxyByteCount > 0 ? expectedChunks : vector.assetCount
                    )
                    metrics.enqueued(
                        jobID: job.id,
                        at: DispatchTime.now().uptimeNanoseconds
                    )
                    jobIDs.append(job.id)
                    _ = try await runner.enqueue(job)
                }
                try await waitForIdle(runner, timeout: .seconds(60))
            }
            let snapshot = metrics.snapshot()
            XCTAssertEqual(snapshot.latenciesMilliseconds.count, repetitionCount)
            XCTAssertEqual(snapshot.hangCount, 0)
            XCTAssertFalse(snapshot.observedMainThread)
            XCTAssertLessThanOrEqual(snapshot.maximumActive, budget.maximumConcurrency)
            XCTAssertGreaterThanOrEqual(
                snapshot.maximumActive,
                min(budget.maximumConcurrency, repetitionCount)
            )
            XCTAssertLessThanOrEqual(
                snapshot.maximumInitialStallMilliseconds,
                budget.maximumInitialStallMilliseconds
            )
            XCTAssertLessThanOrEqual(
                snapshot.maximumHeartbeatMilliseconds,
                budget.progressHeartbeatMilliseconds
            )
            let sorted = snapshot.latenciesMilliseconds.sorted()
            let p50 = percentile(sorted, 0.50)
            let p95 = percentile(sorted, 0.95)
            XCTAssertLessThanOrEqual(p50, budget.p50LatencyMilliseconds, "\(vector.fixture)")
            XCTAssertLessThanOrEqual(p95, budget.p95LatencyMilliseconds, "\(vector.fixture)")
            XCTAssertLessThanOrEqual(
                snapshot.maximumPhysicalFootprintDeltaBytes,
                budget.maximumResidentMemoryBytes
            )
            for jobID in jobIDs {
                let loaded = try await runner.job(id: jobID)
                XCTAssertEqual(loaded?.state, .succeeded)
                XCTAssertNotNil(loaded?.publicationReceipt)
            }
        }
    }

    private func makeRoot(_ label: String) throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_09ConcurrencyScaleTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func makeJob(
        workspaceID: UUID,
        kind: ResumableLocalJobKindV1,
        digest: String,
        stagingPath: String,
        units: Int,
        generationEpoch: GenerationEpochV1? = nil
    ) throws -> ResumableLocalJobV1 {
        try ResumableLocalJobV1(
            workspaceID: workspaceID,
            kind: kind,
            immutableInputSHA256: digest,
            stagingRelativePath: stagingPath,
            generationEpoch: generationEpoch,
            createdAt: Date(timeIntervalSinceReferenceDate: 230_205),
            checkpoint: LocalJobCheckpointV1(
                nextChunkIndex: 0,
                completedUnitCount: 0,
                totalUnitCount: units
            )
        )
    }

    private func loadCorpus() throws -> V909Corpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P02C05ConcurrencyScaleCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Concurrency"
            ) ?? bundle.url(
                forResource: "V21P02C05ConcurrencyScaleCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(V909Corpus.self, from: Data(contentsOf: url))
    }

    private func percentile(_ sorted: [Int], _ value: Double) -> Int {
        sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * value)) - 1)]
    }

    private func waitForIdle(
        _ runner: ResumableLocalJobRunnerV1,
        timeout: Duration
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while await runner.activeJobCount() > 0 {
            guard clock.now < deadline else {
                throw V909InjectedFailure.timeout
            }
            try await clock.sleep(for: .milliseconds(10))
        }
    }

    private func uuid(_ value: Int) -> UUID {
        let suffix = String(format: "%012x", value)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    private static func digest(_ character: String) -> String {
        String(repeating: character, count: 64)
    }

    private func scaleDigest(_ value: Int) -> String {
        String(format: "%064x", value)
    }

    private static func processPhysicalFootprintBytes() throws -> Int64 {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard status == KERN_SUCCESS else {
            throw V909InjectedFailure.memorySampleFailed
        }
        return Int64(information.phys_footprint)
    }

    private static func publicationReceipt(
        _ context: ResumableLocalJobPublicationContextV1,
        disposition: LocalJobPublicationDispositionV1
    ) -> LocalJobPublicationReceiptV1 {
        LocalJobPublicationReceiptV1(
            jobID: context.job.id,
            attemptCount: context.pending.attemptCount,
            kind: context.job.kind,
            outputSHA256: context.pending.result.outputSHA256,
            disposition: disposition,
            readBackAt: Date(timeIntervalSinceReferenceDate: 230_206)
        )
    }
}

private actor V909Gate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private actor V909ExecutionProbe {
    private(set) var active = 0
    private(set) var maximumActive = 0
    private(set) var completionCount = 0
    private(set) var observedMainThread = false

    func enter(onMainThread: Bool) {
        active += 1
        maximumActive = max(maximumActive, active)
        observedMainThread = observedMainThread || onMainThread
    }

    func leave() {
        active -= 1
        completionCount += 1
    }

    func waitForActiveCount(_ expected: Int) async {
        for _ in 0..<20_000 {
            if active >= expected { return }
            await Task.yield()
        }
    }
}

private final class V909Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }
    func increment() { lock.withLock { storedValue += 1 } }
}

private final class V909SynchronousGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpenStorage = false

    func wait() {
        condition.lock()
        while !isOpenStorage { condition.wait() }
        condition.unlock()
    }

    func open() {
        condition.lock()
        isOpenStorage = true
        condition.broadcast()
        condition.unlock()
    }

    var isOpen: Bool {
        condition.lock()
        defer { condition.unlock() }
        return isOpenStorage
    }

    func waitForOpen() -> Bool {
        let deadline = Date().addingTimeInterval(5)
        condition.lock()
        defer { condition.unlock() }
        while !isOpenStorage {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }
}

private final class V909SynchronousProbe: @unchecked Sendable {
    private let condition = NSCondition()
    private var active = 0
    private var observedMainThread = false

    func enter(onMainThread: Bool) {
        condition.lock()
        active += 1
        observedMainThread = observedMainThread || onMainThread
        condition.broadcast()
        condition.unlock()
    }

    func leave() {
        condition.lock()
        active = max(0, active - 1)
        condition.broadcast()
        condition.unlock()
    }

    func waitForActiveCount(_ expected: Int) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        condition.lock()
        defer { condition.unlock() }
        while active < expected {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }
}

private actor V909StartBarrier {
    private let participantCount: Int
    private var arrivals = 0
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func arriveAndWait() async {
        guard !isOpen else { return }
        arrivals += 1
        if arrivals >= participantCount {
            isOpen = true
            let waiting = continuations
            continuations.removeAll()
            waiting.forEach { $0.resume() }
            return
        }
        await withCheckedContinuation { continuations.append($0) }
    }
}

private final class V909GenerationCommitAuthority: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var accepted: GenerationEpochV1
    private var nextCommitGate: V909SynchronousGate?
    let commitEntered = V909SynchronousGate()
    let replacementAttempted = V909SynchronousGate()
    let replacementCompleted = V909SynchronousGate()

    init(accepted: GenerationEpochV1) {
        self.accepted = accepted
    }

    func currentEpoch() -> GenerationEpochV1 {
        lock.lock()
        defer { lock.unlock() }
        return accepted
    }

    func blockNextCommit(on gate: V909SynchronousGate) {
        lock.lock()
        nextCommitGate = gate
        lock.unlock()
    }

    func replaceImmediately(with successor: GenerationEpochV1) {
        lock.lock()
        accepted = successor
        lock.unlock()
    }

    func replaceDuringCommit(with successor: GenerationEpochV1) {
        replacementAttempted.open()
        lock.lock()
        accepted = successor
        lock.unlock()
        replacementCompleted.open()
    }

    func withAuthorizedCommit(
        expected: GenerationEpochV1,
        effect: @escaping @Sendable () throws -> LocalJobPublicationOutcomeV1
    ) throws -> LocalJobPublicationOutcomeV1 {
        lock.lock()
        defer { lock.unlock() }
        guard expected == accepted else {
            throw GenerationLocalJobPublicationFailureV1.staleGeneration
        }
        if let gate = nextCommitGate {
            nextCommitGate = nil
            commitEntered.open()
            gate.wait()
        }
        let outcome = try effect()
        guard expected == accepted else {
            throw GenerationLocalJobPublicationFailureV1.staleGeneration
        }
        return outcome
    }
}

private actor V909GenerationReplacementWorker {
    func replace(
        _ authority: V909GenerationCommitAuthority,
        with successor: GenerationEpochV1
    ) {
        authority.replaceDuringCommit(with: successor)
    }
}

private struct V909ScaleSnapshot: Sendable {
    let latenciesMilliseconds: [Int]
    let maximumActive: Int
    let maximumInitialStallMilliseconds: Int
    let maximumHeartbeatMilliseconds: Int
    let maximumPhysicalFootprintDeltaBytes: Int64
    let observedMainThread: Bool
    let hangCount: Int
}

private final class V909ScaleMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private let baselineFootprint: Int64
    private var enqueuedAt: [LocalJobIDV1: UInt64] = [:]
    private var startedAt: [LocalJobIDV1: UInt64] = [:]
    private var lastHeartbeatAt: [LocalJobIDV1: UInt64] = [:]
    private var completedJobIDs: Set<LocalJobIDV1> = []
    private var latenciesMilliseconds: [Int] = []
    private var active = 0
    private var maximumActive = 0
    private var maximumInitialStallMilliseconds = 0
    private var maximumHeartbeatMilliseconds = 0
    private var maximumPhysicalFootprintDeltaBytes: Int64 = 0
    private var observedMainThread = false

    init(baselineFootprint: Int64) {
        self.baselineFootprint = baselineFootprint
    }

    func enqueued(jobID: LocalJobIDV1, at time: UInt64) {
        lock.withLock { enqueuedAt[jobID] = time }
    }

    func begin(jobID: LocalJobIDV1, at time: UInt64, onMainThread: Bool) {
        lock.withLock {
            active += 1
            maximumActive = max(maximumActive, active)
            observedMainThread = observedMainThread || onMainThread
            startedAt[jobID] = time
            lastHeartbeatAt[jobID] = time
            if let queued = enqueuedAt[jobID] {
                maximumInitialStallMilliseconds = max(
                    maximumInitialStallMilliseconds,
                    Self.milliseconds(from: queued, to: time)
                )
            }
        }
    }

    func sample(jobID: LocalJobIDV1, at time: UInt64, physicalFootprint: Int64) {
        lock.withLock {
            if let previous = lastHeartbeatAt[jobID] {
                maximumHeartbeatMilliseconds = max(
                    maximumHeartbeatMilliseconds,
                    Self.milliseconds(from: previous, to: time)
                )
            }
            lastHeartbeatAt[jobID] = time
            maximumPhysicalFootprintDeltaBytes = max(
                maximumPhysicalFootprintDeltaBytes,
                max(0, physicalFootprint - baselineFootprint)
            )
        }
    }

    func finish(jobID: LocalJobIDV1, at time: UInt64) {
        lock.withLock {
            active = max(0, active - 1)
            if let heartbeat = lastHeartbeatAt[jobID] {
                maximumHeartbeatMilliseconds = max(
                    maximumHeartbeatMilliseconds,
                    Self.milliseconds(from: heartbeat, to: time)
                )
            }
            if let queued = enqueuedAt[jobID] {
                latenciesMilliseconds.append(Self.milliseconds(from: queued, to: time))
            }
            completedJobIDs.insert(jobID)
            startedAt.removeValue(forKey: jobID)
            lastHeartbeatAt.removeValue(forKey: jobID)
        }
    }

    func snapshot() -> V909ScaleSnapshot {
        lock.withLock {
            V909ScaleSnapshot(
                latenciesMilliseconds: latenciesMilliseconds,
                maximumActive: maximumActive,
                maximumInitialStallMilliseconds: maximumInitialStallMilliseconds,
                maximumHeartbeatMilliseconds: maximumHeartbeatMilliseconds,
                maximumPhysicalFootprintDeltaBytes: maximumPhysicalFootprintDeltaBytes,
                observedMainThread: observedMainThread,
                hangCount: enqueuedAt.keys.reduce(into: 0) { count, jobID in
                    if !completedJobIDs.contains(jobID) { count += 1 }
                }
            )
        }
    }

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Int {
        Int((end &- start) / 1_000_000)
    }
}

private struct V909Clock: ApplicationClock {
    let value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { value }
}

private struct V909IDSource: ApplicationIDSource {
    let value: UUID
    init(_ value: UUID) { self.value = value }
    func makeID() -> UUID { value }
}

private enum V909InjectedFailure: Error {
    case effectBeforeReceipt
    case memorySampleFailed
    case timeout
}

extension V9_09ConcurrencyScaleTests {
    func testC36AttachmentJobsUseBoundedDedicatedKind() {
        XCTAssertTrue(ResumableLocalJobKindV1.allCases.contains(.draftAttachmentProcessing))
        XCTAssertEqual(
            JobScaleBudgetPolicyV1.draftAttachmentMaximumConcurrency,
            JobScaleBudgetPolicyV1.maximumRunnerConcurrency
        )
        XCTAssertGreaterThan(JobScaleBudgetPolicyV1.draftAttachmentChunkByteCount, 0)
        XCTAssertGreaterThan(JobScaleBudgetPolicyV1.draftAttachmentRetryLimit, 0)
    }
}

private struct V909Corpus: Decodable, Sendable {
    let schemaVersion: Int
    let synthetic: Bool
    let containsCustomerData: Bool
    let containsSecrets: Bool
    let generator: Generator
    let scaleCases: [Vector]
    let hostileCases: [String]
    let interruptionBoundaries: [String]
    let recoveryCases: [String]

    struct Generator: Decodable, Sendable {
        let seed: Int
    }

    struct Vector: Decodable, Sendable {
        let fixture: JobScaleFixtureV1
        let assetCount: Int
        let proxyByteCount: Int64
        let expectedLogicalChunkCount: Int
        let measurementRepetitions: Int
        let proxyBacking: String?
    }
}

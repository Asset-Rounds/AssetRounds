import Foundation
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_10LifecycleBoundaryTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    private let fileManager = FileManager.default

    func testV9_10G01ProtectedDataAndSceneLifecycleMatrix() async throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(
            corpus.fixtureIdentity,
            "V21-P02-C06-LIFECYCLE-BOUNDARY-CORPUS-V1"
        )
        XCTAssertEqual(corpus.lifecycleEvents.count, 5)

        let port = V910LifecyclePortProbe()
        let coordinator = try await DeviceLifecycleCoordinatorV1.bootstrap(
            jobs: port,
            initialState: .initiallyActive
        )

        var transition = try await coordinator.handle(.sceneBecameInactive)
        XCTAssertEqual(transition.current.scene, .inactive)
        XCTAssertEqual(transition.action, .none)

        transition = try await coordinator.handle(.protectedDataBecameUnavailable)
        XCTAssertEqual(transition.current.protectedData, .unavailable)
        XCTAssertEqual(transition.action, .suspend(.protectedDataUnavailable))
        let afterProtectedSuspend = await port.actions()
        XCTAssertEqual(afterProtectedSuspend, [.suspend(.protectedDataUnavailable)])

        transition = try await coordinator.handle(.sceneEnteredBackground)
        XCTAssertEqual(transition.current.scene, .background)
        XCTAssertEqual(transition.action, .suspend(.sceneBackground))
        transition = try await coordinator.handle(.sceneEnteredBackground)
        XCTAssertEqual(transition.action, .none)
        transition = try await coordinator.handle(.sceneBecameInactive)
        XCTAssertEqual(transition.current.scene, .inactive)
        XCTAssertEqual(transition.action, .none)

        transition = try await coordinator.handle(.protectedDataBecameAvailable)
        XCTAssertEqual(transition.action, .resume(.protectedDataUnavailable))
        XCTAssertEqual(transition.current.scene, .inactive)
        transition = try await coordinator.handle(.sceneBecameActive)
        XCTAssertEqual(transition.action, .resume(.sceneBackground))
        transition = try await coordinator.handle(.sceneBecameActive)
        XCTAssertEqual(transition.action, .none)
        let finalState = await coordinator.currentState()
        XCTAssertEqual(finalState, .initiallyActive)
        let finalActions = await port.actions()
        XCTAssertEqual(
            finalActions,
            [
                .suspend(.protectedDataUnavailable),
                .suspend(.sceneBackground),
                .resume(.protectedDataUnavailable),
                .resume(.sceneBackground),
            ]
        )

        let conservativePort = V910LifecyclePortProbe()
        let conservative = try await DeviceLifecycleCoordinatorV1.bootstrap(
            jobs: conservativePort
        )
        let initialConservativeState = await conservative.currentState()
        XCTAssertEqual(initialConservativeState, .initiallyConservative)
        let bootstrapActions = await conservativePort.actions()
        XCTAssertEqual(
            bootstrapActions,
            [.suspend(.protectedDataUnavailable)],
            "fail-closed bootstrap must suspend before returning"
        )
        let unlockTransition = try await conservative.handle(.protectedDataBecameAvailable)
        XCTAssertEqual(unlockTransition.action, .resume(.protectedDataUnavailable))
        let activeTransition = try await conservative.handle(.sceneBecameActive)
        XCTAssertEqual(activeTransition.action, .resume(.sceneBackground))
        let recoveredState = await conservative.currentState()
        XCTAssertEqual(recoveredState, .initiallyActive)
        let recoveredActions = await conservativePort.actions()
        XCTAssertEqual(
            recoveredActions,
            [
                .suspend(.protectedDataUnavailable),
                .resume(.protectedDataUnavailable),
                .resume(.sceneBackground),
            ]
        )
    }

    func testV9_10A01LowSpacePreflightRefusesBeforeCanonicalMutation() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(
            corpus.storage.canonicalMutationAllowanceBytes,
            WorkspaceStorageEstimateV1.canonicalMutationAllowanceBytes
        )
        let root = try makeRoot("a01")
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let ownedRoots = try makeOwnedRoots(applicationSupportURL: root)
        let ownedRootURL = try XCTUnwrap(
            ownedRoots.first(where: { $0.kind == .data })?.url
        )
        let capacity = V910Int64Box(0)
        let ledger = try OwnedStorageLedgerV1(
            rootURLs: ownedRoots,
            capacityProvider: { _ in capacity.value }
        )
        XCTAssertThrowsError(
            try OwnedStorageLedgerV1(
                rootURLs: Array(ownedRoots.dropLast()),
                capacityProvider: { _ in 1_000_000 }
            )
        ) { error in
            XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .invalidRoot)
        }
        let adapter = V910WriterAdapter()
        let writer = try V910WriterHarness(adapter: adapter, storageAdmission: ledger)
        let request = try writer.request(mutationByte: 11)
        let required = try WorkspaceStorageEstimateV1.requiredBytes(for: request.command)

        capacity.value = required - 1
        XCTAssertThrowsError(try writer.writer.execute(request)) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .storageAdmissionFailed)
        }
        XCTAssertEqual(adapter.applyCount, 0)
        XCTAssertEqual(try writer.writer.currentRevision().revision, 0)
        XCTAssertEqual(ledger.snapshot().reservedByteCount, 0)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: ownedRootURL.path), [])

        capacity.value = required
        let outcome = try writer.writer.execute(request)
        XCTAssertEqual(outcome.after.revision, 1)
        XCTAssertEqual(adapter.applyCount, 1)
        XCTAssertEqual(ledger.snapshot().reservedByteCount, 0)

        capacity.value = 10_000_000
        let sharedMutationID = try MutationIDV1(rawValue: uuid(13))
        let firstScopedAttempt = try OwnedStorageAttemptIDV1(
            workspaceID: WorkspaceID(rawValue: uuid(14)),
            generationID: uuid(16),
            mutationID: sharedMutationID
        )
        let secondScopedAttempt = try OwnedStorageAttemptIDV1(
            workspaceID: WorkspaceID(rawValue: uuid(15)),
            generationID: uuid(17),
            mutationID: sharedMutationID
        )
        let generationScopedAttempt = try OwnedStorageAttemptIDV1(
            workspaceID: WorkspaceID(rawValue: uuid(14)),
            generationID: uuid(18),
            mutationID: sharedMutationID
        )
        XCTAssertNotEqual(firstScopedAttempt, secondScopedAttempt)
        XCTAssertNotEqual(firstScopedAttempt, generationScopedAttempt)
        let firstScopedReservation = try ledger.reserve(
            attemptID: firstScopedAttempt,
            requiredBytes: 4_096
        )
        let secondScopedReservation = try ledger.reserve(
            attemptID: secondScopedAttempt,
            requiredBytes: 8_192
        )
        let generationScopedReservation = try ledger.reserve(
            attemptID: generationScopedAttempt,
            requiredBytes: 2_048
        )
        XCTAssertEqual(ledger.snapshot().activeReservationCount, 3)
        XCTAssertEqual(ledger.snapshot().reservedByteCount, 14_336)
        ledger.release(reservation: firstScopedReservation)
        XCTAssertEqual(ledger.snapshot().activeReservationCount, 2)
        XCTAssertEqual(ledger.snapshot().reservedByteCount, 10_240)
        XCTAssertEqual(
            try ledger.reserve(attemptID: secondScopedAttempt, requiredBytes: 8_192),
            secondScopedReservation
        )
        ledger.release(reservation: secondScopedReservation)
        ledger.release(reservation: generationScopedReservation)

        let unavailable = try OwnedStorageLedgerV1(
            rootURLs: ownedRoots,
            capacityProvider: { _ in nil }
        )
        XCTAssertThrowsError(
            try unavailable.reserve(
                attemptID: try storageAttempt(
                    workspaceSeed: 12,
                    generationSeed: 112,
                    mutationSeed: 212
                ),
                requiredBytes: 1
            )
        ) { XCTAssertEqual($0 as? OwnedStorageLedgerFailureV1, .capacityUnavailable) }
    }

    func testV9_10H01LockDuringOperationFailsRecoverablyWithoutPartialSuccess() async throws {
        let root = try makeRoot("h01")
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let protectedFailure = V910ProtectedDataHook()
        let store = try LocalJobStoreV1(
            applicationSupportURL: root,
            protectedDataFailureHook: { protectedFailure.shouldFail($0) }
        )
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let canonicalURL = root.appendingPathComponent("canonical.bin")
        let gate = V910Gate()
        let attempts = V910IntBox(0)
        let runner = try ResumableLocalJobRunnerV1(
            store: store,
            stagingRootURL: stagingRoot,
            maximumConcurrency: 1
        )
        await runner.register(.archive) { context in
            let attempt = attempts.increment()
            let staging = stagingRoot.appendingPathComponent(context.job.stagingRelativePath)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try Data("attempt-owned".utf8).write(to: staging.appendingPathComponent("part.bin"))
            if attempt == 1 {
                try await context.checkpoint(Self.checkpoint(job: context.job, completed: 1, total: 2))
                await gate.arriveAndWait()
                try await context.cancellationBoundary()
            }
            try await context.checkpoint(Self.checkpoint(job: context.job, completed: 2, total: 2))
            return .init(outputSHA256: Self.digest("d"), completedUnitCount: 2)
        }
        let publicationCount = V910IntBox(0)
        await runner.registerPublisher(.archive) { context in
            try Data("accepted".utf8).write(to: canonicalURL, options: .atomic)
            _ = publicationCount.increment()
            return .completed(Self.receipt(context, disposition: .published))
        }
        let job = try makeJob(rootLabel: "h01", kind: .archive, units: 2, seed: 21)
        _ = try await runner.enqueue(job)
        await gate.waitUntilArrived()

        protectedFailure.failOperations = [.write]
        let coordinator = try await DeviceLifecycleCoordinatorV1.bootstrap(
            jobs: runner,
            initialState: .initiallyActive
        )
        _ = try await coordinator.handle(.protectedDataBecameUnavailable)
        await gate.open()
        await runner.waitUntilIdle()
        XCTAssertFalse(fileManager.fileExists(atPath: canonicalURL.path))
        XCTAssertEqual(publicationCount.value, 0)

        protectedFailure.failOperations = []
        _ = try await coordinator.handle(.protectedDataBecameAvailable)
        await runner.waitUntilIdle()
        let completedLoaded = try await runner.job(id: job.id)
        let completed = try XCTUnwrap(completedLoaded)
        XCTAssertEqual(completed.state, .succeeded)
        XCTAssertEqual(completed.attemptCount, 2)
        XCTAssertEqual(completed.checkpoint.completedUnitCount, 2)
        XCTAssertEqual(publicationCount.value, 1)
        XCTAssertEqual(try Data(contentsOf: canonicalURL), Data("accepted".utf8))

        let lostOrderingRoot = try makeRoot("lost-job-ordering")
        addTeardownBlock { try FileManager.default.removeItem(at: lostOrderingRoot) }
        let lostStore = try LocalJobStoreV1(applicationSupportURL: lostOrderingRoot)
        let oldOperationGate = V910Gate()
        let suspensionPersistenceGate = V910Gate()
        let lostStarts = V910IntBox(0)
        let lostRunner = try ResumableLocalJobRunnerV1(
            store: lostStore,
            stagingRootURL: lostOrderingRoot.appendingPathComponent("staging", isDirectory: true),
            maximumConcurrency: 1,
            lifecycleHook: { _, point in
                if point == .beforeSuspensionPersistence {
                    await suspensionPersistenceGate.arriveAndWait()
                }
            }
        )
        await lostRunner.register(.hash) { context in
            let attempt = lostStarts.increment()
            if attempt == 1 {
                await oldOperationGate.arriveAndWait()
                try await context.cancellationBoundary()
            }
            try await context.checkpoint(
                Self.checkpoint(job: context.job, completed: 1, total: 1)
            )
            return .init(outputSHA256: Self.digest("9"), completedUnitCount: 1)
        }
        await lostRunner.registerPublisher(.hash) { context in
            .completed(Self.receipt(context, disposition: .published))
        }
        let lostJob = try makeJob(
            rootLabel: "lost-job-ordering",
            kind: .hash,
            units: 1,
            seed: 29
        )
        _ = try await lostRunner.enqueue(lostJob)
        await oldOperationGate.waitUntilArrived()
        try await lostRunner.suspendForLifecycle(.protectedDataUnavailable)
        await oldOperationGate.open()
        await suspensionPersistenceGate.waitUntilArrived()

        try await lostRunner.resumeAfterLifecycle(.protectedDataUnavailable)
        let queuedBeforeOldPersistence = try await lostRunner.job(id: lostJob.id)
        XCTAssertEqual(queuedBeforeOldPersistence?.state, .queued)
        XCTAssertEqual(lostStarts.value, 1)
        await suspensionPersistenceGate.open()
        await lostRunner.waitUntilIdle()

        let recoveredLostJob = try await lostRunner.job(id: lostJob.id)
        XCTAssertEqual(recoveredLostJob?.state, .succeeded)
        XCTAssertEqual(recoveredLostJob?.attemptCount, 2)
        XCTAssertEqual(lostStarts.value, 2)
        XCTAssertNotEqual(recoveredLostJob?.state, .blockedProtectedData)

        for operation: LocalJobStoreProtectedDataAccessV1 in [.read, .write, .cleanup] {
            let lockedRoot = try makeRoot("h01-\(operation)")
            addTeardownBlock { try FileManager.default.removeItem(at: lockedRoot) }
            if operation == .read {
                let seed = try LocalJobStoreV1(applicationSupportURL: lockedRoot)
                _ = try await seed.jobs(workspaceID: nil)
            } else if operation == .cleanup {
                let directory = lockedRoot.appendingPathComponent(
                    LocalJobStoreSchemaV1.directoryName,
                    isDirectory: true
                )
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data("{corrupt".utf8).write(
                    to: directory.appendingPathComponent(LocalJobStoreSchemaV1.storeFileName)
                )
            }
            let lockedStore = try LocalJobStoreV1(
                applicationSupportURL: lockedRoot,
                protectedDataFailureHook: { $0 == operation }
            )
            do {
                _ = try await lockedStore.jobs(workspaceID: nil)
                XCTFail("\(operation) lock must fail closed")
            } catch let failure as LocalJobStoreFailureV1 {
                XCTAssertEqual(failure, .protectedDataUnavailable)
            }
        }

        let hostileRoot = try makeRoot("hostile-symlink")
        addTeardownBlock { try FileManager.default.removeItem(at: hostileRoot) }
        let outsideURL = hostileRoot.appendingPathComponent("outside.bin")
        try Data("must-survive".utf8).write(to: outsideURL)
        let hostileRoots = try makeOwnedRoots(
            applicationSupportURL: hostileRoot
        )
        let ownedURL = try XCTUnwrap(
            hostileRoots.first(where: { $0.kind == .data })?.url
        )
        try fileManager.createSymbolicLink(
            at: ownedURL.appendingPathComponent("escape"),
            withDestinationURL: outsideURL
        )
        XCTAssertThrowsError(
            try OwnedStorageLedgerV1(
                rootURLs: hostileRoots,
                capacityProvider: { _ in 1_000_000 }
            )
        ) { error in
            XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .unsupportedEntry)
        }
        XCTAssertEqual(
            try Data(contentsOf: outsideURL),
            Data("must-survive".utf8),
            "hostile-symlink must fail closed under O_NOFOLLOW / AT_SYMLINK_NOFOLLOW"
        )

        let resumeRaceRoot = try makeRoot("resume-readback-race")
        addTeardownBlock { try FileManager.default.removeItem(at: resumeRaceRoot) }
        let readbackGate = V910ProtectedReadbackGate()
        let raceStore = try LocalJobStoreV1(
            applicationSupportURL: resumeRaceRoot,
            protectedDataFailureHook: { readbackGate.hook($0) }
        )
        let raceRunner = try ResumableLocalJobRunnerV1(
            store: raceStore,
            stagingRootURL: resumeRaceRoot.appendingPathComponent("staging", isDirectory: true),
            maximumConcurrency: 1
        )
        let raceStarts = V910IntBox(0)
        await raceRunner.register(.hash) { context in
            _ = raceStarts.increment()
            try await context.checkpoint(
                Self.checkpoint(job: context.job, completed: 1, total: 1)
            )
            return .init(outputSHA256: Self.digest("a"), completedUnitCount: 1)
        }
        await raceRunner.registerPublisher(.hash) { context in
            .completed(Self.receipt(context, disposition: .published))
        }
        try await raceRunner.suspendForLifecycle(.protectedDataUnavailable)
        let raceJob = try makeJob(
            rootLabel: "resume-readback-race",
            kind: .hash,
            units: 1,
            seed: 31
        )
        _ = try await raceRunner.enqueue(raceJob)
        let firstGeneration = await raceRunner.lifecycleGeneration(.protectedDataUnavailable)
        XCTAssertEqual(firstGeneration, 1)
        readbackGate.arm()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await raceRunner.resumeAfterLifecycle(.protectedDataUnavailable)
            }
            try readbackGate.waitUntilReadEntered()
            defer { readbackGate.open() }
            try await raceRunner.suspendForLifecycle(.protectedDataUnavailable)
            let newerGeneration = await raceRunner.lifecycleGeneration(.protectedDataUnavailable)
            XCTAssertEqual(newerGeneration, 2)
            readbackGate.open()
            try await group.waitForAll()
        }
        let remainedSuspended = await raceRunner.isLifecycleSuspended(.protectedDataUnavailable)
        XCTAssertTrue(remainedSuspended)
        XCTAssertEqual(raceStarts.value, 0)
        let staleResumeJob = try await raceRunner.job(id: raceJob.id)
        XCTAssertEqual(staleResumeJob?.state, .queued)

        try await raceRunner.resumeAfterLifecycle(.protectedDataUnavailable)
        await raceRunner.waitUntilIdle()
        let recoveredSuspension = await raceRunner.isLifecycleSuspended(.protectedDataUnavailable)
        XCTAssertFalse(recoveredSuspension)
        XCTAssertEqual(raceStarts.value, 1)
        let trulyResumed = try await raceRunner.job(id: raceJob.id)
        XCTAssertEqual(trulyResumed?.state, .succeeded)
    }

    func testV9_10I01BackgroundTerminationAtEveryDurableBoundaryRelaunchesCleanly() async throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(
            corpus.durableBoundaries,
            ["queuedBeforeClaim", "runningAfterCheckpoint", "awaitingPublicationEffectBeforeReceipt", "terminalSucceeded"]
        )
        let root = try makeRoot("i01")
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.appendingPathComponent("canonical", isDirectory: true)
        try fileManager.createDirectory(at: canonicalRoot, withIntermediateDirectories: false)

        for (index, boundary) in corpus.durableBoundaries.enumerated() {
            let caseRoot = root.appendingPathComponent(boundary, isDirectory: true)
            try fileManager.createDirectory(at: caseRoot, withIntermediateDirectories: false)
            let stagingRoot = caseRoot.appendingPathComponent("staging", isDirectory: true)
            let canonicalURL = canonicalRoot.appendingPathComponent("\(boundary).bin")
            let job = try makeJob(rootLabel: boundary, kind: .hash, units: 1, seed: 40 + index)
            let firstStore = try LocalJobStoreV1(applicationSupportURL: caseRoot)
            let firstRunner = try ResumableLocalJobRunnerV1(
                store: firstStore,
                stagingRootURL: stagingRoot,
                maximumConcurrency: 1
            )
            let gate = V910Gate()
            let escapedEffects = V910IntBox(0)
            await firstRunner.register(.hash) { context in
                if boundary == "runningAfterCheckpoint" {
                    try await context.checkpoint(Self.checkpoint(job: context.job, completed: 1, total: 1))
                    await gate.arriveAndWait()
                    try await context.cancellationBoundary()
                } else {
                    try await context.checkpoint(Self.checkpoint(job: context.job, completed: 1, total: 1))
                }
                return .init(outputSHA256: Self.digest("e"), completedUnitCount: 1)
            }
            await firstRunner.registerPublisher(.hash) { context in
                try Data("accepted-\(boundary)".utf8).write(to: canonicalURL, options: .atomic)
                _ = escapedEffects.increment()
                if boundary == "awaitingPublicationEffectBeforeReceipt" {
                    throw V910Failure.effectBeforeReceipt
                }
                return .completed(Self.receipt(context, disposition: .published))
            }

            if boundary == "queuedBeforeClaim" {
                try await firstRunner.suspendForLifecycle(.sceneBackground)
            }
            _ = try await firstRunner.enqueue(job)
            if boundary == "runningAfterCheckpoint" {
                await gate.waitUntilArrived()
                try await firstRunner.suspendForLifecycle(.sceneBackground)
                await gate.open()
            }
            await firstRunner.waitUntilIdle()

            let beforeRelaunchLoaded = try await firstRunner.job(id: job.id)
            let beforeRelaunch = try XCTUnwrap(beforeRelaunchLoaded)
            switch boundary {
            case "queuedBeforeClaim": XCTAssertEqual(beforeRelaunch.state, .queued)
            case "runningAfterCheckpoint":
                XCTAssertEqual(beforeRelaunch.state, .queued)
                XCTAssertEqual(beforeRelaunch.checkpoint.completedUnitCount, 1)
            case "awaitingPublicationEffectBeforeReceipt":
                XCTAssertEqual(beforeRelaunch.state, .awaitingPublication)
                XCTAssertEqual(escapedEffects.value, 1)
            case "terminalSucceeded": XCTAssertEqual(beforeRelaunch.state, .succeeded)
            default: XCTFail("unknown durable boundary")
            }

            let reopenedStore = try LocalJobStoreV1(applicationSupportURL: caseRoot)
            let relaunched = try ResumableLocalJobRunnerV1(
                store: reopenedStore,
                stagingRootURL: stagingRoot,
                maximumConcurrency: 1
            )
            await relaunched.register(.hash) { context in
                try await context.checkpoint(Self.checkpoint(job: context.job, completed: 1, total: 1))
                return .init(outputSHA256: Self.digest("e"), completedUnitCount: 1)
            }
            await relaunched.registerPublisher(.hash) { context in
                if FileManager.default.fileExists(atPath: canonicalURL.path) {
                    return .completed(Self.receipt(context, disposition: .adopted))
                }
                try Data("accepted-\(boundary)".utf8).write(to: canonicalURL, options: .atomic)
                _ = escapedEffects.increment()
                return .completed(Self.receipt(context, disposition: .published))
            }
            try await relaunched.resumePending()
            await relaunched.waitUntilIdle()
            let finalLoaded = try await relaunched.job(id: job.id)
            let final = try XCTUnwrap(finalLoaded)
            XCTAssertEqual(final.state, .succeeded, boundary)
            XCTAssertEqual(final.checkpoint.completedUnitCount, 1, boundary)
            XCTAssertEqual(escapedEffects.value, 1, boundary)
            XCTAssertEqual(
                try Data(contentsOf: canonicalURL),
                Data("accepted-\(boundary)".utf8),
                boundary
            )
        }


        try await proveDestructiveReconciliation(
            root: root.appendingPathComponent("removeJobs", isDirectory: true),
            canonicalURL: canonicalRoot.appendingPathComponent("removeJobs.bin"),
            eraseAll: false
        )
        try await proveDestructiveReconciliation(
            root: root.appendingPathComponent("eraseAll", isDirectory: true),
            canonicalURL: canonicalRoot.appendingPathComponent("eraseAll.bin"),
            eraseAll: true
        )
    }

    func testV9_10R01StorageReconciliationAndClockTimezoneDSTRecovery() async throws {
        let corpus = try loadCorpus()
        let root = try makeRoot("r01")
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let roots = try makeOwnedRoots(applicationSupportURL: root)
        for (index, byteCount) in corpus.storage.ownedFileBytes.enumerated() {
            try Data(repeating: UInt8(index + 1), count: byteCount).write(
                to: roots[index].url.appendingPathComponent("owned.bin")
            )
        }
        let ledger = try OwnedStorageLedgerV1(rootURLs: roots, capacityProvider: { _ in 1_000_000 })
        let initial = ledger.snapshot()
        XCTAssertEqual(initial.ownedByteCount, Int64(corpus.storage.ownedFileBytes.reduce(0, +)))
        XCTAssertEqual(initial.activeReservationCount, 0)

        let kept = try ledger.reserve(
            attemptID: try storageAttempt(
                workspaceSeed: 81,
                generationSeed: 181,
                mutationSeed: 281
            ),
            requiredBytes: Int64(corpus.storage.reservationBytes[0])
        )
        _ = try ledger.reserve(
            attemptID: try storageAttempt(
                workspaceSeed: 82,
                generationSeed: 182,
                mutationSeed: 282
            ),
            requiredBytes: Int64(corpus.storage.reservationBytes[1])
        )
        try Data(repeating: 9, count: 13).write(to: roots[0].url.appendingPathComponent("later.bin"))
        let reconciled = try ledger.reconcile(activeReservations: [kept])
        XCTAssertEqual(reconciled.ownedByteCount, initial.ownedByteCount + 13)
        XCTAssertEqual(reconciled.reservedByteCount, kept.requiredBytes)
        XCTAssertEqual(reconciled.activeReservationCount, 1)
        XCTAssertTrue(fileManager.fileExists(atPath: roots[0].url.appendingPathComponent("owned.bin").path))
        XCTAssertTrue(fileManager.fileExists(atPath: roots[0].url.appendingPathComponent("later.bin").path))

        let raceGate = V910CapacityRaceGate(capacity: 1_000_000)
        let raceLedger = try OwnedStorageLedgerV1(
            rootURLs: roots,
            capacityProvider: { _ in raceGate.provideCapacity() }
        )
        let adopted = try raceLedger.reserve(
            attemptID: try storageAttempt(
                workspaceSeed: 83,
                generationSeed: 183,
                mutationSeed: 283
            ),
            requiredBytes: Int64(corpus.storage.reservationBytes[0])
        )
        let concurrentAttempt = try storageAttempt(
            workspaceSeed: 84,
            generationSeed: 184,
            mutationSeed: 284
        )
        raceGate.arm()
        let racedReservation = try await withThrowingTaskGroup(
            of: OwnedStorageReservationV1.self
        ) { group in
            group.addTask {
                try raceLedger.reserve(
                    attemptID: concurrentAttempt,
                    requiredBytes: Int64(corpus.storage.reservationBytes[1])
                )
            }
            try raceGate.waitUntilProviderEntered()
            defer { raceGate.open() }

            let duringRace = try raceLedger.reconcile(
                activeReservations: [adopted]
            )
            XCTAssertEqual(duringRace.activeReservationCount, 1)
            XCTAssertEqual(duringRace.reservedByteCount, adopted.requiredBytes)

            // The release linearizes after reconcile while the concurrent
            // reserve is still blocked outside the ledger lock. It must not be
            // reintroduced when that later reserve inserts successfully.
            raceLedger.release(reservation: adopted)
            raceGate.open()
            let result = try await group.next()
            return try XCTUnwrap(result)
        }
        let racedFinal = raceLedger.snapshot()
        XCTAssertEqual(racedFinal.activeReservationCount, 1)
        XCTAssertEqual(racedFinal.reservedByteCount, racedReservation.requiredBytes)
        XCTAssertEqual(racedFinal.ownedByteCount, reconciled.ownedByteCount)
        XCTAssertEqual(
            try raceLedger.reserve(
                attemptID: racedReservation.attemptID,
                requiredBytes: racedReservation.requiredBytes
            ),
            racedReservation,
            "successful concurrent reservation must survive reconciliation"
        )
        raceLedger.release(reservation: adopted)
        XCTAssertEqual(raceLedger.snapshot(), racedFinal)

        let wall = V910MutableWallClock(Date(timeIntervalSince1970: 0))
        let monotonic = V910MutableMonotonicClock(1_000_000_000)
        let semantics = DeviceTimeSemanticsV1(wallClock: wall, monotonicClock: monotonic)
        let formatter = ISO8601DateFormatter()
        var recordsByUTC: [String: DeviceWallTimeRecordV1] = [:]
        for timeCase in corpus.timeCases {
            let instant = try XCTUnwrap(formatter.date(from: timeCase.utc))
            wall.value = instant
            let zone = try XCTUnwrap(TimeZone(identifier: timeCase.zone))
            let record = try semantics.wallTimeRecord(timeZone: zone)
            XCTAssertEqual(record.recordedAtUTC, instant)
            XCTAssertEqual(record.utcOffsetSeconds, timeCase.offset)
            XCTAssertEqual(record.isDaylightSavingTime, timeCase.dst)
            try record.validate()
            recordsByUTC[timeCase.utc] = record
        }

        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/New_York")
        )
        let civilFields: Set<Calendar.Component> = [
            .year, .month, .day, .hour, .minute, .second,
        ]
        let springBefore = try XCTUnwrap(recordsByUTC["2026-03-08T06:59:59Z"])
        let springAfter = try XCTUnwrap(recordsByUTC["2026-03-08T07:00:00Z"])
        let springBeforeCivil = newYorkCalendar.dateComponents(
            civilFields,
            from: springBefore.recordedAtUTC
        )
        let springAfterCivil = newYorkCalendar.dateComponents(
            civilFields,
            from: springAfter.recordedAtUTC
        )
        XCTAssertEqual(
            [springBeforeCivil.year, springBeforeCivil.month, springBeforeCivil.day,
             springBeforeCivil.hour, springBeforeCivil.minute, springBeforeCivil.second],
            [2026, 3, 8, 1, 59, 59]
        )
        XCTAssertEqual(
            [springAfterCivil.year, springAfterCivil.month, springAfterCivil.day,
             springAfterCivil.hour, springAfterCivil.minute, springAfterCivil.second],
            [2026, 3, 8, 3, 0, 0]
        )
        XCTAssertEqual(springBefore.utcOffsetSeconds, -18_000)
        XCTAssertFalse(springBefore.isDaylightSavingTime)
        XCTAssertEqual(springAfter.utcOffsetSeconds, -14_400)
        XCTAssertTrue(springAfter.isDaylightSavingTime)

        let foldFirst = try XCTUnwrap(recordsByUTC["2026-11-01T05:00:00Z"])
        let foldSecond = try XCTUnwrap(recordsByUTC["2026-11-01T06:00:00Z"])
        let foldFirstCivil = newYorkCalendar.dateComponents(
            civilFields,
            from: foldFirst.recordedAtUTC
        )
        let foldSecondCivil = newYorkCalendar.dateComponents(
            civilFields,
            from: foldSecond.recordedAtUTC
        )
        XCTAssertEqual(
            [foldFirstCivil.year, foldFirstCivil.month, foldFirstCivil.day,
             foldFirstCivil.hour, foldFirstCivil.minute],
            [foldSecondCivil.year, foldSecondCivil.month, foldSecondCivil.day,
             foldSecondCivil.hour, foldSecondCivil.minute]
        )
        XCTAssertEqual(foldFirstCivil.hour, 1)
        XCTAssertEqual(foldFirstCivil.minute, 0)
        XCTAssertNotEqual(foldFirst.recordedAtUTC, foldSecond.recordedAtUTC)
        XCTAssertEqual(foldFirst.utcOffsetSeconds, -14_400)
        XCTAssertTrue(foldFirst.isDaylightSavingTime)
        XCTAssertEqual(foldSecond.utcOffsetSeconds, -18_000)
        XCTAssertFalse(foldSecond.isDaylightSavingTime)

        let driftInstant = try XCTUnwrap(
            formatter.date(from: "2026-07-15T16:00:00Z")
        )
        let driftZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        wall.value = driftInstant
        let liveTuple = try semantics.wallTimeRecord(timeZone: driftZone)
        XCTAssertEqual(liveTuple.utcOffsetSeconds, -14_400)
        XCTAssertTrue(liveTuple.isDaylightSavingTime)
        let capturedBeforeTZDBDrift = DeviceWallTimeRecordV1(
            recordedAtUTC: driftInstant,
            timeZoneIdentifier: "America/New_York",
            utcOffsetSeconds: -18_000,
            isDaylightSavingTime: false
        )
        XCTAssertNotEqual(
            capturedBeforeTZDBDrift.utcOffsetSeconds,
            driftZone.secondsFromGMT(for: driftInstant)
        )
        XCTAssertNotEqual(
            capturedBeforeTZDBDrift.isDaylightSavingTime,
            driftZone.isDaylightSavingTime(for: driftInstant)
        )
        XCTAssertNoThrow(
            try capturedBeforeTZDBDrift.validate(),
            "durable captured tuple must survive later TZDB interpretation drift"
        )
        let capturedBytes = try JSONEncoder().encode(capturedBeforeTZDBDrift)
        let restoredCapturedTuple = try JSONDecoder().decode(
            DeviceWallTimeRecordV1.self,
            from: capturedBytes
        )
        XCTAssertEqual(restoredCapturedTuple, capturedBeforeTZDBDrift)
        XCTAssertNoThrow(try restoredCapturedTuple.validate())

        let malformedWallRecords = [
            DeviceWallTimeRecordV1(
                recordedAtUTC: Date(timeIntervalSinceReferenceDate: .infinity),
                timeZoneIdentifier: "UTC",
                utcOffsetSeconds: 0,
                isDaylightSavingTime: false
            ),
            DeviceWallTimeRecordV1(
                recordedAtUTC: driftInstant,
                timeZoneIdentifier: "",
                utcOffsetSeconds: 0,
                isDaylightSavingTime: false
            ),
            DeviceWallTimeRecordV1(
                recordedAtUTC: driftInstant,
                timeZoneIdentifier: String(
                    repeating: "x",
                    count: DeviceWallTimeRecordV1
                        .maximumTimeZoneIdentifierUTF8ByteCount + 1
                ),
                utcOffsetSeconds: 0,
                isDaylightSavingTime: false
            ),
            DeviceWallTimeRecordV1(
                recordedAtUTC: driftInstant,
                timeZoneIdentifier: "UTC",
                utcOffsetSeconds: DeviceWallTimeRecordV1
                    .maximumAbsoluteUTCOffsetSeconds + 1,
                isDaylightSavingTime: false
            ),
            DeviceWallTimeRecordV1(
                recordedAtUTC: driftInstant,
                timeZoneIdentifier: "UTC",
                utcOffsetSeconds: -DeviceWallTimeRecordV1
                    .maximumAbsoluteUTCOffsetSeconds - 1,
                isDaylightSavingTime: false
            ),
        ]
        for malformed in malformedWallRecords {
            XCTAssertThrowsError(try malformed.validate()) { error in
                XCTAssertEqual(error as? DeviceTimeSemanticsFailureV1, .invalidWallTime)
            }
        }

        let token = semantics.beginDuration()
        let startWall = wall.value
        wall.value = startWall.addingTimeInterval(TimeInterval(corpus.wallClockJumpsSeconds[0]))
        monotonic.value += UInt64(corpus.monotonicElapsedNanoseconds)
        XCTAssertEqual(
            try semantics.elapsed(since: token),
            .nanoseconds(Int64(corpus.monotonicElapsedNanoseconds))
        )
        wall.value = startWall.addingTimeInterval(TimeInterval(corpus.wallClockJumpsSeconds[1]))
        XCTAssertEqual(
            try semantics.elapsed(since: token),
            .nanoseconds(Int64(corpus.monotonicElapsedNanoseconds))
        )

        let regressingToken = semantics.beginDuration()
        monotonic.value -= 1
        XCTAssertThrowsError(try semantics.elapsed(since: regressingToken)) {
            XCTAssertEqual($0 as? DeviceTimeSemanticsFailureV1, .monotonicClockRegressed)
        }
        monotonic.value = 0
        let overflowToken = semantics.beginDuration()
        monotonic.value = UInt64(Int64.max) + 1
        XCTAssertThrowsError(try semantics.elapsed(since: overflowToken)) {
            XCTAssertEqual($0 as? DeviceTimeSemanticsFailureV1, .durationOverflow)
        }

        wall.value = try XCTUnwrap(formatter.date(from: corpus.timeCases[0].utc))
        let durableWall = try semantics.wallTimeRecord(
            timeZone: XCTUnwrap(TimeZone(identifier: corpus.timeCases[0].zone))
        )
        let encoded = try JSONEncoder().encode(durableWall)
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(encodedText.contains("uptime"))
        XCTAssertFalse(encodedText.contains("monotonic"))
        XCTAssertEqual(try JSONDecoder().decode(DeviceWallTimeRecordV1.self, from: encoded), durableWall)
    }

    private func makeRoot(_ label: String) throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_10LifecycleBoundaryTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func makeOwnedRoots(
        applicationSupportURL: URL
    ) throws -> [OwnedStorageRootV1] {
        let roots = try OwnedStorageRootV1.closedSet(
            applicationSupportURL: applicationSupportURL
        )
        for root in roots {
            try fileManager.createDirectory(
                at: root.url,
                withIntermediateDirectories: false
            )
        }
        XCTAssertEqual(roots.count, OwnedStorageRootKindV1.allCases.count)
        XCTAssertEqual(Set(roots.map(\.kind)), Set(OwnedStorageRootKindV1.allCases))
        return roots
    }

    private func proveDestructiveReconciliation(
        root: URL,
        canonicalURL: URL,
        eraseAll: Bool
    ) async throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let store = try LocalJobStoreV1(applicationSupportURL: root)
        let runner = try ResumableLocalJobRunnerV1(
            store: store,
            stagingRootURL: stagingRoot,
            maximumConcurrency: 1
        )
        let escapedEffects = V910IntBox(0)
        await runner.register(.thumbnail) { context in
            try await context.checkpoint(Self.checkpoint(job: context.job, completed: 1, total: 1))
            return .init(outputSHA256: Self.digest("f"), completedUnitCount: 1)
        }
        await runner.registerPublisher(.thumbnail) { _ in
            try Data("retained-canonical".utf8).write(to: canonicalURL, options: .atomic)
            _ = escapedEffects.increment()
            throw V910Failure.effectBeforeReceipt
        }
        let job = try makeJob(
            rootLabel: eraseAll ? "eraseAll" : "removeJobs",
            kind: .thumbnail,
            units: 1,
            seed: eraseAll ? 92 : 91
        )
        _ = try await runner.enqueue(job)
        await runner.waitUntilIdle()
        let awaiting = try await runner.job(id: job.id)
        XCTAssertEqual(awaiting?.state, .awaitingPublication)

        let relaunchedStore = try LocalJobStoreV1(applicationSupportURL: root)
        let relaunched = try ResumableLocalJobRunnerV1(
            store: relaunchedStore,
            stagingRootURL: stagingRoot,
            maximumConcurrency: 1
        )
        await relaunched.registerPublisher(.thumbnail) { context in
            XCTAssertEqual(context.mode, .adoptOnly)
            guard try Data(contentsOf: canonicalURL) == Data("retained-canonical".utf8) else {
                return .absent
            }
            return .completed(Self.receipt(context, disposition: .adopted))
        }
        let activeGate = V910Gate()
        let rejectedCanonicalEffects = V910IntBox(0)
        await relaunched.register(.hash) { context in
            await activeGate.arriveAndWait()
            try await context.cancellationBoundary()
            try await context.checkpoint(
                Self.checkpoint(job: context.job, completed: 1, total: 1)
            )
            return .init(outputSHA256: Self.digest("b"), completedUnitCount: 1)
        }
        await relaunched.registerPublisher(.hash) { context in
            _ = rejectedCanonicalEffects.increment()
            return .completed(Self.receipt(context, disposition: .published))
        }
        let blocker = try makeJob(
            workspaceID: job.workspaceID,
            rootLabel: eraseAll ? "eraseAll-blocker" : "removeJobs-blocker",
            kind: .hash,
            units: 1,
            seed: eraseAll ? 93 : 94
        )
        _ = try await relaunched.enqueue(blocker)
        await activeGate.waitUntilArrived()
        let lateJob = try makeJob(
            workspaceID: eraseAll ? uuid(95) : job.workspaceID,
            rootLabel: eraseAll ? "eraseAll-late" : "removeJobs-late",
            kind: .hash,
            units: 1,
            seed: eraseAll ? 96 : 97
        )
        // Both public destructive APIs exercise the runner's internal
        // reconcileForDestructiveRemoval fail-closed path before row removal.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                if eraseAll {
                    try await relaunched.eraseAll()
                } else {
                    try await relaunched.removeJobs(workspaceID: job.workspaceID)
                }
            }
            do {
                try await waitForDestructiveGate(
                    relaunched,
                    workspaceID: eraseAll ? nil : job.workspaceID
                )
                do {
                    _ = try await relaunched.enqueue(lateJob)
                    XCTFail("enqueue must be rejected while destructive scope is gated")
                } catch let failure as ResumableLocalJobRunnerFailureV1 {
                    XCTAssertEqual(failure, .destructiveScopeBusy)
                }
                let rejectedRow = try await relaunched.job(id: lateJob.id)
                XCTAssertNil(rejectedRow)
                XCTAssertEqual(rejectedCanonicalEffects.value, 0)
            } catch {
                await activeGate.open()
                throw error
            }
            await activeGate.open()
            try await group.waitForAll()
        }
        let remaining = try await relaunched.jobs(workspaceID: nil)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(escapedEffects.value, 1)
        XCTAssertEqual(rejectedCanonicalEffects.value, 0)
        XCTAssertEqual(try Data(contentsOf: canonicalURL), Data("retained-canonical".utf8))
    }

    private func waitForDestructiveGate(
        _ runner: ResumableLocalJobRunnerV1,
        workspaceID: UUID?
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !(await runner.isDestructiveOperationGated(workspaceID: workspaceID)) {
            guard clock.now < deadline else { throw V910Failure.timeout }
            try await clock.sleep(for: .milliseconds(1))
        }
    }

    private func makeJob(
        rootLabel: String,
        kind: ResumableLocalJobKindV1,
        units: Int,
        seed: Int
    ) throws -> ResumableLocalJobV1 {
        try makeJob(
            workspaceID: uuid(seed),
            rootLabel: rootLabel,
            kind: kind,
            units: units,
            seed: seed
        )
    }

    private func makeJob(
        workspaceID: UUID,
        rootLabel: String,
        kind: ResumableLocalJobKindV1,
        units: Int,
        seed: Int
    ) throws -> ResumableLocalJobV1 {
        try ResumableLocalJobV1(
            workspaceID: workspaceID,
            kind: kind,
            immutableInputSHA256: Self.digest(String(format: "%x", seed % 16)),
            stagingRelativePath: "\(rootLabel)/job",
            createdAt: Date(timeIntervalSinceReferenceDate: 240_000),
            checkpoint: LocalJobCheckpointV1(
                nextChunkIndex: 0,
                completedUnitCount: 0,
                totalUnitCount: units
            )
        )
    }

    private func loadCorpus() throws -> V910Corpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P02C06LifecycleBoundaryCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Lifecycle"
            ) ?? bundle.url(
                forResource: "V21P02C06LifecycleBoundaryCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(V910Corpus.self, from: Data(contentsOf: url))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    private func storageAttempt(
        workspaceSeed: Int,
        generationSeed: Int,
        mutationSeed: Int
    ) throws -> OwnedStorageAttemptIDV1 {
        try OwnedStorageAttemptIDV1(
            workspaceID: WorkspaceID(rawValue: uuid(workspaceSeed)),
            generationID: uuid(generationSeed),
            mutationID: MutationIDV1(rawValue: uuid(mutationSeed))
        )
    }

    nonisolated private static func digest(_ character: String) -> String {
        String(repeating: character, count: 64)
    }

    nonisolated private static func checkpoint(
        job: ResumableLocalJobV1,
        completed: Int,
        total: Int
    ) -> LocalJobCheckpointV1 {
        LocalJobCheckpointV1(
            nextChunkIndex: completed,
            completedUnitCount: completed,
            totalUnitCount: total,
            lastChunkID: completed == 0 ? nil : .deterministic(jobID: job.id, index: completed - 1),
            rollingOutputSHA256: completed == 0 ? nil : digest("c")
        )
    }

    nonisolated private static func receipt(
        _ context: ResumableLocalJobPublicationContextV1,
        disposition: LocalJobPublicationDispositionV1
    ) -> LocalJobPublicationReceiptV1 {
        LocalJobPublicationReceiptV1(
            jobID: context.job.id,
            attemptCount: context.pending.attemptCount,
            kind: context.job.kind,
            outputSHA256: context.pending.result.outputSHA256,
            disposition: disposition,
            readBackAt: Date(timeIntervalSinceReferenceDate: 240_001)
        )
    }
}

private final class C27V910TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

private actor V910LifecyclePortProbe: ResumableLocalJobLifecyclePortV1 {
    private var observed: [DeviceLifecycleActionV1] = []
    func suspendForLifecycle(_ reason: LocalJobLifecycleSuspensionReasonV1) {
        observed.append(.suspend(reason))
    }
    func resumeAfterLifecycle(_ reason: LocalJobLifecycleSuspensionReasonV1) {
        observed.append(.resume(reason))
    }
    func actions() -> [DeviceLifecycleActionV1] { observed }
}

private actor V910Gate {
    private var arrived = false
    private var openState = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func arriveAndWait() async {
        arrived = true
        let waiters = arrivalWaiters
        arrivalWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !openState else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilArrived() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func open() {
        openState = true
        let waiters = openWaiters
        openWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class V910IntBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int
    init(_ value: Int) { storage = value }
    var value: Int { lock.withLock { storage } }
    @discardableResult func increment() -> Int {
        lock.withLock { storage += 1; return storage }
    }
}

private final class V910Int64Box: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int64
    init(_ value: Int64) { storage = value }
    var value: Int64 {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

private final class V910ProtectedDataHook: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LocalJobStoreProtectedDataAccessV1] = []
    var failOperations: [LocalJobStoreProtectedDataAccessV1] {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
    func shouldFail(_ operation: LocalJobStoreProtectedDataAccessV1) -> Bool {
        lock.withLock { storage.contains(operation) }
    }
}

private final class V910CapacityRaceGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let capacity: Int64
    private var armed = false
    private var entered = false
    private var opened = false

    init(capacity: Int64) { self.capacity = capacity }

    func arm() {
        condition.lock()
        armed = true
        entered = false
        opened = false
        condition.unlock()
    }

    func provideCapacity() -> Int64 {
        condition.lock()
        if armed {
            entered = true
            condition.broadcast()
            while !opened { condition.wait() }
            armed = false
        }
        condition.unlock()
        return capacity
    }

    func waitUntilProviderEntered() throws {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(5)
        while !entered {
            guard condition.wait(until: deadline) else {
                throw V910Failure.timeout
            }
        }
    }

    func open() {
        condition.lock()
        opened = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class V910ProtectedReadbackGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var armed = false
    private var entered = false
    private var opened = false

    func arm() {
        condition.lock()
        armed = true
        entered = false
        opened = false
        condition.unlock()
    }

    func hook(_ access: LocalJobStoreProtectedDataAccessV1) -> Bool {
        condition.lock()
        if armed, access == .read {
            entered = true
            condition.broadcast()
            while !opened { condition.wait() }
            armed = false
        }
        condition.unlock()
        return false
    }

    func waitUntilReadEntered() throws {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(5)
        while !entered {
            guard condition.wait(until: deadline) else {
                throw V910Failure.timeout
            }
        }
    }

    func open() {
        condition.lock()
        opened = true
        condition.broadcast()
        condition.unlock()
    }
}

private enum V910Failure: Error {
    case effectBeforeReceipt
    case timeout
}

private struct V910MutableWallClock: ApplicationClock, @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var value: Date
        init(_ value: Date) { self.value = value }
    }
    private let storage: Storage
    init(_ value: Date) { storage = Storage(value) }
    var value: Date {
        get { storage.lock.withLock { storage.value } }
        nonmutating set { storage.lock.withLock { storage.value = newValue } }
    }
    func now() -> Date { value }
}

private struct V910MutableMonotonicClock: ApplicationMonotonicClockV1, @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var value: UInt64
        init(_ value: UInt64) { self.value = value }
    }
    private let storage: Storage
    init(_ value: UInt64) { storage = Storage(value) }
    var value: UInt64 {
        get { storage.lock.withLock { storage.value } }
        nonmutating set { storage.lock.withLock { storage.value = newValue } }
    }
    func instant() -> ApplicationMonotonicInstantV1 {
        ApplicationMonotonicInstantV1(uptimeNanoseconds: value)
    }
}

@MainActor
private final class V910WriterAdapter: WorkspaceWriterAdapterPortV1 {
    private(set) var applyCount = 0
    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        applyCount += 1
        let identities: [WorkspaceEntityIdentityV1]
        switch command {
        case .createFirstSign(let value):
            identities = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
                WorkspaceEntityIdentityV1(kind: .site, id: value.siteID),
            ]
        default:
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )
    }
}

private struct V910Clock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct V910IDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct V910FileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class V910WriterHarness {
    let writer: WorkspaceWriterV1
    private let workspaceID = WorkspaceID(rawValue: V910WriterHarness.id(1))
    private let generationID = V910WriterHarness.id(2)
    private let siteID = V910WriterHarness.id(3)
    private let assetID = V910WriterHarness.id(4)

    init(adapter: V910WriterAdapter, storageAdmission: any WorkspaceStorageAdmissionPortV1) throws {
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: Self.id(5))
        )
        let initial = try WorkspaceRevisionV1(
            workspaceID: workspaceID,
            generationID: generationID,
            revision: 0,
            entityRevisions: [
                WorkspaceEntityRevisionV1(identity: try .init(kind: .site, id: siteID), revision: 0),
                WorkspaceEntityRevisionV1(identity: try .init(kind: .asset, id: assetID), revision: 0),
            ]
        )
        writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: initial,
            clock: V910Clock(value: Date(timeIntervalSince1970: 1_800_000_000)),
            idSource: V910IDSource(value: Self.id(90)),
            fileAuthority: V910FileAuthority(),
            adapter: adapter,
            storageAdmission: storageAdmission
        )
    }

    func request(mutationByte: UInt8) throws -> WorkspaceMutationRequestV1 {
        WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: Self.id(mutationByte)),
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: try writer.currentRevision()),
            command: .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(id: siteID, label: "Site", address: nil, timeZoneID: "UTC"),
                assetID: assetID,
                assetLabel: "Asset",
                packID: "test.pack",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: Date(timeIntervalSince1970: 1_800_000_010)
            ))
        )
    }

    private static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }
}

private struct V910Corpus: Decodable, Sendable {
    let schemaVersion: Int
    let fixtureIdentity: String
    let lifecycleEvents: [String]
    let durableBoundaries: [String]
    let storage: Storage
    let timeCases: [TimeCase]
    let wallClockJumpsSeconds: [Int]
    let monotonicElapsedNanoseconds: Int

    struct Storage: Decodable, Sendable {
        let canonicalMutationAllowanceBytes: Int64
        let ownedFileBytes: [Int]
        let reservationBytes: [Int]
    }

    struct TimeCase: Decodable, Sendable {
        let utc: String
        let zone: String
        let offset: Int
        let dst: Bool
    }
}

extension V9_10LifecycleBoundaryTests {
    func testV23P03C36LifecycleSeparatesOperationalDraftsFromCanonicalTruth() throws {
        let fixture = try C36FieldDraftTestSupportV1.makeFixture()
        XCTAssertEqual(DraftLifecycleDispositionV1.allCases.map(\.rawValue), [
            "PERSISTENT_WORKSPACE_OPERATIONAL", "SAFE_RESUME_DERIVED_ONLY", "EXCLUDED_FROM_CANONICAL_TRUTH"
        ])
        XCTAssertEqual(V16BackupFieldDraftRecordV1.Kind.allCases.map { $0.rawValue.uppercased() }, [
            "CHECKPOINT", "STAGINGITEM", "COMMITSAGA", "CONTENTRESERVATION", "COMMITRECEIPT", "DISCARDRECEIPT"
        ])
        XCTAssertEqual(fixture.activeCheckpoint.state, .active)
        XCTAssertEqual(fixture.committedCheckpoint.state, .committed)
        XCTAssertEqual(fixture.committedItem.state, .committed)
        XCTAssertEqual(fixture.commitReceipt.sagaEventSHA256Chain.count, 5)
    }
}
extension V9_10LifecycleBoundaryTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleActionV1.allCases.count, 7)
        XCTAssertEqual(SurveyDefinitionLifecycleStateV1.allCases.count, 3)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
    }
}
extension V9_10LifecycleBoundaryTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_10LifecycleBoundaryTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}

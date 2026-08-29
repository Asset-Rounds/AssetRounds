import Foundation
import CryptoKit
import XCTest

@testable import FieldEvidenceApp

/// C42 is a bounded, nonshipping TestSupport conformance lane.  These tests
/// exercise the two synthetic archetypes through the same canonical model and
/// codec; they do not introduce a product market, a second writer, or a
/// persistent model.
@MainActor
final class V9_47CrossMarketConformanceTests: XCTestCase {
    func testV23P03C42G01BothArchetypesCompleteOfflineSharedKernelJourney() async throws {
        let corpus = try KernelConformanceFixtureHarnessV1.loadC42CrossMarketCorpus()
        let composite = try CompositeAreaSafetyArchetypeV1.run()
        let controller = try ControllerZoneDistributionArchetypeV1.run()
        let compositeScenario = try CompositeAreaSafetyArchetypeV1.scenario()
        let controllerScenario = try ControllerZoneDistributionArchetypeV1.scenario()

        XCTAssertEqual(composite.archetypeID, CompositeAreaSafetyArchetypeV1.archetypeID)
        XCTAssertEqual(controller.archetypeID, ControllerZoneDistributionArchetypeV1.archetypeID)
        XCTAssertEqual(composite.generatorVersion, ModelRunReceiptV1.generatorVersion)
        XCTAssertEqual(controller.generatorVersion, ModelRunReceiptV1.generatorVersion)
        XCTAssertTrue(compositeScenario.capabilities.contains(.siteLocationCompositionArea))
        XCTAssertTrue(compositeScenario.capabilities.contains(.reportProjection))
        XCTAssertTrue(controllerScenario.capabilities.contains(.controllerZoneTopology))
        XCTAssertTrue(controllerScenario.capabilities.contains(.exactMeasurement))

        let sharedJourney: Set<ModelOperationKindV1> = [
            .canonicalRoundTrip, .backupRestore, .rebuildProjection,
            .deleteErase, .verifyReleaseExclusion
        ]
        XCTAssertTrue(sharedJourney.isSubset(of: Set(composite.operations.map(\.kind))))
        XCTAssertTrue(sharedJourney.isSubset(of: Set(controller.operations.map(\.kind))))
        XCTAssertTrue(Set(composite.operations.map(\.kind)).contains(.cloneFork))
        XCTAssertTrue(composite.operations.contains { $0.kind == .interruptAfterEffectBeforeReceipt })
        XCTAssertTrue(controller.operations.contains { $0.kind == .interruptAfterEffectBeforeReceipt })
        XCTAssertTrue(composite.scratchCleanupComplete)
        XCTAssertTrue(controller.scratchCleanupComplete)
        XCTAssertFalse(composite.acceptanceCredit)
        XCTAssertFalse(controller.acceptanceCredit)
        XCTAssertEqual(corpus.archetypes, [
            "CompositeAreaSafetyArchetypeV1",
            "ControllerZoneDistributionArchetypeV1",
        ])
        XCTAssertEqual(KernelConformanceFixtureHarnessV1.c42EvidenceIDs, [
            "V23-P03-C42-G01", "V23-P03-C42-A01", "V23-P03-C42-H01",
            "V23-P03-C42-I01", "V23-P03-C42-R01",
        ])

        let compositeBytes = try canonicalBytes(composite)
        let controllerBytes = try canonicalBytes(controller)
        XCTAssertFalse(compositeBytes.isEmpty)
        XCTAssertFalse(controllerBytes.isEmpty)
        XCTAssertNotEqual(composite.receiptSHA256, controller.receiptSHA256)

        let toolLock = try PortableContractToolLockReaderV1.readForCrossMarketConformance(
            at: KernelConformanceFixtureHarnessV1.toolLockURL()
        )
        let portableReceipts = try PortableContractValidatorAdapterV1(toolLock: toolLock)
            .validateCrossMarketCorpus(corpus.portableCases)
        XCTAssertEqual(portableReceipts.map(\.caseID), corpus.portableCases.map(\.id))
        XCTAssertEqual(Set(portableReceipts.map(\.classification)), [.accepted, .rejected])
        XCTAssertTrue(portableReceipts.allSatisfy {
            $0.toolDistributionSHA256 == toolLock.distributionSHA256
        })

        let historicDigests = try V907CompatibilitySupport.crossMarketHistoricReportDigests()
        XCTAssertFalse(historicDigests.isEmpty)
        XCTAssertTrue(historicDigests.values.allSatisfy(CrossMarketCanonicalV1.isSHA256))
        XCTAssertTrue(corpus.offlineSharedKernel)
        XCTAssertFalse(corpus.productPersistence)

        let compositeHarness = try KernelConformanceProductionHarnessV1(
            label: "C42-composite-area-safety"
        )
        let controllerHarness = try KernelConformanceProductionHarnessV1(
            label: "C42-controller-zone-distribution"
        )
        defer {
            compositeHarness.cleanup()
            controllerHarness.cleanup()
        }
        let compositeJourney = try await compositeHarness.exerciseCrossMarketArchetype(
            compositeScenario
        )
        let controllerJourney = try await controllerHarness.exerciseCrossMarketArchetype(
            controllerScenario
        )
        let compositeLifecycle = compositeJourney.lifecycle
        let controllerLifecycle = controllerJourney.lifecycle
        XCTAssertEqual(compositeJourney.archetypeID, compositeScenario.archetypeID)
        XCTAssertEqual(controllerJourney.archetypeID, controllerScenario.archetypeID)
        XCTAssertEqual(
            compositeJourney.semanticStateSHA256,
            try CrossMarketCanonicalV1.sha256(compositeScenario.semanticState)
        )
        XCTAssertEqual(
            controllerJourney.semanticStateSHA256,
            try CrossMarketCanonicalV1.sha256(controllerScenario.semanticState)
        )
        XCTAssertEqual(
            compositeJourney.semanticEntityCount,
            try compositeScenario.semanticState.semanticEntities().count
        )
        XCTAssertEqual(
            controllerJourney.semanticEntityCount,
            try controllerScenario.semanticState.semanticEntities().count
        )
        XCTAssertTrue(compositeJourney.canonicalWriterExecuted)
        XCTAssertTrue(compositeJourney.packageRegistryExecuted)
        XCTAssertTrue(compositeJourney.rendererExecuted)
        XCTAssertTrue(compositeJourney.archiveRestoreExecuted)
        XCTAssertTrue(compositeJourney.searchExecuted)
        XCTAssertTrue(compositeJourney.deleteEraseExecuted)
        XCTAssertTrue(controllerJourney.canonicalWriterExecuted)
        XCTAssertTrue(controllerJourney.packageRegistryExecuted)
        XCTAssertTrue(controllerJourney.rendererExecuted)
        XCTAssertTrue(controllerJourney.archiveRestoreExecuted)
        XCTAssertTrue(controllerJourney.searchExecuted)
        XCTAssertTrue(controllerJourney.deleteEraseExecuted)
        XCTAssertEqual(
            Set(compositeLifecycle.executedActions),
            Set(KernelConformanceFixtureHarnessV1.requiredLifecycle)
        )
        XCTAssertEqual(
            Set(controllerLifecycle.executedActions),
            Set(KernelConformanceFixtureHarnessV1.requiredLifecycle)
        )
        XCTAssertGreaterThan(compositeLifecycle.restoredAssetCount, 0)
        XCTAssertGreaterThan(controllerLifecycle.restoredAssetCount, 0)
        XCTAssertGreaterThan(compositeLifecycle.restoredReportCount, 0)
        XCTAssertGreaterThan(controllerLifecycle.restoredReportCount, 0)
    }

    func testV23P03C42A01FixedSeedModelRunsAreByteIdenticalAndBounded() throws {
        let corpus = try KernelConformanceFixtureHarnessV1.loadC42CrossMarketCorpus()
        let compositeFirst = try CompositeAreaSafetyArchetypeV1.run(seed: CompositeAreaSafetyArchetypeV1.defaultSeed)
        let compositeSecond = try CompositeAreaSafetyArchetypeV1.run(seed: CompositeAreaSafetyArchetypeV1.defaultSeed)
        let controllerFirst = try ControllerZoneDistributionArchetypeV1.run(seed: ControllerZoneDistributionArchetypeV1.defaultSeed)
        let controllerSecond = try ControllerZoneDistributionArchetypeV1.run(seed: ControllerZoneDistributionArchetypeV1.defaultSeed)

        XCTAssertEqual(try canonicalBytes(compositeFirst), try canonicalBytes(compositeSecond))
        XCTAssertEqual(try canonicalBytes(controllerFirst), try canonicalBytes(controllerSecond))
        XCTAssertEqual(compositeFirst.operations, compositeSecond.operations)
        XCTAssertEqual(controllerFirst.operations, controllerSecond.operations)

        var left = SeededModelGeneratorV1(seed: 42_2303)
        var right = SeededModelGeneratorV1(seed: 42_2303)
        for _ in 0..<16 {
            XCTAssertEqual(left.next(), right.next())
        }

        let bounds = compositeFirst.bounds
        try bounds.validate()
        let caseBudget = bounds.maximumCases
        let operationBudget = bounds.maximumOperationsPerCase
        let byteBudget = bounds.maximumScratchBytes
        let timeBudget = bounds.maximumDurationMilliseconds
        let shrinkBudget = bounds.maximumShrinkSteps
        XCTAssertEqual(caseBudget, 64)
        XCTAssertEqual(operationBudget, 64)
        XCTAssertEqual(byteBudget, 1_048_576)
        XCTAssertEqual(timeBudget, 5_000)
        XCTAssertEqual(shrinkBudget, 64)
        XCTAssertEqual(corpus.modelBounds.maximumCases, caseBudget)
        XCTAssertEqual(corpus.modelBounds.maximumOperationsPerCase, operationBudget)
        XCTAssertEqual(corpus.modelBounds.maximumScratchBytes, byteBudget)
        XCTAssertEqual(corpus.modelBounds.maximumDurationMilliseconds, timeBudget)
        XCTAssertEqual(corpus.modelBounds.maximumShrinkSteps, shrinkBudget)
        XCTAssertEqual(compositeFirst.executedCaseCount, caseBudget)
        XCTAssertEqual(controllerFirst.executedCaseCount, caseBudget)
        XCTAssertEqual(compositeFirst.caseResultSHA256s.count, caseBudget)
        XCTAssertEqual(controllerFirst.caseResultSHA256s.count, caseBudget)
        XCTAssertTrue(compositeFirst.caseResultSHA256s.allSatisfy(CrossMarketCanonicalV1.isSHA256))
        XCTAssertTrue(controllerFirst.caseResultSHA256s.allSatisfy(CrossMarketCanonicalV1.isSHA256))
        XCTAssertGreaterThanOrEqual(compositeFirst.executedOperationCount, caseBudget)
        XCTAssertGreaterThanOrEqual(controllerFirst.executedOperationCount, caseBudget)
        XCTAssertLessThanOrEqual(
            compositeFirst.executedOperationCount, caseBudget * operationBudget
        )
        XCTAssertLessThanOrEqual(
            controllerFirst.executedOperationCount,
            caseBudget * ControllerZoneDistributionArchetypeV1.bounds.maximumOperationsPerCase
        )
        XCTAssertGreaterThan(compositeFirst.scratchBytesRemoved, 0)
        XCTAssertGreaterThan(controllerFirst.scratchBytesRemoved, 0)
        XCTAssertLessThanOrEqual(compositeFirst.scratchBytesRemoved, byteBudget)
        XCTAssertLessThanOrEqual(controllerFirst.scratchBytesRemoved, byteBudget)
        XCTAssertLessThanOrEqual(compositeFirst.operations.count, operationBudget)
        XCTAssertLessThanOrEqual(controllerFirst.operations.count, ControllerZoneDistributionArchetypeV1.bounds.maximumOperationsPerCase)
        XCTAssertLessThanOrEqual(try canonicalBytes(compositeFirst).count, byteBudget)
        XCTAssertLessThanOrEqual(try canonicalBytes(controllerFirst).count, byteBudget)
        XCTAssertTrue(compositeFirst.operations.map(\.ordinal) == Array(1...compositeFirst.operations.count))
        XCTAssertTrue(controllerFirst.operations.map(\.ordinal) == Array(1...controllerFirst.operations.count))

        let otherSeed = try CompositeAreaSafetyArchetypeV1.run(
            seed: CompositeAreaSafetyArchetypeV1.defaultSeed &+ 1
        )
        XCTAssertNotEqual(try canonicalBytes(compositeFirst), try canonicalBytes(otherSeed))
        XCTAssertEqual(
            corpus.fixedSeeds["CompositeAreaSafetyArchetypeV1"],
            String(CompositeAreaSafetyArchetypeV1.defaultSeed)
        )
        XCTAssertEqual(
            corpus.fixedSeeds["ControllerZoneDistributionArchetypeV1"],
            String(ControllerZoneDistributionArchetypeV1.defaultSeed)
        )

        XCTAssertEqual(
            Set(corpus.hostileCases.map(\.vector)),
            Set(CrossMarketHostileVectorV1.allCases)
        )
    }

    func testV23P03C42H01HostileCorpusAndReleaseLeakageFailClosed() throws {
        let corpus = try KernelConformanceFixtureHarnessV1.loadC42CrossMarketCorpus()
        let hostileCases = corpus.hostileCases
        XCTAssertEqual(hostileCases.count, CrossMarketHostileVectorV1.allCases.count)
        XCTAssertEqual(Set(hostileCases.map(\.id)).count, hostileCases.count)
        XCTAssertEqual(
            Set(hostileCases.map(\.vector)),
            Set(CrossMarketHostileVectorV1.allCases)
        )
        let hostileReceipts = try KernelConformanceFixtureHarnessV1.executeC42HostileCases(
            hostileCases
        )
        XCTAssertEqual(hostileReceipts.map(\.id), hostileCases.map(\.id))
        XCTAssertEqual(hostileReceipts.map(\.vector), hostileCases.map(\.vector))
        XCTAssertTrue(hostileReceipts.allSatisfy { CrossMarketCanonicalV1.isSHA256($0.inputSHA256) })
        XCTAssertEqual(
            hostileReceipts.filter { $0.disposition == .recoveredExactlyOnce }
                .map(\.exactlyOnceEffectCount),
            [1]
        )
        let unicodeReceipt = try XCTUnwrap(hostileReceipts.first {
            $0.vector == .unicodeNonnormalized
        })
        XCTAssertEqual(unicodeReceipt.canonicalValue, "Café", "Unicode NFC must be deterministic")
        XCTAssertNotNil(
            hostileReceipts.first { $0.vector == .daylightSavingTransition },
            "DST timeZone transition hostile evidence must execute"
        )
        let requiredConcernReceipts: [(CrossMarketHostileVectorV1, String)] = [
            (.unknownFallback, "UNKNOWN"),
            (.stalePrerequisite, "stale"),
            (.destinationCardinality, "cardinality"),
            (.qualificationExpired, "qualification"),
            (.productIdentityCollision, "productIdentity"),
            (.lowStorageBoundary, "lowStorage"),
            (.symlinkEscape, "symlink"),
            (.decompressionBomb, "decompression"),
            (.bundleTamper, "tamper"),
            (.recoveryFrontier, "relaunch")
        ]
        for (vector, concern) in requiredConcernReceipts {
            XCTAssertNotNil(
                hostileReceipts.first { $0.vector == vector },
                "Missing executed hostile receipt for \(concern)"
            )
        }

        let invalidBounds = ModelRunBoundsV1(
            maximumCases: 0,
            maximumOperationsPerCase: 1,
            maximumShrinkSteps: 0,
            maximumScratchBytes: 1,
            maximumDurationMilliseconds: 1
        )
        XCTAssertThrowsError(try invalidBounds.validate()) { error in
            XCTAssertEqual(error as? CrossMarketConformanceFailureV1, .limitExceeded)
        }
        XCTAssertThrowsError(try ModelOperationV1(
            ordinal: 0,
            kind: .canonicalRoundTrip,
            payloadSHA256: String(repeating: "g", count: 64),
            expectedDisposition: .accepted
        ))

        let scenario = try CompositeAreaSafetyArchetypeV1.scenario()
        let failingScenario = try duplicateReplayScenario(from: scenario)
        XCTAssertThrowsError(try ModelConformanceRunnerV1.run(failingScenario, expectedInvariant: .replayConverges)) { error in
            guard let failure = error as? ModelConformanceRunFailureV1 else {
                return XCTFail("expected deterministic model failure, got \(error)")
            }
            XCTAssertEqual(failure.cause, .invariantViolated(.replayConverges))
            XCTAssertEqual(failure.fingerprint.invariant, .replayConverges)
            XCTAssertEqual(failure.fingerprint.faultBoundary, .replay)
            XCTAssertEqual(
                failure.fingerprint.causalOperations.map(\.kind),
                [.interruptAfterEffectBeforeReceipt, .replay, .replay]
            )
            XCTAssertNoThrow(try failure.counterexample.validate(
                bounds: scenario.bounds, preserving: failure.fingerprint
            ))
            XCTAssertNoThrow(try failure.diagnosticReceipt.validate())
            XCTAssertEqual(
                failure.diagnosticReceipt.fingerprint.fingerprintSHA256,
                failure.fingerprint.fingerprintSHA256
            )
            XCTAssertLessThan(
                failure.counterexample.operations.count,
                failingScenario.operations.count
            )
            XCTAssertGreaterThan(failure.counterexample.shrinkStepCount, 0)
        }

        let duplicateMutationScenario = try duplicateAcceptedMutationScenario(from: scenario)
        XCTAssertThrowsError(try ModelConformanceRunnerV1.run(
            duplicateMutationScenario, expectedInvariant: .oneWriterReceipt
        )) { error in
            guard let failure = error as? ModelConformanceRunFailureV1 else {
                return XCTFail("expected duplicate-mutation model failure, got \(error)")
            }
            XCTAssertEqual(failure.cause, .preconditionRejected)
            XCTAssertEqual(failure.fingerprint.invariant, .oneWriterReceipt)
            let duplicateMutationID = failure.fingerprint.duplicateMutationID
            XCTAssertNotNil(duplicateMutationID)
            XCTAssertEqual(
                failure.fingerprint.causalOperations.map(\.kind),
                [.append, .supersede]
            )
            XCTAssertEqual(
                failure.counterexample.operations.map(\.kind),
                [.append, .supersede]
            )
            XCTAssertEqual(
                failure.counterexample.operations.map(\.mutationID),
                [duplicateMutationID, duplicateMutationID]
            )
            XCTAssertNoThrow(try failure.counterexample.validate(
                bounds: scenario.bounds, preserving: failure.fingerprint
            ))
        }

        XCTAssertThrowsError(try ReleaseExclusionObservationV1(
            surface: .sourceMembership,
            sourceIdentity: .repositoryProjectFile,
            repositoryRelativeInputs: ["FieldEvidenceApp.xcodeproj/project.pbxproj"],
            artifactIdentity: "C42-hostile",
            evidenceBytes: Data("CompositeAreaSafetyArchetypeV1".utf8),
            forbiddenMatches: ["CompositeAreaSafetyArchetypeV1"]
        )) { error in
            XCTAssertEqual(error as? CrossMarketConformanceFailureV1, .releaseLeak("SOURCE_MEMBERSHIP"))
        }
        XCTAssertThrowsError(
            try PortableContractValidatorAdapterV1(
                toolLock: PortableContractToolLockReaderV1.readForCrossMarketConformance(
                    at: KernelConformanceFixtureHarnessV1.toolLockURL()
                )
            ).validateCrossMarketCorpus([])
        ) { error in
            XCTAssertEqual(error as? PortableContractValidationFailureV1, .invalidCorpus)
        }
        let receipt = try makeReleaseExclusionReceipt(corpus: corpus)
        XCTAssertEqual(receipt.observations.count, 13)
        XCTAssertEqual(receipt.observations.map(\.surface), ReleaseExclusionSurfaceV1.allCases.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(receipt.testSupportPaths.count, 4)
        XCTAssertTrue(receipt.testSupportPaths.allSatisfy { $0.contains("TestSupport") })
        XCTAssertTrue(receipt.forbiddenReleaseSymbols.contains("ControllerZoneDistributionArchetypeV1"))
        try receipt.validate()
        XCTAssertFalse(receipt.isComplete)
        XCTAssertFalse(receipt.certifiesReleaseExclusion)
        XCTAssertEqual(
            receipt.observations.filter { $0.disposition == .staticPendingNative }
                .map(\.surface),
            ReleaseExclusionSurfaceV1.allCases.filter(\.requiresNativeOrExternalEvidence)
                .sorted { $0.rawValue < $1.rawValue }
        )
        XCTAssertNil(Bundle.main.url(
            forResource: "V22P03C42CrossMarketConformanceCorpusV1",
            withExtension: "json"
        ))
        XCTAssertFalse(try bundleResourceInventory().contains {
            $0.localizedCaseInsensitiveContains("CrossMarketConformance")
        })
        XCTAssertFalse(corpus.containsCustomerData)
        XCTAssertFalse(corpus.containsLicensedContent)
    }

    func testV23P03C42I01EveryStagedBoundaryConvergesAfterInterruption() async throws {
        let scenarios = [
            try CompositeAreaSafetyArchetypeV1.scenario(),
            try ControllerZoneDistributionArchetypeV1.scenario()
        ]
        for scenario in scenarios {
            let expected: ModelInvariantV1 = scenario.archetypeID == CompositeAreaSafetyArchetypeV1.archetypeID
                ? .replayConverges : .boundedExecution
            let receipt = try ModelConformanceRunnerV1.run(scenario, expectedInvariant: expected)
            let kinds = receipt.operations.map(\.kind)
            XCTAssertTrue(kinds.contains(.interruptAfterEffectBeforeReceipt))
            XCTAssertTrue(kinds.contains(.replay))
            if let interrupted = kinds.firstIndex(of: .interruptAfterEffectBeforeReceipt),
               let replay = kinds.firstIndex(of: .replay) {
                XCTAssertLessThan(interrupted, replay)
            } else {
                XCTFail("missing effect-before-receipt/replay boundary")
            }
            if scenario.archetypeID == CompositeAreaSafetyArchetypeV1.archetypeID {
                XCTAssertTrue(kinds.contains(.interruptBeforeEffect))
            }
            XCTAssertGreaterThan(receipt.scratchBytesRemoved, 0)
            XCTAssertLessThanOrEqual(receipt.scratchBytesRemoved, scenario.bounds.maximumScratchBytes)
            XCTAssertTrue(receipt.scratchCleanupComplete)
            XCTAssertFalse(receipt.acceptanceCredit)
            let mutationIDs = receipt.operations.compactMap(\.mutationID)
            XCTAssertEqual(Set(mutationIDs).count, mutationIDs.count)
            XCTAssertEqual(try canonicalBytes(receipt), try canonicalBytes(receipt))
        }

        let boundaryHarness = try KernelConformanceProductionHarnessV1(
            label: "C42-every-staged-writer-boundary"
        )
        defer { boundaryHarness.cleanup() }
        let boundaryReceipts = try await boundaryHarness.exerciseProductionFaultBoundaries(
            Array(KernelConformanceProductionHarnessV1.productionExecutedFaultBoundaries)
        )
        XCTAssertEqual(
            Set(boundaryReceipts.map(\.boundary)),
            KernelConformanceProductionHarnessV1.productionExecutedFaultBoundaries
        )
        XCTAssertEqual(
            boundaryReceipts.map(\.boundary),
            KernelConformanceProductionHarnessV1.productionExecutedFaultBoundaries.sorted()
        )
        XCTAssertTrue(boundaryReceipts.allSatisfy(\.coldRecoverySucceeded))
        XCTAssertTrue(boundaryReceipts.allSatisfy(\.noPartialAuthority))
        XCTAssertTrue(boundaryReceipts.allSatisfy { !$0.visibleFailure.isEmpty })
        XCTAssertTrue(boundaryReceipts.allSatisfy { !$0.operationAttempted.isEmpty })
        XCTAssertTrue(boundaryReceipts.allSatisfy { $0.recoveryOperation.contains("cold-") })
        XCTAssertTrue(boundaryReceipts.allSatisfy { $0.residualIntentCount == 0 })
        XCTAssertTrue(boundaryReceipts.allSatisfy { $0.orphanPathCount == 0 })

        let repeated = try CompositeAreaSafetyArchetypeV1.run(seed: CompositeAreaSafetyArchetypeV1.defaultSeed)
        let retried = try CompositeAreaSafetyArchetypeV1.run(seed: CompositeAreaSafetyArchetypeV1.defaultSeed)
        XCTAssertEqual(repeated.receiptSHA256, retried.receiptSHA256)
        XCTAssertEqual(try canonicalBytes(repeated), try canonicalBytes(retried))
    }

    func testV23P03C42R01PromotedCounterexamplesReplayAndReleaseExclusionRemainsExact() throws {
        let corpus = try KernelConformanceFixtureHarnessV1.loadC42CrossMarketCorpus()
        let scenario = try CompositeAreaSafetyArchetypeV1.scenario()
        let corpusBytes = try corpusData()
        let corpusSHA256 = SHA256.hash(data: corpusBytes)
            .map { String(format: "%02x", $0) }.joined()
        let failingScenario = try duplicateReplayScenario(from: scenario)
        let failure: ModelConformanceRunFailureV1
        do {
            _ = try ModelConformanceRunnerV1.run(
                failingScenario, expectedInvariant: .replayConverges
            )
            throw CrossMarketConformanceFailureV1.invariantViolated(.oneWriterReceipt)
        } catch let observed as ModelConformanceRunFailureV1 {
            failure = observed
        }
        XCTAssertEqual(failure.cause, .invariantViolated(.replayConverges))
        XCTAssertEqual(failure.fingerprint.invariant, .replayConverges)
        XCTAssertEqual(failure.fingerprint.faultBoundary, .replay)
        XCTAssertEqual(
            failure.fingerprint.causalOperations.map(\.kind),
            [.interruptAfterEffectBeforeReceipt, .replay, .replay]
        )
        XCTAssertNil(failure.fingerprint.duplicateMutationID)
        XCTAssertTrue(CrossMarketCanonicalV1.isSHA256(failure.fingerprint.fingerprintSHA256))
        let counterexample = failure.counterexample
        try counterexample.validate(bounds: scenario.bounds, preserving: failure.fingerprint)
        XCTAssertLessThan(counterexample.operations.count, failingScenario.operations.count)
        XCTAssertGreaterThan(counterexample.shrinkStepCount, 0)
        XCTAssertEqual(counterexample.invariant, .replayConverges)
        XCTAssertEqual(counterexample.operations.map(\.ordinal), Array(1...counterexample.operations.count))
        XCTAssertEqual(
            counterexample.operations.map(\.kind),
            [.interruptAfterEffectBeforeReceipt, .replay, .replay]
        )
        try failure.diagnosticReceipt.validate()
        XCTAssertEqual(failure.diagnosticReceipt.counterexample, counterexample)
        XCTAssertEqual(failure.diagnosticReceipt.fingerprint, failure.fingerprint)
        XCTAssertTrue(CrossMarketCanonicalV1.isSHA256(failure.diagnosticReceipt.receiptSHA256))
        XCTAssertEqual(
            try ModelConformanceRunnerV1.replay(
                failure.diagnosticReceipt, in: failingScenario
            ),
            failure.fingerprint
        )
        let promotedFixture = try XCTUnwrap(corpus.promotedCounterexamples.first {
            $0.invariant == ModelInvariantV1.replayConverges.rawValue
        })
        XCTAssertEqual(
            promotedFixture.operationKinds,
            counterexample.operations.map(\.kind.rawValue)
        )
        let promotion = try DeterministicRegressionPromotionReceiptV1(
            sourceDiagnosticReceipt: failure.diagnosticReceipt,
            promotedFixtureRelativePath: "FieldEvidenceAppTests/Fixtures/V22/CrossMarketConformance/V22P03C42CrossMarketConformanceCorpusV1.json",
            promotedFixtureSHA256: corpusSHA256,
            bounds: scenario.bounds
        )
        try promotion.validate(bounds: scenario.bounds)
        let promotedBytes = try CrossMarketCanonicalV1.data(promotion)
        let decodedPromotion = try CrossMarketCanonicalV1.decode(
            DeterministicRegressionPromotionReceiptV1.self,
            from: promotedBytes
        )
        XCTAssertEqual(decodedPromotion, promotion)
        XCTAssertEqual(promotion.sourceDiagnosticReceipt, failure.diagnosticReceipt)
        XCTAssertEqual(
            promotion.sourceFailingDiagnosticReceiptSHA256,
            failure.diagnosticReceipt.receiptSHA256
        )
        XCTAssertEqual(promotion.promotedFixtureSHA256, corpusSHA256)
        XCTAssertEqual(
            promotion.promotedFixtureRelativePath,
            "FieldEvidenceAppTests/Fixtures/V22/CrossMarketConformance/V22P03C42CrossMarketConformanceCorpusV1.json"
        )

        let faultingReplay = try XCTUnwrap(counterexample.operations.last)
        XCTAssertEqual(faultingReplay.kind, .replay)
        let semanticDegenerateCounterexample = MinimizedCounterexampleV1(
            invariant: .replayConverges,
            originalOperationCount: counterexample.originalOperationCount,
            operations: [try faultingReplay.replacingOrdinal(1)],
            shrinkStepCount: counterexample.shrinkStepCount
        )
        XCTAssertNoThrow(try semanticDegenerateCounterexample.validate(bounds: scenario.bounds))
        XCTAssertThrowsError(try semanticDegenerateCounterexample.validate(
            bounds: scenario.bounds, preserving: failure.fingerprint
        )) { error in
            XCTAssertEqual(error as? CrossMarketConformanceFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(try ModelFailingDiagnosticReceiptV1(
            archetypeID: failingScenario.archetypeID,
            seed: failingScenario.seed,
            bounds: failingScenario.bounds,
            sourceScenarioSHA256: failure.diagnosticReceipt.sourceScenarioSHA256,
            fingerprint: failure.fingerprint,
            counterexample: semanticDegenerateCounterexample
        )) { error in
            XCTAssertEqual(error as? CrossMarketConformanceFailureV1, .invalidValue)
        }

        let receipt = try makeReleaseExclusionReceipt(corpus: corpus)
        let releaseBytes = try CrossMarketCanonicalV1.data(receipt)
        let decodedRelease = try CrossMarketCanonicalV1.decode(ReleaseExclusionReceiptV1.self, from: releaseBytes)
        XCTAssertEqual(decodedRelease, receipt)
        XCTAssertTrue(receipt.generatedScratchRemoved)
        XCTAssertEqual(receipt.releaseConfiguration, "Release")
        XCTAssertFalse(receipt.isComplete)
        XCTAssertFalse(receipt.certifiesReleaseExclusion)

        XCTAssertTrue(corpus.migrationIsolatedCopies)
        XCTAssertTrue(corpus.historicSignReportByteParity)
        XCTAssertTrue(corpus.historicLightingReportByteParity)
        XCTAssertFalse(corpus.runtimeProductPersistence)
        XCTAssertFalse(corpus.promotedCounterexamples.isEmpty)
        XCTAssertTrue(corpus.promotedCounterexamples.allSatisfy(\.immutable))
        let operationKinds = Set(scenario.operations.map { $0.kind.rawValue })
        XCTAssertTrue(corpus.promotedCounterexamples.allSatisfy {
            Set($0.operationKinds).isSubset(of: operationKinds)
                || $0.invariant == ModelInvariantV1.immutableHistory.rawValue
        })
        let surfaces = corpus.releaseExclusionSurfaces
        XCTAssertEqual(Set(surfaces).count, 13)
        XCTAssertTrue(surfaces.contains("COMPILED_ARCHIVE"))
        XCTAssertTrue(surfaces.contains("RUNTIME_SURFACE"))
    }

    private func canonicalBytes<T: Codable & Equatable>(_ value: T) throws -> Data {
        let bytes = try CrossMarketCanonicalV1.data(value)
        let decoded = try CrossMarketCanonicalV1.decode(T.self, from: bytes)
        XCTAssertEqual(decoded, value)
        return bytes
    }

    private func duplicateReplayScenario(
        from scenario: CrossMarketArchetypeScenarioV1
    ) throws -> CrossMarketArchetypeScenarioV1 {
        let replayIndex = try XCTUnwrap(
            scenario.operations.firstIndex { $0.kind == .replay }
        )
        let originalReplay = scenario.operations[replayIndex]
        let duplicateReplay = try ModelOperationV1(
            ordinal: originalReplay.ordinal + 1,
            kind: .replay,
            payloadSHA256: try CrossMarketCanonicalV1.sha256([
                "C42.DUPLICATE.REPLAY.V1", originalReplay.payloadSHA256
            ]),
            expectedDisposition: .idempotentReplay
        )
        var operations = scenario.operations
        operations.insert(duplicateReplay, at: replayIndex + 1)
        operations = try operations.enumerated().map {
            try $0.element.replacingOrdinal($0.offset + 1)
        }
        return CrossMarketArchetypeScenarioV1(
            archetypeID: scenario.archetypeID,
            archetypeVersion: scenario.archetypeVersion,
            seed: scenario.seed,
            bounds: scenario.bounds,
            operations: operations,
            semanticState: scenario.semanticState,
            capabilities: scenario.capabilities,
            expectedInvariants: scenario.expectedInvariants
        )
    }

    private func duplicateAcceptedMutationScenario(
        from scenario: CrossMarketArchetypeScenarioV1
    ) throws -> CrossMarketArchetypeScenarioV1 {
        let firstAppend = try XCTUnwrap(scenario.operations.first { $0.kind == .append })
        let duplicate = try ModelOperationV1(
            ordinal: scenario.operations.count + 1,
            kind: .supersede,
            entityKind: firstAppend.entityKind,
            entityID: firstAppend.entityID,
            expectedRevision: 1,
            resultingRevision: 2,
            mutationID: firstAppend.mutationID,
            payloadSHA256: firstAppend.payloadSHA256,
            expectedDisposition: .accepted
        )
        return CrossMarketArchetypeScenarioV1(
            archetypeID: scenario.archetypeID,
            archetypeVersion: scenario.archetypeVersion,
            seed: scenario.seed,
            bounds: scenario.bounds,
            operations: scenario.operations + [duplicate],
            semanticState: scenario.semanticState,
            capabilities: scenario.capabilities,
            expectedInvariants: scenario.expectedInvariants
        )
    }

    private func corpusURL() -> URL {
        KernelConformanceFixtureHarnessV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V22/CrossMarketConformance/V22P03C42CrossMarketConformanceCorpusV1.json"
        )
    }

    private func corpusData() throws -> Data {
        try Data(contentsOf: corpusURL(), options: [.mappedIfSafe])
    }

    private func makeReleaseExclusionReceipt(
        corpus: CrossMarketConformanceCorpusFixtureV1
    ) throws -> ReleaseExclusionReceiptV1 {
        let observations = try corpus.releaseScanInputs.map { scan in
            let surface = scan.surface
            XCTAssertEqual(scan.evidenceKind, surface.requiredEvidenceKind)
            XCTAssertEqual(scan.sourceIdentity, surface.requiredSourceIdentity)
            if scan.expectedDisposition == .staticPendingNative {
                XCTAssertTrue(surface.requiresNativeOrExternalEvidence)
                return try ReleaseExclusionObservationV1.staticPendingNative(
                    surface: surface,
                    repositoryRelativeInputs: scan.repositoryRelativeInputs
                )
            }
            XCTAssertFalse(surface.requiresNativeOrExternalEvidence)
            let artifact = try releaseStaticArtifact(scan: scan)
            let forbiddenMatches = ReleaseExclusionReceiptV1.forbiddenReleaseSymbols.filter {
                artifact.text.contains($0)
            }
            try ReleaseExclusionObservationV1(
                surface: surface,
                sourceIdentity: surface.requiredSourceIdentity,
                repositoryRelativeInputs: artifact.inputs,
                artifactIdentity: artifact.identity,
                evidenceBytes: artifact.data,
                forbiddenMatches: forbiddenMatches
            )
        }
        return try ReleaseExclusionReceiptV1(
            observations: observations,
            hostileFixtureCount: corpus.hostileCases.count,
            generatedScratchRemoved: true
        )
    }

    private func releaseStaticArtifact(
        scan: CrossMarketReleaseScanInputFixtureV1
    ) throws -> (identity: String, inputs: [String], data: Data, text: String) {
        let surface = scan.surface
        guard !surface.requiresNativeOrExternalEvidence else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        let inputs = scan.repositoryRelativeInputs
        let data = try boundedRepositoryInventory(relativePaths: inputs)
        return (
            "C42_STATIC_\(surface.rawValue)",
            inputs,
            data,
            String(decoding: data, as: UTF8.self)
        )
    }

    private func boundedRepositoryInventory(relativePaths: [String]) throws -> Data {
        let root = KernelConformanceFixtureHarnessV1.sourceRoot()
        var data = Data()
        for relativePath in relativePaths.sorted() {
            let url = root.appendingPathComponent(relativePath).standardizedFileURL
            guard url.pathComponents.starts(with: root.standardizedFileURL.pathComponents),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
            data.append(Data(relativePath.utf8))
            data.append(0x0a)
            data.append(try Data(contentsOf: url, options: [.mappedIfSafe]))
            data.append(0x0a)
            guard data.count <= CrossMarketCanonicalV1.maximumCanonicalBytes else {
                throw CrossMarketConformanceFailureV1.limitExceeded
            }
        }
        return data
    }

    private func bundleResourceInventory() throws -> [String] {
        guard let root = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return try enumerator.compactMap { item -> String? in
            guard let url = item as? URL,
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return nil
            }
            return url.path.replacingOccurrences(of: root.path, with: "")
        }.sorted()
    }
}

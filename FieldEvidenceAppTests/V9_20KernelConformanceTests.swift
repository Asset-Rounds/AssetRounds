import XCTest
import Foundation
import SwiftData
@testable import FieldEvidenceApp

private final class C45KernelConformanceCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityUsesClosedChecksumAlphabetAndCanonicalLimit() {
        XCTAssertEqual(ManualShortCodeV1.alphabet, "23456789ABCDEFGHJKMNPQRSTUVWXYZ")
        XCTAssertEqual(ManualShortCodeV1.randomBodyLength, 10)
        XCTAssertEqual(AssetLabelOpaqueQRPayloadV1.maximumPayloadBytes, 64)
    }
}

private final class C30EvidenceContextAnchorV9_20KernelConformance: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

@MainActor
final class V9_20KernelConformanceTests: XCTestCase {
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
    func testV9_20G01BothFixtureShapesCompleteFullLifecycleWithPortableSchemaParity() async throws {
        let checklist = try KernelConformanceFixtureHarnessV1.loadManifest(.checklist)
        let measurement = try KernelConformanceFixtureHarnessV1.loadManifest(.measurementRepeat)
        let graph = try KernelConformanceFixtureHarnessV1.loadScenarioGraph()
        let corpus = try KernelConformanceFixtureHarnessV1.loadPortableCorpus()
        XCTAssertNotEqual(checklist.shapeID, measurement.shapeID)
        XCTAssertNotEqual(checklist.expectedNormalizedProjection.sha256, measurement.expectedNormalizedProjection.sha256)
        XCTAssertEqual(Set(graph.selectorBindings.map(\.selector)), Set(KernelConformanceFixtureHarnessV1.selectors))

        let c06Corpus = try KernelConformanceFixtureHarnessV1.readRequiredData(
            KernelConformanceFixtureHarnessV1.c06CorpusURL()
        )
        let c06Schema = try KernelConformanceFixtureHarnessV1.readRequiredData(
            KernelConformanceFixtureHarnessV1.c06SchemaURL()
        )
        let c06CorpusObject = try XCTUnwrap(JSONSerialization.jsonObject(with: c06Corpus) as? [String: Any])
        let c06SchemaObject = try XCTUnwrap(JSONSerialization.jsonObject(with: c06Schema) as? [String: Any])
        XCTAssertEqual(c06CorpusObject["schema"] as? String, "V21P03C06SnapshotProjectionCorpusV1")
        XCTAssertEqual(c06SchemaObject["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")

        let lock = try PortableContractToolLockReaderV1.read(at: KernelConformanceFixtureHarnessV1.toolLockURL())
        let adapter = try PortableContractValidatorAdapterV1(toolLock: lock)
        let receipts = try corpus.cases.map { try adapter.validate($0) }
        XCTAssertEqual(receipts.map(\.caseID), corpus.cases.map(\.id))
        XCTAssertEqual(Set(receipts.map(\.classification)), [.accepted, .rejected])
        XCTAssertTrue(receipts.allSatisfy {
            !$0.inputSHA256.isEmpty && $0.toolDistributionSHA256 == lock.distributionSHA256
        })

        let evidenceReceiptURL = KernelConformanceFixtureHarnessV1.sourceRoot()
            .appendingPathComponent(
                "docs/design/v23/tooling/V23P03C10KernelConformanceEvidenceReceiptV1.json"
            )
        let evidenceData = try KernelConformanceFixtureHarnessV1.readRequiredData(evidenceReceiptURL)
        let evidenceRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: evidenceData) as? [String: Any]
        )
        let portableReceipt = try XCTUnwrap(
            evidenceRoot["portableValidationReceipts"] as? [String: Any]
        )
        let pythonCases = try XCTUnwrap(portableReceipt["cases"] as? [[String: Any]])
        let lockSHA256 = KernelConformanceFixtureHarnessV1.sha256(
            try KernelConformanceFixtureHarnessV1.readRequiredData(
                KernelConformanceFixtureHarnessV1.toolLockURL()
            )
        )
        XCTAssertEqual(portableReceipt["toolID"] as? String, lock.tool.toolID)
        XCTAssertEqual(portableReceipt["toolSourceSHA256"] as? String, lock.distributionSHA256)
        XCTAssertEqual(portableReceipt["lockSHA256"] as? String, lockSHA256)
        XCTAssertEqual(portableReceipt["networkFetchCount"] as? Int, 0)
        XCTAssertEqual(portableReceipt["deterministicReplayMatched"] as? Bool, true)
        XCTAssertEqual(pythonCases.count, 10)
        XCTAssertEqual(pythonCases.count, receipts.count)
        XCTAssertEqual(
            pythonCases.compactMap { $0["caseID"] as? String },
            corpus.cases.map(\.id)
        )
        XCTAssertEqual(Set(pythonCases.compactMap { $0["caseID"] as? String }).count, 10)
        for (swift, python) in zip(receipts, pythonCases) {
            XCTAssertEqual(python["caseID"] as? String, swift.caseID)
            XCTAssertEqual(python["classification"] as? String, swift.classification.rawValue)
            XCTAssertEqual(python["instancePath"] as? String, swift.instancePath)
            XCTAssertEqual(python["schemaPath"] as? String, swift.schemaPath)
            XCTAssertEqual(python["inputSHA256"] as? String, swift.inputSHA256)
            XCTAssertEqual(python["toolSourceSHA256"] as? String, lock.distributionSHA256)
            XCTAssertEqual(python["lockSHA256"] as? String, lockSHA256)
            XCTAssertEqual(python["deterministicReplayMatched"] as? Bool, true)
        }

        for (shape, manifest) in [(KernelConformanceFixtureShapeV1.checklist, checklist), (.measurementRepeat, measurement)] {
            let harness = try KernelConformanceProductionHarnessV1(label: shape.resourceName)
            defer { harness.cleanup() }
            let trace = try await harness.exerciseFullLifecycle(shape: shape)
            let expectedActions = manifest.lifecycleTransitions
                .sorted { $0.sequence < $1.sequence }
                .map(\.action)
            XCTAssertEqual(trace.shapeID, manifest.shapeID)
            XCTAssertEqual(trace.executedActions, expectedActions)
            XCTAssertGreaterThan(trace.sourceRevision.commitRevision, 0)
            XCTAssertGreaterThan(trace.indexedRecordCount, 0)
            XCTAssertGreaterThan(trace.restoredAssetCount, 0)
            XCTAssertGreaterThan(trace.restoredReportCount, 0)
            XCTAssertNotEqual(trace.deletionID, UUID())
            XCTAssertTrue(trace.erasedWorkspaceIsEmpty)
        }
    }

    func testV9_20A01EveryPublicationBoundaryFaultRecoversWithoutPartialAuthority() async throws {
        let manifests = try KernelConformanceFixtureShapeV1.allCases.map {
            try KernelConformanceFixtureHarnessV1.loadManifest($0)
        }
        let boundaries = Set(manifests.flatMap(\.faultInjections).map(\.boundary))
        XCTAssertEqual(boundaries, Set(KernelConformanceFixtureHarnessV1.productionFaultIdentities.keys))
        XCTAssertEqual(boundaries.count, 53)
        let requiredFamilies = [
            "FINALIZATION_", "WORK_", "REPORT_", "JOURNAL_", "RESTORE_",
            "DELETE_", "ERASE_", "SEARCH_",
        ]
        for family in requiredFamilies {
            XCTAssertTrue(boundaries.contains(where: { $0.hasPrefix(family) }), "Missing fault family \(family)")
        }
        let faults = Dictionary(
            manifests.flatMap(\.faultInjections).map { ($0.boundary, $0) },
            uniquingKeysWith: { first, second in
                XCTAssertEqual(first, second)
                return first
            }
        )
        XCTAssertEqual(faults.count, boundaries.count)
        XCTAssertTrue(Array(faults.values).allSatisfy {
            !$0.expectedDisposition.isEmpty
                && !$0.selectors.isEmpty
                && !$0.evidenceIDs.isEmpty
                && ($0.recoveryAction == "RECOVER" || $0.recoveryAction == "RESUME")
        })
        let harness = try KernelConformanceProductionHarnessV1(label: "fault-matrix")
        defer { harness.cleanup() }
        let receipts = try await harness.exerciseProductionFaultBoundaries(boundaries.sorted())
        XCTAssertEqual(receipts.count, 53)
        XCTAssertEqual(Set(receipts.map(\.boundary)), boundaries)
        for receipt in receipts {
            XCTAssertFalse(receipt.family.isEmpty, receipt.boundary)
            XCTAssertFalse(receipt.visibleFailure.isEmpty, receipt.boundary)
            XCTAssertFalse(receipt.operationAttempted.isEmpty, receipt.boundary)
            XCTAssertFalse(receipt.recoveryOperation.isEmpty, receipt.boundary)
            XCTAssertTrue(receipt.coldRecoverySucceeded, receipt.boundary)
            XCTAssertTrue(receipt.noPartialAuthority, receipt.boundary)
            XCTAssertGreaterThanOrEqual(receipt.canonicalRowCount, 0, receipt.boundary)
            XCTAssertEqual(receipt.residualIntentCount, 0, receipt.boundary)
            XCTAssertEqual(receipt.orphanPathCount, 0, receipt.boundary)
        }
    }

    func testV9_20H01HostilePortableCorpusFixtureLeakAndReleaseHooksFailClosed() async throws {
        let manifests = try KernelConformanceFixtureShapeV1.allCases.map {
            try KernelConformanceFixtureHarnessV1.loadManifest($0)
        }
        let corpus = try KernelConformanceFixtureHarnessV1.loadPortableCorpus()
        let lock = try PortableContractToolLockReaderV1.read(at: KernelConformanceFixtureHarnessV1.toolLockURL())
        XCTAssertFalse(lock.networkFetchAllowed)
        XCTAssertTrue(manifests.allSatisfy {
            $0.releaseAbsence.testOnly
                && !$0.releaseAbsence.shippingAdoptionEnabled
                && !$0.releaseAbsence.acceptanceCredit
                && !$0.releaseAbsence.releaseCredit
        })
        let fixtureResourceNames = [
            "V21P03C10ChecklistFixtureManifestV1",
            "V21P03C10MeasurementRepeatFixtureManifestV1",
            "V21P03C10KernelConformanceScenarioGraphV1",
            "V21P03C10PortableContractCorpusV1",
        ]
        for resourceName in fixtureResourceNames {
            XCTAssertNil(Bundle.main.url(forResource: resourceName, withExtension: "json"))
        }

        let hostile = corpus.cases.filter { $0.expectedClass == .rejected }
        XCTAssertFalse(hostile.isEmpty)
        XCTAssertTrue(hostile.allSatisfy { !$0.instancePath.isEmpty && !$0.schemaPath.isEmpty })
        let adapter = try PortableContractValidatorAdapterV1(toolLock: lock)
        let hostileReceipts = try hostile.map { try adapter.validate($0) }
        XCTAssertTrue(hostileReceipts.allSatisfy {
            $0.classification == .rejected
                && !$0.instancePath.isEmpty
                && !$0.schemaPath.isEmpty
        })
        let crash = try XCTUnwrap(hostileReceipts.first { $0.caseID == "crash-before-publication" })
        let lowSpace = try XCTUnwrap(hostileReceipts.first { $0.caseID == "low-space-during-publication" })
        let protectedData = try XCTUnwrap(hostileReceipts.first { $0.caseID == "protected-data-after-publication" })
        let tamper = try XCTUnwrap(hostileReceipts.first { $0.caseID == "tamper-after-publication" })
        XCTAssertEqual(Set([crash, lowSpace, protectedData, tamper].map(\.classification)), [.rejected])

        for (token, boundary) in [
            ("cancellation", "SEARCH_CANCELLATION"),
            ("stale", "SEARCH_STALE"),
        ] {
            let harness = try KernelConformanceProductionHarnessV1(label: "hostile-\(token)")
            defer { harness.cleanup() }
            let receipt = try await harness.exerciseSearchFaultBoundary(boundary)
            XCTAssertEqual(receipt.boundary, boundary)
            XCTAssertFalse(receipt.visibleFailure.isEmpty)
            XCTAssertTrue(receipt.coldRecoverySucceeded)
            XCTAssertTrue(receipt.noPartialAuthority)
        }
        let productionSources = try productionSwiftSources()
        for source in productionSources {
            let text = try String(contentsOf: source, encoding: .utf8)
            XCTAssertFalse(text.contains("KernelConformance"), source.path)
            XCTAssertFalse(text.contains("PortableContract"), source.path)
            for resourceName in fixtureResourceNames {
                XCTAssertFalse(text.contains(resourceName), source.path)
            }
        }
        let harnessAndFaultHookMarkers = [
            "KernelConformanceFixtureHarnessV1",
            "KernelConformanceProductionHarnessV1",
            "KernelConformanceFaultBoundaryReceiptV1",
            "PortableContractValidatorAdapterV1",
            "PortableContractToolLockReaderV1",
            "V21-P03-C10-CHECKLIST-FIXTURE-V1",
            "V21-P03-C10-MEASUREMENT-REPEAT-FIXTURE-V1",
            "V23-P03-C10-A01",
            "BackupRestoreFailureInjection",
            "EraseAllFailureInjection",
            "WorkCoordinatorFailureInjection",
            "ReportRenderFailureInjection",
            "ReportRecoveryFailureInjection",
            "WholeSignDeletionFailureInjection",
            "FinalizationIntentStoreFailureInjection",
            "FinalizationServiceFailureInjection",
        ]
        if _isDebugAssertConfiguration() {
            XCTAssertTrue(manifests.allSatisfy {
                !$0.releaseAbsence.nativeCompileRan
                    && !$0.releaseAbsence.hostedDispatchRan
                    && $0.releaseAbsence.requiresAcceptedS10_6Reconciliation
            })
        } else {
            let releaseExecutableURL = try XCTUnwrap(Bundle.main.executableURL)
            let releaseExecutable = try Data(
                contentsOf: releaseExecutableURL, options: [.mappedIfSafe]
            )
            for marker in harnessAndFaultHookMarkers {
                XCTAssertNil(
                    releaseExecutable.range(of: Data(marker.utf8)),
                    "Release executable contains test-only harness/fault hook: \(marker)"
                )
            }
        }
    }

    func testV9_20I01RelaunchResumesOrCleansEveryDurableBoundaryDeterministically() async throws {
        let graph = try KernelConformanceFixtureHarnessV1.loadScenarioGraph()
        let manifests = try KernelConformanceFixtureShapeV1.allCases.map {
            try KernelConformanceFixtureHarnessV1.loadManifest($0)
        }
        let interruptionSelector = KernelConformanceFixtureHarnessV1.selectors[3]
        let binding = try XCTUnwrap(graph.selectorBindings.first { $0.selector == interruptionSelector })
        let durable = Set(manifests.flatMap(\.faultInjections).filter {
            $0.selectors.contains(interruptionSelector)
        }.map(\.boundary))
        XCTAssertFalse(durable.isEmpty)
        XCTAssertEqual(Set(binding.boundaries), durable)
        XCTAssertTrue(manifests.flatMap(\.faultInjections).filter {
            durable.contains($0.boundary)
        }.allSatisfy {
            $0.expectedDisposition.contains("ZERO_OR_COMPLETE")
                || $0.expectedDisposition.contains("OLD_OR_NEW")
                || $0.expectedDisposition.contains("OLD_OR_EMPTY")
                || $0.expectedDisposition.contains("FORWARD_ONLY")
                || $0.expectedDisposition.contains("EXACTLY_ONCE")
                || $0.expectedDisposition.contains("REPLAY_TWICE")
                || $0.expectedDisposition.contains("CHECKPOINT")
        })

        let harness = try KernelConformanceProductionHarnessV1(label: "durable-relaunch-matrix")
        defer { harness.cleanup() }
        let firstReceipts = try await harness.exerciseProductionFaultBoundaries(durable.sorted())
        let secondReceipts = try await harness.exerciseProductionFaultBoundaries(durable.sorted())
        XCTAssertEqual(Set(firstReceipts.map(\.boundary)), durable)
        XCTAssertEqual(firstReceipts, secondReceipts)
        for receipt in firstReceipts {
            XCTAssertTrue(durable.contains(receipt.boundary))
            XCTAssertFalse(receipt.visibleFailure.isEmpty)
            XCTAssertTrue(receipt.coldRecoverySucceeded)
            XCTAssertTrue(receipt.noPartialAuthority)
            XCTAssertEqual(receipt.residualIntentCount, 0)
            XCTAssertEqual(receipt.orphanPathCount, 0)
        }
    }

    func testV9_20R01TwoAndThreeReplicaSchedulesReconcileArchiveRestoreSearchDeleteAndErase() async throws {
        let manifests = try KernelConformanceFixtureShapeV1.allCases.map {
            try KernelConformanceFixtureHarnessV1.loadManifest($0)
        }
        let c11 = try c11Schedules()
        for manifest in manifests {
            XCTAssertEqual(manifest.replicaSchedules.map(\.id), c11.map(\.id))
            for (declared, inherited) in zip(manifest.replicaSchedules, c11) {
                XCTAssertEqual(declared.replicas, inherited.replicas)
                XCTAssertEqual(declared.deliveries, inherited.deliveries)
                XCTAssertEqual(declared.expectedSemanticSHA256, inherited.expectedSemanticSHA256)
                XCTAssertEqual(declared.expectedNormalizedSHA256, inherited.expectedSemanticSHA256)
                XCTAssertEqual(declared.replayCount, 2)
            }
            let actions = Set(manifest.lifecycleTransitions.map(\.action))
            XCTAssertTrue(Set(["ARCHIVE", "RESTORE", "SEARCH", "DELETE", "ERASE", "RECOVER"]).isSubset(of: actions))
        }

        let twoReplica = try XCTUnwrap(c11.first { $0.id == "two-replica-golden" })
        let threeReplica = try XCTUnwrap(c11.first { $0.id == "three-replica-adversarial" })
        XCTAssertEqual(c11.map(\.id), [twoReplica.id, threeReplica.id])
        XCTAssertEqual([twoReplica.replicas.count, threeReplica.replicas.count], [2, 3])
        let inheritedBounds = try c11Bounds()
        let compatibilityHarness = try KernelConformanceProductionHarnessV1(
            label: "c11-compatibility-bounds"
        )
        defer { compatibilityHarness.cleanup() }
        let compatibility = try await compatibilityHarness.exerciseCompatibilityAndBounds()
        XCTAssertTrue(compatibility.unknownBatchVersionRejected)
        XCTAssertTrue(compatibility.unknownBatchFieldRejected)
        XCTAssertTrue(compatibility.unknownConflictRuleRejected)
        XCTAssertTrue(compatibility.unknownConflictVersionRejected)
        XCTAssertTrue(compatibility.unknownRegisteredCodecRejected)
        XCTAssertTrue(compatibility.noncanonicalCodecRejected)
        XCTAssertEqual(compatibility.observedMaximumPageItems, inheritedBounds.maximumPageItems)
        XCTAssertLessThanOrEqual(compatibility.observedMaximumPageBytes, inheritedBounds.maximumPageBytes)
        XCTAssertEqual(compatibility.configuredMaximumGapPages, inheritedBounds.maximumGapPages)
        XCTAssertEqual(compatibility.configuredMaximumReplayAttempts, inheritedBounds.maximumReplayAttempts)
        XCTAssertEqual(compatibility.scaleItemCount, inheritedBounds.scaleItemCount)
        XCTAssertEqual(compatibility.scalePageItemLimit, inheritedBounds.scalePageItemLimit)
        XCTAssertEqual(compatibility.scalePageCount, inheritedBounds.scaleExpectedPageCount)
        XCTAssertLessThanOrEqual(
            compatibility.scaleMaximumResidentBytes,
            inheritedBounds.scaleMaximumResidentBytes
        )
        XCTAssertEqual(compatibility.scaleSemanticSHA256, inheritedBounds.scaleSemanticSHA256)

        let renderer = try compatibilityHarness.exerciseRendererReconciliation()
        XCTAssertEqual(renderer.corpusSchema, "V21P03C06SnapshotProjectionCorpusV1")
        XCTAssertTrue(isSHA256(renderer.snapshotSHA256))
        XCTAssertTrue(isSHA256(renderer.pdfSHA256))
        XCTAssertTrue(isSHA256(renderer.openJSONSHA256))
        XCTAssertTrue(isSHA256(renderer.structuredTextSHA256))
        XCTAssertTrue(isSHA256(renderer.semanticSHA256))
        XCTAssertFalse(renderer.orderedSemanticIDs.isEmpty)
        XCTAssertEqual(Set(renderer.orderedSemanticIDs).count, renderer.orderedSemanticIDs.count)
        XCTAssertTrue(renderer.pdfReopened)
        XCTAssertTrue(renderer.openJSONReopened)
        XCTAssertTrue(renderer.structuredTextReopened)
        XCTAssertEqual(Set(renderer.inheritedAcceptanceTests), Set([
            "hostile text and accessibility-claim negatives",
            "independent language-neutral fixture validation",
            "old package/profile render",
            "original/amended/superseded report and open-JSON reconciliation",
            "PDF/JSON/text reconciliation",
            "repeat-render byte equality",
        ]))
        XCTAssertTrue(renderer.repeatRenderByteIdentical)
        XCTAssertEqual(
            renderer.zeroOrCompleteBoundaryCount,
            ReportProjectionPublicationBoundaryV1.allCases.count
        )
        XCTAssertTrue(renderer.retryByteIdentical)
        XCTAssertTrue(renderer.legacySnapshotRoundTrip)
        XCTAssertTrue(renderer.oldProfileRendered)
        XCTAssertEqual(renderer.hostileTextRejectionCount, 4)
        XCTAssertTrue(renderer.privacyCanaryRejected)
        XCTAssertEqual(renderer.declaredHostileCaseRejectionCount, 18)
        XCTAssertEqual(renderer.privacyCanaryRejectionCount, 9)
        XCTAssertTrue(renderer.unsupportedAccessibilityClaimRejected)
        XCTAssertTrue(renderer.originalAmendedSupersededReconciled)
        XCTAssertTrue(renderer.originalHistoricalBytesImmutable)
        var canonicalByScheduleAndShape: [String: [String: String]] = [:]
        for shape in KernelConformanceFixtureShapeV1.allCases {
            for schedule in [twoReplica, threeReplica] {
                let harness = try KernelConformanceProductionHarnessV1(
                    label: "\(shape.resourceName)-\(schedule.id)"
                )
                defer { harness.cleanup() }
                let replay = try await harness.exerciseReplicaSchedule(
                    shape: shape,
                    replicas: schedule.replicas,
                    deliveries: schedule.deliveries
                )
                XCTAssertEqual(replay.shapeID, shape.shapeID)
                XCTAssertEqual(replay.replicaCount, schedule.replicas.count)
                XCTAssertEqual(replay.deliveries, schedule.deliveries)
                XCTAssertEqual(replay.firstRunReplicaProjectionCount, schedule.replicas.count)
                XCTAssertEqual(replay.secondRunReplicaProjectionCount, schedule.replicas.count)
                XCTAssertTrue(isSHA256(replay.firstRun.semanticSHA256))
                XCTAssertTrue(isSHA256(replay.secondRun.semanticSHA256))
                XCTAssertTrue(isSHA256(replay.firstRun.canonicalSnapshotSHA256))
                XCTAssertTrue(isSHA256(replay.firstRun.contentDispositionSHA256))
                XCTAssertEqual(replay.firstRun.semanticSHA256, replay.secondRun.semanticSHA256)
                XCTAssertEqual(replay.firstRun.canonicalSnapshotSHA256, replay.secondRun.canonicalSnapshotSHA256)
                XCTAssertEqual(Set(replay.firstRun.tombstoneStableKeys), Set(replay.secondRun.tombstoneStableKeys))
                XCTAssertEqual(Set(replay.firstRun.unresolvedConflictSHA256), Set(replay.secondRun.unresolvedConflictSHA256))
                XCTAssertEqual(replay.firstRun.contentDispositionSHA256, replay.secondRun.contentDispositionSHA256)
                XCTAssertEqual(Set(replay.firstRun.contentDependencyIDs), Set(replay.secondRun.contentDependencyIDs))
                XCTAssertEqual(Set(replay.firstRun.observedMutationIDs), Set(replay.secondRun.observedMutationIDs))
                let expectedMutationIDs: Set<String>
                if schedule.id == "two-replica-golden" {
                    expectedMutationIDs = [
                        "92000000-0000-4000-8000-000000006541",
                        "92000000-0000-4000-8000-000000006641",
                        "92000000-0000-4000-8000-000000006542",
                        "92000000-0000-4000-8000-000000006642",
                    ]
                } else {
                    expectedMutationIDs = [
                        "92000000-0000-4000-8000-000000006541",
                        "92000000-0000-4000-8000-000000006542",
                        "92000000-0000-4000-8000-000000006543",
                        "92000000-0000-4000-8000-000000006643",
                    ]
                }
                XCTAssertEqual(Set(replay.firstRun.observedMutationIDs), expectedMutationIDs)
                XCTAssertTrue(replay.firstRun.tombstoneStableKeys.isEmpty)
                XCTAssertTrue(replay.firstRun.unresolvedConflictSHA256.isEmpty)
                XCTAssertTrue(replay.firstRun.contentDependencyIDs.isEmpty)
                XCTAssertEqual(replay.firstRun.siteCount, schedule.replicas.count)
                XCTAssertEqual(replay.firstRun.assetCount, schedule.replicas.count)
                XCTAssertEqual(replay.firstRun.placementEventCount, schedule.replicas.count)
                canonicalByScheduleAndShape[schedule.id, default: [:]][shape.shapeID] = replay.firstRun.canonicalSnapshotSHA256
                XCTAssertTrue(replay.postConvergence.archivePrepared)
                XCTAssertTrue(replay.postConvergence.restoreActivated)
                XCTAssertTrue(replay.postConvergence.searchRebuilt)
                XCTAssertTrue(replay.postConvergence.deletionCommitted)
                XCTAssertTrue(replay.postConvergence.eraseActivated)
                XCTAssertTrue(replay.postConvergence.recoveryCompleted)
            }
        }
        for schedule in [twoReplica, threeReplica] {
            let byShape = try XCTUnwrap(canonicalByScheduleAndShape[schedule.id])
            XCTAssertEqual(byShape.count, KernelConformanceFixtureShapeV1.allCases.count)
            XCTAssertEqual(Set(byShape.values).count, KernelConformanceFixtureShapeV1.allCases.count)
        }
    }

    private struct C11ScheduleV1 {
        let id: String
        let replicas: [String]
        let deliveries: [String]
        let expectedSemanticSHA256: String
    }

    private struct C11BoundsV1 {
        let maximumPageItems: Int
        let maximumPageBytes: Int
        let maximumGapPages: Int
        let maximumReplayAttempts: Int
        let scaleItemCount: Int
        let scalePageItemLimit: Int
        let scaleExpectedPageCount: Int
        let scaleMaximumResidentBytes: Int
        let scaleSemanticSHA256: String
    }

    private func c11Schedules() throws -> [C11ScheduleV1] {
        let data = try KernelConformanceFixtureHarnessV1.readRequiredData(
            KernelConformanceFixtureHarnessV1.c11CorpusURL()
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["schema"] as? String, "V21P03C11ChangeJournalCheckpointReplayCorpusV1")
        let rows = try XCTUnwrap(root["replicaSchedules"] as? [[String: Any]])
        return try rows.map {
            C11ScheduleV1(
                id: try XCTUnwrap($0["id"] as? String),
                replicas: try XCTUnwrap($0["replicas"] as? [String]),
                deliveries: try XCTUnwrap($0["deliveries"] as? [String]),
                expectedSemanticSHA256: try XCTUnwrap($0["expectedSemanticSHA256"] as? String)
            )
        }
    }

    private func c11Bounds() throws -> C11BoundsV1 {
        let data = try KernelConformanceFixtureHarnessV1.readRequiredData(
            KernelConformanceFixtureHarnessV1.c11CorpusURL()
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let bounds = try XCTUnwrap(root["bounds"] as? [String: Any])
        let scale = try XCTUnwrap(root["scale"] as? [String: Any])
        return C11BoundsV1(
            maximumPageItems: try XCTUnwrap(bounds["maximumPageItems"] as? Int),
            maximumPageBytes: try XCTUnwrap(bounds["maximumPageBytes"] as? Int),
            maximumGapPages: try XCTUnwrap(bounds["maximumGapPages"] as? Int),
            maximumReplayAttempts: try XCTUnwrap(bounds["maximumReplayAttempts"] as? Int),
            scaleItemCount: try XCTUnwrap(scale["assetCount"] as? Int),
            scalePageItemLimit: try XCTUnwrap(scale["pageItemLimit"] as? Int),
            scaleExpectedPageCount: try XCTUnwrap(scale["expectedPageCount"] as? Int),
            scaleMaximumResidentBytes: try XCTUnwrap(scale["maximumResidentBytes"] as? Int),
            scaleSemanticSHA256: try XCTUnwrap(scale["expectedNormalizedMetadataSHA256"] as? String)
        )
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private func productionSwiftSources() throws -> [URL] {
        let root = KernelConformanceFixtureHarnessV1.sourceRoot().appendingPathComponent("FieldEvidenceApp")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

}

private final class C27V920TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(PersistentSchemaV26.models.count, 94)
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

extension V9_20KernelConformanceTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_20KernelConformanceTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.stagingPersistence, "DERIVED_ONLY_DROP_AND_REBUILD")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed)
    }
}

extension V9_20KernelConformanceTests {
    func testV23P03C18SurfaceIsClosedInPortableHarness() throws {
        XCTAssertTrue(KernelConformanceFixtureHarnessV1.c18PackageEvolutionSurfaceIsClosed())
        XCTAssertEqual(PackageSemanticDiffClassificationV1.allCases.count, 5)
        XCTAssertEqual(PackageSandboxCheckKindV1.allCases.count, 12)
    }
}

extension V9_20KernelConformanceTests {
    func testV23P03C36KernelConformanceCorpusHasFiveSelectorsAndPrivacyExclusions() throws {
        let data = try Data(contentsOf: C36FieldDraftTestSupportV1.corpusURL())
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(source.contains("V21P03C36FieldDraftResilienceCorpusV1"))
        XCTAssertTrue(source.contains("\"persistentModelCount\": 64"))
        XCTAssertTrue(source.contains("\"recordsSchemaVersion\": 15"))
        XCTAssertTrue(source.contains("\"privacyExclusions\": [\"EVIDENCE\", \"REPORT\", \"EXPORT\", \"SEARCH\", \"SPOTLIGHT\", \"SUPPORT\", \"INTEGRATION_EVENT\", \"METRICS\"]"))
        for selector in ["G01", "A01", "H01", "I01", "R01"] {
            XCTAssertTrue(source.contains("V23-P03-C36-\(selector)"))
        }
    }

    func testV23P03C17TypedRegistryCheckpointConformanceIsProviderFree() throws {
        let fixture = try C17IntegrationEventTestSupportV1.makeFixture()
        XCTAssertEqual(
            fixture.registry.definitions.map(\.stableKey),
            ["asset.changed:1", "site.changed:1"]
        )
        XCTAssertEqual(
            fixture.registry.definitions.map(\.lifecycle),
            [
                IntegrationEventLifecycleV1.derivedDropAndRebuild,
                IntegrationEventLifecycleV1.derivedDropAndRebuild,
            ]
        )

        let consumer = try IntegrationEventConformanceConsumerV1(
            consumerID: fixture.consumerID,
            consumerVersion: fixture.consumerVersion
        )
        let first = try consumer.consume(
            workspaceID: fixture.workspaceID,
            registry: fixture.registry,
            events: [],
            priorCheckpoint: fixture.emptyCheckpoint
        )
        XCTAssertTrue(first.acceptedEventIDs.isEmpty)
        XCTAssertEqual(
            first.terminalStateSHA256,
            fixture.emptyCheckpoint.consumerStateSHA256
        )
        XCTAssertEqual(first.checkpoint, fixture.emptyCheckpoint)

        let retry = try consumer.consume(
            workspaceID: fixture.workspaceID,
            registry: fixture.registry,
            events: [],
            priorCheckpoint: first.checkpoint
        )
        XCTAssertEqual(retry, first)

        let registryBytes = try IntegrationEventCanonicalCodecV1.encode(
            fixture.registry, limits: fixture.limits
        )
        XCTAssertEqual(
            try IntegrationEventCanonicalCodecV1.decodeRegistry(
                registryBytes, limits: fixture.limits
            ),
            fixture.registry
        )
        let checkpointBytes = try IntegrationEventCanonicalCodecV1.encode(
            fixture.emptyCheckpoint
        )
        XCTAssertEqual(
            try IntegrationEventCanonicalCodecV1.decodeCheckpoint(checkpointBytes),
            fixture.emptyCheckpoint
        )
    }

    func testV23P03KernelConformanceCoversAllPersistentMeasurementKinds() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let kinds = MeasurementIntegrityLifecycleCatalogV1.persistentKinds
        XCTAssertEqual(kinds.count, 5)
        XCTAssertTrue(kinds.allSatisfy {
            MeasurementIntegrityLifecycleCatalogV1.disposition(for: $0) == .canonicalPersistent
        })
        try C19MeasurementIntegrityTestSupport.assertAllCanonicalRoundTrips(fixture)
    }

    func testC20PrivacyTransformPortableAnchorUsesCanonicalLifecycleClosure() throws {
        let manifestSHA256 = try KernelConformanceFixtureHarnessV1.c20PrivacyTransformAnchor()
        XCTAssertEqual(manifestSHA256.count, 64)
    }
}

extension V9_20KernelConformanceTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_20KernelConformanceTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindV1.allCases.count, 5)
        XCTAssertEqual(SurveyDefinitionLifecycleStateV1.allCases.count, 3)
        XCTAssertFalse(ActivityKindV1.allCases.map { ActivityKindSemanticsV1(kind: $0) }.contains { $0.mayClaimReleaseToService })
    }
}
extension V9_20KernelConformanceTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_20KernelConformanceTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV920KernelConformanceTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension V9_20KernelConformanceTests {
    func testC42CrossMarketCorpusReusesPinnedKernelAndCompatibilityOwners() throws {
        let corpus = try KernelConformanceFixtureHarnessV1.loadC42CrossMarketCorpus()
        let lock = try PortableContractToolLockReaderV1.readForCrossMarketConformance(
            at: KernelConformanceFixtureHarnessV1.toolLockURL()
        )
        let portableReceipts = try PortableContractValidatorAdapterV1(toolLock: lock)
            .validateCrossMarketCorpus(corpus.portableCases)
        let historicDigests = try V907CompatibilitySupport.crossMarketHistoricReportDigests()
        let composite = try CompositeAreaSafetyArchetypeV1.run()
        let controller = try ControllerZoneDistributionArchetypeV1.run()
        let hostileReceipts = try KernelConformanceFixtureHarnessV1.executeC42HostileCases(
            corpus.hostileCases
        )

        XCTAssertEqual(portableReceipts.count, corpus.portableCases.count)
        XCTAssertEqual(hostileReceipts.count, CrossMarketHostileVectorV1.allCases.count)
        XCTAssertEqual(Set(hostileReceipts.map(\.vector)), Set(CrossMarketHostileVectorV1.allCases))
        XCTAssertEqual(
            corpus.releaseScanInputs.map(\.surface),
            ReleaseExclusionReceiptV1.requiredSurfaces
        )
        XCTAssertTrue(corpus.releaseScanInputs.allSatisfy {
            $0.evidenceKind == $0.surface.requiredEvidenceKind
                && $0.sourceIdentity == $0.surface.requiredSourceIdentity
        })
        XCTAssertFalse(historicDigests.isEmpty)
        XCTAssertEqual(composite.generatorVersion, corpus.generatorVersion)
        XCTAssertEqual(controller.generatorVersion, corpus.generatorVersion)
        XCTAssertEqual(composite.executedCaseCount, corpus.modelBounds.maximumCases)
        XCTAssertEqual(controller.executedCaseCount, corpus.modelBounds.maximumCases)
        XCTAssertEqual(composite.caseResultSHA256s.count, composite.executedCaseCount)
        XCTAssertEqual(controller.caseResultSHA256s.count, controller.executedCaseCount)
        XCTAssertGreaterThan(composite.scratchBytesRemoved, 0)
        XCTAssertGreaterThan(controller.scratchBytesRemoved, 0)
        XCTAssertTrue(composite.scratchCleanupComplete)
        XCTAssertTrue(controller.scratchCleanupComplete)
        XCTAssertFalse(composite.acceptanceCredit)
        XCTAssertFalse(controller.acceptanceCredit)
    }
}

private final class C33TemporalEvidenceAnchorV920KernelConformance: XCTestCase {
    func testC33V920KernelConformanceCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "kernel.temporal-evidence-subject",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "kernel.temporal-evidence-subject",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV920KernelConformance: XCTestCase {
    func testC32V920KernelConformanceCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .factCapture,
            fieldID: "kernel.typed-proposal",
            value: .triState(.notObserved)
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .factCapture,
            fieldID: "kernel.typed-proposal",
            valueKind: .triState
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V920KernelConformanceCompatibilityTests: XCTestCase {
    func testC46KernelConformanceKeepsSoleContactWriterBoundary() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "kernel-conformance",
            kind: .email,
            handoff: .email,
            slot: 46020
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift_Tests: XCTestCase {
    func testC47V920KernelConformanceTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_20KernelConformanceTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityStateMachineV2.exhaustiveTable.count, ActivityStateV2.allCases.count)
        XCTAssertFalse(ActivityStateMachineV2.permits(from: .finalized, to: .draft))
    }
}

private final class C48PortableReviewV920KernelTests: XCTestCase {
    func testC48JournalReplayUsesExactResponseAndExistingC14Postimages() {
        XCTAssertEqual(PortableReviewChangeJournalPolicyV1.commandKind, .applyPortableReview)
        XCTAssertTrue(PortableReviewChangeJournalPolicyV1.replaysExactResponseBytes)
        XCTAssertTrue(PortableReviewChangeJournalPolicyV1.postimagesUseOnlyExistingC14Families)
        XCTAssertTrue(PortableReviewChangeJournalPolicyV1.historyDiscardAndQuarantineAreSessionOnly)
    }
}
private final class C49WorkResourceKernelConformanceBoundaryTests: XCTestCase {
    func testManualResourceTruthHasOneWriterAndAppendOnlyHistory() {
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.appendOnly)
        XCTAssertEqual(C49WorkResourceContractBoundaryV1.soleWriter, "WorkspaceWriterV1")
        XCTAssertEqual(WorkspaceCommandKindV1.applyWorkResource.rawValue, "apply_work_resource_v1")
    }
}

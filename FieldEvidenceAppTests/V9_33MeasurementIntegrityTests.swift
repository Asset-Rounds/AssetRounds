import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Small, deterministic values shared by the C19 anchor tests.  The fixture
/// deliberately exercises the real C19 contracts rather than creating a
/// parallel test-only store or writer.
enum C19MeasurementIntegrityTestSupport {
    struct Fixture {
        let workspace: WorkspaceID
        let mutationID: MutationIDV1
        let instrument: InstrumentReferenceV1
        let calibrations: [CalibrationStatusSnapshotV1]
        let currentCalibration: CalibrationStatusSnapshotV1
        let expiredCalibration: CalibrationStatusSnapshotV1
        let unknownCalibration: CalibrationStatusSnapshotV1
        let outOfServiceCalibration: CalibrationStatusSnapshotV1
        let evidence: ContentReferenceV1
        let actor: ActorSnapshotV1
        let reviewer: ActorSnapshotV1
        let fieldDefinition: ResponseFieldDefinitionV1
        let measurement: ExactMeasurementV1
        let secondMeasurement: ExactMeasurementV1
        let capture: MeasurementCaptureV1
        let secondCapture: MeasurementCaptureV1
        let reviewCapture: MeasurementCaptureV1
        let manualCapture: MeasurementCaptureV1
        let evaluator: DerivedFactEvaluatorDescriptorV1
        let protocolRelease: MeasurementProtocolReleaseV1
        let openSeries: MeasurementSeriesV1
        let series: MeasurementSeriesV1
        let qualityClear: MeasurementQualityAssessmentV1
        let qualityReview: MeasurementQualityAssessmentV1
        let qualityOverride: MeasurementQualityAssessmentV1
        let bundle: MeasurementIntegrityAtomicBundleV1
    }

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c1900000-0000-4000-8000-%012x", slot))!
    }

    static func digest(_ value: Character = "a") -> String {
        String(repeating: value, count: 64)
    }

    static func makeFixture() throws -> Fixture {
        let workspace = WorkspaceID(rawValue: id(1))
        let mutationID = try MutationIDV1(rawValue: id(2))
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let later = capturedAt.addingTimeInterval(2)
        let sourceCreatedAt = "2026-08-28T00:00:00.000Z"
        let contentDigest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: digest("b")
        )
        let evidence = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: "c19-calibration-evidence",
            byteLength: 64,
            mediaType: "application/json",
            digests: try ContentDigestSetV1([contentDigest]),
            byteRole: .immutableOriginal,
            createdAt: sourceCreatedAt
        )

        let instrument = try InstrumentReferenceV1(
            referenceID: id(10),
            instrumentID: id(11),
            workspaceID: workspace,
            kind: .illuminanceMeter,
            label: "Local illuminance meter",
            opaqueSerial: "local-c19-serial",
            manufacturer: "Declared manufacturer",
            model: "Declared model",
            supportedUnitIDs: ["lx", "[fc_i]"],
            lifecycleState: .active,
            recordedAt: capturedAt,
            mutationID: mutationID
        )
        let instrumentReference = try InstrumentRevisionReferenceV1(instrument)

        let notRequired = try CalibrationStatusSnapshotV1(
            snapshotID: id(20), workspaceID: workspace, instrument: instrumentReference,
            status: .notRequired, basis: .declaredNotRequired,
            capturedAt: capturedAt, mutationID: mutationID
        )
        let current = try CalibrationStatusSnapshotV1(
            snapshotID: id(21), workspaceID: workspace, instrument: instrumentReference,
            status: .current, basis: .referencedEvidence,
            effectiveAt: capturedAt.addingTimeInterval(-60),
            expiresAt: capturedAt.addingTimeInterval(60),
            sourceReference: evidence, capturedAt: capturedAt, mutationID: mutationID
        )
        let expired = try CalibrationStatusSnapshotV1(
            snapshotID: id(22), workspaceID: workspace, instrument: instrumentReference,
            status: .expired, basis: .referencedEvidence,
            effectiveAt: capturedAt.addingTimeInterval(-120),
            expiresAt: capturedAt.addingTimeInterval(-30),
            sourceReference: evidence, capturedAt: capturedAt, mutationID: mutationID
        )
        let unknown = try CalibrationStatusSnapshotV1(
            snapshotID: id(23), workspaceID: workspace, instrument: instrumentReference,
            status: .unknown, basis: .unknown,
            capturedAt: capturedAt, mutationID: mutationID
        )
        let outOfService = try CalibrationStatusSnapshotV1(
            snapshotID: id(24), workspaceID: workspace, instrument: instrumentReference,
            status: .outOfService, basis: .locallyRecordedStatus,
            capturedAt: capturedAt, mutationID: mutationID
        )

        let localActor = try LocalActorReferenceV1(
            actorReferenceID: id(30), workspaceID: workspace, displayName: "Local operator"
        )
        let actor = try ActorSnapshotV1(
            snapshotID: id(31), workspaceID: workspace, actor: localActor,
            responsibility: .performedBy, displayNameAtTime: "Local operator",
            capturedAt: capturedAt
        )
        let reviewActor = try LocalActorReferenceV1(
            actorReferenceID: id(32), workspaceID: workspace, displayName: "Local reviewer"
        )
        let reviewer = try ActorSnapshotV1(
            snapshotID: id(33), workspaceID: workspace, actor: reviewActor,
            responsibility: .reviewedBy, displayNameAtTime: "Local reviewer",
            capturedAt: later
        )
        let observationBasis = try ObservationBasisV1(
            kind: .directlyObserved,
            method: try ObservationMethodV1(key: "measurement"),
            source: try ObservationSourceReferenceV1(kind: .observer)
        )

        let measurement = try ExactMeasurementV1(
            enteredValue: try ExactDecimalV1(mantissa: 1, scale: 0),
            enteredUnitID: "[fc_i]", precisionScale: 0,
            uncertaintyCanonical: try ExactDecimalV1(mantissa: 1, scale: 1),
            source: .instrumentObserved, captureMethodID: "c19.instrument.manual"
        )
        let secondMeasurement = try ExactMeasurementV1(
            enteredValue: try ExactDecimalV1(mantissa: 2, scale: 0),
            enteredUnitID: "[fc_i]", precisionScale: 0,
            uncertaintyCanonical: try ExactDecimalV1(mantissa: 1, scale: 1),
            source: .instrumentObserved, captureMethodID: "c19.instrument.repeat"
        )
        let manualMeasurement = try ExactMeasurementV1(
            enteredValue: try ExactDecimalV1(mantissa: 1, scale: 0),
            enteredUnitID: "[fc_i]", precisionScale: 0,
            uncertaintyCanonical: try ExactDecimalV1(mantissa: 1, scale: 1),
            source: .manualEntry, captureMethodID: "c19.manual.entry"
        )
        let packageReleaseID = digest("c")
        let workflowSHA256 = digest("d")
        let cardinality = try ResponseCardinalityV1(minimum: 0, maximum: 1)
        let fieldDefinition = try ResponseFieldDefinitionV1(
            fieldID: "measurement.illuminance",
            packageReleaseID: packageReleaseID,
            workflowSHA256: workflowSHA256,
            valueKind: .measurement,
            cardinality: cardinality,
            minimumNumericValue: try ExactDecimalV1(mantissa: 0, scale: 0),
            maximumNumericValue: try ExactDecimalV1(mantissa: 10_000, scale: 0),
            measurementDimension: .illuminance,
            allowedUnitIDs: ["[fc_i]", "lx"],
            maximumPrecisionScale: 0,
            maximumUncertaintyCanonical: try ExactDecimalV1(mantissa: 1, scale: 0)
        )
        let response = try BoundResponseValueV1(
            fieldID: fieldDefinition.fieldID, value: .measurement(measurement)
        )
        let secondResponse = try BoundResponseValueV1(
            fieldID: fieldDefinition.fieldID, value: .measurement(secondMeasurement)
        )
        let manualResponse = try BoundResponseValueV1(
            fieldID: fieldDefinition.fieldID, value: .measurement(manualMeasurement)
        )

        let capture = try MeasurementCaptureV1(
            captureID: id(40), workspaceID: workspace,
            packageReleaseID: packageReleaseID, workflowSHA256: workflowSHA256,
            response: response, measurement: measurement,
            sourceMode: .localObservation,
            instrument: instrumentReference,
            calibration: try CalibrationSnapshotReferenceV1(current),
            observationBasis: observationBasis, operatorSnapshot: actor,
            evidence: [evidence], capturedAt: capturedAt, mutationID: mutationID
        )
        let secondCapture = try MeasurementCaptureV1(
            captureID: id(41), workspaceID: workspace,
            packageReleaseID: packageReleaseID, workflowSHA256: workflowSHA256,
            response: secondResponse, measurement: secondMeasurement,
            sourceMode: .localObservation,
            instrument: instrumentReference,
            calibration: try CalibrationSnapshotReferenceV1(current),
            observationBasis: observationBasis, operatorSnapshot: actor,
            evidence: [evidence], capturedAt: later, mutationID: mutationID
        )
        let reviewCapture = try MeasurementCaptureV1(
            captureID: id(42), workspaceID: workspace,
            packageReleaseID: packageReleaseID, workflowSHA256: workflowSHA256,
            response: response, measurement: measurement,
            sourceMode: .localObservation,
            instrument: instrumentReference,
            calibration: try CalibrationSnapshotReferenceV1(expired),
            observationBasis: observationBasis, operatorSnapshot: actor,
            evidence: [evidence], capturedAt: capturedAt, mutationID: mutationID
        )
        let manualCapture = try MeasurementCaptureV1(
            captureID: id(43), workspaceID: workspace,
            packageReleaseID: packageReleaseID, workflowSHA256: workflowSHA256,
            response: manualResponse, measurement: manualMeasurement,
            sourceMode: .manualEntry,
            observationBasis: observationBasis, operatorSnapshot: actor,
            capturedAt: capturedAt, mutationID: mutationID
        )

        let evaluator = try BundledDerivedFactEvaluatorRegistryV1.descriptor(
            descriptorID: id(50), workspaceID: workspace,
            kind: .arithmeticMeanCanonical, inputDimension: .illuminance,
            recordedAt: capturedAt
        )
        let protocolRelease = try MeasurementProtocolReleaseV1(
            releaseID: id(51), workspaceID: workspace, protocolID: id(52),
            designation: "C19 illuminance repeat",
            dimension: .illuminance, normativeUnitID: "lx",
            samplingPolicy: .orderedSeries, minimumSampleCount: 1,
            maximumSampleCount: 2, missingSamplePolicy: .failClosed,
            outlierPolicy: .retainAll, duplicatePolicy: .reject,
            requiresUncertainty: false, evaluatorDescriptorID: evaluator.descriptorID,
            recordedAt: capturedAt, mutationID: mutationID
        )
        let firstReference = try MeasurementCaptureReferenceV1(
            captureID: capture.captureID, revision: capture.revision,
            captureSHA256: capture.captureSHA256, sampleOrdinal: 1
        )
        let openSeries = try MeasurementSeriesV1(
            snapshotID: id(60), seriesID: id(61), workspaceID: workspace,
            protocolReference: try MeasurementProtocolReferenceV1(protocolRelease),
            samples: [firstReference], expectedSampleCount: 2,
            aggregationPolicy: .mean, state: .open,
            recordedAt: capturedAt, mutationID: mutationID
        )
        let series = try MeasurementSeriesEvaluatorV1.finalized(
            snapshotID: id(62), seriesID: id(61), workspaceID: workspace,
            protocolRelease: protocolRelease, evaluator: evaluator,
            captures: [capture, secondCapture], expectedSampleCount: 2,
            aggregationPolicy: .mean,
            provenanceID: id(63), recordedAt: later, supersedes: openSeries,
            mutationID: mutationID
        )

        let policyVersion = "C19-MEASUREMENT-POLICY-V1"
        let qualityClear = try MeasurementQualityEvaluatorV1.assessCapture(
            assessmentID: id(70), capture: capture, calibration: current,
            requiresUncertainty: false, policyVersion: policyVersion,
            policySHA256: digest("e"), assessedAt: later, mutationID: mutationID
        )
        let qualityReview = try MeasurementQualityEvaluatorV1.assessCapture(
            assessmentID: id(71), capture: reviewCapture, calibration: expired,
            requiresUncertainty: false, policyVersion: policyVersion,
            policySHA256: digest("e"), assessedAt: later, mutationID: mutationID
        )
        let qualityOverride = try MeasurementQualityAssessmentV1(
            assessmentID: id(72), workspaceID: workspace,
            subjectKind: .capture, subjectID: reviewCapture.captureID,
            subjectRevision: reviewCapture.revision,
            subjectSHA256: reviewCapture.captureSHA256, result: .overridden,
            reasonCodes: [.humanOverride], policyVersion: policyVersion,
            policySHA256: digest("e"), evidence: [evidence], reviewer: reviewer,
            overrideRationale: "Human review recorded.", assessedAt: later,
            supersedesAssessmentID: qualityReview.assessmentID, revision: 2,
            mutationID: mutationID
        )
        let bundle = try MeasurementIntegrityCoordinatorV1.prepare(
            workspaceID: workspace, mutationID: mutationID,
            instruments: [instrument], calibrations: [notRequired, current, expired, unknown, outOfService],
            captures: [capture, secondCapture, reviewCapture, manualCapture],
            series: [series], assessments: [qualityClear, qualityReview, qualityOverride]
        )
        return Fixture(
            workspace: workspace, mutationID: mutationID, instrument: instrument,
            calibrations: [notRequired, current, expired, unknown, outOfService],
            currentCalibration: current, expiredCalibration: expired,
            unknownCalibration: unknown, outOfServiceCalibration: outOfService,
            evidence: evidence, actor: actor, reviewer: reviewer,
            fieldDefinition: fieldDefinition, measurement: measurement,
            secondMeasurement: secondMeasurement, capture: capture,
            secondCapture: secondCapture, reviewCapture: reviewCapture,
            manualCapture: manualCapture, evaluator: evaluator,
            protocolRelease: protocolRelease, openSeries: openSeries,
            series: series, qualityClear: qualityClear,
            qualityReview: qualityReview, qualityOverride: qualityOverride,
            bundle: bundle
        )
    }

    static func assertAllCanonicalRoundTrips(_ fixture: Fixture) throws {
        let decodedInstrument = try MeasurementIntegrityCanonicalCodecV1.decode(
            InstrumentReferenceV1.self,
            from: MeasurementIntegrityCanonicalCodecV1.encode(fixture.instrument)
        )
        guard decodedInstrument == fixture.instrument else {
            throw MeasurementIntegrityFailureV1.nonCanonicalData
        }
        for value in fixture.calibrations {
            let decoded = try MeasurementIntegrityCanonicalCodecV1.decode(
                CalibrationStatusSnapshotV1.self,
                from: MeasurementIntegrityCanonicalCodecV1.encode(value)
            )
            guard decoded == value else { throw MeasurementIntegrityFailureV1.nonCanonicalData }
        }
        for value in [fixture.capture, fixture.secondCapture, fixture.reviewCapture, fixture.manualCapture] {
            let decoded = try MeasurementIntegrityCanonicalCodecV1.decode(
                MeasurementCaptureV1.self,
                from: MeasurementIntegrityCanonicalCodecV1.encode(value)
            )
            guard decoded == value else { throw MeasurementIntegrityFailureV1.nonCanonicalData }
        }
        let series = try MeasurementIntegrityCanonicalCodecV1.decode(
            MeasurementSeriesV1.self,
            from: MeasurementIntegrityCanonicalCodecV1.encode(fixture.series)
        )
        guard series == fixture.series else { throw MeasurementIntegrityFailureV1.nonCanonicalData }
        for value in [fixture.qualityClear, fixture.qualityReview, fixture.qualityOverride] {
            let decoded = try MeasurementIntegrityCanonicalCodecV1.decode(
                MeasurementQualityAssessmentV1.self,
                from: MeasurementIntegrityCanonicalCodecV1.encode(value)
            )
            guard decoded == value else { throw MeasurementIntegrityFailureV1.nonCanonicalData }
        }
    }
}

private struct C19CorpusSelectorV1: Decodable {
    let id: String
    let selector: String
    let focus: String
}

private struct C19CorpusFlagsV1: Decodable {
    let native: Bool
    let hosted: Bool
    let adoption: Bool
    let acceptance: Bool
    let release: Bool
}

private struct C53MeasurementReliabilityBoundaryFixtureV1: Decodable {
    let contractNames: [String]
    let usesMeasurementAsEvidenceOnly: Bool
    let unknownIntervalsQualifyForExactMetrics: Bool
}

private struct C19CorpusFixtureV1: Decodable {
    let schema: String
    let schemaVersion: Int
    let corpusID: String
    let cardID: String
    let ordinal: Int
    let phase: String
    let previousCardID: String
    let records: Int
    let recordsSchemaVersion: Int
    let persistentSchemaVersion: Int
    let persistentModelCount: Int
    let evidenceSelectors: [C19CorpusSelectorV1]
    let coverage: [String]
    let evidenceIDs: [String]
    let localeAndOrderingIndependent: Bool
    let classifications: [String]
    let instrumentTypes: [String]
    let instrumentLifecycleStates: [String]
    let calibrationStates: [String]
    let qualityDispositions: [String]
    let qualityReasonCodes: [String]
    let measurementUnits: [String]
    let measurementSourceModes: [String]
    let observationBases: [String]
    let aggregationPolicies: [String]
    let fixedPointCases: [String]
    let unitCases: [String]
    let localeCases: [String]
    let seriesCases: [String]
    let atomicInterruptionBoundaries: [String]
    let lifecycleConsumers: [String]
    let privacyExclusions: [String]
    let hostileCases: [String]
    let interruptionCases: [String]
    let recoveryCases: [String]
    let persistentKinds: [String]
    let oldOrNewOnly: Bool
    let retryDisposition: String
    let rollbackCompatibility: [String]
    let brandExclusion: String
    let forbiddenProductionSymbols: [String]
    let noSecondWriter: Bool
    let noSecondStore: Bool
    let noActivationFromSandbox: Bool
    let c53SharedBoundary: C53MeasurementReliabilityBoundaryFixtureV1
    let provisionalFlags: C19CorpusFlagsV1
}

@MainActor
final class V9_33MeasurementIntegrityTests: XCTestCase {
    private func makeWriterRetryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("C19-writer-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeWriterRetryBundle(workspaceID: WorkspaceID) throws -> MeasurementIntegrityAtomicBundleV1 {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        // A first-revision manual capture needs no instrument/calibration rows or predecessors.
        return try MeasurementIntegrityCoordinatorV1.prepare(
            workspaceID: workspaceID, mutationID: fixture.mutationID,
            captures: [try fixture.manualCapture.rebound(to: workspaceID)]
        )
    }

    private func measurementWriterSnapshot(_ context: ModelContext) throws -> [[Data]] {
        let receipts = try context.fetch(FetchDescriptor<MutationReceiptRow>())
        let values: [[Data]] = [
            try context.fetch(FetchDescriptor<InstrumentReferenceRow>()).map {
                try MeasurementIntegrityCanonicalCodecV1.encode($0.value())
            },
            try context.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>()).map {
                try MeasurementIntegrityCanonicalCodecV1.encode($0.value())
            },
            try context.fetch(FetchDescriptor<MeasurementCaptureRow>()).map {
                try MeasurementIntegrityCanonicalCodecV1.encode($0.value())
            },
            try context.fetch(FetchDescriptor<MeasurementSeriesRow>()).map {
                try MeasurementIntegrityCanonicalCodecV1.encode($0.value())
            },
            try context.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>()).map {
                try MeasurementIntegrityCanonicalCodecV1.encode($0.value())
            },
            receipts.map(\.receiptData),
            receipts.map(\.envelopeData)
        ]
        return values.map { $0.sorted { $0.lexicographicallyPrecedes($1) } }
    }

    func testMeasurementWriterExactRetryReturnsOriginalReceiptWithoutDuplicateEffects() async throws {
        let directory = try makeWriterRetryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try StoreGenerationFactory(applicationSupportURL: directory).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        let writer = coordinator.workspaceWriter
        let bundle = try makeWriterRetryBundle(workspaceID: session.workspaceID)
        let before = try writer.currentRevision()
        let first = try await writer.commitMeasurementIntegrity(bundle)
        let committed = try writer.currentRevision()
        let snapshot = try measurementWriterSnapshot(session.modelContext)
        XCTAssertEqual(committed.revision, before.revision + 1)
        XCTAssertEqual(snapshot.map(\.count), [0, 0, 1, 0, 0, 1, 1])
        XCTAssertEqual(first.journalReceiptSHA256, try MutationReceiptV1.decodeCanonical(
            from: XCTUnwrap(snapshot[5].first)
        ).canonicalSHA256())

        let retry = try await writer.commitMeasurementIntegrity(bundle)

        XCTAssertEqual(retry, first)
        XCTAssertEqual(try writer.currentRevision(), committed)
        XCTAssertEqual(try measurementWriterSnapshot(session.modelContext), snapshot)
    }

    func testMeasurementWriterExactRetryAfterReopeningUsesPersistedReceipt() async throws {
        let directory = try makeWriterRetryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle: MeasurementIntegrityAtomicBundleV1
        let first: MeasurementIntegrityWriteReceiptV1
        let committed: WorkspaceRevisionV1
        let snapshot: [[Data]]
        do {
            let session = try StoreGenerationFactory(applicationSupportURL: directory).openOrBootstrapCurrent()
            let coordinator = try StoreSessionCoordinator(validatingSession: session)
            bundle = try makeWriterRetryBundle(workspaceID: session.workspaceID)
            first = try await coordinator.workspaceWriter.commitMeasurementIntegrity(bundle)
            committed = try coordinator.workspaceWriter.currentRevision()
            snapshot = try measurementWriterSnapshot(session.modelContext)
            coordinator.workspaceWriter.invalidate()
        }

        let reopened = try StoreGenerationFactory(applicationSupportURL: directory).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: reopened)
        let writer = coordinator.workspaceWriter
        let recovered = try writer.currentRevision()
        XCTAssertNotEqual(recovered.writerInstanceID, committed.writerInstanceID)
        XCTAssertEqual(recovered.workspaceID, committed.workspaceID)
        XCTAssertEqual(recovered.generationID, committed.generationID)
        XCTAssertEqual(recovered.revision, committed.revision)
        XCTAssertEqual(recovered.entityRevisions, committed.entityRevisions)
        XCTAssertEqual(try measurementWriterSnapshot(reopened.modelContext), snapshot)

        let retry = try await writer.commitMeasurementIntegrity(bundle)

        XCTAssertEqual(retry, first)
        XCTAssertEqual(try writer.currentRevision(), recovered)
        XCTAssertEqual(try measurementWriterSnapshot(reopened.modelContext), snapshot)
    }

    func testMeasurementWriterDivergentMutationReuseRejectsWithoutChangingState() async throws {
        let directory = try makeWriterRetryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try StoreGenerationFactory(applicationSupportURL: directory).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        let writer = coordinator.workspaceWriter
        let bundle = try makeWriterRetryBundle(workspaceID: session.workspaceID)
        _ = try await writer.commitMeasurementIntegrity(bundle)
        let committed = try writer.currentRevision()
        let snapshot = try measurementWriterSnapshot(session.modelContext)
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let divergent = try MeasurementIntegrityCoordinatorV1.prepare(
            workspaceID: bundle.workspaceID, mutationID: bundle.mutationID,
            instruments: [try fixture.instrument.rebound(to: bundle.workspaceID)],
            captures: bundle.captures
        )
        XCTAssertNotEqual(divergent.bundleSHA256, bundle.bundleSHA256)
        do {
            _ = try await writer.commitMeasurementIntegrity(divergent)
            XCTFail("A durable receipt must not authorize different content under the same mutation ID")
        } catch {
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .invalidReceipt)
        }
        XCTAssertEqual(try writer.currentRevision(), committed)
        XCTAssertEqual(try measurementWriterSnapshot(session.modelContext), snapshot)
    }

    func testMeasurementWriterInvalidationRejectsEvenAnExactDurableRetry() async throws {
        let directory = try makeWriterRetryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try StoreGenerationFactory(applicationSupportURL: directory).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        let writer = coordinator.workspaceWriter
        let bundle = try makeWriterRetryBundle(workspaceID: session.workspaceID)
        _ = try await writer.commitMeasurementIntegrity(bundle)
        let snapshot = try measurementWriterSnapshot(session.modelContext)
        writer.invalidate()

        do {
            _ = try await writer.commitMeasurementIntegrity(bundle)
            XCTFail("An invalidated writer must reject even a previously committed bundle")
        } catch {
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        XCTAssertEqual(try measurementWriterSnapshot(session.modelContext), snapshot)
    }

    func testMeasurementWriterReleasedLeaseRejectsEvenAnExactDurableRetry() async throws {
        let directory = try makeWriterRetryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let factory = StoreGenerationFactory(applicationSupportURL: directory)
        let session = try factory.openOrBootstrapCurrent()
        let epoch = try XCTUnwrap(session.generationEpoch)
        let registry = try factory.makeGenerationLeaseRegistry()
        let lease = try registry.acquireHandle(epoch: epoch, role: .writer)
        defer { try? lease.close() }
        let fence = try factory.makeWriterFence(
            expectedGenerationEpoch: epoch, writerLeaseToken: lease.token, registry: registry
        )
        let journal = try MutationJournalStoreV1(
            modelContext: session.modelContext, identity: session.workspaceIdentity,
            generationID: session.generationID, allowStateBootstrap: false,
            staleWriterFence: fence
        )
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity, generationID: session.generationID,
            initialRevision: WorkspaceRevisionV1(
                workspaceID: session.workspaceID, generationID: session.generationID,
                revision: 0, entityRevisions: []
            ),
            clock: SystemApplicationClock(), idSource: SystemApplicationIDSource(),
            fileAuthority: SystemApplicationFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: journal
        )
        let bundle = try makeWriterRetryBundle(workspaceID: session.workspaceID)
        _ = try await writer.commitMeasurementIntegrity(bundle)
        let snapshot = try measurementWriterSnapshot(session.modelContext)
        // Keep the writer active while revoking its durable authority to access this generation.
        try lease.close()
        XCTAssertThrowsError(try writer.currentRevision()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongGeneration)
        }

        do {
            _ = try await writer.commitMeasurementIntegrity(bundle)
            XCTFail("A durable retry must still validate the writer lease")
        } catch {
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .wrongGeneration)
        }
        XCTAssertEqual(try measurementWriterSnapshot(session.modelContext), snapshot)
    }

    private func loadCorpus() throws -> C19CorpusFixtureV1 {
        let bundled = Bundle(for: Self.self).url(
            forResource: "V21P03C19MeasurementIntegrityCorpusV1", withExtension: "json"
        )
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V21/Measurement/V21P03C19MeasurementIntegrityCorpusV1.json")
        let url = bundled ?? source
        return try JSONDecoder().decode(C19CorpusFixtureV1.self, from: Data(contentsOf: url))
    }

    private func assertCorpus(_ corpus: C19CorpusFixtureV1) {
        XCTAssertEqual(corpus.schema, "V21P03C19MeasurementIntegrityCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C19")
        XCTAssertEqual(corpus.ordinal, 56)
        XCTAssertEqual(corpus.phase, "P03")
        XCTAssertEqual(corpus.previousCardID, "V23-P03-C17")
        XCTAssertEqual(corpus.records, 17)
        XCTAssertEqual(corpus.recordsSchemaVersion, 17)
        XCTAssertEqual(corpus.persistentSchemaVersion, 18)
        XCTAssertEqual(corpus.persistentModelCount, 73)
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), ["G", "A", "H", "I", "R"])
        XCTAssertEqual(corpus.evidenceSelectors.map(\.id), [
            "V23-P03-C19-G01", "V23-P03-C19-A01", "V23-P03-C19-H01",
            "V23-P03-C19-I01", "V23-P03-C19-R01"
        ])
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertTrue(corpus.localeAndOrderingIndependent)
        XCTAssertEqual(corpus.coverage, ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"])
        XCTAssertEqual(corpus.instrumentTypes, InstrumentKindV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.instrumentLifecycleStates.sorted(), InstrumentLifecycleStateV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(corpus.calibrationStates.sorted(), CalibrationStatusV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(corpus.qualityDispositions.sorted(), MeasurementQualityResultV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(corpus.qualityReasonCodes.sorted(), MeasurementQualityReasonV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(corpus.classifications.count, 5)
        XCTAssertEqual(corpus.measurementSourceModes, MeasurementCaptureSourceModeV1.allCases.map(\.rawValue))
        XCTAssertTrue(corpus.observationBases.contains("DIRECT_OBSERVATION"))
        XCTAssertEqual(corpus.aggregationPolicies, MeasurementAggregationPolicyV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.fixedPointCases, ["ZERO", "NEGATIVE", "MAX_SCALE", "TIES_TO_EVEN", "INT64_OVERFLOW", "PRECISION_LOSS"])
        XCTAssertEqual(corpus.unitCases, ["SAME_DIMENSION_CONVERSION", "UNKNOWN_UNIT", "DIMENSION_MISMATCH"])
        XCTAssertEqual(corpus.localeCases, ["EN_US", "DECIMAL_SEPARATOR", "GROUPING_SEPARATOR", "RTL"])
        XCTAssertEqual(corpus.seriesCases, ["OPEN_PREFIX", "FINALIZED_ORDERED", "DUPLICATE_SAMPLE", "RETRY_IDEMPOTENT"])
        XCTAssertTrue(corpus.measurementUnits.contains("LUX"))
        XCTAssertTrue(corpus.atomicInterruptionBoundaries.count >= 5)
        XCTAssertTrue(corpus.lifecycleConsumers.contains("BACKUP"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("ERASE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("SEARCH_REBUILD"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("ISOLATED_REPLAY"))
        XCTAssertTrue(corpus.privacyExclusions.contains("PROVIDER_DELIVERY"))
        XCTAssertTrue(corpus.hostileCases.contains("floating-point-value"))
        XCTAssertTrue(corpus.hostileCases.contains("changed-calibration-after-capture"))
        XCTAssertTrue(corpus.interruptionCases.contains("restore"))
        XCTAssertTrue(corpus.recoveryCases.contains("rebuild-series"))
        XCTAssertEqual(corpus.persistentKinds.count, 5)
        XCTAssertTrue(corpus.oldOrNewOnly)
        XCTAssertEqual(corpus.retryDisposition, "SAME_IMMUTABLE_RECEIPT_OR_SAFE_DISCARD")
        XCTAssertEqual(corpus.rollbackCompatibility, [
            "PRE_ACTIVATION_DISCARDABLE", "ACTIVATED_FORWARD_FIX_REQUIRED"
        ])
        XCTAssertEqual(corpus.brandExclusion, "BRAND_IMPACT_MANIFEST_IS_EVIDENCE_ONLY")
        XCTAssertTrue(corpus.forbiddenProductionSymbols.contains("URLSession"))
        XCTAssertTrue(corpus.forbiddenProductionSymbols.contains("CloudKit"))
        XCTAssertTrue(corpus.noSecondWriter)
        XCTAssertTrue(corpus.noSecondStore)
        XCTAssertTrue(corpus.noActivationFromSandbox)
        XCTAssertFalse(corpus.provisionalFlags.native)
        XCTAssertFalse(corpus.provisionalFlags.hosted)
        XCTAssertFalse(corpus.provisionalFlags.adoption)
        XCTAssertFalse(corpus.provisionalFlags.acceptance)
        XCTAssertFalse(corpus.provisionalFlags.release)
        XCTAssertEqual(corpus.c53SharedBoundary.contractNames,
                       C53SharedServiceReliabilitySemanticBoundaryV1.contractNames)
        XCTAssertTrue(corpus.c53SharedBoundary.usesMeasurementAsEvidenceOnly)
        XCTAssertFalse(corpus.c53SharedBoundary.unknownIntervalsQualifyForExactMetrics)
        XCTAssertTrue(C53SharedMeasurementEvidenceBoundaryV1.measurementCapturesRemainEvidenceInputs)
        XCTAssertTrue(C53SharedMeasurementEvidenceBoundaryV1.unqualifiedCaptureCannotSatisfyServiceExposure)
    }

    func testV23P03C19G01InstrumentCalibrationCaptureAndQualityReviewAreDeterministic() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        assertCorpus(try loadCorpus())
        try fixture.instrument.validate()
        XCTAssertEqual(fixture.instrument.supportedUnitIDs, ["[fc_i]", "lx"])
        XCTAssertEqual(fixture.calibrations.map(\.status.rawValue).sorted(), CalibrationStatusV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(fixture.capture.measurement.canonicalUnitID, "lx")
        XCTAssertEqual(fixture.capture.measurement.canonicalValue, try ExactDecimalV1(mantissa: 1_076_391, scale: 5))
        XCTAssertEqual(fixture.qualityClear.result, .clear)
        XCTAssertEqual(fixture.qualityReview.result, .reviewRequired)
        XCTAssertEqual(fixture.qualityOverride.result, .overridden)
        XCTAssertEqual(fixture.qualityReview.reasonCodes, [.calibrationExpired])
        XCTAssertEqual(fixture.qualityOverride.reasonCodes, [.humanOverride])
        let stateReasons: [[MeasurementQualityReasonV1]] = [
            try MeasurementQualityEvaluatorV1.reasons(capture: fixture.capture, calibration: fixture.calibrations[0], requiresUncertainty: false),
            try MeasurementQualityEvaluatorV1.reasons(capture: fixture.capture, calibration: fixture.calibrations[1], requiresUncertainty: false),
            try MeasurementQualityEvaluatorV1.reasons(capture: fixture.capture, calibration: fixture.calibrations[2], requiresUncertainty: false),
            try MeasurementQualityEvaluatorV1.reasons(capture: fixture.capture, calibration: fixture.calibrations[3], requiresUncertainty: false),
            try MeasurementQualityEvaluatorV1.reasons(capture: fixture.capture, calibration: fixture.calibrations[4], requiresUncertainty: false)
        ]
        XCTAssertEqual(stateReasons, [
            [.calibrationNotRequired], [.declaredChecksClear], [.calibrationExpired],
            [.calibrationUnknown], [.instrumentOutOfService]
        ])
        let tie = try ExactUnitConverterV1.rounded(numerator: 5, denominator: 2, targetScale: 0)
        XCTAssertEqual(tie.canonicalValue, try ExactDecimalV1(mantissa: 2, scale: 0))
        try C19MeasurementIntegrityTestSupport.assertAllCanonicalRoundTrips(fixture)
        let prepared = try MeasurementIntegrityCoordinatorV1.captureBundle(
            workspaceID: fixture.workspace, mutationID: fixture.mutationID,
            instrument: fixture.instrument, calibration: fixture.currentCalibration,
            capture: fixture.capture, fieldDefinition: fixture.fieldDefinition,
            assessment: fixture.qualityClear
        )
        let reordered = try MeasurementIntegrityCoordinatorV1.prepare(
            workspaceID: fixture.workspace, mutationID: fixture.mutationID,
            instruments: fixture.bundle.instruments,
            calibrations: Array(fixture.bundle.calibrations.reversed()),
            captures: Array(fixture.bundle.captures.reversed()),
            series: Array(fixture.bundle.series.reversed()),
            assessments: Array(fixture.bundle.assessments.reversed())
        )
        XCTAssertEqual(reordered.bundleSHA256, fixture.bundle.bundleSHA256)
        let receipt = try MeasurementIntegrityWriteReceiptV1(
            workspaceID: fixture.workspace, mutationID: fixture.mutationID,
            bundleSHA256: prepared.bundleSHA256,
            journalReceiptSHA256: C19MeasurementIntegrityTestSupport.digest("f")
        )
        try MeasurementIntegrityCoordinatorV1.validate(receipt, for: prepared)
    }

    func testV23P03C19A01OptionalPlanReferencesRemainIndependentAndTyped() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try fixture.manualCapture.validateClosure(instrument: nil, calibration: nil)
        XCTAssertEqual(fixture.manualCapture.sourceMode, .manualEntry)
        XCTAssertNil(fixture.manualCapture.instrument)
        XCTAssertNil(fixture.manualCapture.calibration)
        XCTAssertTrue(fixture.manualCapture.measurement.source.isLocalMeasurementCaptureSource)
        let installation = try InstallationPlanReferenceV1(
            workspaceID: fixture.workspace, planID: C19MeasurementIntegrityTestSupport.id(80),
            planVersion: 1, planSHA256: C19MeasurementIntegrityTestSupport.digest("g"),
            measurementSubjectID: fixture.capture.captureID,
            measurementSubjectRevision: fixture.capture.revision,
            measurementSubjectSHA256: fixture.capture.captureSHA256
        )
        let punch = try PunchPlanReferenceV1(
            workspaceID: fixture.workspace, planID: C19MeasurementIntegrityTestSupport.id(81),
            planVersion: 1, planSHA256: C19MeasurementIntegrityTestSupport.digest("h"),
            measurementSubjectID: fixture.capture.captureID,
            measurementSubjectRevision: fixture.capture.revision,
            measurementSubjectSHA256: fixture.capture.captureSHA256
        )
        XCTAssertNotEqual(installation.planID, punch.planID)
        try installation.validate()
        try punch.validate()
        let rebound = try fixture.manualCapture.rebound(
            to: WorkspaceID(rawValue: C19MeasurementIntegrityTestSupport.id(82))
        )
        XCTAssertEqual(rebound.captureID, fixture.manualCapture.captureID)
        XCTAssertNotEqual(rebound.workspaceID, fixture.manualCapture.workspaceID)
        try MeasurementIntegrityForwardFixPolicyV1.requireForwardFix(
            afterFirstWrite: false, requestedGeneration: 17
        )
        try MeasurementIntegrityForwardFixPolicyV1.requireForwardFix(
            afterFirstWrite: true, requestedGeneration: 18
        )
        XCTAssertThrowsError(try MeasurementIntegrityForwardFixPolicyV1.requireForwardFix(
            afterFirstWrite: true, requestedGeneration: 17
        ))
    }

    func testV23P03C19H01UnknownCalibrationAndInvalidProvenanceFailClosed() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        XCTAssertEqual(fixture.unknownCalibration.status, .unknown)
        XCTAssertEqual(fixture.unknownCalibration.basis, .unknown)
        let mismatchedCurrentCalibration = try CalibrationStatusSnapshotV1(
            snapshotID: C19MeasurementIntegrityTestSupport.id(120),
            workspaceID: fixture.workspace,
            instrument: try InstrumentRevisionReferenceV1(fixture.instrument),
            status: .current,
            basis: .referencedEvidence,
            effectiveAt: fixture.capture.capturedAt.addingTimeInterval(-60),
            expiresAt: fixture.capture.capturedAt.addingTimeInterval(60),
            sourceReference: fixture.evidence,
            capturedAt: fixture.capture.capturedAt,
            mutationID: fixture.mutationID
        )
        XCTAssertThrowsError(try MeasurementQualityEvaluatorV1.reasons(
            capture: fixture.capture,
            calibration: mismatchedCurrentCalibration,
            requiresUncertainty: false
        ))
        XCTAssertThrowsError(try MeasurementQualityEvaluatorV1.assessCapture(
            assessmentID: C19MeasurementIntegrityTestSupport.id(121),
            capture: fixture.capture,
            calibration: mismatchedCurrentCalibration,
            requiresUncertainty: false,
            policyVersion: "C19-MEASUREMENT-POLICY-V1",
            policySHA256: C19MeasurementIntegrityTestSupport.digest("e"),
            assessedAt: fixture.capture.capturedAt,
            mutationID: fixture.mutationID
        ))
        XCTAssertThrowsError(try KernelUnitRegistryV1.definition(unitID: "localized.lx"))
        XCTAssertThrowsError(try ExactIntegerMathV1.multiply(Int64.max, 2))
        XCTAssertThrowsError(try ExactMeasurementV1(
            enteredValue: try ExactDecimalV1(mantissa: 1, scale: 1),
            enteredUnitID: "[fc_i]", precisionScale: 0,
            uncertaintyCanonical: nil, source: .instrumentObserved,
            captureMethodID: "c19.precision"
        ))
        XCTAssertThrowsError(try MeasurementSeriesEvaluatorV1.finalized(
            snapshotID: C19MeasurementIntegrityTestSupport.id(90),
            seriesID: fixture.series.seriesID, workspaceID: fixture.workspace,
            protocolRelease: fixture.protocolRelease, evaluator: fixture.evaluator,
            captures: [fixture.capture, fixture.capture], expectedSampleCount: 2,
            provenanceID: C19MeasurementIntegrityTestSupport.id(91),
            recordedAt: fixture.capture.capturedAt, supersedes: nil,
            mutationID: fixture.mutationID
        ))
        let duplicateClosure = {
            try fixture.series.validateClosure(
                captures: [fixture.capture, fixture.capture],
                protocolRelease: fixture.protocolRelease
            )
        }
        XCTAssertThrowsError(try duplicateClosure())
        XCTAssertThrowsError(try duplicateClosure())
        XCTAssertThrowsError(try fixture.series.validateSuccessor(of: fixture.series))
        XCTAssertThrowsError(try fixture.expiredCalibration.validateSuccessor(of: fixture.currentCalibration))
        XCTAssertThrowsError(try MeasurementQualityAssessmentV1(
            assessmentID: C19MeasurementIntegrityTestSupport.id(92),
            workspaceID: fixture.workspace, subjectKind: .capture,
            subjectID: fixture.capture.captureID, subjectRevision: fixture.capture.revision,
            subjectSHA256: fixture.capture.captureSHA256, result: .clear,
            reasonCodes: [.calibrationExpired], policyVersion: "C19-MEASUREMENT-POLICY-V1",
            policySHA256: C19MeasurementIntegrityTestSupport.digest("e"),
            assessedAt: fixture.capture.capturedAt, mutationID: fixture.mutationID
        ))
        var forgedObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: MeasurementIntegrityCanonicalCodecV1.encode(fixture.capture)
        ) as? [String: Any])
        forgedObject["captureSHA256"] = C19MeasurementIntegrityTestSupport.digest("z")
        let forgedData = try JSONSerialization.data(withJSONObject: forgedObject, options: [.sortedKeys])
        XCTAssertThrowsError(try MeasurementIntegrityCanonicalCodecV1.decode(
            MeasurementCaptureV1.self, from: forgedData
        ))
        let foreign = try fixture.capture.rebound(
            to: WorkspaceID(rawValue: C19MeasurementIntegrityTestSupport.id(93))
        )
        XCTAssertThrowsError(try foreign.validateClosure(
            instrument: fixture.instrument, calibration: fixture.currentCalibration
        ))
    }

    func testV23P03C19I01InterruptedMeasurementLifecycleRetainsExactSnapshot() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try fixture.openSeries.validate()
        try fixture.series.validateClosure(
            captures: [fixture.capture, fixture.secondCapture],
            protocolRelease: fixture.protocolRelease
        )
        try fixture.series.validateSuccessor(of: fixture.openSeries)
        try fixture.qualityOverride.validateSuccessor(of: fixture.qualityReview)
        let seriesAssessment = try MeasurementQualityAssessmentV1(
            assessmentID: C19MeasurementIntegrityTestSupport.id(94),
            workspaceID: fixture.workspace,
            subjectKind: .series,
            subjectID: fixture.series.seriesID,
            subjectRevision: fixture.series.revision,
            subjectSHA256: fixture.series.seriesSHA256,
            result: .reviewRequired,
            reasonCodes: [.retainedOutlier],
            policyVersion: "C19-MEASUREMENT-POLICY-V1",
            policySHA256: C19MeasurementIntegrityTestSupport.digest("e"),
            assessedAt: fixture.series.recordedAt,
            mutationID: fixture.mutationID
        )
        let validSeriesSuccessor = try MeasurementQualityAssessmentV1(
            assessmentID: C19MeasurementIntegrityTestSupport.id(95),
            workspaceID: fixture.workspace,
            subjectKind: .series,
            subjectID: fixture.series.seriesID,
            subjectRevision: fixture.series.revision,
            subjectSHA256: fixture.series.seriesSHA256,
            result: .reviewRequired,
            reasonCodes: [.retainedOutlier],
            policyVersion: "C19-MEASUREMENT-POLICY-V1",
            policySHA256: C19MeasurementIntegrityTestSupport.digest("e"),
            assessedAt: fixture.series.recordedAt.addingTimeInterval(1),
            supersedesAssessmentID: seriesAssessment.assessmentID,
            revision: 2,
            mutationID: fixture.mutationID
        )
        try validSeriesSuccessor.validateSuccessor(of: seriesAssessment)
        let wrongSeriesSubject = try MeasurementQualityAssessmentV1(
            assessmentID: C19MeasurementIntegrityTestSupport.id(96),
            workspaceID: fixture.workspace,
            subjectKind: .series,
            subjectID: C19MeasurementIntegrityTestSupport.id(97),
            subjectRevision: fixture.series.revision,
            subjectSHA256: fixture.series.seriesSHA256,
            result: .reviewRequired,
            reasonCodes: [.retainedOutlier],
            policyVersion: "C19-MEASUREMENT-POLICY-V1",
            policySHA256: C19MeasurementIntegrityTestSupport.digest("e"),
            assessedAt: fixture.series.recordedAt.addingTimeInterval(1),
            supersedesAssessmentID: seriesAssessment.assessmentID,
            revision: 2,
            mutationID: fixture.mutationID
        )
        let wrongSeriesRevision = try MeasurementQualityAssessmentV1(
            assessmentID: C19MeasurementIntegrityTestSupport.id(98),
            workspaceID: fixture.workspace,
            subjectKind: .series,
            subjectID: fixture.series.seriesID,
            subjectRevision: fixture.series.revision + 1,
            subjectSHA256: fixture.series.seriesSHA256,
            result: .reviewRequired,
            reasonCodes: [.retainedOutlier],
            policyVersion: "C19-MEASUREMENT-POLICY-V1",
            policySHA256: C19MeasurementIntegrityTestSupport.digest("e"),
            assessedAt: fixture.series.recordedAt.addingTimeInterval(1),
            supersedesAssessmentID: seriesAssessment.assessmentID,
            revision: 2,
            mutationID: fixture.mutationID
        )
        let wrongSeriesDigest = try MeasurementQualityAssessmentV1(
            assessmentID: C19MeasurementIntegrityTestSupport.id(99),
            workspaceID: fixture.workspace,
            subjectKind: .series,
            subjectID: fixture.series.seriesID,
            subjectRevision: fixture.series.revision,
            subjectSHA256: C19MeasurementIntegrityTestSupport.digest("q"),
            result: .reviewRequired,
            reasonCodes: [.retainedOutlier],
            policyVersion: "C19-MEASUREMENT-POLICY-V1",
            policySHA256: C19MeasurementIntegrityTestSupport.digest("e"),
            assessedAt: fixture.series.recordedAt.addingTimeInterval(1),
            supersedesAssessmentID: seriesAssessment.assessmentID,
            revision: 2,
            mutationID: fixture.mutationID
        )
        XCTAssertThrowsError(try wrongSeriesSubject.validateSuccessor(of: seriesAssessment))
        XCTAssertThrowsError(try wrongSeriesRevision.validateSuccessor(of: seriesAssessment))
        XCTAssertThrowsError(try wrongSeriesDigest.validateSuccessor(of: seriesAssessment))
        XCTAssertThrowsError(try MeasurementIntegrityCoordinatorV1.prepare(
            workspaceID: fixture.workspace,
            mutationID: fixture.mutationID,
            series: [fixture.series],
            assessments: [seriesAssessment, seriesAssessment]
        ))
        let instrumentRow = try InstrumentReferenceRow(fixture.instrument)
        let currentRow = try CalibrationStatusSnapshotRow(fixture.currentCalibration)
        let captureRow = try MeasurementCaptureRow(fixture.capture)
        let seriesRow = try MeasurementSeriesRow(fixture.series)
        let reviewRow = try MeasurementQualityAssessmentRow(fixture.qualityReview)
        XCTAssertEqual(try instrumentRow.value(), fixture.instrument)
        XCTAssertEqual(try currentRow.value(), fixture.currentCalibration)
        XCTAssertEqual(try captureRow.value(), fixture.capture)
        XCTAssertEqual(try seriesRow.value(), fixture.series)
        XCTAssertEqual(try reviewRow.value(), fixture.qualityReview)
        let rowIDs = [
            instrumentRow.referenceID, currentRow.snapshotID, captureRow.captureID,
            seriesRow.snapshotID, reviewRow.assessmentID
        ]
        XCTAssertEqual(Set(rowIDs).count, rowIDs.count)
        XCTAssertTrue(rowIDs.allSatisfy {
            $0 != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        })
        XCTAssertEqual(fixture.bundle.mutationID, fixture.mutationID)
        XCTAssertEqual(fixture.series.samples.map(\.sampleOrdinal), [1, 2])
    }

    func testV23P03C19R01RecoveryReplayBackupDeleteAndReportRemainExact() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let corpus = try loadCorpus()
        assertCorpus(corpus)
        XCTAssertEqual(PersistentSchemaV18.versionIdentifier, Schema.Version(18, 0, 0))
        XCTAssertEqual(PersistentSchemaV18.models.count, 73)
        XCTAssertEqual(PersistentSchemaMigrationPlanV17.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV17.stages.count, 1)
        try KernelBackupRestoreRegistryV4.validateMeasurementIntegrityLifecycle()
        try KernelDeletionEraseRegistryV4.validateMeasurementIntegrityLifecycle()
        try MeasurementIntegrityDeletionLedgerPolicyV1.validate()
        try MeasurementIntegrityEraseIntentStorePolicyV1.validate()
        XCTAssertEqual(V18BackupMeasurementIntegrityRecordV1.Kind.allCases.count, 5)
        XCTAssertEqual(KernelBackupRestoreRegistryV4.measurementIntegrityArchiveKinds.count, 5)
        XCTAssertEqual(KernelDeletionEraseRegistryV4.measurementIntegrityDeleteKinds.count, 5)
        XCTAssertEqual(MeasurementIntegrityLifecycleCatalogV1.persistentKinds.count, 5)
        XCTAssertEqual(MeasurementIntegrityLifecycleCatalogV1.nonpersistentKinds.count, 2)
        for kind in MeasurementIntegrityLifecycleCatalogV1.persistentKinds {
            XCTAssertEqual(MeasurementIntegrityLifecycleCatalogV1.disposition(for: kind), .canonicalPersistent)
        }
        for kind in MeasurementIntegrityLifecycleCatalogV1.nonpersistentKinds {
            XCTAssertEqual(MeasurementIntegrityLifecycleCatalogV1.disposition(for: kind), .nonpersistentProjection)
        }
        XCTAssertTrue(corpus.lifecycleConsumers.contains("OPEN_JSON"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("REPORT"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("DELETE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("RESTORE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("SYNC_CLASSIFICATION"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("BRAND_IMPACT_MANIFEST"))
        try C19MeasurementIntegrityTestSupport.assertAllCanonicalRoundTrips(fixture)
        let bundleData = try MeasurementIntegrityCanonicalCodecV1.encode(fixture.bundle)
        let rebuilt = try MeasurementIntegrityCanonicalCodecV1.decode(
            MeasurementIntegrityAtomicBundleV1.self, from: bundleData
        )
        XCTAssertEqual(rebuilt, fixture.bundle)
        XCTAssertTrue(corpus.noSecondWriter)
        XCTAssertTrue(corpus.noSecondStore)
    }
}

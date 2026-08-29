import Foundation
import MetricKit
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_12SystemHealthOperationalDiagnosticsTests: XCTestCase {
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV9_12G01BoundedSystemHealthAndSingleMetricSource() throws {
        let corpus = try Self.loadCorpus()
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(
            corpus.fixtureIdentity,
            "V21-P02-C08-SYSTEM-HEALTH-OPERATIONAL-DIAGNOSTICS-CORPUS-V1"
        )
        XCTAssertEqual(MetricReportingSourceContractV1.sourceCount, 1)
        XCTAssertEqual(
            MetricReportingSourceContractV1.retainedSource,
            "IOS18_METRICKIT_FALLBACK"
        )
        XCTAssertFalse(MetricReportingSourceContractV1.permitsBetaOnlyAPI)
        XCTAssertFalse(MetricReportingSourceContractV1.permitsSecondReportingSource)

        let source = V912MetricSource()
        let adapter = MetricKitDiagnosticsAdapter(reportingSource: source)
        adapter.start()
        adapter.start()
        XCTAssertEqual(source.addCount, 1)
        XCTAssertTrue(adapter.accept(MetricKitSummaryV1(
            crashCount: corpus.health.crashCount,
            hangCount: corpus.health.hangCount,
            launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                from1000Through1999: corpus.health.launchBuckets[2],
                from2000Up: corpus.health.launchBuckets[3],
                from500Through999: corpus.health.launchBuckets[1],
                under500: corpus.health.launchBuckets[0]
            ),
            peakMemoryBytes: corpus.health.peakMemoryBytes
        )))
        XCTAssertEqual(adapter.snapshot()?.crashCount, corpus.health.crashCount)
        adapter.stop()
        adapter.stop()
        XCTAssertEqual(source.removeCount, 1)
        let adapterBox = V912MetricAdapterBox(adapter)
        DispatchQueue.concurrentPerform(iterations: 32) { _ in adapterBox.start() }
        XCTAssertEqual(source.addCount, 2)
        DispatchQueue.concurrentPerform(iterations: 32) { _ in adapterBox.stop() }
        XCTAssertEqual(source.removeCount, 2)
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            index.isMultiple(of: 2) ? adapterBox.start() : adapterBox.stop()
        }
        adapterBox.stop()
        XCTAssertEqual(source.addCount, source.removeCount)

        let reentrantSource = V912ReentrantMetricSource()
        let reentrantAdapter = MetricKitDiagnosticsAdapter(reportingSource: reentrantSource)
        reentrantSource.adapter = reentrantAdapter
        reentrantAdapter.start()
        XCTAssertEqual(reentrantSource.addCount, 1)
        XCTAssertEqual(reentrantSource.removeCount, 1)

        let failures = try (0..<SystemHealthDiagnosticsV1.maximumFailureCount).map {
            try Self.failure(.interrupted, at: corpus.createdAt.addingTimeInterval(Double($0)))
        }
        let health = try SystemHealthDiagnosticsV1(
            generatedAt: corpus.createdAt,
            state: .degraded,
            failures: failures,
            metricKit: adapter.snapshot()
        )
        XCTAssertEqual(health.failures.count, SystemHealthDiagnosticsV1.maximumFailureCount)
        XCTAssertThrowsError(try SystemHealthDiagnosticsV1(
            generatedAt: corpus.createdAt,
            state: .degraded,
            failures: failures + [try Self.failure(.interrupted, at: corpus.createdAt)],
            metricKit: nil
        ))
        XCTAssertFalse(adapter.accept(MetricKitSummaryV1(
            crashCount: -1,
            hangCount: 0,
            launchTimeMilliseconds: nil,
            peakMemoryBytes: nil
        )))
    }

    func testV9_12A01OperationalFailureRegistryAndDefaultOffFrictionAreClosed() async throws {
        let corpus = try Self.loadCorpus()
        try OperationalFailureRegistryV1.validate()
        XCTAssertEqual(
            Set(OperationalFailureCodeV1.allCases.map(\.rawValue)),
            Set(corpus.failureCodes)
        )
        for code in OperationalFailureCodeV1.allCases {
            let descriptor = try OperationalFailureRegistryV1.descriptor(for: code)
            XCTAssertEqual(descriptor.code, code)
            XCTAssertFalse(descriptor.owner.rawValue.isEmpty)
            XCTAssertFalse(descriptor.primaryAction.rawValue.isEmpty)
            XCTAssertEqual(descriptor.privacyClass, .aggregate)
            XCTAssertFalse(descriptor.retryability.rawValue.isEmpty)
            if descriptor.retryability != .notRetryable {
                XCTAssertNotEqual(descriptor.primaryAction, .none)
            }
        }
        let unknown = try OperationalFailureRegistryV1.descriptor(for: .unknown)
        XCTAssertEqual(unknown.primaryAction.rawValue, corpus.unknownFailure.primaryAction)
        XCTAssertEqual(unknown.fallbackAction?.rawValue, corpus.unknownFailure.fallbackAction)
        XCTAssertEqual(unknown.retryability, .notRetryable)
        XCTAssertFalse(corpus.unknownFailure.destructiveAutomaticRetryAllowed)

        let typedCases: [(String, OperationalFailureBoundaryV1, any Error)] = [
            ("StoreMigrationFailure.invalidDigest", .persistence, StoreMigrationFailure.invalidDigest),
            ("MediaImportErrorV1.malformedSource", .content, MediaImportErrorV1.malformedSource),
            ("ReportRenderServiceError.writeFailed", .report, ReportRenderServiceError.writeFailed),
            ("BackupExportServiceError.sourceChanged", .backup, BackupExportServiceError.sourceChanged),
            ("ApplicationFileAuthorityErrorV1.invalidComponent", .permissionFileAuthority, ApplicationFileAuthorityErrorV1.invalidComponent),
            ("StoreKitProductLoaderError.unavailable", .commerce, StoreKitProductLoaderError.unavailable),
            ("OperationalDiagnosticsValidationFailureV1.invalidValue", .persistence, OperationalDiagnosticsValidationFailureV1.invalidValue),
        ]
        XCTAssertEqual(corpus.typedErrorMapping.cases.count, typedCases.count)
        XCTAssertFalse(corpus.typedErrorMapping.underlyingFailureCanBecomeEmptySuccess)
        XCTAssertTrue(corpus.typedErrorMapping.storeWriteFailurePropagates)
        XCTAssertTrue(corpus.typedErrorMapping.provisionalKernelOnly)
        XCTAssertEqual(
            corpus.typedErrorMapping.shippingBoundaryAdoption,
            "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION"
        )
        for fixtureCase in corpus.typedErrorMapping.cases {
            let typed = try XCTUnwrap(typedCases.first { $0.0 == fixtureCase.typedError })
            XCTAssertEqual(typed.1.rawValue, fixtureCase.boundary)
            let mapped = try OperationalFailureMapperV1.failure(
                for: typed.2,
                at: typed.1,
                occurredAt: corpus.createdAt
            )
            XCTAssertEqual(mapped.descriptor.code.rawValue, fixtureCase.expectedCode)
            XCTAssertEqual(mapped.descriptor.primaryAction.rawValue, fixtureCase.expectedPrimaryAction)
            XCTAssertEqual(mapped.descriptor.retryability.rawValue, fixtureCase.expectedRetryability)
            XCTAssertEqual(mapped.descriptor.privacyClass.rawValue, fixtureCase.expectedPrivacyClass)
        }

        let boundaryRoot = try Self.temporaryRoot("A01-boundary")
        defer { try? FileManager.default.removeItem(at: boundaryRoot) }
        let boundaryStore = DiagnosticsStore(
            applicationSupportURL: boundaryRoot,
            now: { corpus.createdAt }
        )
        let beforeBoundary = try await boundaryStore.operationalSupportSnapshot()
        XCTAssertTrue(beforeBoundary.health.failures.isEmpty)
        var originalFailureRethrown = false
        do {
            try await boundaryStore.recordAndRethrowOperationalFailure(
                at: .persistence
            ) {
                throw StoreMigrationFailure.invalidDigest
            }
        } catch {
            XCTAssertEqual(error as? StoreMigrationFailure, .invalidDigest)
            originalFailureRethrown = true
        }
        XCTAssertTrue(originalFailureRethrown)
        let afterBoundary = try await boundaryStore.operationalSupportSnapshot()
        XCTAssertEqual(afterBoundary.health.failures.count, 1)
        XCTAssertEqual(
            afterBoundary.health.failures.first?.descriptor.code,
            .persistenceMigrationRequired
        )

        let writeFailureRoot = try Self.temporaryRoot("A01-write-failure")
        defer { try? FileManager.default.removeItem(at: writeFailureRoot) }
        let seededWriteFailureStore = DiagnosticsStore(
            applicationSupportURL: writeFailureRoot,
            now: { corpus.createdAt },
            capacityProvider: { _ in Int64.max }
        )
        _ = try await seededWriteFailureStore.operationalSupportSnapshot()
        let writeFailureStore = DiagnosticsStore(
            applicationSupportURL: writeFailureRoot,
            now: { corpus.createdAt },
            capacityProvider: { _ in 0 }
        )
        var diagnosticsWriteFailurePropagated = false
        do {
            try await writeFailureStore.recordAndRethrowOperationalFailure(
                at: .persistence
            ) {
                throw StoreMigrationFailure.invalidDigest
            }
        } catch {
            XCTAssertNil(error as? StoreMigrationFailure)
            diagnosticsWriteFailurePropagated = true
        }
        XCTAssertTrue(diagnosticsWriteFailurePropagated)

        XCTAssertEqual(DeviceOperationalSupportStoreSchemaV2.maximumRecordBytes, corpus.bounds.supportStoreRecordBytes)
        XCTAssertEqual(DeviceOperationalSupportStoreSchemaV2.maximumTotalBytes, corpus.bounds.supportStoreTotalBytes)
        XCTAssertEqual(DeviceOperationalSupportStoreSchemaV2.maximumRecords, corpus.bounds.supportStoreRecordCount)
        XCTAssertEqual(SupportBundleManifestV1.maximumCanonicalBytes, corpus.bounds.supportBundleBytes)
        for budget in corpus.bounds.scratch {
            let purpose = try Self.scratchPurpose(budget.purpose)
            XCTAssertEqual(purpose.maximumByteCount, budget.maximumBytes)
            XCTAssertEqual(purpose.maximumLifetimeSeconds, budget.maximumLifetimeSeconds)
        }

        let profile = try WorkflowFrictionProfileV1(
            profileID: corpus.workflowFriction.profileID,
            declaredStateKeys: corpus.workflowFriction.declaredStates
        )
        XCTAssertEqual(profile.declaredStateKeys, WorkflowStateRegistryV1.states)
        XCTAssertFalse(profile.recordsCustomerContent)
        XCTAssertFalse(profile.permitsNetwork)
        XCTAssertFalse(LocalDiagnosticsPreferenceV1.declaration.isEnabled)
        XCTAssertFalse(LocalDiagnosticsPreferenceV1.declaration.productionWritesAllowed)
        XCTAssertFalse(LocalDiagnosticsPreferenceV1.declaration.networkAllowed)
        XCTAssertEqual(corpus.workflowFriction.productionWriteCount, 0)
        XCTAssertEqual(corpus.workflowFriction.networkRequestCount, 0)
        XCTAssertThrowsError(try WorkflowFrictionEventV1(
            profileID: profile.profileID,
            stateKey: "customer note",
            elapsedMilliseconds: 1
        ))

        try OperationalLogRegistryV1.validate()
        try PerformanceSignpostRegistryV1.validate()
        XCTAssertFalse(OSLogEmissionPolicyV1.permitsDynamicMessages)
        XCTAssertFalse(OSLogEmissionPolicyV1.permitsCustomerContent)
        XCTAssertFalse(OSLogEmissionPolicyV1.permitsCustomerIdentifiers)
        XCTAssertFalse(OSLogEmissionPolicyV1.permitsRawLogExport)
        XCTAssertTrue(PerformanceSignpostPolicyV1.requiresBalancedBeginEnd)
        let signposts = PerformanceSignpostRecorderV1()
        for index in 0..<corpus.logging.beginCount {
            let token = try signposts.begin(.supportExport, tokenID: Self.id(UInt8(60 + index)))
            try signposts.end(token, outcome: index.isMultiple(of: 2) ? .success : .failure)
        }
        let signpostSnapshot = try signposts.snapshot(requireBalanced: true)
        XCTAssertEqual(signpostSnapshot.events.filter { $0.phase == .begin }.count, corpus.logging.beginCount)
        XCTAssertEqual(signpostSnapshot.events.count, corpus.logging.beginCount + corpus.logging.endCount)
        XCTAssertTrue(signpostSnapshot.isBalanced)
    }

    func testV9_12H01SupportExportRejectsCustomerDataAndSourceScratch() async throws {
        let corpus = try Self.loadCorpus()
        let scratch = V912ScratchStore()
        let diagnostic = try Self.preparedDiagnostic(corpus)
        let support = try Self.supportSnapshot(corpus)
        let ids = V912IDSource([
            corpus.supportExport.operationID,
            Self.id(2),
            Self.id(3),
            Self.id(4),
        ])
        let builder = SupportBundleBuilderV1(
            diagnostic: { diagnostic },
            support: { support },
            scratch: scratch,
            clock: { corpus.createdAt },
            idSource: { ids.next() }
        )
        let result = try await builder.prepare(mode: .full)
        XCTAssertEqual(result.disposition, .prepared)
        let manifest = try XCTUnwrap(result.manifest)
        XCTAssertEqual(Set(manifest.entries.map(\.kind)), [.diagnosticSummary, .systemHealth])
        XCTAssertLessThanOrEqual(manifest.totalCanonicalByteCount, corpus.bounds.supportBundleBytes)
        XCTAssertFalse(manifest.containsCustomerContent)
        XCTAssertFalse(manifest.containsCustomerIdentifier)
        XCTAssertFalse(manifest.containsRawLogs)
        XCTAssertFalse(manifest.permitsAutomaticUpload)
        let capturedPayload = await scratch.lastPayload()
        let payload = try XCTUnwrap(capturedPayload)
        let payloadText = String(decoding: payload, as: UTF8.self)
        for forbidden in corpus.supportExport.forbiddenValues {
            XCTAssertFalse(payloadText.contains(forbidden), forbidden)
        }
        XCTAssertEqual(corpus.supportExport.networkRequestCount, 0)
        XCTAssertTrue(corpus.supportExport.offlineAllowed)
        XCTAssertFalse(corpus.supportExport.automaticUploadAllowed)
        XCTAssertFalse(corpus.supportExport.externalShareRecallable)
        let shared = try await builder.finish(result, disposition: .shared)
        XCTAssertEqual(shared.disposition, .shared)
        XCTAssertNotNil(shared.manifest)
        XCTAssertNil(shared.fileURL)
        let terminals = await scratch.terminals()
        let activeCount = await scratch.activeCount()
        XCTAssertEqual(terminals, [.completed])
        XCTAssertEqual(activeCount, 0)
        await XCTAssertThrowsErrorAsync(
            try await builder.finish(result, disposition: .shared),
            equals: SupportBundleBuilderFailureV1.alreadyFinished
        )
        await XCTAssertThrowsErrorAsync(
            try await builder.finish(result, disposition: .cancelled),
            equals: SupportBundleBuilderFailureV1.alreadyFinished
        )
        let replayTerminals = await scratch.terminals()
        XCTAssertEqual(replayTerminals, [.completed])

        for disposition in [
            SupportExportDispositionV1.cancelled,
            .failed,
            .expired,
        ] {
            let prepared = try await builder.prepare(mode: .full)
            let finished = try await builder.finish(prepared, disposition: disposition)
            XCTAssertEqual(finished.disposition, disposition)
            XCTAssertNil(finished.manifest)
            XCTAssertNil(finished.fileURL)
        }
        let allTerminalEffects = await scratch.terminals()
        XCTAssertEqual(allTerminalEffects, [
            .completed, .cancelled, .failed, .recoveredExpired,
        ])

        let cancelled = try await builder.prepare(
            mode: .full,
            cancellation: SupportExportCancellationV1 { true }
        )
        XCTAssertEqual(cancelled.disposition, .cancelled)
        XCTAssertNil(cancelled.fileURL)

        let sourceRequest = try ScratchDataLeaseRequestV1(
            leaseID: Self.id(5),
            purpose: .source,
            owner: .source,
            ownerOperationID: Self.id(6),
            requestedByteCount: 1,
            createdAt: corpus.createdAt,
            expiresAt: corpus.createdAt.addingTimeInterval(1)
        )
        XCTAssertThrowsError(try ScratchDataLeaseRequestV1(
            leaseID: Self.id(7),
            purpose: sourceRequest.purpose,
            owner: .supportExport,
            ownerOperationID: sourceRequest.ownerOperationID,
            requestedByteCount: sourceRequest.requestedByteCount,
            createdAt: sourceRequest.createdAt,
            expiresAt: sourceRequest.expiresAt
        ))

        let tooLarge = PreparedDiagnosticExportV1(
            value: diagnostic.value,
            canonicalData: Data(count: SupportBundleManifestV1.maximumCanonicalBytes + 1)
        )
        let oversized = SupportBundleBuilderV1(
            diagnostic: { tooLarge }, support: { support }, scratch: scratch,
            clock: { corpus.createdAt }, idSource: { Self.id(8) }
        )
        await XCTAssertThrowsErrorAsync(
            try await oversized.prepare(mode: .full),
            equals: SupportBundleBuilderFailureV1.sizeLimitExceeded
        )
        let mismatched = PreparedDiagnosticExportV1(
            value: diagnostic.value,
            canonicalData: Data("{}".utf8)
        )
        let mismatchedBuilder = SupportBundleBuilderV1(
            diagnostic: { mismatched }, support: { support }, scratch: scratch,
            clock: { corpus.createdAt }, idSource: { Self.id(9) }
        )
        await XCTAssertThrowsErrorAsync(
            try await mismatchedBuilder.prepare(mode: .full),
            equals: SupportBundleBuilderFailureV1.invalidSource
        )

        let retryScratch = V912ScratchStore(releaseFailuresRemaining: 1)
        let retryBuilder = SupportBundleBuilderV1(
            diagnostic: { diagnostic }, support: { support }, scratch: retryScratch,
            clock: { corpus.createdAt }, idSource: { Self.id(10) }
        )
        let retryPrepared = try await retryBuilder.prepare(mode: .full)
        await XCTAssertThrowsErrorAsync(
            try await retryBuilder.finish(retryPrepared, disposition: .shared),
            equals: SupportBundleBuilderFailureV1.cleanupFailed
        )
        await XCTAssertThrowsErrorAsync(
            try await retryBuilder.finish(retryPrepared, disposition: .cancelled),
            equals: SupportBundleBuilderFailureV1.alreadyFinished
        )
        let retryReceipt = try await retryBuilder.finish(retryPrepared, disposition: .shared)
        XCTAssertEqual(retryReceipt.disposition, .shared)
        let retryEffects = await retryScratch.terminals()
        let retryAttempts = await retryScratch.releaseAttemptCount()
        XCTAssertEqual(retryEffects, [.completed])
        XCTAssertEqual(retryAttempts, 2)
    }

    func testV9_12I01StoreScratchAndSupportExportRecoverWithoutDuplicateEffects() async throws {
        let corpus = try Self.loadCorpus()
        let root = try Self.temporaryRoot("I01")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = V912Clock(corpus.createdAt)
        let store = try ScratchDataLeaseStoreV1(
            applicationSupportURL: root,
            clock: { clock.now },
            capacityProvider: { _ in Int64.max }
        )
        let request = try ScratchDataLeaseRequestV1(
            leaseID: Self.id(20),
            purpose: .supportExport,
            owner: .supportExport,
            ownerOperationID: Self.id(21),
            requestedByteCount: 64,
            createdAt: corpus.createdAt,
            expiresAt: corpus.createdAt.addingTimeInterval(900)
        )
        XCTAssertEqual(request.protection, .complete)
        XCTAssertEqual(request.backupPolicy, .excluded)
        let lease = try await store.acquireScratchLease(request)
        let boundedData = Data("bounded".utf8)
        let firstURL = try await store.writeScratchData(
            boundedData, named: "support.json", lease: lease
        )
        let adoptedURL = try await store.writeScratchData(
            boundedData, named: "support.json", lease: lease
        )
        XCTAssertEqual(adoptedURL, firstURL)
        await XCTAssertThrowsErrorAsync(
            try await store.writeScratchData(
                Data("changed".utf8), named: "support.json", lease: lease
            ),
            equals: ScratchDataLeaseStoreFailureV1.leaseCollision
        )
        XCTAssertEqual(try Data(contentsOf: firstURL), boundedData)

        let exactData = Data("exact-cap".utf8)
        let exactRequest = try ScratchDataLeaseRequestV1(
            leaseID: Self.id(28), purpose: .supportExport, owner: .supportExport,
            ownerOperationID: Self.id(68),
            requestedByteCount: UInt64(exactData.count),
            createdAt: corpus.createdAt,
            expiresAt: corpus.createdAt.addingTimeInterval(900)
        )
        let exactLease = try await store.acquireScratchLease(exactRequest)
        let exactURL = try await store.writeScratchData(
            exactData, named: "exact.json", lease: exactLease
        )
        let exactAdoptedURL = try await store.writeScratchData(
            exactData, named: "exact.json", lease: exactLease
        )
        XCTAssertEqual(exactAdoptedURL, exactURL)
        await XCTAssertThrowsErrorAsync(
            try await store.writeScratchData(
                Data("different".utf8), named: "exact.json", lease: exactLease
            ),
            equals: ScratchDataLeaseStoreFailureV1.leaseCollision
        )
        XCTAssertEqual(try Data(contentsOf: exactURL), exactData)
        try await store.releaseScratchLease(exactLease, terminal: .completed)

        let relaunched = try ScratchDataLeaseStoreV1(
            applicationSupportURL: root,
            clock: { clock.now },
            capacityProvider: { _ in Int64.max }
        )
        let initialRecovery = try await relaunched.recoverScratchLeases()
        XCTAssertEqual(initialRecovery.recoveredExpiredLeaseCount, 0)
        XCTAssertEqual(initialRecovery.removedByteCount, 0)
        let reacquired = try await relaunched.acquireScratchLease(request)
        XCTAssertEqual(reacquired, lease)
        try await relaunched.releaseScratchLease(lease, terminal: .cancelled)
        try await relaunched.releaseScratchLease(lease, terminal: .cancelled)
        let postReleaseRecovery = try await relaunched.recoverScratchLeases()
        XCTAssertEqual(postReleaseRecovery.recoveredExpiredLeaseCount, 0)

        let expiring = try ScratchDataLeaseRequestV1(
            leaseID: Self.id(22), purpose: .supportExport, owner: .supportExport,
            ownerOperationID: Self.id(23), requestedByteCount: 8,
            createdAt: corpus.createdAt,
            expiresAt: corpus.createdAt.addingTimeInterval(10)
        )
        _ = try await relaunched.acquireScratchLease(expiring)
        clock.advance(seconds: 11)
        let expiryRecovery = try await relaunched.recoverScratchLeases()
        XCTAssertEqual(expiryRecovery.recoveredExpiredLeaseCount, 1)
        XCTAssertGreaterThan(expiryRecovery.removedByteCount, 0)

        XCTAssertThrowsError(try ScratchDataLeaseRequestV1(
            leaseID: Self.id(24), purpose: .supportExport, owner: .supportExport,
            ownerOperationID: Self.id(25),
            requestedByteCount: ScratchDataPurposeV1.supportExport.maximumByteCount + 1,
            createdAt: clock.now, expiresAt: clock.now.addingTimeInterval(1)
        ))
        let lowSpaceRoot = try Self.temporaryRoot("I01-low")
        defer { try? FileManager.default.removeItem(at: lowSpaceRoot) }
        let lowSpace = try ScratchDataLeaseStoreV1(
            applicationSupportURL: lowSpaceRoot,
            clock: { clock.now }, capacityProvider: { _ in 0 }
        )
        await XCTAssertThrowsErrorAsync(
            try await lowSpace.acquireScratchLease(try ScratchDataLeaseRequestV1(
                leaseID: Self.id(26), purpose: .supportExport, owner: .supportExport,
                ownerOperationID: Self.id(27), requestedByteCount: 1,
                createdAt: clock.now, expiresAt: clock.now.addingTimeInterval(1)
            )),
            equals: ScratchDataLeaseStoreFailureV1.insufficientCapacity
        )

        let interruptedRoot = try Self.temporaryRoot("I01-store-stage")
        defer { try? FileManager.default.removeItem(at: interruptedRoot) }
        try Self.writeLegacyDiagnosticsV1(at: interruptedRoot)
        let firstStore = DiagnosticsStore(
            applicationSupportURL: interruptedRoot, now: { corpus.createdAt }
        )
        let firstSnapshot = try await firstStore.operationalSupportSnapshot()
        XCTAssertEqual(firstSnapshot.counters.firstSignCreated, 1)
        let canonicalURL = Self.diagnosticsURL(interruptedRoot)
        let stagedURL = canonicalURL.deletingLastPathComponent()
            .appendingPathComponent(".counters.json.next")
        try FileManager.default.moveItem(at: canonicalURL, to: stagedURL)
        let recoveredStore = DiagnosticsStore(
            applicationSupportURL: interruptedRoot, now: { corpus.createdAt }
        )
        let recoveredSnapshot = try await recoveredStore.operationalSupportSnapshot()
        XCTAssertEqual(recoveredSnapshot.counters.firstSignCreated, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))

        for (offset, replacement) in [
            (30, ("\"schemaVersion\":1", "\"schemaVersion\":2")),
            (31, ("\"backupPolicy\":\"EXCLUDED\"", "\"backupPolicy\":\"INCLUDED\"")),
        ] {
            let hostileRoot = try Self.temporaryRoot("I01-metadata-\(offset)")
            defer { try? FileManager.default.removeItem(at: hostileRoot) }
            let hostileStore = try ScratchDataLeaseStoreV1(
                applicationSupportURL: hostileRoot,
                clock: { corpus.createdAt },
                capacityProvider: { _ in Int64.max }
            )
            let hostileRequest = try ScratchDataLeaseRequestV1(
                leaseID: Self.id(UInt8(offset)), purpose: .supportExport,
                owner: .supportExport, ownerOperationID: Self.id(UInt8(offset + 40)),
                requestedByteCount: 8, createdAt: corpus.createdAt,
                expiresAt: corpus.createdAt.addingTimeInterval(900)
            )
            let hostileLease = try await hostileStore.acquireScratchLease(hostileRequest)
            let metadataURL = Self.scratchRoot(hostileRoot)
                .appendingPathComponent(hostileLease.relativeDirectory, isDirectory: true)
                .appendingPathComponent("lease.json")
            let originalMetadata = String(decoding: try Data(contentsOf: metadataURL), as: UTF8.self)
            let hostileMetadata = Data(originalMetadata.replacingOccurrences(
                of: replacement.0, with: replacement.1
            ).utf8)
            XCTAssertNotEqual(hostileMetadata, Data(originalMetadata.utf8))
            try hostileMetadata.write(to: metadataURL)
            try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: metadataURL)
            let hostileRelaunch = try ScratchDataLeaseStoreV1(
                applicationSupportURL: hostileRoot,
                clock: { corpus.createdAt }, capacityProvider: { _ in Int64.max }
            )
            await XCTAssertThrowsErrorAsync(
                try await hostileRelaunch.recoverScratchLeases(),
                equals: ScratchDataLeaseStoreFailureV1.invalidLease
            )
            XCTAssertEqual(try Data(contentsOf: metadataURL), hostileMetadata)
        }

        let tombstoneRoot = try Self.temporaryRoot("I01-tombstone")
        defer { try? FileManager.default.removeItem(at: tombstoneRoot) }
        let tombstoneStore = try ScratchDataLeaseStoreV1(
            applicationSupportURL: tombstoneRoot,
            clock: { corpus.createdAt }, capacityProvider: { _ in Int64.max }
        )
        let tombstoneRequest = try ScratchDataLeaseRequestV1(
            leaseID: Self.id(32), purpose: .supportExport, owner: .supportExport,
            ownerOperationID: Self.id(72), requestedByteCount: 8,
            createdAt: corpus.createdAt, expiresAt: corpus.createdAt.addingTimeInterval(900)
        )
        let tombstoneLease = try await tombstoneStore.acquireScratchLease(tombstoneRequest)
        let tombstoneOriginal = Self.scratchRoot(tombstoneRoot)
            .appendingPathComponent(tombstoneLease.relativeDirectory, isDirectory: true)
        let tombstoneURL = tombstoneOriginal.deletingLastPathComponent()
            .appendingPathComponent(".deleting-\(tombstoneLease.relativeDirectory)", isDirectory: true)
        try FileManager.default.moveItem(at: tombstoneOriginal, to: tombstoneURL)
        let tombstoneRelaunch = try ScratchDataLeaseStoreV1(
            applicationSupportURL: tombstoneRoot,
            clock: { corpus.createdAt }, capacityProvider: { _ in Int64.max }
        )
        _ = try await tombstoneRelaunch.recoverScratchLeases()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tombstoneURL.path))

        let collisionLease = try await tombstoneRelaunch.acquireScratchLease(tombstoneRequest)
        let collisionOriginal = Self.scratchRoot(tombstoneRoot)
            .appendingPathComponent(collisionLease.relativeDirectory, isDirectory: true)
        let collisionTombstone = collisionOriginal.deletingLastPathComponent()
            .appendingPathComponent(".deleting-\(collisionLease.relativeDirectory)", isDirectory: true)
        try FileManager.default.copyItem(at: collisionOriginal, to: collisionTombstone)
        let collisionRelaunch = try ScratchDataLeaseStoreV1(
            applicationSupportURL: tombstoneRoot,
            clock: { corpus.createdAt }, capacityProvider: { _ in Int64.max }
        )
        await XCTAssertThrowsErrorAsync(
            try await collisionRelaunch.recoverScratchLeases(),
            equals: ScratchDataLeaseStoreFailureV1.leaseCollision
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: collisionOriginal.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: collisionTombstone.path))
    }

    func testV9_12R01MigrationResetEraseAndBootstrapRemainDeviceLocal() async throws {
        let corpus = try Self.loadCorpus()
        let root = try Self.temporaryRoot("R01")
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeLegacyDiagnosticsV1(at: root)
        let store = DiagnosticsStore(applicationSupportURL: root, now: { corpus.createdAt })
        let migrated = try await store.operationalSupportSnapshot()
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.counters.firstSignCreated, 1)
        XCTAssertTrue(migrated.health.failures.isEmpty)
        let envelope = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.diagnosticsURL(root))
        ) as? [String: Any]
        XCTAssertEqual((envelope?["schemaVersion"] as? NSNumber)?.intValue, 2)

        let futureRoot = try Self.temporaryRoot("R01-future")
        defer { try? FileManager.default.removeItem(at: futureRoot) }
        var futureObject = try XCTUnwrap(envelope)
        futureObject["schemaVersion"] = 99
        let futureBytes = try JSONSerialization.data(
            withJSONObject: futureObject, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        try Self.writeDiagnosticsBytes(futureBytes, at: futureRoot)
        let futureStore = DiagnosticsStore(applicationSupportURL: futureRoot)
        var futureRejected = false
        do {
            _ = try await futureStore.operationalSupportSnapshot()
        } catch {
            futureRejected = true
        }
        XCTAssertTrue(futureRejected)
        XCTAssertEqual(try Data(contentsOf: Self.diagnosticsURL(futureRoot)), futureBytes)

        let corruptRoot = try Self.temporaryRoot("R01-corrupt")
        defer { try? FileManager.default.removeItem(at: corruptRoot) }
        try Self.writeDiagnosticsBytes(Data("{corrupt".utf8), at: corruptRoot)
        let corruptStore = DiagnosticsStore(applicationSupportURL: corruptRoot, now: { corpus.createdAt })
        let repaired = try await corruptStore.operationalSupportSnapshot()
        XCTAssertEqual(repaired.counters, .zero)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: Self.diagnosticsURL(corruptRoot)
                .deletingLastPathComponent()
                .appendingPathComponent(".counters.json.quarantine").path
        ))

        let lowStorageRoot = try Self.temporaryRoot("R01-low-store")
        defer { try? FileManager.default.removeItem(at: lowStorageRoot) }
        let lowStorageStore = DiagnosticsStore(
            applicationSupportURL: lowStorageRoot,
            now: { corpus.createdAt },
            capacityProvider: { _ in 0 }
        )
        var lowStorageRejected = false
        do {
            try await lowStorageStore.recordOperationalFailure(
                Self.failure(.storageWriteFailed, at: corpus.createdAt)
            )
        } catch {
            lowStorageRejected = true
        }
        XCTAssertTrue(lowStorageRejected)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: Self.diagnosticsURL(lowStorageRoot).path
        ))

        try await store.recordOperationalFailure(
            Self.failure(.storageWriteFailed, at: corpus.createdAt)
        )
        let failedSnapshot = try await store.operationalSupportSnapshot()
        XCTAssertEqual(failedSnapshot.health.failures.count, 1)
        try await store.resetOperationalSupport()
        let reset = try await store.operationalSupportSnapshot()
        XCTAssertEqual(reset.counters, .zero)
        XCTAssertTrue(reset.health.failures.isEmpty)

        let scratch = V912ScratchStore()
        let diagnostic = try Self.preparedDiagnostic(corpus)
        let canonicalOpenCount = V912Counter()
        let bootstrap = SupportBundleBuilderV1(
            diagnostic: { diagnostic },
            support: {
                canonicalOpenCount.increment()
                throw V912Failure.unexpectedCanonicalOpen
            },
            scratch: scratch,
            clock: { corpus.createdAt },
            idSource: { Self.id(40) }
        )
        let bootstrapResult = try await bootstrap.prepare(mode: .bootstrapOnly)
        XCTAssertEqual(bootstrapResult.manifest?.entries.map(\.kind), [.diagnosticSummary])
        XCTAssertEqual(
            canonicalOpenCount.value,
            corpus.supportExport.bootstrapCanonicalStoreOpenCount,
            "bootstrap support export must perform no canonical store open"
        )
        let bootstrapFinished = try await bootstrap.finish(
            bootstrapResult, disposition: .shared
        )
        XCTAssertEqual(bootstrapFinished.disposition, .shared)
        let bootstrapActiveCount = await scratch.activeCount()
        XCTAssertEqual(bootstrapActiveCount, 0)

        let lifecycleTrace = V912LifecycleTrace()
        let lifecycleJobs = V912LifecycleJobs(trace: lifecycleTrace)
        let lifecycleSupport = V912SupportStore(
            snapshot: try Self.supportSnapshot(corpus), trace: lifecycleTrace
        )
        let lifecycleScratch = V912ScratchStore(trace: lifecycleTrace)
        let lifecycle = try await DeviceLifecycleCoordinatorV1.bootstrap(
            jobs: lifecycleJobs,
            operationalSupportStore: lifecycleSupport,
            scratchDataLeaseStore: lifecycleScratch
        )
        let bootstrapSuspensions = await lifecycleJobs.suspensions()
        let deferredSupportReads = await lifecycleSupport.snapshotCount()
        let deferredScratchReads = await lifecycleScratch.recoveryCount()
        XCTAssertEqual(bootstrapSuspensions, [.protectedDataUnavailable])
        XCTAssertEqual(deferredSupportReads, 0)
        XCTAssertEqual(deferredScratchReads, 0)
        _ = try await lifecycle.handle(.protectedDataBecameAvailable)
        let recoveredSupportReads = await lifecycleSupport.snapshotCount()
        let recoveredScratchReads = await lifecycleScratch.recoveryCount()
        let recoveryResumptions = await lifecycleJobs.resumptions()
        XCTAssertEqual(recoveredSupportReads, 1)
        XCTAssertEqual(recoveredScratchReads, 1)
        XCTAssertEqual(recoveryResumptions, [.protectedDataUnavailable])
        try await lifecycle.resetDeviceLocalState()
        let supportResets = await lifecycleSupport.resetCount()
        let scratchResets = await lifecycleScratch.resetCount()
        let resetSupportSnapshot = try await lifecycleSupport.operationalSupportSnapshot()
        XCTAssertEqual(supportResets, 1)
        XCTAssertEqual(scratchResets, 1)
        XCTAssertEqual(resetSupportSnapshot.counters, .zero)
        XCTAssertTrue(resetSupportSnapshot.health.failures.isEmpty)
        _ = try await lifecycle.handle(.protectedDataBecameUnavailable)
        _ = try await lifecycle.handle(.protectedDataBecameAvailable)
        let secondCycleSupportReads = await lifecycleSupport.snapshotCount()
        let secondCycleScratchReads = await lifecycleScratch.recoveryCount()
        let secondCycleResumptions = await lifecycleJobs.resumptions()
        let lifecycleEvents = await lifecycleTrace.events()
        XCTAssertEqual(secondCycleSupportReads, 3)
        XCTAssertEqual(secondCycleScratchReads, 2)
        XCTAssertEqual(secondCycleResumptions, [
            .protectedDataUnavailable, .protectedDataUnavailable,
        ])
        XCTAssertEqual(Array(lifecycleEvents.suffix(3)), ["support", "scratch", "resume"])

        let catalog = try CurrentSyncClassificationCatalogV1.current
        for name in ["DiagnosticExportV1", "DeviceOperationalSupportStoreV2", "ScratchDataLeaseStoreV1"] {
            let subject = try SyncSubjectIdentityV1(category: .diagnostic, stableName: name)
            let registration = try catalog.registration(for: subject)
            let route = try catalog.lifecycleRoute(for: subject)
            XCTAssertEqual(registration.classification, .privateDeviceOnly)
            XCTAssertEqual(registration.replicationPolicy.transport, .excluded)
            XCTAssertEqual(registration.replicationPolicy.export, .exclude)
            XCTAssertEqual(route.semanticBackup, .exclude)
            XCTAssertEqual(route.portableExport, .exclude)
        }

        let scratchRoot = try Self.temporaryRoot("R01-scratch")
        defer { try? FileManager.default.removeItem(at: scratchRoot) }
        let concreteScratch = try ScratchDataLeaseStoreV1(
            applicationSupportURL: scratchRoot,
            clock: { corpus.createdAt },
            capacityProvider: { _ in Int64.max }
        )
        let eraseRequest = try ScratchDataLeaseRequestV1(
            leaseID: Self.id(41), purpose: .supportExport, owner: .supportExport,
            ownerOperationID: Self.id(42), requestedByteCount: 8,
            createdAt: corpus.createdAt,
            expiresAt: corpus.createdAt.addingTimeInterval(900)
        )
        let eraseLease = try await concreteScratch.acquireScratchLease(eraseRequest)
        _ = try await concreteScratch.writeScratchData(
            Data("erase-me".utf8), named: "support.json", lease: eraseLease
        )
        try await concreteScratch.resetScratchData()
        let resetScratch = try await concreteScratch.recoverScratchLeases()
        XCTAssertEqual(resetScratch.recoveredExpiredLeaseCount, 0)
        _ = try await concreteScratch.acquireScratchLease(eraseRequest)
        try await concreteScratch.eraseScratchData()
        let scratchStoreURL = scratchRoot
            .appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
            .appendingPathComponent("ScratchDataV1", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratchStoreURL.path))
        XCTAssertEqual(corpus.resetErase.operationalRowsAfterReset, 0)
        XCTAssertEqual(corpus.resetErase.operationalRowsAfterErase, 0)
        XCTAssertEqual(corpus.resetErase.scratchRowsAfterErase, 0)
        XCTAssertEqual(corpus.resetErase.canonicalWorkspaceMutationCount, 0)
    }
}

private final class C27V912TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorInputSourceV1.allCases.count, 3)
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension V9_12SystemHealthOperationalDiagnosticsTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.liveRestorePermitted)
    }
}

extension V9_12SystemHealthOperationalDiagnosticsTests {
    func testV23P03C18ReplayClassificationIsPartOfOperationalLifecycle() throws {
        let required: Set<PackageSandboxCheckKindV1> = [.classification, .replay, .searchRebuild]
        XCTAssertTrue(required.isSubset(of: Set(PackageSandboxCheckKindV1.allCases)))
        XCTAssertTrue(PackageEvolutionLifecycleV1.searchRebuildReplayRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.exportReportRequired)
    }
}

extension V9_12SystemHealthOperationalDiagnosticsTests {
    func testV23P03C17DiagnosticsExcludeEventCheckpointAndSubjectPayloads() throws {
        let coverage = IntegrationEventJournalCoverageV1()
        XCTAssertNoThrow(try coverage.validate())
        XCTAssertFalse(coverage.exportIncluded)
        XCTAssertTrue(coverage.dropAndRebuild)
        XCTAssertEqual(coverage.sourceTruth, "ACCEPTED_MUTATION_RECEIPTS_AND_CHANGE_JOURNAL_V1")
        XCTAssertNoThrow(
            try IntegrationProjectionDiagnosticExclusionV1.validate(Data("{}".utf8))
        )
        XCTAssertThrowsError(
            try IntegrationProjectionDiagnosticExclusionV1.validate(
                Data("{\"eventID\":\"sensitive-canary\"}".utf8)
            )
        )
    }
}

private extension V9_12SystemHealthOperationalDiagnosticsTests {
    nonisolated static func loadCorpus() throws -> V912Corpus {
        let bundle = Bundle(for: V9_12SystemHealthOperationalDiagnosticsTests.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "V21P02C08SystemHealthOperationalDiagnosticsCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/Diagnostics"
        ) ?? bundle.url(
            forResource: "V21P02C08SystemHealthOperationalDiagnosticsCorpusV1",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(V912Corpus.self, from: Data(contentsOf: url))
    }

    nonisolated static func failure(
        _ code: OperationalFailureCodeV1,
        at date: Date
    ) throws -> OperationalFailureV1 {
        try OperationalFailureV1(
            code: code,
            occurredAt: date,
            facts: [.init(key: .retryAttempt, value: 1)]
        )
    }

    nonisolated static func supportSnapshot(_ corpus: V912Corpus) throws
        -> DeviceOperationalSupportSnapshotV2 {
        try DeviceOperationalSupportSnapshotV2(
            health: SystemHealthDiagnosticsV1(
                generatedAt: corpus.createdAt,
                state: .degraded,
                failures: [failure(.interrupted, at: corpus.createdAt)],
                metricKit: nil
            ),
            counters: .zero
        )
    }

    nonisolated static func preparedDiagnostic(_ corpus: V912Corpus) throws
        -> PreparedDiagnosticExportV1 {
        let value = DiagnosticExportV1(
            app: .init(build: "2801", version: "28.0"),
            counters: .zero,
            device: .init(model: "Synthetic iPhone", osVersion: "18.0"),
            diagnosticSchemaVersion: 1,
            generatedAt: corpus.createdAt,
            metricKit: nil
        )
        return PreparedDiagnosticExportV1(
            value: value,
            canonicalData: try DiagnosticExportCanonicalEncoderV1.encode(value)
        )
    }

    nonisolated static func scratchPurpose(_ value: String) throws -> ScratchDataPurposeV1 {
        switch value {
        case "SUPPORT_EXPORT": return .supportExport
        case "CAPTURE": return .capture
        case "IMPORT": return .importData
        case "SOURCE": return .source
        default: throw V912Failure.invalidFixture
        }
    }

    nonisolated static func temporaryRoot(_ suffix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_12-\(suffix)-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    nonisolated static func diagnosticsURL(_ root: URL) -> URL {
        root.appendingPathComponent("FieldEvidenceDiagnostics", isDirectory: true)
            .appendingPathComponent("counters.json")
    }

    nonisolated static func scratchRoot(_ root: URL) -> URL {
        root.appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
            .appendingPathComponent("ScratchDataV1", isDirectory: true)
    }

    nonisolated static func writeLegacyDiagnosticsV1(at root: URL) throws {
        let directory = root.appendingPathComponent("FieldEvidenceDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory)
        var legacy = DiagnosticsV1.zero
        legacy.firstSignCreated = 1
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let url = diagnosticsURL(root)
        try encoder.encode(legacy).write(to: url)
        try ProtectedFilePolicyV1.applyAndVerify(.diagnostics, at: url)
    }

    nonisolated static func writeDiagnosticsBytes(_ data: Data, at root: URL) throws {
        let directory = root.appendingPathComponent("FieldEvidenceDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory)
        let url = diagnosticsURL(root)
        try data.write(to: url)
        try ProtectedFilePolicyV1.applyAndVerify(.diagnostics, at: url)
    }

    nonisolated static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }
}

private final class V912MetricSource: MetricReportingSourceV1, @unchecked Sendable {
    private let lock = NSLock()
    private var additions = 0
    private var removals = 0
    var addCount: Int { lock.withLock { additions } }
    var removeCount: Int { lock.withLock { removals } }
    func add(_ subscriber: any MXMetricManagerSubscriber) {
        _ = subscriber
        lock.withLock { additions += 1 }
    }
    func remove(_ subscriber: any MXMetricManagerSubscriber) {
        _ = subscriber
        lock.withLock { removals += 1 }
    }
}

private final class V912MetricAdapterBox: @unchecked Sendable {
    private let adapter: MetricKitDiagnosticsAdapter
    init(_ adapter: MetricKitDiagnosticsAdapter) { self.adapter = adapter }
    func start() { adapter.start() }
    func stop() { adapter.stop() }
}

private final class V912ReentrantMetricSource: MetricReportingSourceV1, @unchecked Sendable {
    weak var adapter: MetricKitDiagnosticsAdapter?
    private let lock = NSLock()
    private var additions = 0
    private var removals = 0
    var addCount: Int { lock.withLock { additions } }
    var removeCount: Int { lock.withLock { removals } }
    func add(_ subscriber: any MXMetricManagerSubscriber) {
        _ = subscriber
        lock.withLock { additions += 1 }
        adapter?.stop()
    }
    func remove(_ subscriber: any MXMetricManagerSubscriber) {
        _ = subscriber
        lock.withLock { removals += 1 }
    }
}

private actor V912ScratchStore: ScratchDataLeasePortV1 {
    private var active: [UUID: ScratchDataLeaseV1] = [:]
    private var payload: Data?
    private var released: [ScratchDataLeaseTerminalV1] = []
    private var recoveries = 0
    private var resets = 0
    private var releaseFailuresRemaining: Int
    private var releaseAttempts = 0
    private let trace: V912LifecycleTrace?

    init(
        releaseFailuresRemaining: Int = 0,
        trace: V912LifecycleTrace? = nil
    ) {
        self.releaseFailuresRemaining = releaseFailuresRemaining
        self.trace = trace
    }

    func acquireScratchLease(_ request: ScratchDataLeaseRequestV1) async throws
        -> ScratchDataLeaseV1 {
        try request.validate()
        let lease = try ScratchDataLeaseV1(
            request: request,
            relativeDirectory: "support-\(request.leaseID.uuidString.lowercased())"
        )
        active[request.leaseID] = lease
        return lease
    }

    func writeScratchData(_ data: Data, named: String, lease: ScratchDataLeaseV1) async throws
        -> URL {
        guard active[lease.request.leaseID] == lease,
              OperationalDiagnosticsBoundsV1.validRelativeName(named),
              UInt64(data.count) <= lease.request.requestedByteCount else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        payload = data
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(named)
    }

    func releaseScratchLease(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) async throws {
        releaseAttempts += 1
        if releaseFailuresRemaining > 0 {
            releaseFailuresRemaining -= 1
            throw V912Failure.injectedCleanupFailure
        }
        active.removeValue(forKey: lease.request.leaseID)
        released.append(terminal)
        payload = nil
    }

    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        recoveries += 1
        await trace?.record("scratch")
        try ScratchDataLeaseRecoverySummaryV1(
            recoveredExpiredLeaseCount: 0,
            removedByteCount: 0
        )
    }

    func resetScratchData() async throws {
        resets += 1
        active.removeAll(keepingCapacity: false)
        payload = nil
    }

    func eraseScratchData() async throws {
        try await resetScratchData()
    }

    func lastPayload() -> Data? { payload }
    func terminals() -> [ScratchDataLeaseTerminalV1] { released }
    func activeCount() -> Int { active.count }
    func recoveryCount() -> Int { recoveries }
    func resetCount() -> Int { resets }
    func releaseAttemptCount() -> Int { releaseAttempts }
}

private actor V912LifecycleTrace {
    private var values: [String] = []
    func record(_ value: String) { values.append(value) }
    func events() -> [String] { values }
}

private actor V912LifecycleJobs: ResumableLocalJobLifecyclePortV1 {
    private var suspended: [LocalJobLifecycleSuspensionReasonV1] = []
    private var resumed: [LocalJobLifecycleSuspensionReasonV1] = []
    private let trace: V912LifecycleTrace
    init(trace: V912LifecycleTrace) { self.trace = trace }
    func suspendForLifecycle(_ reason: LocalJobLifecycleSuspensionReasonV1) async throws { suspended.append(reason) }
    func resumeAfterLifecycle(_ reason: LocalJobLifecycleSuspensionReasonV1) async throws {
        resumed.append(reason)
        await trace.record("resume")
    }
    func suspensions() -> [LocalJobLifecycleSuspensionReasonV1] { suspended }
    func resumptions() -> [LocalJobLifecycleSuspensionReasonV1] { resumed }
}

private actor V912SupportStore: DeviceOperationalSupportStoreV2 {
    private var value: DeviceOperationalSupportSnapshotV2
    private var snapshots = 0
    private var resets = 0
    private let trace: V912LifecycleTrace
    init(snapshot: DeviceOperationalSupportSnapshotV2, trace: V912LifecycleTrace) {
        value = snapshot
        self.trace = trace
    }
    func operationalSupportSnapshot() async throws -> DeviceOperationalSupportSnapshotV2 {
        snapshots += 1
        await trace.record("support")
        return value
    }
    func recordOperationalFailure(_ failure: OperationalFailureV1) async throws { _ = failure }
    func replaceSystemHealth(_ health: SystemHealthDiagnosticsV1) async throws {
        value = try DeviceOperationalSupportSnapshotV2(health: health, counters: value.counters)
    }
    func resetOperationalSupport() async throws {
        resets += 1
        value = try DeviceOperationalSupportSnapshotV2(
            health: SystemHealthDiagnosticsV1(
                generatedAt: value.health.generatedAt,
                state: .unknown,
                failures: [],
                metricKit: nil
            ),
            counters: .zero
        )
    }
    func snapshotCount() -> Int { snapshots }
    func resetCount() -> Int { resets }
}

private final class V912Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func advance(seconds: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(seconds) }
    }
}

private final class V912IDSource: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]
    init(_ values: [UUID]) { self.values = values }
    func next() -> UUID { lock.withLock { values.isEmpty ? UUID() : values.removeFirst() } }
}

private final class V912Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

extension V9_12SystemHealthOperationalDiagnosticsTests {
    func testC36JobLedgerIsRebuiltFromDraftStagingAndNeverBackedUp() {
        XCTAssertEqual(
            LocalJobStoreSchemaV1.c36AttachmentJobKind,
            .draftAttachmentProcessing
        )
        XCTAssertFalse(LocalJobStoreSchemaV1.c36IncludedInUserBackup)
        XCTAssertFalse(LocalJobStoreSchemaV1.c36IncludedInUserExport)
        XCTAssertTrue(LocalJobStoreSchemaV1.c36RebuiltFromStagingItems)
    }
}

private func XCTAssertThrowsErrorAsync<T, E: Error & Equatable>(
    _ expression: @autoclosure () async throws -> T,
    equals expected: E,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? E, expected, file: file, line: line)
    }
}

private enum V912Failure: Error {
    case invalidFixture
    case injectedCleanupFailure
    case unexpectedCanonicalOpen
}

private struct V912Corpus: Decodable, Sendable {
    struct Clock: Decodable, Sendable {
        let createdAtUTC: Date
        let previewedAtUTC: Date
        let sharedAtUTC: Date
        let expiredAtUTC: Date
    }
    struct ScratchBudget: Decodable, Sendable {
        let purpose: String
        let maximumBytes: UInt64
        let maximumLifetimeSeconds: TimeInterval
    }
    struct Bounds: Decodable, Sendable {
        let supportStoreRecordBytes: Int
        let supportStoreTotalBytes: Int
        let supportStoreRecordCount: Int
        let supportBundleBytes: Int
        let scratch: [ScratchBudget]
    }
    struct Health: Decodable, Sendable {
        let state: String
        let crashCount: Int64
        let hangCount: Int64
        let peakMemoryBytes: Int64
        let launchBuckets: [Int64]
    }
    struct UnknownFailure: Decodable, Sendable {
        let code: String
        let primaryAction: String
        let fallbackAction: String?
        let destructiveAutomaticRetryAllowed: Bool
    }
    struct TypedErrorMapping: Decodable, Sendable {
        struct Case: Decodable, Sendable {
            let id: String
            let boundary: String
            let typedError: String
            let expectedCode: String
            let expectedPrimaryAction: String
            let expectedRetryability: String
            let expectedPrivacyClass: String
        }
        let provisionalKernelOnly: Bool
        let shippingBoundaryAdoption: String
        let underlyingFailureCanBecomeEmptySuccess: Bool
        let storeWriteFailurePropagates: Bool
        let cases: [Case]
    }
    struct SupportExport: Decodable, Sendable {
        let operationID: UUID
        let allowlist: [String]
        let forbiddenValues: [String]
        let terminalCases: [String]
        let offlineAllowed: Bool
        let networkRequestCount: Int
        let automaticUploadAllowed: Bool
        let externalShareRecallable: Bool
        let bootstrapCanonicalStoreOpenCount: Int
    }
    struct WorkflowFriction: Decodable, Sendable {
        let profileID: String
        let declaredStates: [String]
        let enabledByDefault: Bool
        let productionWriteCount: Int
        let networkRequestCount: Int
        let customerContentAllowed: Bool
    }
    struct Logging: Decodable, Sendable {
        let allowedCodes: [String]
        let forbiddenMessage: String
        let beginCount: Int
        let endCount: Int
    }
    struct ResetErase: Decodable, Sendable {
        let operationalRowsAfterReset: Int
        let operationalRowsAfterErase: Int
        let scratchRowsAfterErase: Int
        let canonicalWorkspaceMutationCount: Int
    }
    let schemaVersion: Int
    let fixtureIdentity: String
    let clock: Clock
    let bounds: Bounds
    let health: Health
    let failureCodes: [String]
    let unknownFailure: UnknownFailure
    let typedErrorMapping: TypedErrorMapping
    let supportExport: SupportExport
    let workflowFriction: WorkflowFriction
    let logging: Logging
    let resetErase: ResetErase

    var createdAt: Date { clock.createdAtUTC }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, fixtureIdentity, clock, bounds, health, failureCodes
        case unknownFailure, typedErrorMapping, supportExport, workflowFriction, logging, resetErase
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        fixtureIdentity = try values.decode(String.self, forKey: .fixtureIdentity)
        let clockObject = try values.decode([String: String].self, forKey: .clock)
        func date(_ key: String) throws -> Date {
            guard let raw = clockObject[key],
                  let value = ISO8601DateFormatter().date(from: raw) else {
                throw V912Failure.invalidFixture
            }
            return value
        }
        clock = Clock(
            createdAtUTC: try date("createdAtUTC"),
            previewedAtUTC: try date("previewedAtUTC"),
            sharedAtUTC: try date("sharedAtUTC"),
            expiredAtUTC: try date("expiredAtUTC")
        )
        bounds = try values.decode(Bounds.self, forKey: .bounds)
        health = try values.decode(Health.self, forKey: .health)
        failureCodes = try values.decode([String].self, forKey: .failureCodes)
        unknownFailure = try values.decode(UnknownFailure.self, forKey: .unknownFailure)
        typedErrorMapping = try values.decode(TypedErrorMapping.self, forKey: .typedErrorMapping)
        supportExport = try values.decode(SupportExport.self, forKey: .supportExport)
        workflowFriction = try values.decode(WorkflowFriction.self, forKey: .workflowFriction)
        logging = try values.decode(Logging.self, forKey: .logging)
        resetErase = try values.decode(ResetErase.self, forKey: .resetErase)
    }

}

extension V9_12SystemHealthOperationalDiagnosticsTests {
    func testV23P03C19DiagnosticsExposeNoExternalMeasurementProviderState() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        XCTAssertTrue(fixture.capture.measurement.source.isLocalMeasurementCaptureSource)
        XCTAssertFalse(MeasurementIntegrityLifecycleCatalogV1.persistentKinds.contains("PROVIDER_STATE"))
        XCTAssertTrue(MeasurementIntegrityEraseBoundaryV1.ordinaryDeletionPreservesFrozenHistory)
        XCTAssertTrue(MeasurementIntegrityEraseBoundaryV1.workspaceEraseClearsEntireClosure)
    }

    func testC20PrivacyTransformOperationalProjectionDeniesUnapprovedAudience() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let decision = try PrivacyProjectionV1.decide(
            manifest: fixture.manifest, review: fixture.approvedReview, policy: fixture.policy,
            requestedAudience: .internalReview, currentSourceRevision: 1,
            currentSourceSHA256: fixture.manifest.sourceSHA256, at: fixture.capturedAt
        )
        XCTAssertEqual(decision.denial, .wrongAudience)
        XCTAssertNil(decision.derivative)
    }
}

extension V9_12SystemHealthOperationalDiagnosticsTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension V9_12SystemHealthOperationalDiagnosticsTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}

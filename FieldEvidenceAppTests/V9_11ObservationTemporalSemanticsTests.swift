import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_11ObservationTemporalSemanticsTests: XCTestCase {
    func testV9_11G01ObservationBasisRoundTripsIndependentlyFromOutcome() throws {
        let corpus = try Self.loadCorpus()
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(
            corpus.fixtureIdentity,
            "V21-P02-C07-OBSERVATION-TEMPORAL-CORPUS-V1"
        )
        XCTAssertEqual(corpus.basisKinds.count, ObservationBasisKindV1.allCases.count)
        XCTAssertEqual(corpus.outcomes, ["compliant", "noncompliant", "unknown"])

        var combinationCount = 0
        for kindName in corpus.basisKinds {
            let kind = try Self.basisKind(kindName)
            let basis = try Self.basis(kind: kind, corpus: corpus)
            let bytes = try ObservationAndTimeCodecV1.encode(basis)
            XCTAssertEqual(
                try ObservationAndTimeCodecV1.decodeObservationBasis(bytes),
                basis
            )

            var bytesByOutcome: [String: Data] = [:]
            for outcome in corpus.outcomes {
                let record = Self.backupRecord(
                    basisData: bytes,
                    temporalData: try ObservationAndTimeCodecV1.encode(
                        Self.goldenTemporal(corpus)
                    ),
                    outcomeKey: outcome
                )
                let encoded = try BackupCanonicalEncoderV1().encodeRecords(
                    Self.backupRecords(record: record)
                ).data
                let decoded = try XCTUnwrap(
                    BackupCanonicalDecoderV1().decodeRecords(encoded)
                        .workflowRecords.first
                )
                XCTAssertEqual(decoded.outcomeKey, outcome)
                bytesByOutcome[outcome] = try XCTUnwrap(
                    decoded.observationBasisV1Data
                )
                combinationCount += 1
            }
            XCTAssertEqual(Set(bytesByOutcome.values).count, 1)
            for outcome in corpus.outcomes {
                XCTAssertFalse(
                    String(decoding: bytes, as: UTF8.self).contains(outcome),
                    "outcome must not be encoded into observation authority"
                )
            }
        }
        XCTAssertEqual(combinationCount, 18)

        let golden = try Self.goldenTemporal(corpus)
        XCTAssertEqual(
            try ObservationAndTimeCodecV1.decodeTemporalContext(
                ObservationAndTimeCodecV1.encode(golden)
            ),
            golden
        )
        XCTAssertEqual(golden.occurredAtUTC, try Self.date(corpus.golden.occurredAtUTC))
        XCTAssertEqual(golden.recordedAtUTC, try Self.date(corpus.golden.recordedAtUTC))
        XCTAssertEqual(golden.utcOffsetSeconds, corpus.golden.utcOffsetSeconds)
        XCTAssertEqual(golden.ianaTimeZoneIdentifier, corpus.golden.timeZoneIdentifier)
    }

    func testV9_11A01ReportedInferredAndUnknownRemainDistinct() throws {
        let corpus = try Self.loadCorpus()
        let reported = try ObservationBasisV1(
            kind: .reported,
            method: ObservationMethodV1(key: corpus.alternate.reportedMethod),
            source: ObservationSourceReferenceV1(
                kind: .reportedParty,
                reference: corpus.alternate.reportedSourceReference
            ),
            limitations: [corpus.golden.limitations]
        )
        let inferred = try ObservationBasisV1(
            kind: .inferred,
            method: ObservationMethodV1(key: corpus.alternate.inferredMethod),
            source: ObservationSourceReferenceV1(
                kind: .record,
                reference: corpus.golden.sourceReference
            ),
            limitations: [corpus.golden.limitations]
        )
        let reportedUnknownSource = try ObservationBasisV1(
            kind: .reported,
            method: ObservationMethodV1(key: corpus.alternate.reportedMethod),
            source: ObservationSourceReferenceV1(kind: .unknown)
        )

        XCTAssertNotEqual(reported, inferred)
        XCTAssertNotEqual(
            try ObservationAndTimeCodecV1.encode(reported),
            try ObservationAndTimeCodecV1.encode(inferred)
        )
        XCTAssertEqual(reportedUnknownSource.source.kind, .unknown)
        XCTAssertNil(reportedUnknownSource.source.reference)
        XCTAssertThrowsError(try ObservationBasisV1(
            kind: .directlyObserved,
            method: ObservationMethodV1(key: corpus.golden.method),
            source: ObservationSourceReferenceV1(
                kind: .reportedParty,
                reference: corpus.alternate.reportedSourceReference
            )
        )) {
            XCTAssertEqual(
                $0 as? ObservationAndTimeValidationFailureV1,
                .invalidObservationBasis
            )
        }
        XCTAssertThrowsError(try ObservationSourceReferenceV1(
            kind: .unknown,
            reference: "device-default"
        ))
        XCTAssertThrowsError(try ObservationBasisV1(
            kind: .reported,
            method: ObservationMethodV1(key: corpus.alternate.reportedMethod),
            source: ObservationSourceReferenceV1(
                kind: .record,
                reference: corpus.golden.sourceReference
            )
        ))
    }

    func testV9_11H01DSTGapFoldRollbackUnknownZoneAndNoWallClockCausality() throws {
        let corpus = try Self.loadCorpus()
        let contexts = try Dictionary(uniqueKeysWithValues: corpus.hostileTimeCases.map {
            ($0.id, try Self.temporal($0))
        })
        let first = try XCTUnwrap(contexts["fall-fold-first"])
        let second = try XCTUnwrap(contexts["fall-fold-second"])
        XCTAssertEqual(first.localDate, second.localDate)
        XCTAssertEqual(first.localTime, second.localTime)
        XCTAssertNotEqual(first.occurredAtUTC, second.occurredAtUTC)
        XCTAssertNotEqual(first.utcOffsetSeconds, second.utcOffsetSeconds)
        XCTAssertEqual(first.localTimeDisposition, .ambiguousFold)
        XCTAssertEqual(second.localTimeDisposition, .ambiguousFold)

        let gap = try XCTUnwrap(contexts["spring-gap"])
        XCTAssertNil(gap.occurredAtUTC)
        XCTAssertNil(gap.utcOffsetSeconds)
        XCTAssertEqual(gap.localTime, "02:30:00")
        XCTAssertEqual(gap.localTimeDisposition, .nonexistentGap)

        let unknown = try XCTUnwrap(contexts["unknown-zone"])
        XCTAssertNil(unknown.ianaTimeZoneIdentifier)
        XCTAssertNil(unknown.utcOffsetSeconds)
        XCTAssertEqual(unknown.localTimeDisposition, .unknown)

        let rollback = try XCTUnwrap(contexts["wall-clock-rollback"])
        XCTAssertGreaterThan(rollback.occurredAtUTC!, rollback.recordedAtUTC)
        XCTAssertNoThrow(try rollback.validate())
        let acceptedMutationOrder = [first, rollback, second]
        XCTAssertEqual(acceptedMutationOrder[1], rollback)
        XCTAssertNotEqual(
            acceptedMutationOrder.map(\.recordedAtUTC),
            acceptedMutationOrder.map(\.recordedAtUTC).sorted()
        )

        XCTAssertThrowsError(try TemporalContextV1(
            occurredAtUTC: nil,
            recordedAtUTC: try Self.date("2026-03-08T07:00:00Z"),
            localDate: "2026-03-08",
            localTime: "02:30:00",
            utcOffsetSeconds: nil,
            ianaTimeZoneIdentifier: nil,
            localTimeDisposition: .nonexistentGap
        ))
        XCTAssertThrowsError(
            try ObservationAndTimeCodecV1.decodeTemporalContext(
                Data("{\"version\":2147483647}".utf8)
            )
        )
    }

    func testV9_11I01AtomicInterruptionRetryNeverPersistsPartialPair() throws {
        let corpus = try Self.loadCorpus()
        XCTAssertEqual(
            corpus.interruptionBoundaries,
            MutationJournalFaultBoundaryV1.allCases.map(\.rawValue)
        )
        XCTAssertEqual(MutationJournalFaultBoundaryV1.allCases.count, 3)

        for (offset, boundary) in MutationJournalFaultBoundaryV1.allCases.enumerated() {
            let harness = try V911WriterHarness(
                failureBoundary: boundary,
                suffix: "\(offset)"
            )
            let basis = try Self.basis(kind: .directlyObserved, corpus: corpus)
            let temporal = try Self.goldenTemporal(corpus)
            let request = try harness.request(
                mutationByte: UInt8(40 + offset),
                recordByte: UInt8(60 + offset),
                basis: basis,
                temporal: temporal
            )
            XCTAssertThrowsError(try harness.writer.execute(request)) {
                XCTAssertEqual($0 as? MutationJournalFailureV1, .injected(boundary))
            }

            let relaunched = try harness.relaunch()
            let recordsBeforeRetry = try relaunched.context.fetch(FetchDescriptor<WorkflowRecord>())
            let companionsBeforeRetry = try relaunched.context.fetch(
                FetchDescriptor<ObservationAndTimeRow>()
            )
            XCTAssertEqual(recordsBeforeRetry.count, companionsBeforeRetry.count)
            try MutationReceiptRecoveryServiceV1(store: relaunched.store)
                .recoverBeforeWriterActivation()
            let outcome = try relaunched.writer.execute(request)
            XCTAssertEqual(outcome.after.revision, 1)
            let persisted = try XCTUnwrap(
                try relaunched.context.fetch(FetchDescriptor<WorkflowRecord>()).first
            )
            let persistedCompanion = try ObservationAndTimeRowStoreV1.requireRow(
                recordID: persisted.id,
                in: relaunched.context
            )
            XCTAssertEqual(try persistedCompanion.observationBasisV1(), basis)
            XCTAssertEqual(try persistedCompanion.temporalContextV1(), temporal)
            XCTAssertEqual(
                try relaunched.context.fetchCount(FetchDescriptor<WorkflowRecord>()),
                1
            )
            XCTAssertEqual(
                try relaunched.context.fetchCount(FetchDescriptor<ObservationAndTimeRow>()),
                1
            )
            XCTAssertEqual(
                try relaunched.context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
                1
            )

            let changed = try harness.request(
                mutationByte: UInt8(40 + offset),
                recordByte: UInt8(60 + offset),
                basis: try ObservationBasisV1(
                    kind: .directlyObserved,
                    method: ObservationMethodV1(key: corpus.golden.method),
                    source: ObservationSourceReferenceV1(kind: .observer),
                    limitations: ["changed-after-retry"]
                ),
                temporal: temporal,
                expected: request.expectedRevision
            )
            XCTAssertThrowsError(try relaunched.writer.execute(changed)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertEqual(
                try relaunched.context.fetchCount(FetchDescriptor<WorkflowRecord>()),
                1
            )
        }
    }

    func testV9_11R01LegacyMigrationPortableReplayDeleteEraseAndQuarantine() async throws {
        let corpus = try Self.loadCorpus()
        let legacy = corpus.legacyCouldNotVerify
        let completeMigration = try Self.migrateLegacy(
            corpus: corpus,
            couldNotVerifyKey: legacy.reasonKey,
            displaySnapshot: legacy.reasonDisplaySnapshot,
            registryVersion: legacy.reasonRegistryVersion
        )
        XCTAssertEqual(completeMigration.disposition, .migratedLegacyValues)
        XCTAssertFalse(completeMigration.requiresForwardRepair)
        XCTAssertFalse(completeMigration.receipt.inventedDirectObservation)
        XCTAssertTrue(completeMigration.receipt.legacyColumnsPreserved)
        let migratedBasis = try ObservationAndTimeCodecV1.decodeObservationBasis(
            XCTUnwrap(completeMigration.observationBasisData)
        )
        XCTAssertEqual(migratedBasis.kind, .unverifiable)
        XCTAssertEqual(migratedBasis.method.key, ObservationMethodV1.unknownKey)
        XCTAssertEqual(migratedBasis.source.kind, .unknown)
        XCTAssertEqual(legacy.expectedBasisKind, "unverifiable")
        XCTAssertEqual(legacy.expectedMethod, migratedBasis.method.key)
        XCTAssertNil(legacy.expectedSourceReference)
        XCTAssertNotEqual(migratedBasis.kind, .directlyObserved)

        let partialMigration = try Self.migrateLegacy(
            corpus: corpus,
            couldNotVerifyKey: legacy.reasonKey,
            displaySnapshot: nil,
            registryVersion: nil
        )
        let incomplete = try ObservationAndTimeCodecV1.decodeObservationBasis(
            XCTUnwrap(partialMigration.observationBasisData)
        )
        XCTAssertEqual(incomplete.kind, .unknown)
        XCTAssertNotEqual(incomplete.kind, .directlyObserved)

        let ordinaryMigration = try Self.migrateLegacy(
            corpus: corpus,
            couldNotVerifyKey: nil,
            displaySnapshot: nil,
            registryVersion: nil
        )
        let ordinaryBasis = try ObservationAndTimeCodecV1.decodeObservationBasis(
            XCTUnwrap(ordinaryMigration.observationBasisData)
        )
        XCTAssertEqual(ordinaryBasis.kind, .unknown)
        XCTAssertEqual(ordinaryBasis.method.key, ObservationMethodV1.unknownKey)
        XCTAssertNotEqual(ordinaryBasis.kind, .directlyObserved)

        let migratedTemporal = try ObservationAndTimeCodecV1.decodeTemporalContext(
            XCTUnwrap(completeMigration.temporalContextData)
        )
        XCTAssertEqual(migratedTemporal.utcOffsetSeconds, -18_000)
        XCTAssertEqual(migratedTemporal.localTimeDisposition, .unknown)

        let basisBytes = try XCTUnwrap(completeMigration.observationBasisData)
        let temporalBytes = try XCTUnwrap(completeMigration.temporalContextData)
        let alreadyCurrent = try ObservationAndTimeMigrationV1.migrate(
            existingObservationBasisData: basisBytes,
            existingTemporalContextData: temporalBytes,
            couldNotVerifyKey: legacy.reasonKey,
            couldNotVerifyDisplaySnapshot: legacy.reasonDisplaySnapshot,
            couldNotVerifyRegistryVersion: legacy.reasonRegistryVersion,
            observedAtUTC: try Self.date(corpus.golden.occurredAtUTC),
            recordedAtUTC: try Self.date(corpus.golden.recordedAtUTC),
            timeZoneID: corpus.golden.timeZoneIdentifier,
            utcOffsetMinutes: corpus.golden.utcOffsetSeconds / 60,
            localDate: corpus.golden.localDate,
            localTime: corpus.golden.localTime
        )
        XCTAssertEqual(alreadyCurrent.disposition, .alreadyCurrent)
        XCTAssertEqual(alreadyCurrent.observationBasisData, basisBytes)
        XCTAssertEqual(alreadyCurrent.temporalContextData, temporalBytes)

        let portableRecord = Self.backupRecord(
            basisData: basisBytes,
            temporalData: temporalBytes
        )
        let portableRecords = Self.backupRecords(record: portableRecord)
        let portableBytes = try BackupCanonicalEncoderV1()
            .encodeRecords(portableRecords).data
        let decodedPortable = try BackupCanonicalDecoderV1()
            .decodeRecords(portableBytes)
        let decodedRecord = try XCTUnwrap(decodedPortable.workflowRecords.first)
        XCTAssertEqual(decodedRecord.observationBasisV1Data, basisBytes)
        XCTAssertEqual(decodedRecord.temporalContextV1Data, temporalBytes)
        XCTAssertEqual(
            try BackupCanonicalEncoderV1().encodeRecords(decodedPortable).data,
            portableBytes
        )
        for hostile in [
            portableRecord.replacingObservationAndTime(
                basisData: nil,
                temporalData: temporalBytes
            ),
            portableRecord.replacingObservationAndTime(
                basisData: basisBytes,
                temporalData: nil
            ),
            portableRecord.replacingObservationAndTime(
                basisData: Data("corrupt".utf8),
                temporalData: temporalBytes
            ),
            portableRecord.replacingObservationAndTime(
                basisData: basisBytes,
                temporalData: Data("corrupt".utf8)
            ),
        ] {
            XCTAssertThrowsError(
                try BackupCanonicalEncoderV1().encodeRecords(
                    Self.backupRecords(record: hostile)
                )
            )
        }

        let deletionPlan = try WholeSignDeletionRule.makePlan(
            Self.deletionInput(basisData: basisBytes, temporalData: temporalBytes)
        )
        XCTAssertTrue(deletionPlan.workflowRecordIDs.contains(Self.id(101)))
        XCTAssertTrue(deletionPlan.intent.ledgerEntries.contains {
            $0.identity.kind == .workflowRecord && $0.identity.id == Self.id(101)
        })
        XCTAssertThrowsError(try WholeSignDeletionRule.makePlan(
            Self.deletionInput(basisData: basisBytes, temporalData: nil)
        )) {
            XCTAssertEqual($0 as? WholeSignDeletionRuleError, .invalidGraph)
        }
        let deletion = try V906Integration.makeHarness("v9-11-delete", withAsset: true)
        defer { V906Integration.remove(deletion.root) }
        let deletionAssetID = try XCTUnwrap(
            deletion.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        let deletionRecordID = Self.id(121)
        try Self.insertObservationRecord(
            id: deletionRecordID,
            assetID: deletionAssetID,
            basisData: basisBytes,
            temporalData: temporalBytes,
            in: deletion.session.modelContext
        )
        let persistedDeletionPair = try ObservationAndTimeRowStoreV1.requireRow(
            recordID: deletionRecordID,
            in: deletion.session.modelContext
        )
        XCTAssertEqual(
            CanonicalJSONV1.sha256(persistedDeletionPair.observationBasisV1Data),
            CanonicalJSONV1.sha256(basisBytes)
        )
        XCTAssertEqual(
            CanonicalJSONV1.sha256(persistedDeletionPair.temporalContextV1Data),
            CanonicalJSONV1.sha256(temporalBytes)
        )
        let deletionOutcome = try await V906Integration.deletionService(deletion)
            .delete(assetID: deletionAssetID)
        XCTAssertEqual(deletionOutcome.assetID, deletionAssetID)
        XCTAssertEqual(
            try deletion.session.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            0
        )
        XCTAssertEqual(
            try deletion.session.modelContext.fetchCount(FetchDescriptor<ObservationAndTimeRow>()),
            0
        )
        XCTAssertTrue(
            try DeletionLedgerStore(context: deletion.session.modelContext)
                .snapshot().entries.contains {
                    $0.identity.kind == .workflowRecord
                        && $0.identity.id == deletionRecordID
                }
        )

        let erase = try V906Integration.makeHarness("v9-11-erase", withAsset: true)
        defer { V906Integration.remove(erase.root) }
        let eraseAssetID = try XCTUnwrap(
            erase.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        let eraseRecordID = Self.id(122)
        try Self.insertObservationRecord(
            id: eraseRecordID,
            assetID: eraseAssetID,
            basisData: basisBytes,
            temporalData: temporalBytes,
            in: erase.session.modelContext
        )
        XCTAssertEqual(
            try erase.session.modelContext.fetchCount(FetchDescriptor<ObservationAndTimeRow>()),
            1
        )
        let oldGenerationID = erase.session.generationID
        let coordinator = StoreSessionCoordinator(session: erase.session)
        let diagnostics = DiagnosticsStore(applicationSupportURL: erase.support)
        await diagnostics.prepare()
        let defaultsName = "V9_11-R01-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: "com.palatis3.fieldrecord") }
        let newGenerationID = Self.id(123)
        let erased = try await EraseAllService(
            applicationSupportURL: erase.support,
            cachesDirectoryURL: erase.caches,
            temporaryDirectoryURL: erase.temporary,
            userDefaults: defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            makeUUID: V906Integration.sequence([
                newGenerationID,
                Self.id(124),
                Self.id(125),
                Self.id(126),
            ])
        ).erase(
            confirmation: "ERASE",
            coordinator: coordinator,
            diagnosticsStore: diagnostics
        ) { session in
            coordinator.activate(session: session)
        }
        XCTAssertNotEqual(erased.session.generationID, oldGenerationID)
        XCTAssertEqual(erased.session.generationID, newGenerationID)
        XCTAssertEqual(try erase.factory.currentGenerationID(), newGenerationID)
        XCTAssertEqual(
            try erased.session.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            0
        )
        XCTAssertEqual(
            try erased.session.modelContext.fetchCount(FetchDescriptor<ObservationAndTimeRow>()),
            0
        )

        let unsupported = Data(
            "{\"kind\":\"UNKNOWN\",\"limitations\":[],\"method\":{\"key\":\"unknown\"},\"source\":{\"kind\":\"UNKNOWN\"},\"version\":\(corpus.unsupportedSchemaVersion)}".utf8
        )
        let quarantined = try ObservationAndTimeMigrationV1.migrate(
            existingObservationBasisData: unsupported,
            existingTemporalContextData: temporalBytes,
            couldNotVerifyKey: legacy.reasonKey,
            couldNotVerifyDisplaySnapshot: legacy.reasonDisplaySnapshot,
            couldNotVerifyRegistryVersion: legacy.reasonRegistryVersion,
            observedAtUTC: try Self.date(corpus.golden.occurredAtUTC),
            recordedAtUTC: try Self.date(corpus.golden.recordedAtUTC),
            timeZoneID: corpus.golden.timeZoneIdentifier,
            utcOffsetMinutes: corpus.golden.utcOffsetSeconds / 60,
            localDate: corpus.golden.localDate,
            localTime: corpus.golden.localTime
        )
        XCTAssertEqual(quarantined.disposition, .quarantinedUnsupportedBytes)
        XCTAssertTrue(quarantined.requiresForwardRepair)
        XCTAssertEqual(quarantined.observationBasisData, unsupported)
        XCTAssertEqual(quarantined.temporalContextData, temporalBytes)
        XCTAssertTrue(quarantined.receipt.requiresForwardRepair)
        XCTAssertFalse(quarantined.receipt.inventedDirectObservation)
        XCTAssertEqual(decodedRecord.observationBasisV1Data, basisBytes)
        XCTAssertEqual(decodedRecord.temporalContextV1Data, temporalBytes)
    }

    nonisolated private static func loadCorpus() throws -> V911Corpus {
        let bundle = Bundle(for: V9_11ObservationTemporalSemanticsTests.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "V21P02C07ObservationTemporalCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/Observation"
        ) ?? bundle.url(
            forResource: "V21P02C07ObservationTemporalCorpusV1",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(V911Corpus.self, from: Data(contentsOf: url))
    }

    nonisolated private static func basisKind(_ value: String) throws -> ObservationBasisKindV1 {
        switch value {
        case "directly_observed": .directlyObserved
        case "reported_by_person": .reported
        case "inferred": .inferred
        case "not_observed": .notObserved
        case "unverifiable": .unverifiable
        case "unknown": .unknown
        default: throw V911TestFailure.unknownFixtureValue(value)
        }
    }

    nonisolated private static func basis(
        kind: ObservationBasisKindV1,
        corpus: V911Corpus
    ) throws -> ObservationBasisV1 {
        let source: ObservationSourceReferenceV1
        switch kind {
        case .directlyObserved:
            source = try ObservationSourceReferenceV1(kind: .observer)
        case .reported:
            source = try ObservationSourceReferenceV1(
                kind: .reportedParty,
                reference: corpus.alternate.reportedSourceReference
            )
        case .inferred:
            source = try ObservationSourceReferenceV1(
                kind: .record,
                reference: corpus.golden.sourceReference
            )
        case .notObserved, .unverifiable, .unknown:
            source = try ObservationSourceReferenceV1(kind: .unknown)
        }
        return try ObservationBasisV1(
            kind: kind,
            method: ObservationMethodV1(key: corpus.golden.method),
            source: source,
            limitations: [corpus.golden.limitations]
        )
    }

    nonisolated private static func goldenTemporal(_ corpus: V911Corpus) throws -> TemporalContextV1 {
        try TemporalContextV1(
            occurredAtUTC: date(corpus.golden.occurredAtUTC),
            recordedAtUTC: date(corpus.golden.recordedAtUTC),
            localDate: corpus.golden.localDate,
            localTime: corpus.golden.localTime,
            utcOffsetSeconds: corpus.golden.utcOffsetSeconds,
            ianaTimeZoneIdentifier: corpus.golden.timeZoneIdentifier,
            localTimeDisposition: .unambiguous
        )
    }

    nonisolated private static func temporal(_ value: V911Corpus.TimeCase) throws -> TemporalContextV1 {
        try TemporalContextV1(
            occurredAtUTC: try value.occurredAtUTC.map(date),
            recordedAtUTC: date(value.recordedAtUTC),
            localDate: value.localDate,
            localTime: value.localTime,
            utcOffsetSeconds: value.utcOffsetSeconds,
            ianaTimeZoneIdentifier: value.timeZoneIdentifier,
            localTimeDisposition: try disposition(value.localTimeDisposition)
        )
    }

    nonisolated private static func disposition(_ value: String) throws -> LocalTimeDispositionV1 {
        switch value {
        case "exact": .unambiguous
        case "fold_first", "fold_second": .ambiguousFold
        case "nonexistent": .nonexistentGap
        case "unknown": .unknown
        default: throw V911TestFailure.unknownFixtureValue(value)
        }
    }

    nonisolated private static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let result = formatter.date(from: value) else {
            throw V911TestFailure.invalidDate(value)
        }
        return result
    }

    nonisolated private static func migrateLegacy(
        corpus: V911Corpus,
        couldNotVerifyKey: String?,
        displaySnapshot: String?,
        registryVersion: String?
    ) throws -> ObservationAndTimeMigrationResultV1 {
        try ObservationAndTimeMigrationV1.migrate(
            existingObservationBasisData: nil,
            existingTemporalContextData: nil,
            couldNotVerifyKey: couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: displaySnapshot,
            couldNotVerifyRegistryVersion: registryVersion,
            observedAtUTC: try date(corpus.golden.occurredAtUTC),
            recordedAtUTC: try date(corpus.golden.recordedAtUTC),
            timeZoneID: corpus.golden.timeZoneIdentifier,
            utcOffsetMinutes: corpus.golden.utcOffsetSeconds / 60,
            localDate: corpus.golden.localDate,
            localTime: corpus.golden.localTime
        )
    }

    nonisolated private static func backupRecords(
        record: V4BackupWorkflowRecordDTO
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            assets: [],
            deletionLedger: .empty,
            evidenceFiles: [],
            issues: [],
            mutationHistory: MutationHistorySnapshotV1(
                workspaceRevision: 0,
                lastLocalSequence: 0,
                receipts: [],
                quarantines: [],
                entityRevisions: []
            ),
            packets: [],
            recordsSchemaVersion: 4,
            reports: [],
            sites: [],
            workflowRecords: [record]
        )
    }

    nonisolated private static func backupRecord(
        basisData: Data?,
        temporalData: Data?,
        outcomeKey: String? = nil
    ) -> V4BackupWorkflowRecordDTO {
        V4BackupWorkflowRecordDTO(
            id: id(101), schemaVersion: 1, assetID: id(102),
            packetID: nil, issueID: nil, parentRecordID: nil,
            recordRevisionRootID: id(101), revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: WorkflowRevisionKind.original.rawValue,
            stage: WorkflowStage.check.rawValue,
            state: WorkflowState.draft.rawValue,
            draftStepKey: WorkflowDraftStep.wide.rawValue,
            startedAt: Date(timeIntervalSince1970: 1_768_496_400),
            completedAt: nil,
            observedAtUTC: Date(timeIntervalSince1970: 1_768_496_400),
            timeZoneID: "America/New_York", utcOffsetMinutes: -300,
            localDate: "2026-01-15", localTime: "12:00:00",
            afterDarkAcknowledgementKey: nil,
            afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil,
            afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil,
            safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil,
            safePositionAcknowledgementAccepted: nil,
            packID: "test.pack", packSchemaVersion: 1, packContentVersion: 1,
            pdfTemplateID: "worklight.report", pdfTemplateVersion: 1,
            outcomeKey: outcomeKey, couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil, note: nil,
            finalizationMutationID: nil,
            observationBasisV1Data: basisData,
            temporalContextV1Data: temporalData
        )
    }

    nonisolated private static func deletionInput(
        basisData: Data?,
        temporalData: Data?
    ) -> WholeSignDeletionRuleInput {
        let siteID = id(100)
        let recordID = id(101)
        let assetID = id(102)
        let record = backupRecord(
            basisData: basisData,
            temporalData: temporalData
        )
        return WholeSignDeletionRuleInput(
            assetID: assetID,
            deletionID: id(103),
            deletedAt: Date(timeIntervalSince1970: 1_800_000_100),
            generationID: id(104),
            sites: [.init(id: siteID, schemaVersion: 1)],
            assets: [.init(id: assetID, schemaVersion: 1, siteID: siteID)],
            records: [WorkflowRecordPayloadV1(
                id: record.id, schemaVersion: record.schemaVersion,
                assetID: record.assetID, packetID: record.packetID,
                issueID: record.issueID, parentRecordID: record.parentRecordID,
                recordRevisionRootID: record.recordRevisionRootID,
                revisesRecordID: record.revisesRecordID,
                evidenceSourceRecordID: record.evidenceSourceRecordID,
                revisionKind: record.revisionKind, stage: record.stage,
                state: record.state, draftStepKey: record.draftStepKey,
                startedAt: record.startedAt, completedAt: record.completedAt,
                observedAtUTC: record.observedAtUTC,
                timeZoneID: record.timeZoneID,
                utcOffsetMinutes: record.utcOffsetMinutes,
                localDate: record.localDate, localTime: record.localTime,
                afterDarkAcknowledgementKey: record.afterDarkAcknowledgementKey,
                afterDarkAcknowledgementCopy: record.afterDarkAcknowledgementCopy,
                afterDarkAcknowledgementVersion: record.afterDarkAcknowledgementVersion,
                afterDarkAcknowledgementAccepted: record.afterDarkAcknowledgementAccepted,
                safePositionAcknowledgementKey: record.safePositionAcknowledgementKey,
                safePositionAcknowledgementCopy: record.safePositionAcknowledgementCopy,
                safePositionAcknowledgementVersion: record.safePositionAcknowledgementVersion,
                safePositionAcknowledgementAccepted: record.safePositionAcknowledgementAccepted,
                packID: record.packID, packSchemaVersion: record.packSchemaVersion,
                packContentVersion: record.packContentVersion,
                pdfTemplateID: record.pdfTemplateID,
                pdfTemplateVersion: record.pdfTemplateVersion,
                outcomeKey: record.outcomeKey,
                couldNotVerifyKey: record.couldNotVerifyKey,
                couldNotVerifyDisplaySnapshot: record.couldNotVerifyDisplaySnapshot,
                couldNotVerifyRegistryVersion: record.couldNotVerifyRegistryVersion,
                workPerformedLocalDate: record.workPerformedLocalDate,
                workDescription: record.workDescription, note: record.note,
                finalizationMutationID: record.finalizationMutationID,
                observationBasisV1Data: record.observationBasisV1Data,
                temporalContextV1Data: record.temporalContextV1Data
            )],
            evidence: [], issues: [], packets: [], reports: []
        )
    }

    nonisolated private static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    private static func insertObservationRecord(
        id: UUID,
        assetID: UUID,
        basisData: Data,
        temporalData: Data,
        in context: ModelContext
    ) throws {
        let recordedAt = Date(timeIntervalSince1970: 1_768_496_400)
        context.insert(WorkflowRecord(
            id: id,
            assetID: assetID,
            packetID: nil,
            issueID: nil,
            parentRecordID: nil,
            recordRevisionRootID: id,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: .check,
            state: .completed,
            draftStepKey: nil,
            startedAt: recordedAt,
            completedAt: recordedAt,
            observedAtUTC: recordedAt,
            timeZoneID: "America/New_York",
            utcOffsetMinutes: -300,
            localDate: "2026-01-15",
            localTime: "12:00:00",
            afterDarkAcknowledgementKey: nil,
            afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil,
            afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil,
            safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil,
            safePositionAcknowledgementAccepted: nil,
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            pdfTemplateID: "worklight.report",
            pdfTemplateVersion: 1,
            outcomeKey: "unknown",
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: nil,
            finalizationMutationID: nil
        ))
        context.insert(try ObservationAndTimeRow(
            recordID: id,
            observationBasisV1Data: basisData,
            temporalContextV1Data: temporalData
        ))
        try context.save()
    }
}

private enum V911TestFailure: Error {
    case invalidDate(String)
    case unknownFixtureValue(String)
}

private struct V911Corpus: Decodable, Sendable {
    struct Golden: Decodable, Sendable {
        let method: String
        let sourceReference: String
        let limitations: String
        let occurredAtUTC: String
        let recordedAtUTC: String
        let localDate: String
        let localTime: String
        let utcOffsetSeconds: Int
        let timeZoneIdentifier: String
        let localTimeDisposition: String
    }
    struct Alternate: Decodable, Sendable {
        let reportedMethod: String
        let reportedSourceReference: String
        let inferredMethod: String
        let unknownSourceReference: String?
    }
    struct TimeCase: Decodable, Sendable {
        let id: String
        let occurredAtUTC: String?
        let recordedAtUTC: String
        let localDate: String
        let localTime: String
        let utcOffsetSeconds: Int?
        let timeZoneIdentifier: String?
        let localTimeDisposition: String
    }
    struct Legacy: Decodable, Sendable {
        let outcomeKey: String
        let reasonKey: String
        let reasonDisplaySnapshot: String
        let reasonRegistryVersion: String
        let expectedBasisKind: String
        let expectedMethod: String
        let expectedSourceReference: String?
    }
    let schemaVersion: Int
    let fixtureIdentity: String
    let basisKinds: [String]
    let outcomes: [String]
    let golden: Golden
    let alternate: Alternate
    let hostileTimeCases: [TimeCase]
    let interruptionBoundaries: [String]
    let legacyCouldNotVerify: Legacy
    let portableLifecycle: [String]
    let unsupportedSchemaVersion: Int
}

private struct V911Clock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

private struct V911IDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct V911FileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class V911WriterHarness {
    struct Relaunch {
        let context: ModelContext
        let store: MutationJournalStoreV1
        let writer: WorkspaceWriterV1
    }

    let container: ModelContainer
    let context: ModelContext
    let store: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    private let identity: WorkspaceReplicaIdentityV1
    private let generationID = Self.id(3)
    private let writerInstanceID = Self.id(4)
    private let assetID = Self.id(6)

    init(failureBoundary: MutationJournalFaultBoundaryV1, suffix: String) throws {
        let schema = Schema(
            PersistentSchemaV5.models,
            version: PersistentSchemaV5.versionIdentifier
        )
        container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V911-\(suffix)",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        context = container.mainContext
        context.autosaveEnabled = false
        context.insert(Site(
            id: Self.id(5),
            label: "Observation site",
            address: nil,
            timeZoneID: "America/New_York",
            createdAt: Date(timeIntervalSince1970: 1_799_999_998)
        ))
        context.insert(Asset(
            id: assetID,
            siteID: Self.id(5),
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Observation asset",
            createdAt: Date(timeIntervalSince1970: 1_799_999_999)
        ))
        try context.save()
        identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: Self.id(1)),
            replicaID: ReplicaID(rawValue: Self.id(2))
        )
        store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID,
            failureInjection: MutationJournalFailureInjectionV1(
                failOnceAt: failureBoundary
            )
        )
        writer = try Self.makeWriter(
            context: context,
            store: store,
            identity: identity,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
    }

    func request(
        mutationByte: UInt8,
        recordByte: UInt8,
        basis: ObservationBasisV1,
        temporal: TemporalContextV1,
        expected: WorkspaceExpectedRevisionV1? = nil
    ) throws -> WorkspaceMutationRequestV1 {
        guard let occurredAtUTC = temporal.occurredAtUTC else {
            throw V911TestFailure.unknownFixtureValue("missing occurredAtUTC")
        }
        return WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: Self.id(mutationByte)),
            expectedRevision: expected ?? WorkspaceExpectedRevisionV1(
                snapshot: try writer.currentRevision()
            ),
            command: .createCheckDraft(CheckDraftMutationV1(
                recordID: Self.id(recordByte),
                assetID: assetID,
                issueID: nil,
                parentRecordID: nil,
                stage: WorkflowStage.check.rawValue,
                draftStepKey: WorkflowDraftStep.wide.rawValue,
                startedAt: occurredAtUTC,
                observedAtUTC: temporal.occurredAtUTC,
                timeZoneID: temporal.ianaTimeZoneIdentifier,
                utcOffsetMinutes: temporal.utcOffsetSeconds.map { $0 / 60 },
                localDate: temporal.localDate,
                localTime: temporal.localTime,
                afterDarkAcknowledgementKey: nil,
                afterDarkAcknowledgementCopy: nil,
                afterDarkAcknowledgementVersion: nil,
                afterDarkAcknowledgementAccepted: nil,
                safePositionAcknowledgementKey: nil,
                safePositionAcknowledgementCopy: nil,
                safePositionAcknowledgementVersion: nil,
                safePositionAcknowledgementAccepted: nil,
                packID: "test.pack",
                packSchemaVersion: 1,
                packContentVersion: 1,
                pdfTemplateID: "worklight.report",
                pdfTemplateVersion: 1,
                observationBasis: basis,
                temporalContext: temporal
            ))
        )
    }

    func relaunch() throws -> Relaunch {
        let newContext = ModelContext(container)
        newContext.autosaveEnabled = false
        let newStore = try MutationJournalStoreV1(
            modelContext: newContext,
            identity: identity,
            generationID: generationID
        )
        return Relaunch(
            context: newContext,
            store: newStore,
            writer: try Self.makeWriter(
                context: newContext,
                store: newStore,
                identity: identity,
                generationID: generationID,
                writerInstanceID: writerInstanceID
            )
        )
    }

    private static func makeWriter(
        context: ModelContext,
        store: MutationJournalStoreV1,
        identity: WorkspaceReplicaIdentityV1,
        generationID: UUID,
        writerInstanceID: UUID
    ) throws -> WorkspaceWriterV1 {
        try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: writerInstanceID),
            clock: V911Clock(),
            idSource: V911IDSource(value: writerInstanceID),
            fileAuthority: V911FileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
    }

    private static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

}

extension V9_11ObservationTemporalSemanticsTests {
    func testV23P03C19ObservationBasisIsIndependentFromQualityOutcome() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        XCTAssertEqual(fixture.capture.observationBasis.kind, .directlyObserved)
        XCTAssertEqual(fixture.capture.observationBasis.source.kind, .observer)
        XCTAssertEqual(fixture.qualityClear.subjectID, fixture.capture.captureID)
        XCTAssertEqual(fixture.qualityReview.result, .reviewRequired)
        XCTAssertEqual(fixture.qualityReview.subjectID, fixture.reviewCapture.captureID)
    }

    func testC20PrivacyTransformRegionAuthorSnapshotIsTemporalAndLocal() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        XCTAssertEqual(fixture.regions.first?.author.workspaceID, fixture.workspace)
        XCTAssertEqual(fixture.regions.first?.authoredAt, fixture.capturedAt)
        XCTAssertEqual(fixture.regions.map(\.order), [0, 1, 2])
    }
}

extension V9_11ObservationTemporalSemanticsTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension V9_11ObservationTemporalSemanticsTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}

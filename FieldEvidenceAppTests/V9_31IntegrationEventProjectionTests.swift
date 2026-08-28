import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V9_31IntegrationEventProjectionTests: XCTestCase {
    private let fileManager = FileManager.default

    func testV23P03C17G01AcceptedReceiptsProjectStableOrderedIDsAndDigests() throws {
        let corpus = try loadCorpus()
        assertSelectors(corpus)
        XCTAssertEqual(corpus.schema, "V21P03C17IntegrationEventProjectionCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C17")
        XCTAssertEqual(corpus.recordsSchemaVersion, 15)
        XCTAssertEqual(corpus.persistentSchemaVersion, 16)
        XCTAssertEqual(corpus.persistentModelCount, 64)

        let fixture = try makeFixture(corpus)
        let projection = try IntegrationEventProjectionV1(
            registry: fixture.registry,
            limits: fixture.limits
        )
        let first = try projection.project(
            workspaceID: fixture.workspaceID,
            acceptedReceipts: fixture.receipts
        )
        let second = try projection.project(
            workspaceID: fixture.workspaceID,
            acceptedReceipts: Array(fixture.receipts.reversed())
        )

        XCTAssertEqual(first.count, corpus.expectedEventCount)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, first.sorted { $0.order < $1.order })
        XCTAssertEqual(first.map(\.eventID), second.map(\.eventID))
        XCTAssertEqual(first.map(\.eventSHA256), second.map(\.eventSHA256))
        XCTAssertEqual(
            first.map { "\($0.eventKind):\($0.eventVersion)" },
            corpus.expectedOrderedKinds
        )
        XCTAssertEqual(
            first.map(\.order.payloadOrdinal),
            corpus.expectedPayloadOrdinals
        )
        XCTAssertTrue(first.allSatisfy {
            IntegrationEventValidationV1.isSHA256($0.eventID)
                && IntegrationEventValidationV1.isSHA256($0.eventSHA256)
                && IntegrationEventValidationV1.isSHA256($0.payloadSHA256)
        })
        let sensitiveEvents = first.filter { $0.eventKind == "asset.changed" }
        XCTAssertEqual(
            sensitiveEvents.map(\.visibility),
            [IntegrationEventVisibilityV1](
                repeating: IntegrationEventVisibilityV1.sensitiveRedacted,
                count: corpus.expectedSensitiveEventCount
            )
        )
        XCTAssertEqual(
            sensitiveEvents.map(\.redaction),
            [IntegrationEventRedactionV1](
                repeating: IntegrationEventRedactionV1.identifiersOnly,
                count: corpus.expectedSensitiveEventCount
            )
        )

        let registryBytes = try IntegrationEventCanonicalCodecV1.encode(
            fixture.registry,
            limits: fixture.limits
        )
        XCTAssertEqual(
            try IntegrationEventCanonicalCodecV1.decodeRegistry(
                registryBytes,
                limits: fixture.limits
            ),
            fixture.registry
        )
        for event in first {
            let bytes = try IntegrationEventCanonicalCodecV1.encode(
                event,
                registry: fixture.registry,
                limits: fixture.limits
            )
            XCTAssertEqual(
                try IntegrationEventCanonicalCodecV1.decodeEvent(
                    bytes,
                    registry: fixture.registry,
                    limits: fixture.limits
                ),
                event
            )
        }
    }

    func testV23P03C17A01LegacyCompatibleConsumerReplaysFromZeroAndArbitraryBoundaries() throws {
        let corpus = try loadCorpus()
        let fixture = try makeFixture(corpus)
        let projection = try IntegrationEventProjectionV1(
            registry: fixture.registry,
            limits: fixture.limits
        )
        let events = try projection.project(
            workspaceID: fixture.workspaceID,
            acceptedReceipts: fixture.receipts
        )
        let consumer = try IntegrationEventConformanceConsumerV1(
            consumerID: corpus.consumer.id,
            consumerVersion: corpus.consumer.version
        )
        let baseline = try consumer.consume(
            workspaceID: fixture.workspaceID,
            registry: fixture.registry,
            events: events
        )
        XCTAssertEqual(
            corpus.consumer.minimumCompatibleVersion,
            fixture.registry.definitions.map(\.minimumCompatibleConsumerVersion).min() ?? 0
        )
        XCTAssertEqual(corpus.consumer.consumerVersionDescription, "OLDER_COMPATIBLE")

        for boundary in corpus.boundaryIndexes {
            let prefix = Array(events.prefix(boundary))
            let prefixResult = try consumer.consume(
                workspaceID: fixture.workspaceID,
                registry: fixture.registry,
                events: prefix
            )
            let remaining = try projection.events(
                after: prefixResult.checkpoint,
                workspaceID: fixture.workspaceID,
                acceptedReceipts: fixture.receipts
            )
            let resumed = try consumer.consume(
                workspaceID: fixture.workspaceID,
                registry: fixture.registry,
                events: remaining,
                priorCheckpoint: prefixResult.checkpoint
            )
            XCTAssertEqual(
                resumed.checkpoint,
                baseline.checkpoint,
                "boundary \(boundary) must converge to the zero-boundary checkpoint"
            )
            XCTAssertEqual(resumed.terminalStateSHA256, baseline.terminalStateSHA256)
        }
    }

    func testV23P03C17H01UnknownVersionDivergentSameIDSensitiveCanaryAndForgedCheckpointFailClosed() throws {
        let corpus = try loadCorpus()
        let fixture = try makeFixture(corpus)
        let projection = try IntegrationEventProjectionV1(
            registry: fixture.registry,
            limits: fixture.limits
        )
        let events = try projection.project(
            workspaceID: fixture.workspaceID,
            acceptedReceipts: fixture.receipts
        )
        let consumer = try IntegrationEventConformanceConsumerV1(
            consumerID: corpus.consumer.id,
            consumerVersion: corpus.consumer.version
        )
        let baseline = try consumer.consume(
            workspaceID: fixture.workspaceID,
            registry: fixture.registry,
            events: events
        )
        let originalReceipts = fixture.receipts
        XCTAssertTrue(corpus.hostile.divergentSameID)
        XCTAssertTrue(corpus.hostile.forgedCheckpoint)

        let unknownSchemaVersion = try mutateEvent(events[0]) { object in
            object["schemaVersion"] = corpus.hostile.unknownSchemaVersion
        }
        XCTAssertThrowsError(
            try projection.validateProjectedStream(
                [unknownSchemaVersion],
                workspaceID: fixture.workspaceID
            )
        )
        XCTAssertThrowsError(
            try consumer.consume(
                workspaceID: fixture.workspaceID,
                registry: fixture.registry,
                events: [unknownSchemaVersion]
            )
        )

        let unknownVersion = try mutateEvent(events[0]) { object in
            object["eventVersion"] = corpus.hostile.unknownEventVersion
        }
        XCTAssertThrowsError(
            try projection.validateProjectedStream(
                [unknownVersion],
                workspaceID: fixture.workspaceID
            )
        )
        XCTAssertThrowsError(
            try consumer.consume(
                workspaceID: fixture.workspaceID,
                registry: fixture.registry,
                events: [unknownVersion]
            )
        )

        let payloadDecoder = JSONDecoder()
        payloadDecoder.dateDecodingStrategy = .millisecondsSince1970
        let originalPayload = try payloadDecoder.decode(
            IntegrationEventPayloadV1.self,
            from: events[0].payload
        )
        let divergentPayload = try IntegrationEventPayloadV1(
            subject: originalPayload.subject,
            subjectRevision: originalPayload.subjectRevision,
            subjectSemanticSHA256: originalPayload.subjectSemanticSHA256,
            commandBodySHA256: originalPayload.commandBodySHA256,
            resultSHA256: String(repeating: "c", count: 64)
        )
        let sourceReceipt = try XCTUnwrap(
            fixture.receipts.first { $0.identity == events[0].sourceReceiptID }
        )
        let divergentSameID = try IntegrationEventV1(
            definition: try fixture.registry.definition(
                eventKind: events[0].eventKind,
                version: events[0].eventVersion
            ),
            receipt: sourceReceipt,
            sourceReceiptSHA256: events[0].sourceReceiptSHA256,
            subject: events[0].subject,
            subjectRevision: events[0].subjectRevision,
            order: events[0].order,
            payload: WorkspaceMutationCanonicalV1.data(divergentPayload),
            limits: fixture.limits
        )
        XCTAssertEqual(divergentSameID.eventID, events[0].eventID)
        XCTAssertNotEqual(divergentSameID.eventSHA256, events[0].eventSHA256)
        XCTAssertThrowsError(
            try consumer.consume(
                workspaceID: fixture.workspaceID,
                registry: fixture.registry,
                events: [events[0], divergentSameID]
            )
        )

        let canaryData = Data(corpus.hostile.sensitiveCanary.utf8)
        let sensitiveCanary = try mutateEvent(events[0]) { object in
            object["payload"] = canaryData.base64EncodedString()
            object["payloadSHA256"] = IntegrationEventValidationV1.sha256(canaryData)
        }
        XCTAssertThrowsError(
            try consumer.consume(
                workspaceID: fixture.workspaceID,
                registry: fixture.registry,
                events: [sensitiveCanary]
            )
        )
        let projectedBytes = try WorkspaceMutationCanonicalV1.data(events)
        XCTAssertFalse(
            String(decoding: projectedBytes, as: UTF8.self)
                .contains(corpus.hostile.sensitiveCanary)
        )

        let forgedCheckpoint = try mutateCheckpoint(baseline.checkpoint) { object in
            object["checkpointSHA256"] = String(repeating: "c", count: 64)
        }
        XCTAssertThrowsError(
            try consumer.consume(
                workspaceID: fixture.workspaceID,
                registry: fixture.registry,
                events: [],
                priorCheckpoint: forgedCheckpoint
            )
        )
        XCTAssertEqual(fixture.receipts, originalReceipts)
        let repeatedBaseline = try consumer.consume(
            workspaceID: fixture.workspaceID,
            registry: fixture.registry,
            events: events
        )
        XCTAssertEqual(baseline.checkpoint, repeatedBaseline.checkpoint)
    }

    @MainActor
    func testV23P03C17I01EffectBeforeCheckpointCrashRetriesWithoutProviderDeliveryState() async throws {
        let corpus = try loadCorpus()
        let fixture = try makeFixture(corpus)
        let support = temporarySupportRoot("c17-interruption")
        defer { try? fileManager.removeItem(at: support) }
        let store = try IntegrationProjectionCheckpointStoreV1(
            generationRootURL: support,
            generationID: fixture.generationID,
            workspaceID: fixture.workspaceID,
            limits: fixture.limits
        )
        let interrupted = try IntegrationConformanceConsumerV1(
            registry: fixture.registry,
            limits: fixture.limits,
            consumerID: corpus.consumer.id,
            consumerVersion: corpus.consumer.version,
            store: store,
            interruptionPoint: { .afterEffectBeforeCheckpoint }
        )

        do {
            _ = try await interrupted.advance(
                workspaceID: fixture.workspaceID,
                acceptedReceipts: fixture.receipts
            )
            XCTFail("effect-before-checkpoint interruption must be visible")
        } catch let error as IntegrationEventFailureV1 {
            XCTAssertEqual(error, .staleCheckpoint)
        }
        let checkpointAfterCrash = try await store.checkpoint(
            consumerID: corpus.consumer.id,
            workspaceID: fixture.workspaceID
        )
        XCTAssertNil(checkpointAfterCrash)
        let effectsAfterCrash = try await store.recordedDerivedEffectEventIDs(
            consumerID: corpus.consumer.id,
            workspaceID: fixture.workspaceID
        )
        XCTAssertEqual(effectsAfterCrash.count, corpus.expectedEventCount)

        let resumed = try IntegrationConformanceConsumerV1(
            registry: fixture.registry,
            limits: fixture.limits,
            consumerID: corpus.consumer.id,
            consumerVersion: corpus.consumer.version,
            store: store
        )
        let retry = try await resumed.advance(
            workspaceID: fixture.workspaceID,
            acceptedReceipts: fixture.receipts
        )
        XCTAssertEqual(retry.acceptedEventIDs.count, corpus.expectedEventCount)
        let duplicateRetry = try await resumed.advance(
            workspaceID: fixture.workspaceID,
            acceptedReceipts: fixture.receipts
        )
        XCTAssertTrue(duplicateRetry.acceptedEventIDs.isEmpty)
        XCTAssertEqual(duplicateRetry.checkpoint, retry.checkpoint)
        XCTAssertEqual(duplicateRetry.terminalStateSHA256, retry.terminalStateSHA256)
        let effectsAfterRetry = try await store.recordedDerivedEffectEventIDs(
            consumerID: corpus.consumer.id,
            workspaceID: fixture.workspaceID
        )
        XCTAssertEqual(effectsAfterRetry, effectsAfterCrash)
        let stored = try await store.checkpoint(
            consumerID: corpus.consumer.id,
            workspaceID: fixture.workspaceID
        )
        XCTAssertEqual(stored, retry.checkpoint)
        XCTAssertTrue(corpus.interruption.noProviderDeliveryRow)
        XCTAssertEqual(corpus.interruption.retryDisposition, "OLD_CHECKPOINT_REPLAYED_IDEMPOTENTLY")
    }

    @MainActor
    func testV23P03C17R01DropAndRebuildReproducesExactConsumerResultAndLeavesCanonicalReceiptsUntouched() async throws {
        let corpus = try loadCorpus()
        let fixture = try makeFixture(corpus)
        let support = temporarySupportRoot("c17-recovery")
        defer { try? fileManager.removeItem(at: support) }
        let store = try IntegrationProjectionCheckpointStoreV1(
            generationRootURL: support,
            generationID: fixture.generationID,
            workspaceID: fixture.workspaceID,
            limits: fixture.limits
        )
        let consumer = try IntegrationConformanceConsumerV1(
            registry: fixture.registry,
            limits: fixture.limits,
            consumerID: corpus.consumer.id,
            consumerVersion: corpus.consumer.version,
            store: store
        )
        let sourceReceipts = fixture.receipts
        let originalReceipts = fixture.receipts
        let first = try await consumer.advance(
            workspaceID: fixture.workspaceID,
            acceptedReceipts: sourceReceipts
        )
        let firstCheckpoint = try await store.checkpoint(
            consumerID: corpus.consumer.id,
            workspaceID: fixture.workspaceID
        )
        XCTAssertEqual(firstCheckpoint, first.checkpoint)

        try await consumer.drop(workspaceID: fixture.workspaceID)
        let afterDrop = try await store.checkpoint(
            consumerID: corpus.consumer.id,
            workspaceID: fixture.workspaceID
        )
        XCTAssertNil(afterDrop)
        let rebuilt = try await consumer.rebuild(
            workspaceID: fixture.workspaceID,
            acceptedReceipts: sourceReceipts
        )
        XCTAssertEqual(rebuilt, first)
        let afterRebuild = try await store.checkpoint(
            consumerID: corpus.consumer.id,
            workspaceID: fixture.workspaceID
        )
        XCTAssertEqual(afterRebuild, first.checkpoint)
        XCTAssertEqual(fixture.receipts, originalReceipts)
        XCTAssertEqual(corpus.recovery.rebuildDisposition, "DROP_DERIVED_EVENTS_AND_CHECKPOINTS_THEN_REPLAY_RECEIPTS")
        XCTAssertFalse(IntegrationProjectionSchemaV1.canonicalBackupIncluded)
        XCTAssertFalse(IntegrationProjectionSchemaV1.canonicalExportIncluded)
        XCTAssertFalse(IntegrationProjectionSchemaV1.canonicalReportSource)
        try assertNoProviderFootprint(corpus)

        let checkpointRoot = support.appendingPathComponent(
            "replication/integration-projections-v1",
            isDirectory: true
        )
        let members = try fileManager.contentsOfDirectory(
            at: checkpointRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        XCTAssertEqual(members.count, 2)
        XCTAssertEqual(
            Set(members.map(\.lastPathComponent).map { name in
                if name.hasPrefix("consumer-") { return "consumer" }
                if name.hasPrefix("effects-") { return "effects" }
                return "unexpected"
            }),
            Set(["consumer", "effects"])
        )
        XCTAssertTrue(members.allSatisfy { $0.lastPathComponent.hasSuffix(".json") })
        XCTAssertTrue(corpus.recovery.noSecondWriter)
        XCTAssertTrue(corpus.recovery.noSecondStore)
    }

    private struct Corpus: Decodable {
        struct Selector: Decodable {
            let id: String
            let selector: String
            let focus: String
        }

        struct Consumer: Decodable {
            let id: String
            let version: Int
            let minimumCompatibleVersion: Int
            let consumerVersionDescription: String
        }

        struct Hostile: Decodable {
            let unknownSchemaVersion: Int
            let unknownEventVersion: Int
            let sensitiveCanary: String
            let divergentSameID: Bool
            let forgedCheckpoint: Bool
        }

        struct Interruption: Decodable {
            let noProviderDeliveryRow: Bool
            let retryDisposition: String
        }

        struct Recovery: Decodable {
            let rebuildDisposition: String
            let noSecondWriter: Bool
            let noSecondStore: Bool
        }

        let schema: String
        let schemaVersion: Int
        let corpusID: String
        let cardID: String
        let recordsSchemaVersion: Int
        let persistentSchemaVersion: Int
        let persistentModelCount: Int
        let workspaceID: UUID
        let generationID: UUID
        let sourceReplicaID: UUID
        let expectedReceiptCount: Int
        let expectedEventCount: Int
        let expectedSensitiveEventCount: Int
        let expectedOrderedKinds: [String]
        let expectedPayloadOrdinals: [Int]
        let boundaryIndexes: [Int]
        let evidenceSelectors: [Selector]
        let consumer: Consumer
        let hostile: Hostile
        let interruption: Interruption
        let recovery: Recovery
        let forbiddenProductionSymbols: [String]
        let forbiddenProductionPaths: [String]
    }

    private struct Fixture {
        let workspaceID: WorkspaceID
        let generationID: UUID
        let sourceReplicaID: ReplicaID
        let limits: IntegrationEventLimitsV1
        let registry: IntegrationContractRegistryV1
        let receipts: [MutationReceiptV1]
    }

    private func loadCorpus() throws -> Corpus {
        let url = sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Integration/V21P03C17IntegrationEventProjectionCorpusV1.json"
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Corpus.self, from: Data(contentsOf: url))
    }

    private func makeFixture(_ corpus: Corpus) throws -> Fixture {
        let limits = try IntegrationEventLimitsV1()
        let registry = try IntegrationContractRegistryV1(
            releaseID: corpus.corpusID,
            definitions: [
                try IntegrationEventContractDefinitionV1(
                    eventKind: "asset.changed",
                    eventVersion: 1,
                    sourceEntityKind: .asset,
                    sensitivity: .sensitiveWorkspaceData,
                    emittedVisibility: .sensitiveRedacted,
                    redaction: .identifiersOnly,
                    minimumCompatibleConsumerVersion: corpus.consumer.minimumCompatibleVersion
                ),
                try IntegrationEventContractDefinitionV1(
                    eventKind: "site.changed",
                    eventVersion: 1,
                    sourceEntityKind: .site,
                    sensitivity: .workspaceData,
                    emittedVisibility: .workspaceInternal,
                    redaction: .notRequired,
                    minimumCompatibleConsumerVersion: corpus.consumer.minimumCompatibleVersion
                ),
            ],
            limits: limits
        )
        let workspaceID = WorkspaceID(rawValue: corpus.workspaceID)
        let sourceReplicaID = ReplicaID(rawValue: corpus.sourceReplicaID)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: sourceReplicaID
        )
        let generationID = corpus.generationID
        let writerInstanceID = try uuid("70000000-0000-4000-8000-000000000001")
        let receipts = try (0..<corpus.expectedReceiptCount).map { offset in
            let serial = UInt64(offset + 1)
            let suffix = String(format: "%04d", offset + 1)
            let siteID = try uuid("50000000-0000-4000-8000-00000000\(suffix)")
            let assetID = try uuid("51000000-0000-4000-8000-00000000\(suffix)")
            let mutationID = try MutationIDV1(
                rawValue: try uuid("60000000-0000-4000-8000-00000000\(suffix)")
            )
            let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
            let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
            let expected = try WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID,
                generationID: generationID,
                writerInstanceID: writerInstanceID,
                revision: serial - 1,
                entityRevisions: [
                    WorkspaceEntityRevisionV1(identity: siteIdentity, revision: 0),
                    WorkspaceEntityRevisionV1(identity: assetIdentity, revision: 0),
                ]
            )
            let command = WorkspaceCommandV1.createFirstSign(.init(
                siteID: siteID,
                newSite: .init(
                    id: siteID,
                    label: "C17 Site \(offset + 1)",
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: assetID,
                assetLabel: "C17 Asset \(offset + 1)",
                packID: "c17.integration.fixture",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
            ))
            let request = WorkspaceMutationRequestV1(
                mutationID: mutationID,
                expectedRevision: expected,
                command: command
            )
            let envelope = try MutationEnvelopeV1(
                request: request,
                identity: identity
            )
            let resulting = try MutationPortableExpectedRevisionV1(
                WorkspaceExpectedRevisionV1(
                    workspaceID: workspaceID,
                    generationID: generationID,
                    writerInstanceID: writerInstanceID,
                    revision: serial,
                    entityRevisions: [
                        WorkspaceEntityRevisionV1(identity: siteIdentity, revision: 1),
                        WorkspaceEntityRevisionV1(identity: assetIdentity, revision: 1),
                    ]
                )
            )
            return try MutationReceiptV1(
                identity: MutationReceiptIdentityV1(
                    workspaceID: workspaceID,
                    replicaID: sourceReplicaID,
                    localSequence: serial
                ),
                envelope: envelope,
                resultingRevision: resulting,
                postImages: [
                    .site(
                        id: siteID,
                        revision: 1,
                        semanticSHA256: String(repeating: "a", count: 64)
                    ),
                    .asset(
                        id: assetID,
                        revision: 1,
                        semanticSHA256: String(repeating: "b", count: 64)
                    ),
                ],
                committedAt: Date(timeIntervalSince1970: 1_700_000_100 + Double(offset))
            )
        }
        return Fixture(
            workspaceID: workspaceID,
            generationID: generationID,
            sourceReplicaID: sourceReplicaID,
            limits: limits,
            registry: registry,
            receipts: receipts
        )
    }

    private func mutateEvent(
        _ event: IntegrationEventV1,
        _ mutate: (inout [String: Any]) -> Void
    ) throws -> IntegrationEventV1 {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: WorkspaceMutationCanonicalV1.data(event)
            ) as? [String: Any]
        )
        mutate(&object)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(IntegrationEventV1.self, from: data)
    }

    private func mutateCheckpoint(
        _ checkpoint: ProjectionCheckpointV1,
        _ mutate: (inout [String: Any]) -> Void
    ) throws -> ProjectionCheckpointV1 {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: WorkspaceMutationCanonicalV1.data(checkpoint)
            ) as? [String: Any]
        )
        mutate(&object)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(ProjectionCheckpointV1.self, from: data)
    }

    private func assertSelectors(_ corpus: Corpus) {
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), ["G", "A", "H", "I", "R"])
        XCTAssertEqual(
            corpus.evidenceSelectors.map(\.id),
            [
                "V23-P03-C17-G01",
                "V23-P03-C17-A01",
                "V23-P03-C17-H01",
                "V23-P03-C17-I01",
                "V23-P03-C17-R01",
            ]
        )
        XCTAssertTrue(corpus.evidenceSelectors.allSatisfy { !$0.focus.isEmpty })
    }

    private func assertNoProviderFootprint(_ corpus: Corpus) throws {
        let paths = [
            "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
            "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
            "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
            "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
        ]
        let source = try paths.map {
            try String(
                contentsOf: sourceRoot().appendingPathComponent($0),
                encoding: .utf8
            )
        }.joined(separator: "\n")
        for symbol in corpus.forbiddenProductionSymbols {
            XCTAssertFalse(source.contains(symbol), "forbidden C17 production symbol: \(symbol)")
        }
        for path in corpus.forbiddenProductionPaths {
            XCTAssertFalse(
                fileManager.fileExists(atPath: sourceRoot().appendingPathComponent(path).path),
                "forbidden C17 production path exists: \(path)"
            )
        }
        XCTAssertTrue(source.contains("IntegrationProjectionOperationalStoreV1"))
        XCTAssertFalse(source.contains("WorkspaceWriterV1"))
        XCTAssertFalse(source.contains("MutationJournalStoreV1"))
    }

    private func temporarySupportRoot(_ label: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("field-evidence-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    private func uuid(_ value: String) throws -> UUID {
        try XCTUnwrap(UUID(uuidString: value))
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

extension V9_31IntegrationEventProjectionTests {
    func testV23P03C18ProjectionCanPersistCanonicalSemanticChange() throws {
        let change = try PackageSemanticChangeV1(
            kind: .fieldAdded,
            stableSubjectID: "c18.field"
        )
        let bytes = try PackageEvolutionCanonicalCodecV1.encode(change)
        XCTAssertEqual(
            try PackageEvolutionCanonicalCodecV1.decode(
                PackageSemanticChangeV1.self,
                from: bytes
            ),
            change
        )
        XCTAssertTrue(PackageEvolutionLifecycleV1.searchRebuildReplayRequired)
    }

    func testV23P03C19ProjectionRebuildRetainsOrderedMeasurementIDs() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let first = fixture.bundle.captures.map(\.captureID)
        let rebuilt = try MeasurementIntegrityCanonicalCodecV1.decode(
            MeasurementIntegrityAtomicBundleV1.self,
            from: MeasurementIntegrityCanonicalCodecV1.encode(fixture.bundle)
        )
        XCTAssertEqual(rebuilt.captures.map(\.captureID), first)
        XCTAssertEqual(rebuilt.bundleSHA256, fixture.bundle.bundleSHA256)
        XCTAssertEqual(rebuilt.assessments.map(\.assessmentID), fixture.bundle.assessments.map(\.assessmentID))
    }

    func testC20PrivacyTransformProjectionRetainsPrivacyProvenance() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        guard case .privacy(let privacy) = fixture.provenance.transform else {
            return XCTFail("privacy transform provenance is required")
        }
        XCTAssertEqual(privacy.privacyManifestID, fixture.manifest.manifestID)
        XCTAssertEqual(privacy.privacyManifestSHA256, fixture.manifest.manifestSHA256)
    }
}

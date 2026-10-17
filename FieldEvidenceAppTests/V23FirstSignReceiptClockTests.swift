import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23FirstSignReceiptClockTests: XCTestCase {
    @MainActor
    func testLocalFirstSignQuantizesGeneratedClockAndColdReplayPreservesExactBytes() throws {
        let fractional = Date(timeIntervalSinceReferenceDate: 811_123_456.000_000_1)
        try assertLocationRowExposesFractionalClockPremise(fractional)

        let cases = [
            Date(timeIntervalSinceReferenceDate: 811_123_456.125),
            fractional,
        ]
        for clockInstant in cases {
            let harness = try FirstSignReceiptClockHarness(clockInstant: clockInstant)
            defer { harness.removeFiles() }

            let scenario = try harness.makeScenario()
            let expectedTime = Self.quantized(clockInstant)
            let outcome = try harness.writer.execute(scenario.request)
            let receipt = try XCTUnwrap(
                harness.store.receipt(mutationID: scenario.mutationID)
            )
            let placementRow = try XCTUnwrap(
                harness.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).first
            )
            let placement = try placementRow.value()

            XCTAssertEqual(outcome.occurredAt, expectedTime)
            XCTAssertEqual(outcome.before.revision, 0)
            XCTAssertEqual(outcome.after.revision, 1)
            XCTAssertEqual(receipt.committedAt, expectedTime)
            XCTAssertEqual(placement.occurredAt, expectedTime)
            XCTAssertEqual(placementRow.occurredAt, expectedTime)
            XCTAssertEqual(placement.mutationID, scenario.mutationID)
            XCTAssertEqual(placement.id, scenario.placementEventID)
            XCTAssertEqual(placement.physicalEpisodeID, scenario.physicalEpisodeID)
            XCTAssertEqual(placement.eventSHA256, placementRow.eventSHA256)

            let site = try XCTUnwrap(
                harness.context.fetch(FetchDescriptor<Site>()).first
            )
            let asset = try XCTUnwrap(
                harness.context.fetch(FetchDescriptor<Asset>()).first
            )
            XCTAssertEqual(site.createdAt, scenario.createdAt)
            XCTAssertEqual(asset.createdAt, scenario.createdAt)

            let placementBytes = placementRow.canonicalData
            let receiptBytes = try receipt.canonicalData()
            XCTAssertEqual(
                try LocationPersistenceCodecV1.encode(
                    LocationPersistenceCodecV1.decode(
                        AssetPlacementEventV1.self,
                        from: placementBytes
                    )
                ),
                placementBytes
            )
            XCTAssertEqual(
                try MutationReceiptV1.decodeCanonical(from: receiptBytes).canonicalData(),
                receiptBytes
            )
            try harness.store.validateAll()
            XCTAssertFalse(harness.context.hasChanges)

            let counts = try harness.rowCounts(in: harness.context)
            XCTAssertEqual(
                counts,
                FirstSignReceiptClockHarness.RowCounts(
                    sites: 1,
                    assets: 1,
                    placements: 1,
                    receipts: 1,
                    entityRevisions: 3
                )
            )
            let cold = try harness.reopen()
            try cold.store.validateAll()
            let coldPlacementRow = try XCTUnwrap(
                cold.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).first
            )
            XCTAssertEqual(coldPlacementRow.canonicalData, placementBytes)
            XCTAssertEqual(try coldPlacementRow.value(), placement)
            XCTAssertEqual(
                try XCTUnwrap(cold.store.receipt(mutationID: scenario.mutationID)).canonicalData(),
                receiptBytes
            )

            let beforeReplay = try cold.writer.currentRevision()
            let replay = try cold.writer.execute(scenario.request)
            XCTAssertEqual(replay.mutationID, outcome.mutationID)
            XCTAssertEqual(replay.commandDigest, outcome.commandDigest)
            XCTAssertEqual(replay.occurredAt, outcome.occurredAt)
            XCTAssertEqual(replay.effect, outcome.effect)
            Self.assertPortableRevision(replay.before, equals: outcome.before, absentIsZero: true)
            XCTAssertEqual(replay.before.entityRevisions, receipt.expectedRevision.entityRevisions)
            Self.assertPortableRevision(replay.after, equals: outcome.after)
            XCTAssertEqual(replay.before.writerInstanceID, beforeReplay.writerInstanceID)
            XCTAssertEqual(replay.after.writerInstanceID, beforeReplay.writerInstanceID)
            let originalWriterInstanceID = try harness.writer.currentRevision().writerInstanceID
            XCTAssertEqual(outcome.before.writerInstanceID, originalWriterInstanceID)
            XCTAssertEqual(outcome.after.writerInstanceID, originalWriterInstanceID)
            XCTAssertNotEqual(beforeReplay.writerInstanceID, originalWriterInstanceID)
            XCTAssertEqual(try cold.writer.currentRevision(), beforeReplay)
            XCTAssertEqual(try harness.rowCounts(in: cold.context), counts)
            XCTAssertFalse(cold.context.hasChanges)
        }
    }

    @MainActor
    func testImportedFirstSignPreservesAcceptedPlacementTimeAcrossFractionalDestinationClockAndColdReplay() throws {
        let destinationClock = Date(timeIntervalSinceReferenceDate: 811_123_456.000_000_1)
        try assertLocationRowExposesFractionalClockPremise(destinationClock)
        let source = try FirstSignReceiptClockHarness(
            clockInstant: Date(timeIntervalSinceReferenceDate: 811_123_450.125)
        )
        defer { source.removeFiles() }
        let destination = try FirstSignReceiptClockHarness(
            clockInstant: destinationClock,
            workspaceID: source.identity.workspaceID
        )
        defer { destination.removeFiles() }
        XCTAssertNotEqual(source.identity.replicaID, destination.identity.replicaID)

        let scenario = try source.makeScenario(
            createdAt: Date(timeIntervalSince1970: 1_789_344_000.079_157_6)
        )
        _ = try source.writer.execute(scenario.request)
        let sourceHistory = try source.writer.sourceMutationHistorySnapshot()
        XCTAssertEqual(sourceHistory.receipts.count, 1)
        let sourceRecord = try XCTUnwrap(sourceHistory.receipts.first)
        let sourceEnvelope = try MutationEnvelopeV1.decodeCanonical(from: sourceRecord.envelopeData)
        let sourceReceipt = try MutationReceiptV1.decodeCanonical(from: sourceRecord.receiptData)
        let sourceBasisBytes = try XCTUnwrap(sourceRecord.reversalBasisData)
        let sourceBasis = try ReversalBasisV1.decodeCanonical(from: sourceBasisBytes)
        let compensation = try XCTUnwrap(sourceBasis.firstSignCompensation)
        let portablePlan = try PortableReversalPlanV1(
            basis: sourceBasis,
            expectedRevision: sourceReceipt.resultingRevision,
            compensatingCommands: [compensation.compensatingCommand()]
        )
        let policy = try ConflictPolicyV1(
            policyID: "test.first-sign-clock", rule: .stableIDAppendUnion
        )
        let change = try JournalChangeV1(
            envelope: sourceEnvelope,
            receipt: sourceReceipt,
            entityChanges: sourceReceipt.postImages.map {
                try EntityChangeV1(postImage: $0, conflictPolicy: policy, conflictIdentity: nil)
            }.sorted { $0.stableKey < $1.stableKey },
            reversalBasis: sourceBasis,
            portableReversalPlan: portablePlan,
            semanticReversalReceipt: nil,
            contentReferences: []
        )
        guard case let .createFirstSign(incomingCommand) = sourceEnvelope.command else {
            return XCTFail("Expected the accepted First Sign command")
        }
        XCTAssertNotEqual(incomingCommand.createdAt, Self.quantized(incomingCommand.createdAt))
        XCTAssertNotEqual(sourceReceipt.committedAt, Self.quantized(destinationClock))
        let sourcePlacementRow = try XCTUnwrap(
            source.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).first
        )
        let sourcePlacement = try sourcePlacementRow.value()
        let sourcePlacementBytes = sourcePlacementRow.canonicalData
        XCTAssertEqual(sourcePlacement.occurredAt, sourceReceipt.committedAt)

        let imported = try destination.writer.executeImported(change)
        let importedReceipt = try XCTUnwrap(
            destination.store.receipt(mutationID: scenario.mutationID)
        )
        let placementRow = try XCTUnwrap(
            destination.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).first
        )
        let placement = try placementRow.value()
        XCTAssertEqual(imported.occurredAt, sourceReceipt.committedAt)
        XCTAssertEqual(importedReceipt.committedAt, sourceReceipt.committedAt)
        XCTAssertEqual(importedReceipt.sourceKind, .importedHistory)
        XCTAssertEqual(placement.occurredAt, sourceReceipt.committedAt)
        XCTAssertEqual(placementRow.occurredAt, sourceReceipt.committedAt)
        XCTAssertEqual(placement, sourcePlacement)
        XCTAssertEqual(placement.eventSHA256, sourcePlacement.eventSHA256)
        XCTAssertEqual(placementRow.canonicalData, sourcePlacementBytes)
        XCTAssertEqual(try LocationPersistenceCodecV1.encode(placement), sourcePlacementBytes)
        let site = try XCTUnwrap(destination.context.fetch(FetchDescriptor<Site>()).first)
        let asset = try XCTUnwrap(destination.context.fetch(FetchDescriptor<Asset>()).first)
        XCTAssertEqual(site.createdAt, incomingCommand.createdAt)
        XCTAssertEqual(asset.createdAt, incomingCommand.createdAt)
        try destination.store.validateAll()
        XCTAssertFalse(destination.context.hasChanges)
        let counts = try destination.rowCounts(in: destination.context)
        XCTAssertEqual(counts, FirstSignReceiptClockHarness.RowCounts(
            sites: 1, assets: 1, placements: 1, receipts: 1, entityRevisions: 3
        ))
        let receiptBytes = try importedReceipt.canonicalData()

        let cold = try destination.reopen()
        try cold.store.validateAll()
        let coldPlacement = try XCTUnwrap(
            cold.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).first
        )
        XCTAssertEqual(coldPlacement.canonicalData, sourcePlacementBytes)
        XCTAssertEqual(try coldPlacement.value(), sourcePlacement)
        let beforeReplay = try cold.writer.currentRevision()
        let replay = try cold.writer.executeImported(change)
        XCTAssertEqual(replay.mutationID, imported.mutationID)
        XCTAssertEqual(replay.commandDigest, imported.commandDigest)
        XCTAssertEqual(replay.occurredAt, sourceReceipt.committedAt)
        XCTAssertEqual(replay.effect, imported.effect)
        XCTAssertEqual(try cold.writer.currentRevision(), beforeReplay)
        XCTAssertEqual(try destination.rowCounts(in: cold.context), counts)
        XCTAssertEqual(
            try XCTUnwrap(cold.store.receipt(mutationID: scenario.mutationID)).canonicalData(),
            receiptBytes
        )
        XCTAssertFalse(cold.context.hasChanges)
        XCTAssertEqual(try source.writer.sourceMutationHistorySnapshot(), sourceHistory)
        XCTAssertEqual(try change.envelope.canonicalData(), sourceRecord.envelopeData)
        XCTAssertEqual(try change.receipt.canonicalData(), sourceRecord.receiptData)
        XCTAssertEqual(try XCTUnwrap(change.reversalBasis).canonicalData(), sourceBasisBytes)
        XCTAssertEqual(sourcePlacementRow.canonicalData, sourcePlacementBytes)
    }

    @MainActor
    func testCanonicalDateReplayUsesExactEnvelopeBytesAndChangedBytesStillQuarantine() throws {
        let sourceDate = Date(timeIntervalSince1970: 1_789_344_000.079_157_6)
        let harness = try FirstSignReceiptClockHarness(
            clockInstant: Date(timeIntervalSince1970: 1_789_344_010.125)
        )
        defer { harness.removeFiles() }
        let scenario = try harness.makeScenario(createdAt: sourceDate)
        let premiseEnvelope = try MutationEnvelopeV1(
            request: scenario.request,
            identity: harness.identity
        )
        let premiseEnvelopeBytes = try premiseEnvelope.canonicalData()
        let decodedEnvelope = try MutationEnvelopeV1.decodeCanonical(from: premiseEnvelopeBytes)
        guard case let .createFirstSign(originalCommand) = premiseEnvelope.command,
              case let .createFirstSign(decodedCommand) = decodedEnvelope.command else {
            return XCTFail("Expected the actual First Sign command")
        }

        XCTAssertNotEqual(decodedCommand.createdAt, originalCommand.createdAt)
        XCTAssertNotEqual(decodedEnvelope, premiseEnvelope)
        XCTAssertEqual(try decodedEnvelope.canonicalData(), premiseEnvelopeBytes)
        XCTAssertEqual(try decodedEnvelope.canonicalSHA256(), try premiseEnvelope.canonicalSHA256())

        _ = try harness.writer.execute(scenario.request)
        let receipt = try XCTUnwrap(
            harness.store.receipt(mutationID: scenario.mutationID)
        )
        // The future eligible original includes its atomically committed basis
        // digest. Retry authority comes from those accepted envelope bytes,
        // not a synthetic pre-execution envelope that omitted the commitment.
        let acceptedRows = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).filter {
            $0.workspaceID == harness.identity.workspaceID.rawValue
                && $0.mutationID == scenario.mutationID.rawValue
        }
        XCTAssertEqual(acceptedRows.count, 1)
        let acceptedRow = try XCTUnwrap(acceptedRows.first)
        let envelopeBytes = acceptedRow.envelopeData
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: envelopeBytes)
        XCTAssertEqual(try envelope.canonicalData(), envelopeBytes)
        XCTAssertEqual(try envelope.canonicalSHA256(), acceptedRow.envelopeSHA256)
        let beforeReplay = try harness.writer.currentRevision()
        let countsBeforeReplay = try harness.rowCounts(in: harness.context)
        XCTAssertEqual(
            try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
            0
        )

        let replay = try XCTUnwrap(harness.store.resolveReplay(
            envelope: envelope,
            detectedAt: Date(timeIntervalSince1970: 1_789_344_011.125)
        ))
        XCTAssertEqual(try replay.canonicalData(), try receipt.canonicalData())
        XCTAssertEqual(try harness.writer.currentRevision(), beforeReplay)
        XCTAssertEqual(try harness.rowCounts(in: harness.context), countsBeforeReplay)
        XCTAssertEqual(
            try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
            0
        )
        XCTAssertFalse(harness.context.hasChanges)

        let changedCommand = WorkspaceCommandV1.createFirstSign(FirstSignMutationV1(
            siteID: originalCommand.siteID,
            newSite: originalCommand.newSite,
            assetID: originalCommand.assetID,
            assetLabel: originalCommand.assetLabel + " changed",
            packID: originalCommand.packID,
            packSchemaVersion: originalCommand.packSchemaVersion,
            packContentVersion: originalCommand.packContentVersion,
            createdAt: originalCommand.createdAt,
            initialPlacementMutationID: originalCommand.initialPlacementMutationID,
            initialPlacementEventID: originalCommand.initialPlacementEventID,
            initialPhysicalEpisodeID: originalCommand.initialPhysicalEpisodeID
        ))
        let changedEnvelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: scenario.mutationID,
                expectedRevision: scenario.request.expectedRevision,
                command: changedCommand
            ),
            identity: harness.identity,
            reversalPlanDigest: envelope.reversalPlanDigest
        )
        XCTAssertNotEqual(try changedEnvelope.canonicalData(), envelopeBytes)
        XCTAssertNotEqual(try changedEnvelope.canonicalSHA256(), try envelope.canonicalSHA256())
        XCTAssertThrowsError(try harness.store.resolveReplay(
            envelope: changedEnvelope,
            detectedAt: Date(timeIntervalSince1970: 1_789_344_012.125)
        )) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try harness.writer.currentRevision(), beforeReplay)
        XCTAssertEqual(try harness.rowCounts(in: harness.context), countsBeforeReplay)
        XCTAssertEqual(
            try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
            1
        )
        let matchingRows = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>())
            .filter {
                $0.workspaceID == harness.identity.workspaceID.rawValue
                    && $0.mutationID == scenario.mutationID.rawValue
            }
        XCTAssertEqual(matchingRows.count, 1)
        let storedOriginal = try XCTUnwrap(matchingRows.first)
        XCTAssertEqual(storedOriginal.envelopeData, envelopeBytes)
        XCTAssertEqual(storedOriginal.receiptData, try receipt.canonicalData())
        XCTAssertFalse(harness.context.hasChanges)
        XCTAssertThrowsError(try harness.store.resolveReplay(
            envelope: envelope,
            detectedAt: Date(timeIntervalSince1970: 1_789_344_013.125)
        )) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
    }

    @MainActor
    func testLocalFirstSignRejectsInvalidGeneratedClockWithoutCanonicalEffect() throws {
        let invalidInstants = [
            Date(timeIntervalSince1970: .nan),
            Date(timeIntervalSince1970: .infinity),
            Date(timeIntervalSince1970: 10_000_000_000_000),
        ]
        for clockInstant in invalidInstants {
            let harness = try FirstSignReceiptClockHarness(clockInstant: clockInstant)
            defer { harness.removeFiles() }
            let scenario = try harness.makeScenario()
            let before = try harness.writer.currentRevision()

            XCTAssertThrowsError(
                try harness.writer.execute(scenario.request)
            ) { error in
                XCTAssertEqual(
                    error as? WorkspaceMutationFailureV1,
                    .invalidCommand
                )
            }
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(
                try harness.rowCounts(in: harness.context),
                FirstSignReceiptClockHarness.RowCounts(
                    sites: 0,
                    assets: 0,
                    placements: 0,
                    receipts: 0,
                    entityRevisions: 0
                )
            )
            XCTAssertNil(try harness.store.receipt(mutationID: scenario.mutationID))
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    @MainActor
    private func assertLocationRowExposesFractionalClockPremise(_ occurredAt: Date) throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let siteID = UUID()
        let event = try AssetPlacementEventV1(
            id: UUID(),
            workspaceID: workspaceID,
            assetID: UUID(),
            siteID: siteID,
            locationNodeID: nil,
            predecessorEventID: nil,
            source: .manual,
            physicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID()),
            continuity: .samePhysicalInstallation,
            pathSnapshot: LocationPathSnapshotV1(
                siteID: siteID,
                siteDisplay: "Fractional clock premise",
                nodes: []
            ),
            mutationID: MutationIDV1(rawValue: UUID()),
            occurredAt: occurredAt
        )
        let canonicalData = try LocationPersistenceCodecV1.encode(event)
        let decoded = try LocationPersistenceCodecV1.decode(
            AssetPlacementEventV1.self,
            from: canonicalData
        )
        XCTAssertNotEqual(decoded.occurredAt, occurredAt)
        XCTAssertEqual(
            try LocationPersistenceCodecV1.encode(decoded),
            canonicalData
        )

        let row = try AssetPlacementEventRow(event)
        XCTAssertThrowsError(try row.value()) { error in
            XCTAssertEqual(error as? LocationContractFailureV1, .digestMismatch)
        }
    }

    private static func quantized(_ value: Date) -> Date {
        let milliseconds = (value.timeIntervalSince1970 * 1_000)
            .rounded(.toNearestOrAwayFromZero)
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func assertPortableRevision(
        _ actual: WorkspaceRevisionV1,
        equals expected: WorkspaceRevisionV1,
        absentIsZero: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.workspaceID, expected.workspaceID, file: file, line: line)
        XCTAssertEqual(actual.generationID, expected.generationID, file: file, line: line)
        XCTAssertEqual(actual.revision, expected.revision, file: file, line: line)
        if absentIsZero {
            let actualByIdentity = Dictionary(uniqueKeysWithValues: actual.entityRevisions.map { ($0.identity, $0.revision) })
            let expectedByIdentity = Dictionary(uniqueKeysWithValues: expected.entityRevisions.map { ($0.identity, $0.revision) })
            for identity in Set(actualByIdentity.keys).union(expectedByIdentity.keys) {
                XCTAssertEqual(actualByIdentity[identity, default: 0], expectedByIdentity[identity, default: 0], file: file, line: line)
            }
        } else {
            XCTAssertEqual(actual.entityRevisions, expected.entityRevisions, file: file, line: line)
        }
    }
}

@MainActor
private final class FirstSignReceiptClockHarness {
    struct Scenario {
        let command: WorkspaceCommandV1
        let request: WorkspaceMutationRequestV1
        let mutationID: MutationIDV1
        let placementEventID: UUID
        let physicalEpisodeID: PhysicalPlacementEpisodeIDV1
        let createdAt: Date
    }

    struct RowCounts: Equatable {
        let sites: Int
        let assets: Int
        let placements: Int
        let receipts: Int
        let entityRevisions: Int
    }

    let root: URL
    let container: ModelContainer
    let context: ModelContext
    let registry: GenerationLeaseRegistryV1
    let fence: StaleWriterFenceV1
    let identity: WorkspaceReplicaIdentityV1
    let generationID: UUID
    let store: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    let clock: FirstSignReceiptClock

    init(clockInstant: Date, workspaceID: WorkspaceID? = nil) throws {
        clock = FirstSignReceiptClock(instant: clockInstant)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-first-sign-receipt-clock-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let release = PersistentSchemaReleaseRegistryV1.activeReleaseDescriptor
        let schema = Schema(release.models, version: release.versionIdentifier)
        container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "FirstSignReceiptClock",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        context = container.mainContext
        context.autosaveEnabled = false
        identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID ?? WorkspaceID(rawValue: UUID()),
            replicaID: ReplicaID(rawValue: UUID())
        )
        generationID = UUID()
        let epoch = try GenerationEpochV1(
            generationID: generationID,
            generationManifestSHA256: String(repeating: "a", count: 64)
        )
        registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let lease = try registry.acquire(epoch: epoch, role: .writer)
        fence = try StaleWriterFenceV1(
            expectedGenerationEpoch: epoch,
            writerLeaseToken: lease,
            registry: registry,
            currentGenerationEpoch: { epoch }
        )
        store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID,
            staleWriterFence: fence
        )
        let writerInstanceID = UUID()
        writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: store.currentRevision(
                writerInstanceID: writerInstanceID
            ),
            clock: clock,
            idSource: FirstSignReceiptIDs(value: writerInstanceID),
            fileAuthority: FirstSignReceiptFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
    }

    func makeScenario(
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000.375)
    ) throws -> Scenario {
        let siteID = UUID()
        let mutationID = try MutationIDV1(rawValue: UUID())
        let placementEventID = UUID()
        let physicalEpisodeID = try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        let assetID = UUID()
        let command = WorkspaceCommandV1.createFirstSign(FirstSignMutationV1(
            siteID: siteID,
            newSite: .init(
                id: siteID,
                label: "First Sign Clock Site",
                address: "10 Clock Street",
                timeZoneID: "UTC"
            ),
            assetID: assetID,
            assetLabel: "First Sign Clock Asset",
            packID: "test.first-sign-clock",
            packSchemaVersion: 1,
            packContentVersion: 1,
            createdAt: createdAt,
            initialPlacementMutationID: mutationID,
            initialPlacementEventID: placementEventID,
            initialPhysicalEpisodeID: physicalEpisodeID
        ))
        let current = try writer.currentRevision()
        let targets = try [
            WorkspaceEntityIdentityV1(kind: .site, id: siteID),
            WorkspaceEntityIdentityV1(kind: .asset, id: assetID),
            WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: placementEventID),
        ]
        let known = Dictionary(
            uniqueKeysWithValues: current.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: targets.map {
                WorkspaceEntityRevisionV1(
                    identity: $0,
                    revision: known[$0, default: 0]
                )
            }
        )
        return Scenario(
            command: command,
            request: WorkspaceMutationRequestV1(
                mutationID: mutationID,
                expectedRevision: expected,
                command: command
            ),
            mutationID: mutationID,
            placementEventID: placementEventID,
            physicalEpisodeID: physicalEpisodeID,
            createdAt: createdAt
        )
    }

    func reopen() throws -> (
        context: ModelContext,
        store: MutationJournalStoreV1,
        writer: WorkspaceWriterV1
    ) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID,
            allowStateBootstrap: false,
            staleWriterFence: fence
        )
        let writerInstanceID = UUID()
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: store.currentRevision(
                writerInstanceID: writerInstanceID
            ),
            clock: clock,
            idSource: FirstSignReceiptIDs(value: writerInstanceID),
            fileAuthority: FirstSignReceiptFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
        return (context, store, writer)
    }

    func rowCounts(in context: ModelContext) throws -> RowCounts {
        RowCounts(
            sites: try context.fetchCount(FetchDescriptor<Site>()),
            assets: try context.fetchCount(FetchDescriptor<Asset>()),
            placements: try context.fetchCount(
                FetchDescriptor<AssetPlacementEventRow>()
            ),
            receipts: try context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            entityRevisions: try context.fetchCount(
                FetchDescriptor<EntityMutationRevisionRow>()
            )
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct FirstSignReceiptClock: ApplicationClock {
    let instant: Date

    func now() -> Date {
        instant
    }
}

private struct FirstSignReceiptIDs: ApplicationIDSource {
    let value: UUID

    func makeID() -> UUID {
        value
    }
}

private struct FirstSignReceiptFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "first-sign-receipt-clock/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23PartsStockReplacementHistoryTests: XCTestCase {
    fileprivate typealias Projector = PartsStockReplacementHistoryProjectionV1

    @MainActor
    func testPublicReplacementAndColdReadbackPreserveEmptyIncomingOverEmptyStock() async throws {
        try await assertPublicEmptyIncomingReplacement(
            name: "empty-empty",
            seedCurrentStock: false,
            restoreOffset: 31
        )
    }

    @MainActor
    func testPublicReplacementAndColdReadbackRemoveNonemptyCurrentStockForEmptyIncoming() async throws {
        try await assertPublicEmptyIncomingReplacement(
            name: "nonempty-empty",
            seedCurrentStock: true,
            restoreOffset: 32
        )
    }

    @MainActor
    func testPublicReplacementAndColdReadbackPreserveMixedIncomingOriginalHistory() async throws {
        let source = try publicReplacementStep("create-source") {
            try V906Integration.makeHarness("c55-mixed-source", withAsset: false)
        }
        registerPublicFixtureCleanup(source)
        let target = try publicReplacementStep("create-target") {
            try V906Integration.makeHarness("c55-mixed-target", withAsset: false)
        }
        registerPublicFixtureCleanup(target)

        let sourceHistory = try publicReplacementStep("seed-incoming-mixed") {
            try seedIncomingMixedHistory(in: source.session, slot: 1_300)
        }
        let sourceSnapshot = try PartsStockLifecycleAdapterV1(
            modelContext: source.session.modelContext
        ).snapshotForBackup(workspaceID: source.session.workspaceIdentity.workspaceID)
        let sourceEnvelopes = try sourceHistory.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }
        XCTAssertEqual(sourceEnvelopes.first?.commandKind, .createFirstSign)
        XCTAssertEqual(sourceEnvelopes.filter {
            $0.commandKind == .applyPartyAccountability
        }.count, 1)
        XCTAssertEqual(sourceEnvelopes.filter {
            $0.commandKind == .applyWorkPacket
        }.count, 1)
        let sourceStockHistoryCount = sourceEnvelopes.filter {
            $0.commandKind == .applyWorkResource || $0.commandKind == .applyPartsStock
        }.count
        XCTAssertEqual(sourceStockHistoryCount, 5)
        XCTAssertEqual(sourceHistory.receipts.count, 8)
        XCTAssertEqual(sourceSnapshot.parts.count, 1)
        XCTAssertEqual(sourceSnapshot.locations.count, 1)
        XCTAssertEqual(sourceSnapshot.movements.count, 2)
        XCTAssertEqual(sourceSnapshot.uses.count, 1)

        try publicReplacementStep("seed-current-stock") {
            try seedCurrentPart(in: target.session, slot: 1_400)
        }
        let archive = try publicReplacementStep("export") {
            try V906Integration.exportStreaming(source)
        }
        let restoredGenerationID: UUID
        let restoredHistory: MutationHistorySnapshotV1
        do {
            let restored = try await publicReplacementAsyncStep("restore") {
                try await V906Integration.restore(
                    archive,
                    into: target,
                    mode: .replaceExisting,
                    ids: V906Integration.restoreIDs(.replaceExisting, offset: 33)
                )
            }
            restoredGenerationID = restored.generationID
            restoredHistory = try assertMixedReplacement(
                in: restored,
                sourceHistory: sourceHistory,
                sourceWorkspaceID: source.session.workspaceIdentity.workspaceID,
                sourceStockHistoryCount: sourceStockHistoryCount
            )
        }

        let reopened = try publicReplacementStep("cold-open") {
            try target.factory.openOrBootstrapCurrent()
        }
        XCTAssertEqual(reopened.generationID, restoredGenerationID)
        XCTAssertEqual(
            try assertMixedReplacement(
                in: reopened,
                sourceHistory: sourceHistory,
                sourceWorkspaceID: source.session.workspaceIdentity.workspaceID,
                sourceStockHistoryCount: sourceStockHistoryCount
            ),
            restoredHistory
        )
    }

    @MainActor
    func testCurrentRecordsProjectEmptyAndNonemptyC55SnapshotsWithoutWritesAndRejectForeignRows() throws {
        let harness = try V906Integration.makeHarness("c55-current-records", withAsset: false)
        registerPublicFixtureCleanup(harness)
        let service = try BackupRestoreService(applicationSupportURL: harness.support)
        let journal = try MutationJournalStoreV1(
            modelContext: harness.session.modelContext,
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            allowStateBootstrap: false
        )

        XCTAssertFalse(harness.session.modelContext.hasChanges)
        let beforeEmptyRead = try journal.exportSnapshot()
        let empty = try service.c55CurrentRecordsForTesting(
            in: harness.session.modelContext
        )
        let emptySnapshot = try XCTUnwrap(empty.partsStockSnapshot)
        XCTAssertEqual(emptySnapshot.workspaceID, harness.session.workspaceIdentity.workspaceID)
        XCTAssertTrue(emptySnapshot.parts.isEmpty)
        XCTAssertTrue(emptySnapshot.locations.isEmpty)
        XCTAssertTrue(emptySnapshot.movements.isEmpty)
        XCTAssertTrue(emptySnapshot.uses.isEmpty)
        XCTAssertTrue(emptySnapshot.reversals.isEmpty)
        XCTAssertTrue(emptySnapshot.returns.isEmpty)
        XCTAssertTrue(emptySnapshot.abandonments.isEmpty)
        XCTAssertNotNil(empty.deletionLedger)
        XCTAssertNotNil(empty.mutationHistory)
        XCTAssertEqual(try journal.exportSnapshot(), beforeEmptyRead)
        XCTAssertFalse(harness.session.modelContext.hasChanges)
        let noHistory = try service.c55CurrentRecordsForTesting(
            in: harness.session.modelContext,
            includingDeletionLedger: false
        )
        XCTAssertNil(noHistory.deletionLedger)
        XCTAssertNil(noHistory.mutationHistory)
        XCTAssertNil(noHistory.partsStockSnapshot)
        XCTAssertEqual(try journal.exportSnapshot(), beforeEmptyRead)
        XCTAssertFalse(harness.session.modelContext.hasChanges)

        try seedCurrentPart(in: harness.session, slot: 1_700)
        XCTAssertFalse(harness.session.modelContext.hasChanges)
        let beforeNonemptyRead = try journal.exportSnapshot()
        let nonempty = try service.c55CurrentRecordsForTesting(
            in: harness.session.modelContext
        )
        let nonemptySnapshot = try XCTUnwrap(nonempty.partsStockSnapshot)
        XCTAssertEqual(nonemptySnapshot.workspaceID, harness.session.workspaceIdentity.workspaceID)
        XCTAssertEqual(nonemptySnapshot.parts.count, 1)
        XCTAssertTrue(nonemptySnapshot.locations.isEmpty)
        XCTAssertEqual(try journal.exportSnapshot(), beforeNonemptyRead)
        XCTAssertFalse(harness.session.modelContext.hasChanges)

        let hostile = try V906Integration.makeHarness("c55-current-records-foreign", withAsset: false)
        registerPublicFixtureCleanup(hostile)
        let foreignWorkspaceID = WorkspaceID(rawValue: V906Integration.id(1_750))
        let foreignPart = try Fixture.part(
            foreignWorkspaceID,
            slot: 1_751,
            mutationID: try MutationIDV1(rawValue: V906Integration.id(1_752))
        )
        hostile.session.modelContext.insert(try LocalPartDefinitionRowV1(foreignPart))
        XCTAssertTrue(hostile.session.modelContext.hasChanges)
        let hostileService = try BackupRestoreService(applicationSupportURL: hostile.support)
        XCTAssertThrowsError(try hostileService.c55CurrentRecordsForTesting(
            in: hostile.session.modelContext
        ))
        XCTAssertTrue(hostile.session.modelContext.hasChanges)
        let retainedForeignRows = try hostile.session.modelContext.fetch(
            FetchDescriptor<LocalPartDefinitionRowV1>()
        )
        XCTAssertEqual(retainedForeignRows.count, 1)
        XCTAssertEqual(retainedForeignRows.first?.workspaceUUID, foreignWorkspaceID.rawValue)
        hostile.session.modelContext.rollback()
        XCTAssertFalse(hostile.session.modelContext.hasChanges)
        XCTAssertEqual(try hostile.session.modelContext.fetchCount(
            FetchDescriptor<LocalPartDefinitionRowV1>()
        ), 0)
    }

    @MainActor
    func testDeletionWinningPlanAcceptsDeclaredC55SchemasAndRejectsMalformedAuthority() throws {
        let source = try V906Integration.makeHarness("c55-schema-source", withAsset: false)
        registerPublicFixtureCleanup(source)
        let target = try V906Integration.makeHarness("c55-schema-target", withAsset: false)
        registerPublicFixtureCleanup(target)
        try seedCurrentPart(in: target.session, slot: 1_800)

        let sourceRecords = try BackupRestoreService(applicationSupportURL: source.support)
            .c55CurrentRecordsForTesting(in: source.session.modelContext)
        let targetRecords = try BackupRestoreService(applicationSupportURL: target.support)
            .c55CurrentRecordsForTesting(in: target.session.modelContext)
        XCTAssertTrue(try XCTUnwrap(sourceRecords.partsStockSnapshot).parts.isEmpty)
        XCTAssertEqual(try XCTUnwrap(targetRecords.partsStockSnapshot).parts.count, 1)

        let declaredSchemas = [
            C04ShopReportProfileBackupEnrollmentV1.recordsSchemaVersion,
            C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion,
            C08ImportBulkBackupEnrollmentV1.legacyRecordsSchemaVersion,
            C08ImportBulkBackupEnrollmentV1.recordsSchemaVersion,
            FastSurveyInboxBackupEnrollmentV1.recordsSchemaVersion,
            ReinspectionExceptionQueueBackupEnrollmentV1.recordsSchemaVersion,
            EntityIdentityResolutionBackupEnrollmentV1.recordsSchemaVersion,
            PracticeWorkspaceBackupEnrollmentV1.recordsSchemaVersion,
            LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion,
            LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,
        ]
        XCTAssertEqual(declaredSchemas, Array(43...52))
        for schema in declaredSchemas {
            let current = try replacingRecordAuthority(
                in: targetRecords,
                recordsSchemaVersion: schema
            )
            let plan = try ReplacementRestoreRule.makeDeletionWinningPlan(.init(
                currentRecords: current,
                currentIdentity: target.session.workspaceIdentity,
                incomingRecords: sourceRecords,
                incomingIdentity: source.session.workspaceIdentity,
                mode: .replaceExisting,
                replacementAt: Fixture.fixedDate.addingTimeInterval(10_000)
            ))
            XCTAssertEqual(plan.recordsAfter.partsStockSnapshot, sourceRecords.partsStockSnapshot,
                           "schema \(schema)")
        }

        let missingLedger = try replacingRecordAuthority(
            in: targetRecords,
            recordsSchemaVersion: C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion,
            deletionLedger: .omitted
        )
        assertInvalidReplacementPlan(
            current: missingLedger, incoming: sourceRecords, target: target, source: source
        )
        let missingHistory = try replacingRecordAuthority(
            in: targetRecords,
            recordsSchemaVersion: C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion,
            mutationHistory: .omitted
        )
        assertInvalidReplacementPlan(
            current: missingHistory, incoming: sourceRecords, target: target, source: source
        )
        let missingC55 = try replacingRecordAuthority(
            in: targetRecords,
            recordsSchemaVersion: C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion,
            partsStockSnapshot: .omitted
        )
        assertInvalidReplacementPlan(
            current: missingC55, incoming: sourceRecords, target: target, source: source
        )
        let foreignSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: source.session.workspaceIdentity.workspaceID,
            parts: [], locations: [], movements: [], uses: [], reversals: [], returns: [],
            abandonments: []
        )
        let foreignC55 = try replacingRecordAuthority(
            in: targetRecords,
            recordsSchemaVersion: C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion,
            partsStockSnapshot: .value(foreignSnapshot)
        )
        assertInvalidReplacementPlan(
            current: foreignC55, incoming: sourceRecords, target: target, source: source
        )
        let future = try replacingRecordAuthority(in: targetRecords, recordsSchemaVersion: 53)
        assertInvalidReplacementPlan(
            current: future, incoming: sourceRecords, target: target, source: source
        )
    }

    @MainActor
    func testActorSnapshotRequiresExistingPartyButAcceptsExplicitUnlinkedActor() throws {
        let harness = try V906Integration.makeHarness("c55-actor-party", withAsset: false)
        registerPublicFixtureCleanup(harness)
        let journal = try MutationJournalStoreV1(
            modelContext: harness.session.modelContext,
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            allowStateBootstrap: false
        )
        let writerID = V906Integration.id(1_900)
        let writer = try WorkspaceWriterV1(
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerID),
            clock: ReplacementClock(),
            idSource: ReplacementIDs(start: 1_910),
            fileAuthority: ReplacementFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: harness.session.modelContext),
            journalStore: journal
        )
        let before = try journal.exportSnapshot()
        let linked = try Fixture.actor(
            harness.session.workspaceIdentity.workspaceID,
            slot: 1_920
        )
        XCTAssertNotNil(linked.actor.partyID)
        XCTAssertThrowsError(try writer.execute(
            .applyPartyAccountability(.appendActorSnapshot(linked)),
            mutationID: try MutationIDV1(rawValue: V906Integration.id(1_921))
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try journal.exportSnapshot(), before)
        XCTAssertNil(try journal.receipt(
            mutationID: try MutationIDV1(rawValue: V906Integration.id(1_921))
        ))
        XCTAssertEqual(
            try harness.session.modelContext.fetchCount(FetchDescriptor<ActorSnapshotRow>()), 0
        )
        XCTAssertEqual(
            try harness.session.modelContext.fetchCount(FetchDescriptor<ServicePartyRow>()), 0
        )
        XCTAssertFalse(harness.session.modelContext.hasChanges)

        let unlinked = try Fixture.actor(
            harness.session.workspaceIdentity.workspaceID,
            slot: 1_930,
            includesPartyReference: false
        )
        XCTAssertNil(unlinked.actor.partyID)
        let mutationID = try MutationIDV1(rawValue: V906Integration.id(1_931))
        let outcome = try writer.execute(
            .applyPartyAccountability(.appendActorSnapshot(unlinked)), mutationID: mutationID
        )
        XCTAssertEqual(outcome.mutationID, mutationID)
        XCTAssertEqual(try XCTUnwrap(journal.receipt(mutationID: mutationID)).mutationID, mutationID)
        let history = try journal.exportSnapshot()
        XCTAssertEqual(history.receipts.count, 1)
        XCTAssertEqual(
            try MutationEnvelopeV1.decodeCanonical(
                from: try XCTUnwrap(history.receipts.first).envelopeData
            ).commandKind,
            .applyPartyAccountability
        )
        let actorRows = try harness.session.modelContext.fetch(FetchDescriptor<ActorSnapshotRow>())
        XCTAssertEqual(actorRows.count, 1)
        XCTAssertEqual(try XCTUnwrap(actorRows.first).value(), unlinked)
        XCTAssertEqual(
            try harness.session.modelContext.fetchCount(FetchDescriptor<ServicePartyRow>()), 0
        )
        XCTAssertFalse(harness.session.modelContext.hasChanges)
    }

    func testAlternatingC49C55ProjectionIsDeterministicAndRetainsUnrelatedCurrentWork() throws {
        let fixture = try Fixture.make()
        let requirements = try Projector.requirements(
            incomingSnapshot: fixture.incoming.snapshot,
            incomingHistory: fixture.incoming.history,
            incomingWorkResources: fixture.incoming.workResources
        )
        XCTAssertEqual(requirements.replicas.count, 2)
        let incomingReceiptMutationIDs = Set(try fixture.incoming.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).mutationID
        })
        XCTAssertEqual(
            Set(requirements.mutationIDs).subtracting(incomingReceiptMutationIDs),
            Set([fixture.unarchivedBaselineMutationID])
        )
        let input = try fixture.input(requirements: requirements)
        let first = try Projector.project(input)
        let second = try Projector.project(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.sourceSnapshotSHA256, fixture.incoming.snapshot.snapshotSHA256)
        XCTAssertEqual(first.targetSnapshot.workspaceID, fixture.targetWorkspaceID)
        XCTAssertNotEqual(first.targetSnapshot.snapshotSHA256, first.sourceSnapshotSHA256)
        XCTAssertEqual(
            Set(first.workResources.map(\.entryID)),
            Set(fixture.incoming.workResources.map(\.entryID))
                .union([fixture.retainedCurrentEntry.entryID])
        )
        XCTAssertEqual(
            first.workResources.first(where: {
                $0.entryID == fixture.retainedCurrentEntry.entryID
            }),
            fixture.retainedCurrentEntry
        )
        XCTAssertTrue(Set(first.workResources.map(\.entryID))
            .isDisjoint(with: fixture.removedCurrentEntryIDs))
        XCTAssertTrue(first.workResources.allSatisfy {
            $0.workspaceID == fixture.targetWorkspaceID
        })
        XCTAssertEqual(first.targetSnapshot.parts.count, 2)
        XCTAssertEqual(first.targetSnapshot.locations.count, 1)
        XCTAssertEqual(first.targetSnapshot.movements.count, 5)
        XCTAssertEqual(first.targetSnapshot.uses.count, 2)
        XCTAssertEqual(first.targetSnapshot.reversals.count, 1)
        XCTAssertEqual(first.targetSnapshot.returns.count, 1)
        XCTAssertEqual(first.targetSnapshot.abandonments.count, 1)
        XCTAssertEqual(first.targetSnapshot.uses[0].workResourceSuccessor.supersedesEntryID,
                       fixture.firstIncomingEntry.entryID)
        XCTAssertNotEqual(first.targetSnapshot.uses[0].workResourceSuccessor.supersedesEntrySHA256,
                          fixture.firstIncomingEntry.entrySHA256)
        XCTAssertEqual(first.targetSnapshot.uses[1].workResourceSuccessor.supersedesEntryID,
                       fixture.secondIncomingEntry.entryID)
        XCTAssertNotEqual(first.targetSnapshot.uses[1].workResourceSuccessor.supersedesEntrySHA256,
                          fixture.secondIncomingEntry.entrySHA256)

        let targetReceipts = try first.history.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
        }
        let targetEnvelopes = try first.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }
        let activeTargetReceipts = zip(targetEnvelopes, targetReceipts).compactMap {
            $0.0.workspaceID == fixture.targetWorkspaceID ? $0.1 : nil
        }
        let activeTargetEnvelopes = targetEnvelopes.filter {
            $0.workspaceID == fixture.targetWorkspaceID
        }
        let sourceReplicas = Set(try fixture.incoming.history.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData).identity.replicaID
        })
        let projectedTargetReplicas = Set(targetReceipts
            .prefix(fixture.incoming.history.receipts.count)
            .map(\.identity.replicaID))
        XCTAssertEqual(sourceReplicas.count, 2)
        XCTAssertEqual(projectedTargetReplicas.count, 2)
        XCTAssertTrue(sourceReplicas.isDisjoint(with: projectedTargetReplicas))
        XCTAssertTrue(Set(targetEnvelopes.map(\.mutationID))
            .isDisjoint(with: fixture.removedCurrentMutationIDs))
        XCTAssertTrue(activeTargetReceipts.allSatisfy {
            $0.identity.workspaceID == fixture.targetWorkspaceID
                && $0.resultingRevision.workspaceID == fixture.targetWorkspaceID
                && $0.resultingRevision.generationID == fixture.targetGenerationID
        })
        XCTAssertTrue(fixture.incoming.history.receipts.allSatisfy {
            first.history.receipts.contains($0)
        })
        XCTAssertEqual(
            activeTargetEnvelopes.map(\.commandKind).filter {
                $0 == .applyWorkResource || $0 == .applyPartsStock
            },
            [
                .applyPartsStock, .applyPartsStock, .applyPartsStock,
                .applyWorkResource, .applyPartsStock,
                .applyPartsStock, .applyWorkResource,
                .applyPartsStock, .applyPartsStock,
                .applyPartsStock,
                .applyWorkResource,
            ]
        )
        for envelope in activeTargetEnvelopes where envelope.commandKind == .applyWorkResource {
            XCTAssertEqual(envelope.expectedRevision.entityRevisions.count, 1)
        }
        XCTAssertEqual(first.history.workspaceRevision, UInt64(activeTargetReceipts.count))
        XCTAssertEqual(first.history.lastLocalSequence, 0)
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(first.history))

        let mutationMap = Dictionary(uniqueKeysWithValues: input.mutationBindings.map {
            ($0.source, $0.target)
        })
        let mappedTargetID = try XCTUnwrap(mutationMap[fixture.semanticTargetMutationID])
        let mappedReversalID = try XCTUnwrap(mutationMap[fixture.semanticReversalMutationID])
        let targetRecord = try XCTUnwrap(zip(targetEnvelopes, first.history.receipts).first {
            $0.0.mutationID == mappedTargetID
        }?.1)
        let reversalRecord = try XCTUnwrap(zip(targetEnvelopes, first.history.receipts).first {
            $0.0.mutationID == mappedReversalID
        }?.1)
        let targetBasis = try ReversalBasisV1.decodeCanonical(
            from: try XCTUnwrap(targetRecord.reversalBasisData)
        )
        let sourceRecord = try XCTUnwrap(fixture.incoming.history.receipts.first { record in
            try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData).mutationID
                == fixture.semanticTargetMutationID
        })
        let sourceBasis = try ReversalBasisV1.decodeCanonical(
            from: try XCTUnwrap(sourceRecord.reversalBasisData)
        )
        let targetSemantic = try SemanticReversalReceiptV1.decodeCanonical(
            from: try XCTUnwrap(reversalRecord.semanticReversalData)
        )
        XCTAssertEqual(targetBasis.targetMutationID, mappedTargetID)
        XCTAssertEqual(targetBasis.targetReceiptIdentity.workspaceID, fixture.targetWorkspaceID)
        XCTAssertEqual(targetBasis.compensatingCommandKinds, [.applyPartsStock])
        XCTAssertEqual(targetBasis.planDigest, sourceBasis.planDigest)
        XCTAssertNotEqual(try targetBasis.canonicalSHA256(), try sourceBasis.canonicalSHA256())
        XCTAssertEqual(targetSemantic.reversesMutationID, mappedTargetID)
        XCTAssertEqual(targetSemantic.compensatingMutationIDs, [mappedReversalID])
        XCTAssertEqual(
            targetSemantic.reversalBasisSHA256,
            try targetBasis.canonicalSHA256()
        )
        let mappedReversalEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: reversalRecord.envelopeData
        )
        XCTAssertEqual(mappedReversalEnvelope.semanticReversalExecution?.targetMutationID,
                       mappedTargetID)
        XCTAssertEqual(mappedReversalEnvelope.semanticReversalExecution?.compensatingMutationIDs,
                       [mappedReversalID])
        XCTAssertEqual(first.history.quarantines.count, 2)
        let targetQuarantine = try XCTUnwrap(first.history.quarantines.first {
            $0.workspaceID == fixture.targetWorkspaceID
        })
        XCTAssertEqual(targetQuarantine.mutationID, mappedReversalID.rawValue)
        XCTAssertEqual(
            targetQuarantine.acceptedIdentitySHA256,
            mappedReversalEnvelope.semanticReversalReplayIdentitySHA256
        )
    }

    func testReceiptIdentityExportOrderAndShuffleUseGlobalRevisionOrder() throws {
        let fixture = try Fixture.make()
        let requirements = try Projector.requirements(
            incomingSnapshot: fixture.incoming.snapshot,
            incomingHistory: fixture.incoming.history,
            incomingWorkResources: fixture.incoming.workResources
        )
        let base = try fixture.input(requirements: requirements)
        let expected = try Projector.project(base)
        let byReceiptIdentity = try fixture.incoming.history.receipts.map { record in
            (
                record,
                try MutationReceiptV1.decodeCanonical(from: record.receiptData)
                    .identity.stableKey
            )
        }.sorted { $0.1 < $1.1 }.map(\.0)
        XCTAssertNotEqual(byReceiptIdentity, fixture.incoming.history.receipts)

        for receipts in [byReceiptIdentity, Array(byReceiptIdentity.reversed())] {
            let incoming = MutationHistorySnapshotV1(
                workspaceRevision: fixture.incoming.history.workspaceRevision,
                lastLocalSequence: fixture.incoming.history.lastLocalSequence,
                receipts: receipts,
                quarantines: fixture.incoming.history.quarantines,
                entityRevisions: fixture.incoming.history.entityRevisions
            )
            XCTAssertEqual(
                try Projector.project(replacingIncomingHistory(in: base, with: incoming)),
                expected
            )
        }

        var brokenReceipts = byReceiptIdentity
        brokenReceipts.remove(at: brokenReceipts.count / 2)
        let broken = MutationHistorySnapshotV1(
            workspaceRevision: fixture.incoming.history.workspaceRevision,
            lastLocalSequence: fixture.incoming.history.lastLocalSequence,
            receipts: brokenReceipts,
            quarantines: fixture.incoming.history.quarantines,
            entityRevisions: fixture.incoming.history.entityRevisions
        )
        XCTAssertThrowsError(try Projector.requirements(
            incomingSnapshot: fixture.incoming.snapshot,
            incomingHistory: broken,
            incomingWorkResources: fixture.incoming.workResources
        )) {
            XCTAssertEqual(
                $0 as? WorkspaceMutationFailureV1,
                .receiptHistoryCorrupt
            )
        }
    }

    func testForeignRawMutationIDCollisionUsesActiveSourceKindAndPreservesRecord() throws {
        let fixture = try Fixture.make()
        let foreignWorkspaceID = WorkspaceID(rawValue: Fixture.id(950))
        let foreignReplica = try WorkspaceReplicaIdentityV1(
            workspaceID: foreignWorkspaceID,
            replicaID: ReplicaID(rawValue: Fixture.id(951))
        )
        let collidingMutationID = fixture.semanticTargetMutationID
        let foreignHistory = try Fixture.history(
            commands: [.createFirstSign(.init(
                siteID: Fixture.id(952),
                newSite: .init(
                    id: Fixture.id(952),
                    label: "Retained foreign site",
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: Fixture.id(953),
                assetLabel: "Retained foreign sign",
                packID: "foreign.history.fixture",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: Fixture.fixedDate,
                initialPlacementMutationID: collidingMutationID,
                initialPlacementEventID: Fixture.id(956),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                    rawValue: Fixture.id(957)
                )
            ))],
            identities: [foreignReplica],
            generationID: Fixture.id(954),
            writerID: Fixture.id(955),
            explicitMutationIDs: [0: collidingMutationID]
        )
        let combined = MutationHistorySnapshotV1(
            workspaceRevision: max(
                fixture.incoming.history.workspaceRevision,
                foreignHistory.workspaceRevision
            ),
            lastLocalSequence: max(
                fixture.incoming.history.lastLocalSequence,
                foreignHistory.lastLocalSequence
            ),
            receipts: fixture.incoming.history.receipts + foreignHistory.receipts,
            quarantines: fixture.incoming.history.quarantines + foreignHistory.quarantines,
            entityRevisions: fixture.incoming.history.entityRevisions
                + foreignHistory.entityRevisions
        )
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(combined))

        let activeKinds = try BackupRestoreService
            .sourceCommandKindsForPartsStockReplacement(
                combined,
                sourceWorkspaceID: fixture.sourceWorkspaceID
            )
        XCTAssertEqual(activeKinds[collidingMutationID.rawValue], .applyPartsStock)
        XCTAssertEqual(activeKinds.count, fixture.incoming.history.receipts.count)

        let requirements = try Projector.requirements(
            incomingSnapshot: fixture.incoming.snapshot,
            incomingHistory: combined,
            incomingWorkResources: fixture.incoming.workResources
        )
        let base = try fixture.input(requirements: requirements)
        let result = try Projector.project(
            replacingIncomingHistory(in: base, with: combined)
        )
        XCTAssertTrue(foreignHistory.receipts.allSatisfy {
            result.history.receipts.contains($0)
        })
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(result.history))
    }

    func testOriginalMembershipAndBindingHostilesFailBeforeProjection() throws {
        let fixture = try Fixture.make()
        let requirements = try Projector.requirements(
            incomingSnapshot: fixture.incoming.snapshot,
            incomingHistory: fixture.incoming.history,
            incomingWorkResources: fixture.incoming.workResources
        )
        let valid = try fixture.input(requirements: requirements)

        var missing = valid.mutationBindings
        missing.removeLast()
        XCTAssertThrowsError(try Projector.project(.init(
            currentSnapshot: valid.currentSnapshot,
            incomingSnapshot: valid.incomingSnapshot,
            currentHistory: valid.currentHistory,
            incomingHistory: valid.incomingHistory,
            plannedHistory: valid.plannedHistory,
            currentWorkResources: valid.currentWorkResources,
            incomingWorkResources: valid.incomingWorkResources,
            plannedWorkResources: valid.plannedWorkResources,
            targetWorkspaceID: valid.targetWorkspaceID,
            targetGenerationID: valid.targetGenerationID,
            writerInstanceID: valid.writerInstanceID,
            mutationBindings: missing,
            subjectBindings: valid.subjectBindings,
            replicaBindings: valid.replicaBindings
        ))) { XCTAssertEqual($0 as? PartsStockReplacementHistoryProjectionFailureV1, .invalidBinding) }

        let collision = Projector.MutationBinding(
            source: requirements.mutationIDs[0],
            target: fixture.retainedCurrentMutationID
        )
        var colliding = valid.mutationBindings
        colliding[0] = collision
        XCTAssertThrowsError(try Projector.project(.init(
            currentSnapshot: valid.currentSnapshot,
            incomingSnapshot: valid.incomingSnapshot,
            currentHistory: valid.currentHistory,
            incomingHistory: valid.incomingHistory,
            plannedHistory: valid.plannedHistory,
            currentWorkResources: valid.currentWorkResources,
            incomingWorkResources: valid.incomingWorkResources,
            plannedWorkResources: valid.plannedWorkResources,
            targetWorkspaceID: valid.targetWorkspaceID,
            targetGenerationID: valid.targetGenerationID,
            writerInstanceID: valid.writerInstanceID,
            mutationBindings: colliding,
            subjectBindings: valid.subjectBindings,
            replicaBindings: valid.replicaBindings
        ))) { XCTAssertEqual($0 as? PartsStockReplacementHistoryProjectionFailureV1, .collision) }

        let wrongSubject = try WorkResourceSubjectV1(
            workspaceID: fixture.targetWorkspaceID,
            kind: requirements.subjects[0].kind,
            subjectID: requirements.subjects[0].subjectID,
            subjectRevision: requirements.subjects[0].subjectRevision + 1,
            subjectSHA256: Fixture.digest("f")
        )
        var subjects = valid.subjectBindings
        subjects[0] = .init(source: subjects[0].source, target: wrongSubject)
        XCTAssertThrowsError(try Projector.project(.init(
            currentSnapshot: valid.currentSnapshot,
            incomingSnapshot: valid.incomingSnapshot,
            currentHistory: valid.currentHistory,
            incomingHistory: valid.incomingHistory,
            plannedHistory: valid.plannedHistory,
            currentWorkResources: valid.currentWorkResources,
            incomingWorkResources: valid.incomingWorkResources,
            plannedWorkResources: valid.plannedWorkResources,
            targetWorkspaceID: valid.targetWorkspaceID,
            targetGenerationID: valid.targetGenerationID,
            writerInstanceID: valid.writerInstanceID,
            mutationBindings: valid.mutationBindings,
            subjectBindings: subjects,
            replicaBindings: valid.replicaBindings
        ))) { XCTAssertEqual($0 as? PartsStockReplacementHistoryProjectionFailureV1, .invalidBinding) }

        var omittedWork = valid.incomingWorkResources
        omittedWork.removeLast()
        XCTAssertThrowsError(try Projector.project(.init(
            currentSnapshot: valid.currentSnapshot,
            incomingSnapshot: valid.incomingSnapshot,
            currentHistory: valid.currentHistory,
            incomingHistory: valid.incomingHistory,
            plannedHistory: valid.plannedHistory,
            currentWorkResources: valid.currentWorkResources,
            incomingWorkResources: omittedWork,
            plannedWorkResources: valid.plannedWorkResources,
            targetWorkspaceID: valid.targetWorkspaceID,
            targetGenerationID: valid.targetGenerationID,
            writerInstanceID: valid.writerInstanceID,
            mutationBindings: valid.mutationBindings,
            subjectBindings: valid.subjectBindings,
            replicaBindings: valid.replicaBindings
        ))) { XCTAssertEqual($0 as? PartsStockReplacementHistoryProjectionFailureV1, .invalidSource) }

        var changedReceipts = valid.plannedHistory.receipts
        changedReceipts.removeLast()
        let changedPlanned = MutationHistorySnapshotV1(
            workspaceRevision: valid.plannedHistory.workspaceRevision,
            lastLocalSequence: valid.plannedHistory.lastLocalSequence,
            receipts: changedReceipts,
            quarantines: valid.plannedHistory.quarantines,
            entityRevisions: valid.plannedHistory.entityRevisions
        )
        XCTAssertThrowsError(try Projector.project(.init(
            currentSnapshot: valid.currentSnapshot,
            incomingSnapshot: valid.incomingSnapshot,
            currentHistory: valid.currentHistory,
            incomingHistory: valid.incomingHistory,
            plannedHistory: changedPlanned,
            currentWorkResources: valid.currentWorkResources,
            incomingWorkResources: valid.incomingWorkResources,
            plannedWorkResources: valid.plannedWorkResources,
            targetWorkspaceID: valid.targetWorkspaceID,
            targetGenerationID: valid.targetGenerationID,
            writerInstanceID: valid.writerInstanceID,
            mutationBindings: valid.mutationBindings,
            subjectBindings: valid.subjectBindings,
            replicaBindings: valid.replicaBindings
        ))) { XCTAssertEqual($0 as? PartsStockReplacementHistoryProjectionFailureV1, .invalidSource) }

        var missingReplica = valid.replicaBindings
        missingReplica.removeLast()
        XCTAssertThrowsError(try Projector.project(.init(
            currentSnapshot: valid.currentSnapshot,
            incomingSnapshot: valid.incomingSnapshot,
            currentHistory: valid.currentHistory,
            incomingHistory: valid.incomingHistory,
            plannedHistory: valid.plannedHistory,
            currentWorkResources: valid.currentWorkResources,
            incomingWorkResources: valid.incomingWorkResources,
            plannedWorkResources: valid.plannedWorkResources,
            targetWorkspaceID: valid.targetWorkspaceID,
            targetGenerationID: valid.targetGenerationID,
            writerInstanceID: valid.writerInstanceID,
            mutationBindings: valid.mutationBindings,
            subjectBindings: valid.subjectBindings,
            replicaBindings: missingReplica
        ))) { XCTAssertEqual($0 as? PartsStockReplacementHistoryProjectionFailureV1, .invalidBinding) }
    }

    func testIncomingOtherFamilyOriginalsAndCausalTargetHistoryArePreserved() throws {
        let fixture = try Fixture.make(
            includeIncomingOtherFamily: true,
            retainedCurrentCausation: true
        )
        let requirements = try Projector.requirements(
            incomingSnapshot: fixture.incoming.snapshot,
            incomingHistory: fixture.incoming.history,
            incomingWorkResources: fixture.incoming.workResources
        )
        let otherMutationID = try XCTUnwrap(fixture.incomingOtherFamilyMutationID)
        XCTAssertFalse(requirements.mutationIDs.contains(otherMutationID))

        let result = try Projector.project(try fixture.input(requirements: requirements))
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(result.history))

        XCTAssertTrue(fixture.incoming.history.receipts.allSatisfy {
            result.history.receipts.contains($0)
        })
        let originalOtherRecord = try XCTUnwrap(
            fixture.incoming.history.receipts.first { record in
                try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData).mutationID
                    == otherMutationID
            }
        )
        XCTAssertTrue(result.history.receipts.contains(originalOtherRecord))

        let envelopes = try result.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }
        let targetMutationID = try XCTUnwrap(fixture.retainedCausalTargetMutationID)
        let reversalMutationID = try XCTUnwrap(fixture.retainedCausalReversalMutationID)
        let target = try XCTUnwrap(envelopes.first {
            $0.workspaceID == fixture.targetWorkspaceID && $0.mutationID == targetMutationID
        })
        let reversal = try XCTUnwrap(envelopes.first {
            $0.workspaceID == fixture.targetWorkspaceID && $0.mutationID == reversalMutationID
        })
        XCTAssertEqual(reversal.causationMutationID, targetMutationID)
        XCTAssertEqual(reversal.semanticReversalExecution?.targetMutationID, targetMutationID)
        XCTAssertEqual(reversal.sourceKind, .semanticReversal)
        XCTAssertEqual(target.sourceKind, .localRecovery)
        XCTAssertNil(target.causationMutationID)
        XCTAssertTrue(Set([targetMutationID, reversalMutationID]).isDisjoint(
            with: fixture.removedCurrentMutationIDs
        ))
        let targetRecord = try XCTUnwrap(result.history.receipts.first { record in
            try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData).mutationID
                == targetMutationID
        })
        let reversalRecord = try XCTUnwrap(result.history.receipts.first { record in
            try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData).mutationID
                == reversalMutationID
        })
        let basis = try ReversalBasisV1.decodeCanonical(
            from: try XCTUnwrap(targetRecord.reversalBasisData)
        )
        let semantic = try SemanticReversalReceiptV1.decodeCanonical(
            from: try XCTUnwrap(reversalRecord.semanticReversalData)
        )
        XCTAssertEqual(basis.targetMutationID, targetMutationID)
        XCTAssertEqual(semantic.reversesMutationID, targetMutationID)
        XCTAssertEqual(semantic.compensatingMutationIDs, [reversalMutationID])
        XCTAssertEqual(semantic.reversalBasisSHA256, try basis.canonicalSHA256())
        XCTAssertEqual(
            envelopes.filter {
                $0.workspaceID == fixture.sourceWorkspaceID
                    && ($0.commandKind == .applyWorkResource
                        || $0.commandKind == .applyPartsStock)
            }.count,
            fixture.incoming.history.receipts.count - 1
        )
        XCTAssertEqual(
            envelopes.filter {
                $0.workspaceID == fixture.targetWorkspaceID
                    && ($0.commandKind == .applyWorkResource
                        || $0.commandKind == .applyPartsStock)
            }.count,
            fixture.incoming.history.receipts.count + 2
        )
    }

    private func replacingIncomingHistory(
        in base: Projector.Input,
        with incoming: MutationHistorySnapshotV1
    ) -> Projector.Input {
        let planned = MutationHistorySnapshotV1(
            workspaceRevision: max(
                base.currentHistory.workspaceRevision,
                incoming.workspaceRevision
            ),
            lastLocalSequence: max(
                base.currentHistory.lastLocalSequence,
                incoming.lastLocalSequence
            ),
            receipts: base.currentHistory.receipts + incoming.receipts,
            quarantines: base.currentHistory.quarantines + incoming.quarantines,
            entityRevisions: base.currentHistory.entityRevisions + incoming.entityRevisions
        )
        return .init(
            currentSnapshot: base.currentSnapshot,
            incomingSnapshot: base.incomingSnapshot,
            currentHistory: base.currentHistory,
            incomingHistory: incoming,
            plannedHistory: planned,
            currentWorkResources: base.currentWorkResources,
            incomingWorkResources: base.incomingWorkResources,
            plannedWorkResources: base.plannedWorkResources,
            targetWorkspaceID: base.targetWorkspaceID,
            targetGenerationID: base.targetGenerationID,
            writerInstanceID: base.writerInstanceID,
            mutationBindings: base.mutationBindings,
            subjectBindings: base.subjectBindings,
            replicaBindings: base.replicaBindings
        )
    }

    private func publicReplacementStep<T>(
        _ phase: String,
        _ operation: () throws -> T
    ) rethrows -> T {
        do {
            return try operation()
        } catch {
            reportPublicReplacementFailure(error, phase: phase)
            throw error
        }
    }

    private func publicReplacementAsyncStep<T>(
        _ phase: String,
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        do {
            return try await operation()
        } catch {
            reportPublicReplacementFailure(error, phase: phase)
            throw error
        }
    }

    private func registerPublicFixtureCleanup(_ harness: V906Integration.Harness) {
        addTeardownBlock { [weak session = harness.session, root = harness.root] in
            guard session == nil else {
                XCTFail("C55 fixture cleanup requires the original session to be released")
                return
            }
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                let observed = error as NSError
                XCTFail("C55 fixture cleanup failed type=\(String(reflecting: type(of: error))) domain=\(observed.domain) code=\(observed.code)")
            }
        }
    }

    private func reportPublicReplacementFailure(_ error: Error, phase: String) {
        let value = error as NSError
        print("C55 public failure phase=\(phase) type=\(String(reflecting: type(of: error))) domain=\(value.domain) code=\(value.code)")
    }

    private enum RecordField<Value: Encodable> {
        case unchanged
        case value(Value)
        case omitted
    }

    private func replacingRecordAuthority(
        in records: V4BackupRecordsV1,
        recordsSchemaVersion: Int,
        deletionLedger: RecordField<DeletionLedgerV2> = .unchanged,
        mutationHistory: RecordField<MutationHistorySnapshotV1> = .unchanged,
        partsStockSnapshot: RecordField<PartsStockBackupSnapshotV1> = .unchanged
    ) throws -> V4BackupRecordsV1 {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(records)) as? [String: Any]
        )
        object["recordsSchemaVersion"] = recordsSchemaVersion
        try replaceJSONField("deletionLedger", deletionLedger, in: &object, encoder: encoder)
        try replaceJSONField("mutationHistory", mutationHistory, in: &object, encoder: encoder)
        try replaceJSONField("partsStockSnapshot", partsStockSnapshot, in: &object, encoder: encoder)
        return try decoder.decode(
            V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func replaceJSONField<Value: Encodable>(
        _ key: String,
        _ replacement: RecordField<Value>,
        in object: inout [String: Any],
        encoder: JSONEncoder
    ) throws {
        switch replacement {
        case .unchanged:
            break
        case let .value(value):
            object[key] = try JSONSerialization.jsonObject(with: encoder.encode(value))
        case .omitted:
            object.removeValue(forKey: key)
        }
    }

    private func assertInvalidReplacementPlan(
        current: V4BackupRecordsV1,
        incoming: V4BackupRecordsV1,
        target: V906Integration.Harness,
        source: V906Integration.Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try ReplacementRestoreRule.makeDeletionWinningPlan(.init(
            currentRecords: current,
            currentIdentity: target.session.workspaceIdentity,
            incomingRecords: incoming,
            incomingIdentity: source.session.workspaceIdentity,
            mode: .replaceExisting,
            replacementAt: Fixture.fixedDate.addingTimeInterval(10_000)
        )), file: file, line: line) {
            XCTAssertEqual(
                $0 as? ReplacementRestoreRuleError,
                .invalidAuthority,
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func assertPublicEmptyIncomingReplacement(
        name: String,
        seedCurrentStock: Bool,
        restoreOffset: Int
    ) async throws {
        let source = try publicReplacementStep("create-source") {
            try V906Integration.makeHarness(
                "c55-\(name)-source", withAsset: true, placementSource: .manual
            )
        }
        registerPublicFixtureCleanup(source)
        let target = try publicReplacementStep("create-target") {
            try V906Integration.makeHarness(
                "c55-\(name)-target", withAsset: true, placementSource: .manual
            )
        }
        registerPublicFixtureCleanup(target)
        if seedCurrentStock {
            try publicReplacementStep("seed-current-stock") {
                try seedCurrentPart(in: target.session, slot: 1_100 + restoreOffset)
            }
        }
        let before = try PartsStockLifecycleAdapterV1(
            modelContext: target.session.modelContext
        ).snapshotForBackup(workspaceID: target.session.workspaceIdentity.workspaceID)
        XCTAssertEqual(before.parts.count, seedCurrentStock ? 1 : 0)

        let archive = try publicReplacementStep("export") {
            try V906Integration.exportStreaming(source)
        }
        let restoredGenerationID: UUID
        do {
            let restoredSession = try await publicReplacementAsyncStep("restore") {
                try await V906Integration.restore(
                    archive,
                    into: target,
                    mode: .replaceExisting,
                    ids: V906Integration.restoreIDs(.replaceExisting, offset: restoreOffset)
                )
            }
            try assertEmptyStock(in: restoredSession)
            XCTAssertTrue(try MutationJournalStoreV1(
                modelContext: restoredSession.modelContext,
                identity: restoredSession.workspaceIdentity,
                generationID: restoredSession.generationID,
                allowStateBootstrap: false
            ).exportSnapshot().receipts.isEmpty)
            restoredGenerationID = restoredSession.generationID
        }
        let reopened = try publicReplacementStep("cold-open") {
            try target.factory.openOrBootstrapCurrent()
        }
        XCTAssertEqual(reopened.generationID, restoredGenerationID)
        try assertEmptyStock(in: reopened)
        XCTAssertTrue(try MutationJournalStoreV1(
            modelContext: reopened.modelContext,
            identity: reopened.workspaceIdentity,
            generationID: reopened.generationID,
            allowStateBootstrap: false
        ).exportSnapshot().receipts.isEmpty)
    }

    @MainActor
    private func seedIncomingMixedHistory(
        in session: StoreGenerationSession,
        slot: Int
    ) throws -> MutationHistorySnapshotV1 {
        var phase = "mixed-journal-init"
        do {
            let journal = try MutationJournalStoreV1(
                modelContext: session.modelContext,
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                allowStateBootstrap: false
            )
            phase = "mixed-writer-init"
            let writerID = V906Integration.id(slot + 1)
            let writer = try WorkspaceWriterV1(
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                initialRevision: journal.currentRevision(writerInstanceID: writerID),
                clock: ReplacementClock(),
                idSource: ReplacementIDs(start: slot + 100),
                fileAuthority: ReplacementFiles(),
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
                journalStore: journal
            )
            phase = "mixed-create-first-sign"
            let workspaceID = session.workspaceIdentity.workspaceID
            let firstSignMutationID = try MutationIDV1(
                rawValue: V906Integration.id(slot + 2)
            )
            _ = try writer.execute(
                .createFirstSign(.init(
                    siteID: V906Integration.id(slot + 3),
                    newSite: .init(
                        id: V906Integration.id(slot + 3),
                        label: "Incoming historic site",
                        address: nil,
                        timeZoneID: "UTC"
                    ),
                    assetID: V906Integration.id(slot + 4),
                    assetLabel: "Incoming historic sign",
                    packID: SignPack.illuminatedSignV1.packID,
                    packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                    packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                    createdAt: Fixture.fixedDate,
                    initialPlacementMutationID: firstSignMutationID,
                    initialPlacementEventID: V906Integration.id(slot + 5),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                        rawValue: V906Integration.id(slot + 6)
                    )
                )),
                mutationID: firstSignMutationID
            )

            phase = "mixed-append-actor"
            let actor = try Fixture.actor(
                workspaceID,
                slot: slot + 40,
                includesPartyReference: false
            )
            _ = try writer.execute(
                .applyPartyAccountability(.appendActorSnapshot(actor)),
                mutationID: try MutationIDV1(rawValue: V906Integration.id(slot + 7))
            )
            phase = "mixed-append-work-packet"
            let packetMutationID = try MutationIDV1(
                rawValue: V906Integration.id(slot + 8)
            )
            let packet = try WorkPacketManifestV1(
                manifestID: V906Integration.id(slot + 9),
                packetID: V906Integration.id(slot + 24),
                packetVersion: 1,
                workspaceID: workspaceID,
                items: [try WorkPacketItemV1(
                    itemID: "C55-PUBLIC-MIXED",
                    kind: .inspection,
                    expectedRevision: 1,
                    itemSHA256: Fixture.digest("e")
                )],
                packageReleases: [],
                creationBasis: .explicitLocalSelection,
                creator: actor,
                createdAt: Fixture.fixedDate,
                mutationID: packetMutationID
            )
            let packetMutation = try WorkPacketMutationV1(
                workspaceID: workspaceID,
                expectedRevision: 0,
                mutationID: packetMutationID,
                postImage: .appendManifest(packet)
            )
            _ = try writer.execute(
                .applyWorkPacket(packetMutation), mutationID: packetMutationID
            )

            phase = "mixed-stock-and-work-value-construction"
            let partMutationID = try MutationIDV1(rawValue: V906Integration.id(slot + 10))
            let part = try Fixture.part(
                workspaceID, slot: slot + 11, mutationID: partMutationID
            )
            let location = try Fixture.location(workspaceID, slot: slot + 12)
            let locationMutationID = try MutationIDV1(
                rawValue: V906Integration.id(slot + 13)
            )
            let openingMutationID = try MutationIDV1(
                rawValue: V906Integration.id(slot + 14)
            )
            let opening = try Fixture.movement(
                workspaceID: workspaceID,
                slot: slot + 15,
                part: part.frozenReference(),
                locationID: location.locationID,
                kind: .openingCount,
                quantity: 7,
                pre: .unknown,
                post: 7,
                expectedRevision: 0,
                mutationID: openingMutationID,
                time: 1
            )
            let workMutationID = try MutationIDV1(
                rawValue: V906Integration.id(slot + 16)
            )
            let subject = try WorkResourceSubjectV1(
                workspaceID: workspaceID,
                kind: .workPacket,
                subjectID: packet.manifestID.uuidString.lowercased(),
                subjectRevision: packet.revision,
                subjectSHA256: packet.manifestSHA256
            )
            let predecessor = try Fixture.work(
                workspaceID: workspaceID,
                slot: slot + 18,
                subject: subject,
                actor: actor,
                mutationID: workMutationID,
                expectedRevision: 0
            )
            let useMutationID = try MutationIDV1(
                rawValue: V906Integration.id(slot + 19)
            )
            let useMovement = try Fixture.movement(
                workspaceID: workspaceID,
                slot: slot + 20,
                part: part.frozenReference(),
                locationID: location.locationID,
                kind: .useOnWork,
                quantity: 2,
                pre: .known(try .init(mantissa: 7, scale: 0, unit: .each)),
                post: 5,
                expectedRevision: 1,
                mutationID: useMutationID,
                time: 3
            )
            let materialLineID = V906Integration.id(slot + 21)
            let material = try ManualMaterialLineV1(
                lineID: materialLineID,
                description: part.displayName,
                quantity: .init(mantissa: 2, scale: 0),
                unit: StockUnitV1.each.rawValue,
                localPartReference: part.frozenReference()
            )
            let successor = try Fixture.work(
                workspaceID: workspaceID,
                slot: slot + 22,
                subject: subject,
                actor: actor,
                mutationID: useMutationID,
                expectedRevision: predecessor.revision,
                predecessor: predecessor,
                materials: [material],
                disposition: .superseded
            )
            let use = try StockUseOnWorkReceiptV1(
                receiptID: V906Integration.id(slot + 23),
                movement: useMovement,
                workResourceSuccessor: successor,
                frozenMaterialLineID: materialLineID,
                mutationID: useMutationID
            )

            phase = "mixed-upsert-part"
            _ = try writer.commitPartsStock(.upsertPart(part))
            phase = "mixed-upsert-location"
            _ = try writer.commitPartsStock(
                .upsertLocation(location, mutationID: locationMutationID)
            )
            phase = "mixed-opening-movement"
            _ = try writer.commitPartsStock(.appendMovement(opening))
            phase = "mixed-predecessor-work-resource"
            let beforeWork = try writer.currentRevision()
            _ = try writer.commitWorkResource(
                try WorkResourceMutationV1(
                    workspaceID: workspaceID,
                    mutationID: workMutationID,
                    postImage: predecessor
                ),
                expectedRevision: try WorkspaceExpectedRevisionV1(
                    workspaceID: beforeWork.workspaceID,
                    generationID: beforeWork.generationID,
                    writerInstanceID: beforeWork.writerInstanceID,
                    workspaceRevision: beforeWork.revision,
                    entityRevisions: [
                        .init(
                            identity: try WorkspaceEntityIdentityV1(
                                kind: .workResourceEntry,
                                id: predecessor.entryID
                            ),
                            revision: predecessor.expectedRevision
                        ),
                    ]
                )
            )
            phase = "mixed-use-on-work"
            _ = try writer.commitPartsStock(.use(use))
            phase = "mixed-export-history"
            return try journal.exportSnapshot()
        } catch {
            reportPublicReplacementFailure(error, phase: phase)
            throw error
        }
    }

    @MainActor
    private func assertMixedReplacement(
        in session: StoreGenerationSession,
        sourceHistory: MutationHistorySnapshotV1,
        sourceWorkspaceID: WorkspaceID,
        sourceStockHistoryCount: Int
    ) throws -> MutationHistorySnapshotV1 {
        let snapshot = try PartsStockLifecycleAdapterV1(
            modelContext: session.modelContext
        ).snapshotForBackup(workspaceID: session.workspaceIdentity.workspaceID)
        XCTAssertEqual(snapshot.parts.count, 1)
        XCTAssertEqual(snapshot.locations.count, 1)
        XCTAssertEqual(snapshot.movements.count, 2)
        XCTAssertEqual(snapshot.uses.count, 1)
        XCTAssertEqual(snapshot.movements.last?.postBalance.mantissa, 5)

        let journal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            allowStateBootstrap: false
        )
        try journal.validateAll()
        let history = try journal.exportSnapshot()
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(history))
        XCTAssertTrue(sourceHistory.receipts.allSatisfy { history.receipts.contains($0) })
        let envelopes = try history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }
        XCTAssertEqual(envelopes.filter {
            $0.workspaceID == sourceWorkspaceID
        }.count, sourceHistory.receipts.count)
        XCTAssertEqual(envelopes.filter {
            $0.workspaceID == sourceWorkspaceID && $0.commandKind == .createFirstSign
        }.count, 1)
        XCTAssertEqual(envelopes.filter {
            $0.workspaceID == sourceWorkspaceID
                && ($0.commandKind == .applyWorkResource
                    || $0.commandKind == .applyPartsStock)
        }.count, sourceStockHistoryCount)
        XCTAssertEqual(envelopes.filter {
            $0.workspaceID == session.workspaceIdentity.workspaceID
                && ($0.commandKind == .applyWorkResource
                    || $0.commandKind == .applyPartsStock)
        }.count, sourceStockHistoryCount)
        XCTAssertFalse(envelopes.contains {
            $0.workspaceID == session.workspaceIdentity.workspaceID
                && $0.commandKind == .createFirstSign
        })
        return history
    }

    @MainActor
    private func seedCurrentPart(in session: StoreGenerationSession, slot: Int) throws {
        let journal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            allowStateBootstrap: false
        )
        let ids = ReplacementIDs(start: slot + 10)
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: journal.currentRevision(
                writerInstanceID: V906Integration.id(slot + 1)
            ),
            clock: ReplacementClock(),
            idSource: ids,
            fileAuthority: ReplacementFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: journal
        )
        let part = try LocalPartDefinitionV1(
            partID: V906Integration.id(slot + 2),
            workspaceID: session.workspaceIdentity.workspaceID,
            displayName: "Current stock removed by exact replacement",
            canonicalUnit: .each,
            productIdentities: [try .init(kind: .sku, value: "C55-\(slot)")],
            preferredMinimum: try .init(mantissa: 1, scale: 0, unit: .each),
            archived: false,
            revision: 1,
            mutationID: try MutationIDV1(rawValue: V906Integration.id(slot + 3))
        )
        _ = try writer.commitPartsStock(.upsertPart(part))
    }

    @MainActor
    private func assertEmptyStock(in session: StoreGenerationSession) throws {
        let snapshot = try PartsStockLifecycleAdapterV1(
            modelContext: session.modelContext
        ).snapshotForBackup(workspaceID: session.workspaceIdentity.workspaceID)
        XCTAssertTrue(snapshot.parts.isEmpty)
        XCTAssertTrue(snapshot.locations.isEmpty)
        XCTAssertTrue(snapshot.movements.isEmpty)
        XCTAssertTrue(snapshot.uses.isEmpty)
        XCTAssertTrue(snapshot.reversals.isEmpty)
        XCTAssertTrue(snapshot.returns.isEmpty)
        XCTAssertTrue(snapshot.abandonments.isEmpty)
    }

    private struct ReplacementClock: ApplicationClock {
        func now() -> Date { Fixture.fixedDate }
    }

    private final class ReplacementIDs: ApplicationIDSource, @unchecked Sendable {
        private let lock = NSLock()
        private var next: Int

        init(start: Int) { next = start }

        func makeID() -> UUID {
            lock.lock()
            defer { lock.unlock() }
            defer { next += 1 }
            return V906Integration.id(next)
        }
    }

    private struct ReplacementFiles: ApplicationFileAuthorityV1 {
        func temporaryRelativePath(
            mutationID: MutationIDV1,
            component: String
        ) throws -> String {
            "c55-replacement/\(mutationID.rawValue.uuidString)/\(component)"
        }
    }
}

private extension V23PartsStockReplacementHistoryTests {
    struct Side {
        let snapshot: PartsStockBackupSnapshotV1
        let history: MutationHistorySnapshotV1
        let workResources: [WorkResourceEntryV1]
    }

    @MainActor
    struct Fixture {
        nonisolated static let fixedDate = Date(timeIntervalSince1970: 1_800_100_000)
        let sourceWorkspaceID: WorkspaceID
        let targetWorkspaceID: WorkspaceID
        let targetGenerationID: UUID
        let current: Side
        let incoming: Side
        let retainedCurrentEntry: WorkResourceEntryV1
        let retainedCurrentMutationID: MutationIDV1
        let retainedCausalTargetMutationID: MutationIDV1?
        let retainedCausalReversalMutationID: MutationIDV1?
        let firstIncomingEntry: WorkResourceEntryV1
        let secondIncomingEntry: WorkResourceEntryV1
        let unarchivedBaselineMutationID: MutationIDV1
        let semanticTargetMutationID: MutationIDV1
        let semanticReversalMutationID: MutationIDV1
        let incomingOtherFamilyMutationID: MutationIDV1?
        let removedCurrentEntryIDs: Set<UUID>
        let removedCurrentMutationIDs: Set<MutationIDV1>

        static func id(_ slot: Int) -> UUID {
            UUID(uuidString: String(format: "55100000-0000-4000-8000-%012x", slot))!
        }

        static func mutation(_ slot: Int) throws -> MutationIDV1 {
            try MutationIDV1(rawValue: id(slot))
        }

        static func digest(_ value: Character) -> String {
            String(repeating: String(value), count: 64)
        }

        static func actor(
            _ workspaceID: WorkspaceID,
            slot: Int,
            includesPartyReference: Bool = true
        ) throws -> ActorSnapshotV1 {
            let actor = try LocalActorReferenceV1(
                actorReferenceID: id(slot),
                workspaceID: workspaceID,
                partyID: includesPartyReference ? id(slot + 1) : nil,
                displayName: "History projection actor"
            )
            return try ActorSnapshotV1(
                snapshotID: id(slot + 2),
                workspaceID: workspaceID,
                actor: actor,
                responsibility: .recordedBy,
                displayNameAtTime: actor.displayName,
                capturedAt: fixedDate
            )
        }

        static func part(
            _ workspaceID: WorkspaceID, slot: Int, mutationID: MutationIDV1
        ) throws -> LocalPartDefinitionV1 {
            try LocalPartDefinitionV1(
                partID: id(slot),
                workspaceID: workspaceID,
                displayName: "Part \(slot)",
                canonicalUnit: .each,
                productIdentities: [try .init(kind: .sku, value: "SKU-\(slot)")],
                preferredMinimum: try .init(mantissa: 1, scale: 0, unit: .each),
                archived: false,
                revision: 1,
                mutationID: mutationID
            )
        }

        static func location(_ workspaceID: WorkspaceID, slot: Int) throws
            -> StockStorageLocationV1 {
            try .init(
                locationID: id(slot), workspaceID: workspaceID, kind: .shop,
                label: "Shelf \(slot)", binLabel: "B-\(slot)", revision: 1
            )
        }

        static func movement(
            workspaceID: WorkspaceID,
            slot: Int,
            part: LocalPartReferenceSnapshotV1,
            locationID: UUID,
            kind: StockMovementKindV1,
            quantity: Int64,
            pre: StockBalanceV1,
            post: Int64,
            expectedRevision: UInt64,
            mutationID: MutationIDV1,
            time: TimeInterval,
            relatedMovementID: UUID? = nil,
            reason: String? = nil
        ) throws -> StockMovementEventV1 {
            try .init(
                movementID: id(slot), workspaceID: workspaceID, part: part,
                locationID: locationID, kind: kind,
                quantity: .init(mantissa: quantity, scale: 0, unit: .each),
                unit: .each, preBalance: pre,
                postBalance: .init(mantissa: post, scale: 0, unit: .each),
                relatedMovementID: relatedMovementID,
                reason: reason,
                actor: actor(workspaceID, slot: slot + 100),
                occurredAt: fixedDate.addingTimeInterval(time),
                recordedAt: fixedDate.addingTimeInterval(time + 1),
                expectedLocationRevision: expectedRevision,
                mutationID: mutationID
            )
        }

        static func work(
            workspaceID: WorkspaceID,
            slot: Int,
            subject: WorkResourceSubjectV1,
            actor: ActorSnapshotV1,
            mutationID: MutationIDV1,
            expectedRevision: UInt64,
            predecessor: WorkResourceEntryV1? = nil,
            materials: [ManualMaterialLineV1] = [],
            disposition: WorkResourceDispositionV1 = .active
        ) throws -> WorkResourceEntryV1 {
            try .init(
                entryID: id(slot), workspaceID: workspaceID, subject: subject,
                actor: actor,
                duration: materials.isEmpty ? try .init(minutes: 5) : nil,
                materials: materials,
                visibility: .internalOnly,
                disposition: disposition,
                recordedAt: fixedDate.addingTimeInterval(TimeInterval(slot)),
                expectedRevision: expectedRevision,
                revision: expectedRevision + 1,
                supersedesEntryID: predecessor?.entryID,
                supersedesEntrySHA256: predecessor?.entrySHA256,
                mutationID: mutationID
            )
        }

        static func make(
            includeIncomingOtherFamily: Bool = false,
            retainedCurrentCausation: Bool = false
        ) throws -> Fixture {
            let sourceWorkspaceID = WorkspaceID(rawValue: id(1))
            let targetWorkspaceID = WorkspaceID(rawValue: id(2))
            let sourceReplica = try WorkspaceReplicaIdentityV1(
                workspaceID: sourceWorkspaceID,
                replicaID: ReplicaID(rawValue: id(3))
            )
            let secondSourceReplica = try WorkspaceReplicaIdentityV1(
                workspaceID: sourceWorkspaceID,
                replicaID: ReplicaID(rawValue: id(10))
            )
            let targetReplica = try WorkspaceReplicaIdentityV1(
                workspaceID: targetWorkspaceID,
                replicaID: ReplicaID(rawValue: id(4))
            )
            let sourceGeneration = id(5)
            let currentGeneration = id(6)
            let targetGeneration = id(7)
            let sourceActor = try actor(sourceWorkspaceID, slot: 20)
            let targetActor = try actor(targetWorkspaceID, slot: 30)
            let sourceSubject = try WorkResourceSubjectV1(
                workspaceID: sourceWorkspaceID,
                kind: .workPacket,
                subjectID: id(40).uuidString,
                subjectRevision: 1,
                subjectSHA256: digest("a")
            )
            let targetSubject = try WorkResourceSubjectV1(
                workspaceID: targetWorkspaceID,
                kind: .workPacket,
                subjectID: sourceSubject.subjectID,
                subjectRevision: sourceSubject.subjectRevision,
                subjectSHA256: digest("b")
            )

            let sourcePartMutation = try mutation(100)
            let sourcePart = try part(sourceWorkspaceID, slot: 101, mutationID: sourcePartMutation)
            let sourceLocation = try location(sourceWorkspaceID, slot: 102)
            let sourceLocationMutation = try mutation(103)
            let openingMutation = try mutation(104)
            let opening = try movement(
                workspaceID: sourceWorkspaceID, slot: 105,
                part: sourcePart.frozenReference(), locationID: sourceLocation.locationID,
                kind: .openingCount, quantity: 10, pre: .unknown, post: 10,
                expectedRevision: 0, mutationID: openingMutation, time: 0
            )
            let firstWorkMutation = try mutation(106)
            let firstWork = try work(
                workspaceID: sourceWorkspaceID, slot: 107, subject: sourceSubject,
                actor: sourceActor, mutationID: firstWorkMutation, expectedRevision: 0
            )
            let useMutation = try mutation(108)
            let useMovement = try movement(
                workspaceID: sourceWorkspaceID, slot: 109,
                part: sourcePart.frozenReference(), locationID: sourceLocation.locationID,
                kind: .useOnWork, quantity: 2,
                pre: .known(try .init(mantissa: 10, scale: 0, unit: .each)), post: 8,
                expectedRevision: 1, mutationID: useMutation, time: 2
            )
            let materialLineID = id(110)
            let material = try ManualMaterialLineV1(
                lineID: materialLineID,
                description: sourcePart.displayName,
                quantity: .init(mantissa: 2, scale: 0),
                unit: StockUnitV1.each.rawValue,
                localPartReference: sourcePart.frozenReference()
            )
            let useWork = try work(
                workspaceID: sourceWorkspaceID, slot: 111, subject: sourceSubject,
                actor: sourceActor, mutationID: useMutation, expectedRevision: 1,
                predecessor: firstWork, materials: [material], disposition: .superseded
            )
            let use = try StockUseOnWorkReceiptV1(
                receiptID: id(112), movement: useMovement,
                workResourceSuccessor: useWork,
                frozenMaterialLineID: materialLineID,
                mutationID: useMutation
            )
            let reverseMutation = try mutation(124)
            let reverseMovement = try movement(
                workspaceID: sourceWorkspaceID, slot: 125,
                part: sourcePart.frozenReference(), locationID: sourceLocation.locationID,
                kind: .reverseUse, quantity: 2,
                pre: .known(try .init(mantissa: 8, scale: 0, unit: .each)), post: 10,
                expectedRevision: 2, mutationID: reverseMutation, time: 4,
                relatedMovementID: useMovement.movementID, reason: "Mistaken issue"
            )
            let reverseWork = try work(
                workspaceID: sourceWorkspaceID, slot: 126, subject: sourceSubject,
                actor: sourceActor, mutationID: reverseMutation,
                expectedRevision: useWork.revision, predecessor: useWork,
                materials: useWork.materials, disposition: .reversed
            )
            let reversal = try StockUseReversalReceiptV1(
                receiptID: id(127), sourceUse: use, reversalMovement: reverseMovement,
                workResourceSuccessor: reverseWork, reason: "Mistaken issue",
                mutationID: reverseMutation
            )
            let secondWorkMutation = try mutation(113)
            let secondWork = try work(
                workspaceID: sourceWorkspaceID, slot: 114, subject: sourceSubject,
                actor: sourceActor, mutationID: secondWorkMutation,
                expectedRevision: 0
            )
            let secondUseMutation = try mutation(115)
            let secondUseMovement = try movement(
                workspaceID: sourceWorkspaceID, slot: 116,
                part: sourcePart.frozenReference(), locationID: sourceLocation.locationID,
                kind: .useOnWork, quantity: 1,
                pre: .known(try .init(mantissa: 10, scale: 0, unit: .each)), post: 9,
                expectedRevision: 3, mutationID: secondUseMutation, time: 6
            )
            let secondMaterialLineID = id(117)
            let secondMaterial = try ManualMaterialLineV1(
                lineID: secondMaterialLineID,
                description: sourcePart.displayName,
                quantity: .init(mantissa: 1, scale: 0),
                unit: StockUnitV1.each.rawValue,
                localPartReference: sourcePart.frozenReference()
            )
            let secondUseWork = try work(
                workspaceID: sourceWorkspaceID, slot: 118, subject: sourceSubject,
                actor: sourceActor, mutationID: secondUseMutation,
                expectedRevision: secondWork.revision, predecessor: secondWork,
                materials: [secondMaterial], disposition: .superseded
            )
            let secondUse = try StockUseOnWorkReceiptV1(
                receiptID: id(119), movement: secondUseMovement,
                workResourceSuccessor: secondUseWork,
                frozenMaterialLineID: secondMaterialLineID,
                mutationID: secondUseMutation
            )
            let returnMutation = try mutation(120)
            let returnMovement = try movement(
                workspaceID: sourceWorkspaceID, slot: 121,
                part: sourcePart.frozenReference(), locationID: sourceLocation.locationID,
                kind: .returnAgainstUse, quantity: 1,
                pre: .known(try .init(mantissa: 9, scale: 0, unit: .each)), post: 10,
                expectedRevision: 4, mutationID: returnMutation, time: 8,
                relatedMovementID: secondUseMovement.movementID
            )
            let returnWork = try work(
                workspaceID: sourceWorkspaceID, slot: 122, subject: sourceSubject,
                actor: sourceActor, mutationID: returnMutation,
                expectedRevision: secondUseWork.revision, predecessor: secondUseWork,
                materials: [], disposition: .superseded
            )
            let returned = try StockReturnAgainstUseReceiptV1(
                receiptID: id(123), sourceUse: secondUse, predecessorFrontier: nil,
                returnMovement: returnMovement,
                workResourcePredecessor: secondUseWork,
                workResourceSuccessor: returnWork,
                mutationID: returnMutation
            )
            let abandonedSourceMutation = try mutation(130)
            let abandonedSource = try part(
                sourceWorkspaceID, slot: 131, mutationID: abandonedSourceMutation
            )
            let abandonmentMutation = try mutation(132)
            let abandonedSuccessor = try LocalPartDefinitionV1(
                partID: abandonedSource.partID,
                workspaceID: sourceWorkspaceID,
                displayName: abandonedSource.displayName,
                canonicalUnit: abandonedSource.canonicalUnit,
                productIdentities: abandonedSource.productIdentities,
                preferredMinimum: abandonedSource.preferredMinimum,
                archived: true,
                revision: abandonedSource.revision + 1,
                mutationID: abandonmentMutation
            )
            let abandonmentDisposition = try AbandonUnverifiedStockDispositionV1(
                dispositionID: id(133), workspaceID: sourceWorkspaceID,
                partID: abandonedSource.partID, locationID: sourceLocation.locationID,
                actor: sourceActor, reason: "Unable to verify stock",
                lastMovementID: nil, lastLocationRevision: 0,
                recordedAt: fixedDate.addingTimeInterval(10),
                mutationID: abandonmentMutation, currentBalance: .unknown
            )
            let abandonment = try StockAbandonmentReceiptV1(
                dispositions: [abandonmentDisposition],
                archivedPartSuccessor: abandonedSuccessor,
                predecessor: abandonedSource
            )
            let incomingSnapshot = try PartsStockBackupSnapshotV1(
                workspaceID: sourceWorkspaceID,
                parts: [sourcePart, abandonedSuccessor], locations: [sourceLocation],
                movements: [
                    opening, useMovement, reverseMovement, secondUseMovement, returnMovement,
                ],
                uses: [use, secondUse], reversals: [reversal], returns: [returned],
                abandonments: [abandonmentDisposition]
            )
            var incomingCommands: [WorkspaceCommandV1] = [
                .applyPartsStock(.upsertPart(sourcePart)),
                .applyPartsStock(.upsertLocation(sourceLocation, mutationID: sourceLocationMutation)),
                .applyPartsStock(.appendMovement(opening)),
                .applyWorkResource(try .init(
                    workspaceID: sourceWorkspaceID,
                    mutationID: firstWorkMutation,
                    postImage: firstWork
                )),
                .applyPartsStock(.use(use)),
                .applyPartsStock(.reverseUse(reversal)),
                .applyWorkResource(try .init(
                    workspaceID: sourceWorkspaceID,
                    mutationID: secondWorkMutation,
                    postImage: secondWork
                )),
                .applyPartsStock(.use(secondUse)),
                .applyPartsStock(.returnAgainstUse(returned)),
                .applyPartsStock(.abandon(abandonment)),
            ]
            let incomingOtherFamilyMutationID: MutationIDV1?
            var incomingExplicitMutationIDs: [Int: MutationIDV1] = [:]
            if includeIncomingOtherFamily {
                let mutationID = try mutation(140)
                incomingOtherFamilyMutationID = mutationID
                incomingExplicitMutationIDs[incomingCommands.count] = mutationID
                incomingCommands.append(.createFirstSign(.init(
                    siteID: id(141),
                    newSite: .init(
                        id: id(141), label: "Historic source site",
                        address: nil, timeZoneID: "UTC"
                    ),
                    assetID: id(142),
                    assetLabel: "Historic source sign",
                    packID: "history.fixture",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    createdAt: fixedDate.addingTimeInterval(20)
                )))
            } else {
                incomingOtherFamilyMutationID = nil
            }
            let abandonedBaselineIdentity = try WorkspaceEntityIdentityV1(
                kind: .localPartDefinition,
                id: abandonedSuccessor.partID
            )
            let incomingHistory = try history(
                commands: incomingCommands,
                identities: [sourceReplica, secondSourceReplica],
                generationID: sourceGeneration,
                writerID: id(8),
                semanticPair: (target: 4, reversal: 5),
                explicitMutationIDs: incomingExplicitMutationIDs,
                catalogBaselines: [.init(
                    identity: abandonedBaselineIdentity,
                    revision: abandonedSuccessor.revision,
                    externalProjectionSHA256: abandonedSuccessor.partSHA256
                )]
            )

            let currentPartMutation = try mutation(200)
            let currentPart = try part(targetWorkspaceID, slot: 201, mutationID: currentPartMutation)
            let currentLocation = try location(targetWorkspaceID, slot: 202)
            let currentLocationMutation = try mutation(203)
            let currentOpeningMutation = try mutation(204)
            let currentOpening = try movement(
                workspaceID: targetWorkspaceID, slot: 205,
                part: currentPart.frozenReference(), locationID: currentLocation.locationID,
                kind: .openingCount, quantity: 4, pre: .unknown, post: 4,
                expectedRevision: 0, mutationID: currentOpeningMutation, time: 0
            )
            let currentCoupledMutation = try mutation(208)
            let currentCoupled = try work(
                workspaceID: targetWorkspaceID, slot: 209, subject: targetSubject,
                actor: targetActor, mutationID: currentCoupledMutation, expectedRevision: 0
            )
            let currentUseMutation = try mutation(210)
            let currentUseMovement = try movement(
                workspaceID: targetWorkspaceID, slot: 211,
                part: currentPart.frozenReference(), locationID: currentLocation.locationID,
                kind: .useOnWork, quantity: 1,
                pre: .known(try .init(mantissa: 4, scale: 0, unit: .each)), post: 3,
                expectedRevision: 1, mutationID: currentUseMutation, time: 2
            )
            let currentMaterialLineID = id(212)
            let currentMaterial = try ManualMaterialLineV1(
                lineID: currentMaterialLineID,
                description: currentPart.displayName,
                quantity: .init(mantissa: 1, scale: 0),
                unit: StockUnitV1.each.rawValue,
                localPartReference: currentPart.frozenReference()
            )
            let currentUseWork = try work(
                workspaceID: targetWorkspaceID, slot: 213, subject: targetSubject,
                actor: targetActor, mutationID: currentUseMutation,
                expectedRevision: currentCoupled.revision, predecessor: currentCoupled,
                materials: [currentMaterial], disposition: .superseded
            )
            let currentUse = try StockUseOnWorkReceiptV1(
                receiptID: id(214), movement: currentUseMovement,
                workResourceSuccessor: currentUseWork,
                frozenMaterialLineID: currentMaterialLineID,
                mutationID: currentUseMutation
            )
            let retainedMutationID = try mutation(206)
            let retained = try work(
                workspaceID: targetWorkspaceID, slot: 207, subject: targetSubject,
                actor: targetActor, mutationID: retainedMutationID, expectedRevision: 0
            )
            let currentSnapshot = try PartsStockBackupSnapshotV1(
                workspaceID: targetWorkspaceID,
                parts: [currentPart], locations: [currentLocation],
                movements: [currentOpening, currentUseMovement], uses: [currentUse],
                reversals: [], returns: [],
                abandonments: []
            )
            var currentCommands: [WorkspaceCommandV1] = [
                .applyPartsStock(.upsertPart(currentPart)),
                .applyPartsStock(.upsertLocation(
                    currentLocation, mutationID: currentLocationMutation
                )),
                .applyPartsStock(.appendMovement(currentOpening)),
                .applyWorkResource(try .init(
                    workspaceID: targetWorkspaceID,
                    mutationID: currentCoupledMutation,
                    postImage: currentCoupled
                )),
                .applyPartsStock(.use(currentUse)),
                .applyWorkResource(try .init(
                    workspaceID: targetWorkspaceID,
                    mutationID: retainedMutationID,
                    postImage: retained
                )),
            ]
            var currentWorkResources = [currentCoupled, currentUseWork, retained]
            var retainedCausalTargetMutationID: MutationIDV1? = nil
            var retainedCausalReversalMutationID: MutationIDV1? = nil
            if retainedCurrentCausation {
                let targetMutation = try mutation(215)
                let targetEntry = try work(
                    workspaceID: targetWorkspaceID, slot: 216, subject: targetSubject,
                    actor: targetActor, mutationID: targetMutation, expectedRevision: 0
                )
                let reversalMutation = try mutation(217)
                let reversalEntry = try work(
                    workspaceID: targetWorkspaceID, slot: 218, subject: targetSubject,
                    actor: targetActor, mutationID: reversalMutation,
                    expectedRevision: targetEntry.revision, predecessor: targetEntry,
                    disposition: .reversed
                )
                currentCommands.append(.applyWorkResource(try .init(
                    workspaceID: targetWorkspaceID,
                    mutationID: targetMutation, postImage: targetEntry
                )))
                currentCommands.append(.applyWorkResource(try .init(
                    workspaceID: targetWorkspaceID,
                    mutationID: reversalMutation, postImage: reversalEntry
                )))
                currentWorkResources.append(contentsOf: [targetEntry, reversalEntry])
                retainedCausalTargetMutationID = targetMutation
                retainedCausalReversalMutationID = reversalMutation
            }
            let currentHistory = try history(
                commands: currentCommands,
                identities: [targetReplica],
                generationID: currentGeneration,
                writerID: id(9),
                semanticPair: retainedCurrentCausation ? (target: 6, reversal: 7) : nil
            )
            return Fixture(
                sourceWorkspaceID: sourceWorkspaceID,
                targetWorkspaceID: targetWorkspaceID,
                targetGenerationID: targetGeneration,
                current: Side(snapshot: currentSnapshot, history: currentHistory,
                              workResources: currentWorkResources),
                incoming: Side(snapshot: incomingSnapshot, history: incomingHistory,
                               workResources: [
                                firstWork, useWork, reverseWork, secondWork,
                                secondUseWork, returnWork,
                               ]),
                retainedCurrentEntry: retained,
                retainedCurrentMutationID: retainedMutationID,
                retainedCausalTargetMutationID: retainedCausalTargetMutationID,
                retainedCausalReversalMutationID: retainedCausalReversalMutationID,
                firstIncomingEntry: firstWork,
                secondIncomingEntry: secondWork,
                unarchivedBaselineMutationID: abandonedSource.mutationID,
                semanticTargetMutationID: useMutation,
                semanticReversalMutationID: reverseMutation,
                incomingOtherFamilyMutationID: incomingOtherFamilyMutationID,
                removedCurrentEntryIDs: [currentCoupled.entryID, currentUseWork.entryID],
                removedCurrentMutationIDs: [currentCoupledMutation, currentUseMutation]
            )
        }

        func input(requirements: Projector.Requirements) throws -> Projector.Input {
            let plannedHistory = MutationHistorySnapshotV1(
                workspaceRevision: max(current.history.workspaceRevision,
                                       incoming.history.workspaceRevision),
                lastLocalSequence: max(current.history.lastLocalSequence,
                                       incoming.history.lastLocalSequence),
                receipts: current.history.receipts + incoming.history.receipts,
                quarantines: current.history.quarantines + incoming.history.quarantines,
                entityRevisions: current.history.entityRevisions
                    + incoming.history.entityRevisions
            )
            try MutationJournalStoreV1.validateImportedSnapshot(plannedHistory)
            let sourceCommandByMutation = try Dictionary(uniqueKeysWithValues:
                incoming.history.receipts.map { record in
                    let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                    return (envelope.mutationID, envelope.commandKind)
                }
            )
            let mutations = try requirements.mutationIDs.enumerated().map { index, source in
                let base = sourceCommandByMutation[source] == .applyPartsStock ? 600 : 700
                return Projector.MutationBinding(
                    source: source,
                    target: try Self.mutation(base + index)
                )
            }
            let subjects = try requirements.subjects.map { source in
                Projector.SubjectBinding(
                    source: source,
                    target: try WorkResourceSubjectV1(
                        workspaceID: targetWorkspaceID,
                        kind: source.kind,
                        subjectID: source.subjectID,
                        subjectRevision: source.subjectRevision,
                        subjectSHA256: Self.digest("c")
                    )
                )
            }
            let replicas = requirements.replicas.enumerated().map { index, source in
                Projector.ReplicaBinding(
                    source: source,
                    target: ReplicaID(rawValue: Self.id(800 + index))
                )
            }
            return .init(
                currentSnapshot: current.snapshot,
                incomingSnapshot: incoming.snapshot,
                currentHistory: current.history,
                incomingHistory: incoming.history,
                plannedHistory: plannedHistory,
                currentWorkResources: current.workResources,
                incomingWorkResources: incoming.workResources,
                plannedWorkResources: current.workResources + incoming.workResources,
                targetWorkspaceID: targetWorkspaceID,
                targetGenerationID: targetGenerationID,
                writerInstanceID: Self.id(900),
                mutationBindings: mutations,
                subjectBindings: subjects,
                replicaBindings: replicas
            )
        }

        static func history(
            commands: [WorkspaceCommandV1],
            identities: [WorkspaceReplicaIdentityV1],
            generationID: UUID,
            writerID: UUID,
            semanticPair: (target: Int, reversal: Int)? = nil,
            explicitMutationIDs: [Int: MutationIDV1] = [:],
            catalogBaselines: [MutationHistoryEntityRevisionV1] = []
        ) throws -> MutationHistorySnapshotV1 {
            guard let workspaceID = identities.first?.workspaceID,
                  identities.allSatisfy({ $0.workspaceID == workspaceID }) else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            let baselineByIdentity = Dictionary(
                uniqueKeysWithValues: catalogBaselines.map { ($0.identity, $0) }
            )
            guard baselineByIdentity.count == catalogBaselines.count,
                  catalogBaselines.allSatisfy({
                      $0.revision >= 1 && $0.externalProjectionSHA256 != nil
                  }) else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            var terminal = Dictionary(uniqueKeysWithValues:
                catalogBaselines.map { ($0.identity, UInt64(1)) }
            )
            var records: [MutationHistoryReceiptRecordV1] = []
            var receiptByIndex: [Int: MutationReceiptV1] = [:]
            var basisByIndex: [Int: ReversalBasisV1] = [:]
            var quarantines: [MutationHistoryQuarantineRecordV1] = []
            var localSequenceByReplica: [ReplicaID: UInt64] = [:]
            for (offset, command) in commands.enumerated() {
                let identity = identities[offset % identities.count]
                let localSequence = localSequenceByReplica[identity.replicaID, default: 0] + 1
                localSequenceByReplica[identity.replicaID] = localSequence
                let mutationID: MutationIDV1
                let concurrency: [WorkspaceEntityIdentityV1]
                let expectedByIdentity: [WorkspaceEntityIdentityV1: UInt64]
                let images: [MutationPostImageV1]
                switch command {
                case let .applyWorkResource(mutation):
                    mutationID = mutation.mutationID
                    concurrency = try mutation.concurrencyIdentities
                    expectedByIdentity = Dictionary(uniqueKeysWithValues: try concurrency.map {
                        ($0, try mutation.expectedRevision(for: $0))
                    })
                    images = try mutation.mutationPostImages
                case let .applyPartsStock(mutation):
                    mutationID = mutation.mutationID
                    concurrency = try mutation.concurrencyIdentities
                    expectedByIdentity = Dictionary(uniqueKeysWithValues: try concurrency.map {
                        ($0, try mutation.expectedRevision(for: $0))
                    })
                    images = try mutation.mutationPostImages
                case let .createFirstSign(firstSign):
                    guard let explicitMutationID = explicitMutationIDs[offset] else {
                        throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
                    }
                    mutationID = explicitMutationID
                    concurrency = try WorkspaceWriterV1.affectedIdentities(for: command)
                    expectedByIdentity = Dictionary(uniqueKeysWithValues: concurrency.map {
                        ($0, terminal[$0, default: 0])
                    })
                    var firstSignImages: [MutationPostImageV1] = [
                        .site(id: firstSign.siteID, revision: 1, semanticSHA256: digest("c")),
                        .asset(id: firstSign.assetID, revision: 1, semanticSHA256: digest("d")),
                    ]
                    if let placementID = firstSign.initialPlacementEventID {
                        firstSignImages.append(.assetPlacementEvent(
                            id: placementID,
                            revision: 1,
                            semanticSHA256: digest("e")
                        ))
                    }
                    images = firstSignImages
                default:
                    throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
                }
                XCTAssertTrue(concurrency.allSatisfy {
                    terminal[$0, default: 0] == expectedByIdentity[$0]
                })
                let expected = try WorkspaceExpectedRevisionV1(
                    workspaceID: workspaceID,
                    generationID: generationID,
                    writerInstanceID: writerID,
                    workspaceRevision: UInt64(offset),
                    entityRevisions: concurrency.map {
                        .init(identity: $0, revision: expectedByIdentity[$0]!)
                    }
                )
                let request = WorkspaceMutationRequestV1(
                    mutationID: mutationID,
                    expectedRevision: expected,
                    command: command
                )
                let receiptIdentity = MutationReceiptIdentityV1(
                    workspaceID: workspaceID,
                    replicaID: identity.replicaID,
                    localSequence: localSequence
                )
                var basis: ReversalBasisV1?
                var execution: SemanticReversalExecutionV1?
                var replayIdentitySHA256: String?
                var reversesMutationID: MutationIDV1?
                var causationMutationID: MutationIDV1? = nil
                if let pair = semanticPair, offset == pair.target {
                    guard commands.indices.contains(pair.reversal), pair.reversal > pair.target else {
                        throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
                    }
                    let plan = try SemanticReversalPlanV1(
                        mutationID: mutationID,
                        commandKind: command.kind,
                        expectedRevision: expected,
                        prospectiveTargets: try images.map { try $0.identity },
                        requiredSemanticValues: [.init(key: "stock", value: "before")],
                        contentReferences: [],
                        dependencyGraph: [],
                        conflicts: [],
                        compensatingCommands: [commands[pair.reversal]]
                    )
                    basis = try ReversalBasisV1(
                        targetMutationID: mutationID,
                        targetReceiptIdentity: receiptIdentity,
                        plan: plan
                    )
                } else if let pair = semanticPair, offset == pair.reversal {
                    guard let targetReceipt = receiptByIndex[pair.target],
                          let targetBasis = basisByIndex[pair.target] else {
                        throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                    }
                    let basisSHA256 = try targetBasis.canonicalSHA256()
                    execution = try SemanticReversalExecutionV1(
                        targetMutationID: targetReceipt.mutationID,
                        targetReceiptIdentity: targetReceipt.identity,
                        reversalBasisSHA256: basisSHA256,
                        planDigest: targetBasis.planDigest,
                        compensatingMutationIDs: [mutationID]
                    )
                    replayIdentitySHA256 = try SemanticReversalReplayIdentityV1(
                        request: request,
                        identity: identity,
                        targetMutationID: targetReceipt.mutationID,
                        planDigest: targetBasis.planDigest,
                        compensatingMutationIDs: [mutationID]
                    ).canonicalSHA256()
                    reversesMutationID = targetReceipt.mutationID
                    causationMutationID = targetReceipt.mutationID
                }
                let envelope = try MutationEnvelopeV1(
                    request: request,
                    identity: identity,
                    sourceKind: execution == nil ? .localUser : .semanticReversal,
                    causationMutationID: causationMutationID,
                    reversalPlanDigest: basis?.planDigest,
                    semanticReversalReplayIdentitySHA256: replayIdentitySHA256,
                    semanticReversalExecution: execution
                )
                for image in images {
                    terminal[try image.identity] = image.revision
                    terminal[try image.concurrencyIdentity] = image.revision
                    if case let .partsStock(id, kind, _, _, _) = image {
                        terminal[try .init(kind: kind, id: id)] = image.revision
                    }
                }
                let resulting = try WorkspaceExpectedRevisionV1(
                    workspaceID: identity.workspaceID,
                    generationID: generationID,
                    writerInstanceID: writerID,
                    workspaceRevision: UInt64(offset + 1),
                    entityRevisions: terminal.map {
                        .init(identity: $0.key, revision: $0.value)
                    }
                )
                let receipt = try MutationReceiptV1(
                    identity: receiptIdentity,
                    envelope: envelope,
                    resultingRevision: .init(resulting),
                    postImages: images,
                    reversesMutationID: reversesMutationID,
                    committedAt: fixedDate.addingTimeInterval(TimeInterval(offset))
                )
                let semantic: SemanticReversalReceiptV1?
                if let execution, let reversesMutationID {
                    semantic = try SemanticReversalReceiptV1(
                        reversalReceiptIdentity: receipt.identity,
                        reversesMutationID: reversesMutationID,
                        targetReceiptIdentity: execution.targetReceiptIdentity,
                        reversalBasisSHA256: execution.reversalBasisSHA256,
                        planDigest: execution.planDigest,
                        compensatingMutationIDs: [mutationID],
                        resultingRevision: receipt.resultingRevision
                    )
                } else {
                    semantic = nil
                }
                records.append(.init(
                    envelopeData: try envelope.canonicalData(),
                    receiptData: try receipt.canonicalData(),
                    reversalBasisData: try basis?.canonicalData(),
                    semanticReversalData: try semantic?.canonicalData()
                ))
                receiptByIndex[offset] = receipt
                if let basis { basisByIndex[offset] = basis }
                if let replayIdentitySHA256 {
                    quarantines.append(.init(
                        workspaceID: identity.workspaceID,
                        mutationID: mutationID.rawValue,
                        identityDomain: .semanticReversalReplayIdentity,
                        acceptedIdentitySHA256: replayIdentitySHA256,
                        conflictingIdentitySHA256: digest("f"),
                        detectedAt: fixedDate.addingTimeInterval(TimeInterval(offset + 100))
                    ))
                }
            }
            return MutationHistorySnapshotV1(
                workspaceRevision: UInt64(commands.count),
                lastLocalSequence: localSequenceByReplica.values.max() ?? 0,
                receipts: records,
                quarantines: quarantines,
                entityRevisions: terminal.map {
                    MutationHistoryEntityRevisionV1(
                        identity: $0.key,
                        revision: $0.value,
                        externalProjectionSHA256:
                            baselineByIdentity[$0.key]?.externalProjectionSHA256
                    )
                }.sorted { $0.identity.stableKey < $1.identity.stableKey }
            )
        }
    }
}

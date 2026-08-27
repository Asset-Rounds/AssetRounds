import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V10_02MutationEnvelopeReceiptTests: XCTestCase {
    @MainActor
    func testV10_02G01CanonicalEnvelopeReceiptBytesAndAtomicCommit() throws {
        let corpus = try Self.loadCorpus()
        let harness = try MutationJournalHarnessV1()
        let request = try harness.request(mutation: 10, label: "North sign")
        let envelope = try harness.envelope(request)
        let envelopeBytes = try envelope.canonicalData()

        XCTAssertEqual(try MutationEnvelopeV1.decodeCanonical(from: envelopeBytes), envelope)
        XCTAssertEqual(try envelope.canonicalSHA256(), MutationJournalHarnessV1.sha256(envelopeBytes))
        XCTAssertEqual(envelope.contentDependencyIDs, ["content-a", "content-b"])
        XCTAssertEqual(envelope.workspaceID.rawValue.uuidString.lowercased(), corpus.canonicalVector.workspaceID.lowercased())
        XCTAssertEqual(envelope.mutationID.rawValue.uuidString.lowercased(), corpus.canonicalVector.mutationID.lowercased())
        XCTAssertEqual(envelope.commandKind.rawValue, corpus.canonicalVector.commandKind)

        let receipt = try harness.commit(envelope, entities: [harness.asset, harness.site])
        let receiptBytes = try receipt.canonicalData()
        XCTAssertEqual(try MutationReceiptV1.decodeCanonical(from: receiptBytes), receipt)
        XCTAssertEqual(try receipt.canonicalSHA256(), MutationJournalHarnessV1.sha256(receiptBytes))
        XCTAssertEqual(receipt.identity.localSequence, 1)
        XCTAssertEqual(receipt.expectedRevision.workspaceRevision, 0)
        XCTAssertEqual(receipt.resultingRevision.workspaceRevision, 1)
        XCTAssertEqual(receipt.postImages.count, 2)
        XCTAssertEqual(receipt.contentDependencyIDs, envelope.contentDependencyIDs)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkspaceMutationStateRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EntityMutationRevisionRow>()), 2)
        try harness.store.validateAll()

        let persistedSite = try XCTUnwrap(
            try harness.context.fetch(FetchDescriptor<Site>()).first
        )
        persistedSite.label = "Tampered after receipt"
        try harness.context.save()
        XCTAssertThrowsError(
            try MutationReceiptRecoveryServiceV1(store: harness.store)
                .recoverBeforeWriterActivation()
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
    }

    @MainActor
    func testV10_02A01RestartReplayChangedHashQuarantineAndSequence() throws {
        let harness = try MutationJournalHarnessV1()
        let originalExpected = try harness.currentExpected()
        let request = try harness.request(mutation: 20, label: "Original", expected: originalExpected)
        let envelope = try harness.envelope(request)
        let receipt = try harness.commit(envelope, entities: [harness.asset])

        let relaunchedContext = ModelContext(harness.container)
        relaunchedContext.autosaveEnabled = false
        let relaunched = try MutationJournalStoreV1(
            modelContext: relaunchedContext,
            identity: harness.identity,
            generationID: harness.generationID
        )
        try MutationReceiptRecoveryServiceV1(store: relaunched).recoverBeforeWriterActivation()
        XCTAssertEqual(
            try relaunched.resolveReplay(envelope: envelope, detectedAt: harness.date(21)),
            receipt
        )

        let changed = try harness.envelope(harness.request(
            mutation: 20,
            label: "Changed",
            expected: originalExpected
        ))
        XCTAssertThrowsError(try relaunched.resolveReplay(envelope: changed, detectedAt: harness.date(22))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try relaunched.resolveReplay(envelope: envelope, detectedAt: harness.date(23))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try relaunchedContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try relaunchedContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
        XCTAssertEqual(try relaunched.currentRevision(writerInstanceID: harness.writerInstanceID).revision, 1)
        let normalQuarantine = try XCTUnwrap(
            try relaunched.exportSnapshot().quarantines.first
        )
        XCTAssertEqual(normalQuarantine.identityDomain, .mutationEnvelope)
        XCTAssertEqual(normalQuarantine.acceptedIdentitySHA256, try envelope.canonicalSHA256())
        XCTAssertEqual(normalQuarantine.conflictingIdentitySHA256, try changed.canonicalSHA256())

        let normalSnapshot = try relaunched.exportSnapshot()
        let normalRestoreContainer = try MutationJournalHarnessV1.makeContainer(
            name: "V10_02NormalQuarantineRestore"
        )
        let normalRestoreStore = try MutationJournalStoreV1(
            modelContext: normalRestoreContainer.mainContext,
            identity: harness.identity,
            generationID: harness.generationID
        )
        try normalRestoreStore.replaceHistory(
            with: normalSnapshot,
            identityDisposition: .preserve
        )
        XCTAssertEqual(
            try normalRestoreStore.exportSnapshot().quarantines,
            normalSnapshot.quarantines
        )
        let malformedDomainRow = try XCTUnwrap(
            try normalRestoreContainer.mainContext.fetch(
                FetchDescriptor<MutationQuarantineRow>()
            ).first
        )
        malformedDomainRow.identityDomain = "UNKNOWN_IDENTITY_DOMAIN"
        try normalRestoreContainer.mainContext.save()
        XCTAssertThrowsError(try normalRestoreStore.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        let mixedDomainSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: normalSnapshot.workspaceRevision,
            lastLocalSequence: normalSnapshot.lastLocalSequence,
            receipts: normalSnapshot.receipts,
            quarantines: [.init(
                workspaceID: normalQuarantine.workspaceID,
                mutationID: normalQuarantine.mutationID,
                identityDomain: .semanticReversalReplayIdentity,
                acceptedIdentitySHA256: normalQuarantine.acceptedIdentitySHA256,
                conflictingIdentitySHA256: normalQuarantine.conflictingIdentitySHA256,
                detectedAt: normalQuarantine.detectedAt
            )],
            entityRevisions: normalSnapshot.entityRevisions
        )
        XCTAssertThrowsError(
            try MutationJournalStoreV1.validateImportedSnapshot(mixedDomainSnapshot)
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }

        let nextRequest = try harness.request(mutation: 21, label: "Next")
        let next = try harness.commit(harness.envelope(nextRequest), entities: [harness.site])
        XCTAssertEqual(next.identity.localSequence, 2)
        XCTAssertNotEqual(receipt.identity.stableKey, next.identity.stableKey)
        XCTAssertTrue(receipt.identity.stableKey.hasPrefix(
            "\(harness.workspaceID.rawValue.uuidString.lowercased()):\(harness.replicaID.rawValue.uuidString.lowercased()):"
        ))

        let secondIdentity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: MutationJournalHarnessV1.id(70)),
            replicaID: ReplicaID(rawValue: MutationJournalHarnessV1.id(71))
        )
        let secondGeneration = MutationJournalHarnessV1.id(72)
        let secondSiteID = MutationJournalHarnessV1.id(73)
        let secondAssetID = MutationJournalHarnessV1.id(74)
        relaunchedContext.insert(Site(id: secondSiteID, label: "Second workspace"))
        relaunchedContext.insert(Asset(
            id: secondAssetID,
            siteID: secondSiteID,
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Second asset"
        ))
        try relaunchedContext.save()
        let secondStore = try MutationJournalStoreV1(
            modelContext: relaunchedContext,
            identity: secondIdentity,
            generationID: secondGeneration
        )
        let secondSite = try WorkspaceEntityIdentityV1(kind: .site, id: secondSiteID)
        let secondAsset = try WorkspaceEntityIdentityV1(kind: .asset, id: secondAssetID)
        let secondCurrent = try secondStore.currentRevision(
            writerInstanceID: MutationJournalHarnessV1.id(75)
        )
        let secondExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: secondIdentity.workspaceID,
            generationID: secondGeneration,
            writerInstanceID: secondCurrent.writerInstanceID,
            workspaceRevision: 0,
            entityRevisions: [
                .init(identity: secondSite, revision: 0),
                .init(identity: secondAsset, revision: 0),
            ]
        )
        let sharedMutationID = request.mutationID
        let secondEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: sharedMutationID,
                expectedRevision: secondExpected,
                command: .createFirstSign(.init(
                    siteID: secondSiteID,
                    newSite: .init(
                        id: secondSiteID,
                        label: "Second workspace",
                        address: nil,
                        timeZoneID: "UTC"
                    ),
                    assetID: secondAssetID,
                    assetLabel: "Second asset",
                    packID: "test.pack",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    createdAt: harness.date(24)
                ))
            ),
            identity: secondIdentity
        )
        let secondReceipt = try secondStore.commit(
            envelope: secondEnvelope,
            writerInstanceID: secondCurrent.writerInstanceID,
            affectedEntities: [secondSite, secondAsset],
            committedAt: harness.date(25)
        )
        XCTAssertEqual(secondReceipt.mutationID, receipt.mutationID)
        XCTAssertNotEqual(secondReceipt.identity.workspaceID, receipt.identity.workspaceID)
        XCTAssertEqual(try secondStore.receipt(mutationID: sharedMutationID), secondReceipt)
        XCTAssertEqual(try harness.store.receipt(mutationID: sharedMutationID), receipt)
    }

    @MainActor
    func testV10_02H01StaleForeignUnknownTamperedSequenceAndReversalRejection() throws {
        let harness = try MutationJournalHarnessV1()
        let initial = try harness.currentExpected()
        let envelope = try harness.envelope(harness.request(mutation: 30, label: "Accepted", expected: initial))
        let receipt = try harness.commit(envelope, entities: [harness.site])

        let revisionMismatchSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: receipt.resultingRevision.workspaceRevision,
            lastLocalSequence: receipt.identity.localSequence,
            receipts: [.init(
                envelopeData: try envelope.canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: nil,
                semanticReversalData: nil
            )],
            quarantines: [],
            entityRevisions: [.init(identity: harness.site, revision: 0)]
        )
        XCTAssertThrowsError(
            try MutationJournalStoreV1.validateImportedSnapshot(revisionMismatchSnapshot)
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        let mismatchContainer = try MutationJournalHarnessV1.makeContainer(
            name: "V10_02RevisionMismatchImport"
        )
        let mismatchContext = mismatchContainer.mainContext
        mismatchContext.autosaveEnabled = false
        let mismatchStore = try MutationJournalStoreV1(
            modelContext: mismatchContext,
            identity: harness.identity,
            generationID: harness.generationID
        )
        XCTAssertThrowsError(try mismatchStore.replaceHistory(
            with: revisionMismatchSnapshot,
            identityDisposition: .preserve
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(
            try mismatchContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            0
        )
        XCTAssertEqual(
            try mismatchContext.fetchCount(FetchDescriptor<EntityMutationRevisionRow>()),
            0
        )

        let stale = try harness.envelope(harness.request(mutation: 31, label: "Stale", expected: initial))
        XCTAssertThrowsError(try harness.commit(stale, entities: [harness.asset])) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
        }
        let current = try harness.store.currentRevision(writerInstanceID: harness.writerInstanceID)
        let staleEntityExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: harness.workspaceID,
            generationID: harness.generationID,
            writerInstanceID: harness.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [.init(identity: harness.site, revision: 0)]
        )
        let staleEntity = try harness.envelope(harness.request(
            mutation: 34,
            label: "Stale entity",
            expected: staleEntityExpected
        ))
        XCTAssertThrowsError(try harness.commit(staleEntity, entities: [harness.site])) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleEntityRevision(harness.site))
        }
        let missingExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: harness.workspaceID,
            generationID: harness.generationID,
            writerInstanceID: harness.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: []
        )
        let missingTargetEnvelope = try harness.envelope(harness.request(
            mutation: 38,
            label: "Missing target token",
            expected: missingExpected
        ))
        XCTAssertThrowsError(try harness.commit(
            missingTargetEnvelope,
            entities: [harness.site, harness.asset]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }

        let foreignWorkspace = WorkspaceID(rawValue: MutationJournalHarnessV1.id(90))
        let foreignRevision = try WorkspaceRevisionV1(
            workspaceID: foreignWorkspace,
            generationID: harness.generationID,
            revision: 0,
            entityRevisions: []
        )
        let foreignRequest = try harness.request(
            mutation: 32,
            label: "Foreign",
            expected: WorkspaceExpectedRevisionV1(snapshot: foreignRevision)
        )
        XCTAssertThrowsError(try MutationEnvelopeV1(request: foreignRequest, identity: harness.identity))

        var unknownVersion = try envelope.canonicalData()
        unknownVersion = try XCTUnwrap(String(data: unknownVersion, encoding: .utf8))
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
            .data(using: .utf8)!
        XCTAssertThrowsError(try MutationEnvelopeV1.decodeCanonical(from: unknownVersion))
        let unknownCommand = try XCTUnwrap(String(data: try envelope.canonicalData(), encoding: .utf8))
            .replacingOccurrences(of: "create_first_sign", with: "future_command")
            .data(using: .utf8)!
        XCTAssertThrowsError(try MutationEnvelopeV1.decodeCanonical(from: unknownCommand))

        let rows = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>())
        let row = try XCTUnwrap(rows.first)
        row.receiptSHA256 = String(repeating: "0", count: 64)
        try harness.context.save()
        XCTAssertThrowsError(try harness.store.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        row.receiptSHA256 = try receipt.canonicalSHA256()
        try harness.context.save()
        try harness.store.validateAll()
        XCTAssertEqual(receipt.identity.localSequence, 1)

        let originalReceiptData = row.receiptData
        let dependencyTamper = try XCTUnwrap(
            String(data: originalReceiptData, encoding: .utf8)
        )
            .replacingOccurrences(of: "content-b", with: "content-c")
            .data(using: .utf8)!
        row.receiptData = dependencyTamper
        row.receiptSHA256 = MutationJournalHarnessV1.sha256(dependencyTamper)
        try harness.context.save()
        XCTAssertThrowsError(try harness.store.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        row.receiptData = originalReceiptData
        row.receiptSHA256 = try receipt.canonicalSHA256()
        try harness.context.save()
        try harness.store.validateAll()

        let targetPlan = try harness.reversalPlan(mutation: 30)
        let basis = try ReversalBasisV1(
            targetMutationID: envelope.mutationID,
            targetReceiptIdentity: receipt.identity,
            plan: targetPlan
        )
        let encodedBasis = try WorkspaceMutationCanonicalV1.data(basis)
        let decodedBasis = try ReversalBasisV1.decodeCanonical(from: encodedBasis)
        XCTAssertEqual(decodedBasis.planDigest, targetPlan.planDigest)
        let tamperedBasis = try XCTUnwrap(String(data: encodedBasis, encoding: .utf8))
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
            .data(using: .utf8)!
        XCTAssertThrowsError(try ReversalBasisV1.decodeCanonical(from: tamperedBasis))
        XCTAssertThrowsError(try ReversalBasisV1(
            targetMutationID: try MutationIDV1(rawValue: MutationJournalHarnessV1.id(33)),
            targetReceiptIdentity: receipt.identity,
            plan: targetPlan
        ))

        let reversalRequest = WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: MutationJournalHarnessV1.id(35)),
            expectedRevision: try harness.currentExpected(),
            command: .updateSiteTimeZone(.init(
                siteID: harness.site.id,
                timeZoneID: "UTC",
                confirmedAt: harness.date(35)
            ))
        )
        let reversalExecution = try SemanticReversalExecutionV1(
            targetMutationID: envelope.mutationID,
            targetReceiptIdentity: receipt.identity,
            reversalBasisSHA256: basis.canonicalSHA256(),
            planDigest: targetPlan.planDigest,
            compensatingMutationIDs: [reversalRequest.mutationID]
        )
        let reversalReplayIdentitySHA256 = try SemanticReversalReplayIdentityV1(
            request: reversalRequest,
            identity: harness.identity,
            targetMutationID: envelope.mutationID,
            planDigest: targetPlan.planDigest,
            compensatingMutationIDs: [reversalRequest.mutationID]
        ).canonicalSHA256()
        let reversalEnvelope = try MutationEnvelopeV1(
            request: reversalRequest,
            identity: harness.identity,
            sourceKind: .semanticReversal,
            causationMutationID: envelope.mutationID,
            correlationID: MutationJournalHarnessV1.id(36),
            semanticReversalReplayIdentitySHA256: reversalReplayIdentitySHA256,
            semanticReversalExecution: reversalExecution
        )
        let reversalResult = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: harness.workspaceID,
                generationID: harness.generationID,
                writerInstanceID: harness.writerInstanceID,
                workspaceRevision: 2,
                entityRevisions: [.init(identity: harness.site, revision: 2)]
            )
        )
        let reversalIdentity = MutationReceiptIdentityV1(
            workspaceID: harness.workspaceID,
            replicaID: harness.replicaID,
            localSequence: 2
        )
        let reversalReceipt = try MutationReceiptV1(
            identity: reversalIdentity,
            envelope: reversalEnvelope,
            resultingRevision: reversalResult,
            postImages: [.site(
                id: harness.site.id,
                revision: 2,
                semanticSHA256: String(repeating: "c", count: 64)
            )],
            reversesMutationID: envelope.mutationID,
            committedAt: harness.date(36)
        )
        let tamperedLink = try SemanticReversalReceiptV1(
            reversalReceiptIdentity: reversalIdentity,
            reversesMutationID: envelope.mutationID,
            targetReceiptIdentity: receipt.identity,
            reversalBasisSHA256: try basis.canonicalSHA256(),
            planDigest: String(repeating: "b", count: 64),
            compensatingMutationIDs: [try MutationIDV1(rawValue: MutationJournalHarnessV1.id(37))],
            resultingRevision: reversalResult
        )
        let hostileSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: 2,
            lastLocalSequence: 2,
            receipts: [
                .init(
                    envelopeData: try envelope.canonicalData(),
                    receiptData: try receipt.canonicalData(),
                    reversalBasisData: try basis.canonicalData(),
                    semanticReversalData: nil
                ),
                .init(
                    envelopeData: try reversalEnvelope.canonicalData(),
                    receiptData: try reversalReceipt.canonicalData(),
                    reversalBasisData: nil,
                    semanticReversalData: try tamperedLink.canonicalData()
                ),
            ],
            quarantines: [],
            entityRevisions: [.init(identity: harness.site, revision: 2)]
        )
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(hostileSnapshot)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        let hostileContainer = try MutationJournalHarnessV1.makeContainer(name: "V10_02HostileImport")
        let hostileContext = hostileContainer.mainContext
        hostileContext.autosaveEnabled = false
        let hostileStore = try MutationJournalStoreV1(
            modelContext: hostileContext,
            identity: harness.identity,
            generationID: harness.generationID
        )
        XCTAssertThrowsError(try hostileStore.replaceHistory(
            with: hostileSnapshot,
            identityDisposition: .preserve
        ))
        XCTAssertEqual(try hostileContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)

        let tombstoneHarness = try MutationJournalHarnessV1()
        let persistedAsset = try XCTUnwrap(
            try tombstoneHarness.context.fetch(FetchDescriptor<Asset>()).first
        )
        tombstoneHarness.context.delete(persistedAsset)
        let deleteEnvelope = try MutationEnvelopeV1(
            request: .init(
                mutationID: try MutationIDV1(rawValue: MutationJournalHarnessV1.id(39)),
                expectedRevision: try tombstoneHarness.currentExpected(),
                command: .deleteAsset(.init(
                    deletionID: MutationJournalHarnessV1.id(40),
                    assetID: tombstoneHarness.asset.id,
                    planDigest: String(repeating: "d", count: 64)
                ))
            ),
            identity: tombstoneHarness.identity
        )
        let deletionReceipt = try tombstoneHarness.commit(
            deleteEnvelope,
            entities: [tombstoneHarness.asset]
        )
        guard case .tombstone = try XCTUnwrap(deletionReceipt.postImages.first) else {
            return XCTFail("Deleted entity must produce a typed tombstone")
        }
        try tombstoneHarness.store.validateAll()
        tombstoneHarness.context.insert(Asset(
            id: tombstoneHarness.asset.id,
            siteID: tombstoneHarness.site.id,
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Illicit resurrection"
        ))
        try tombstoneHarness.context.save()
        XCTAssertThrowsError(
            try MutationReceiptRecoveryServiceV1(store: tombstoneHarness.store)
                .recoverBeforeWriterActivation()
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }

        let reversalHarness = try MutationJournalHarnessV1()
        let targetRequest = try reversalHarness.request(mutation: 60, label: "Target")
        let compensatingCommand = try reversalHarness.request(
            mutation: 61,
            label: "Compensation",
            expected: targetRequest.expectedRevision
        ).command
        let targetPlan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "target")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand]
        )
        _ = try reversalHarness.writer.execute(targetRequest, reversalPlan: targetPlan)
        let reversalMutationID = try MutationIDV1(rawValue: MutationJournalHarnessV1.id(61))
        let reversalRequest = WorkspaceMutationRequestV1(
            mutationID: reversalMutationID,
            expectedRevision: try reversalHarness.currentExpected(),
            command: compensatingCommand
        )
        let targetRow = try XCTUnwrap(
            try reversalHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == targetRequest.mutationID.rawValue }
        )
        let originalBasisData = try XCTUnwrap(targetRow.reversalBasisData)
        let originalBasisSHA256 = try XCTUnwrap(targetRow.reversalBasisSHA256)
        let mismatchedBasisData = try XCTUnwrap(
            String(data: originalBasisData, encoding: .utf8)?
                .replacingOccurrences(
                    of: WorkspaceCommandKindV1.createFirstSign.rawValue,
                    with: WorkspaceCommandKindV1.updateSiteTimeZone.rawValue
                )
                .data(using: .utf8)
        )
        let mismatchedBasis = try ReversalBasisV1.decodeCanonical(from: mismatchedBasisData)
        XCTAssertNotEqual(
            mismatchedBasis.compensatingCommandKinds,
            targetPlan.compensatingCommands.map(\.kind)
        )
        targetRow.reversalBasisData = mismatchedBasisData
        targetRow.reversalBasisSHA256 = try mismatchedBasis.canonicalSHA256()
        try reversalHarness.context.save()
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: targetPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReversal)
        }
        targetRow.reversalBasisData = originalBasisData
        targetRow.reversalBasisSHA256 = originalBasisSHA256
        try reversalHarness.context.save()
        let preflightMultiCommandPlan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "target")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand, compensatingCommand]
        )
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: preflightMultiCommandPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReversal)
        }
        let acceptedReversal = try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: targetPlan,
            compensatingMutationIDs: [reversalMutationID]
        )
        XCTAssertEqual(
            try reversalHarness.writer.executeSemanticReversal(
                reversalRequest,
                targetMutationID: targetRequest.mutationID,
                plan: targetPlan,
                compensatingMutationIDs: [reversalMutationID]
            ),
            acceptedReversal
        )
        let acceptedSemanticSnapshot = try reversalHarness.store.exportSnapshot()
        let acceptedSemanticReplaySHA256 = try SemanticReversalReplayIdentityV1(
            request: reversalRequest,
            identity: reversalHarness.identity,
            targetMutationID: targetRequest.mutationID,
            planDigest: targetPlan.planDigest,
            compensatingMutationIDs: [reversalMutationID]
        ).canonicalSHA256()

        let changedPlan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "changed")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand]
        )
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: changedPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        let changedPlanReplaySHA256 = try SemanticReversalReplayIdentityV1(
            request: reversalRequest,
            identity: reversalHarness.identity,
            targetMutationID: targetRequest.mutationID,
            planDigest: changedPlan.planDigest,
            compensatingMutationIDs: [reversalMutationID]
        ).canonicalSHA256()
        let semanticQuarantine = try XCTUnwrap(
            try reversalHarness.store.exportSnapshot().quarantines.first
        )
        XCTAssertEqual(
            semanticQuarantine.identityDomain,
            .semanticReversalReplayIdentity
        )
        XCTAssertEqual(
            semanticQuarantine.acceptedIdentitySHA256,
            acceptedSemanticReplaySHA256
        )
        XCTAssertEqual(
            semanticQuarantine.conflictingIdentitySHA256,
            changedPlanReplaySHA256
        )
        let acceptedSemanticEnvelope = try XCTUnwrap(
            try acceptedSemanticSnapshot.receipts
                .map { try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData) }
                .first { $0.mutationID == reversalMutationID }
        )
        XCTAssertNotEqual(
            semanticQuarantine.acceptedIdentitySHA256,
            try acceptedSemanticEnvelope.canonicalSHA256()
        )

        let changedTargetID = try MutationIDV1(rawValue: MutationJournalHarnessV1.id(62))
        let changedTargetPlan = try SemanticReversalPlanV1(
            mutationID: changedTargetID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "target")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand]
        )
        let changedCompensatingMutationID = try MutationIDV1(
            rawValue: MutationJournalHarnessV1.id(63)
        )
        let replayVariants: [(String, MutationIDV1, String, [MutationIDV1])] = [
            ("missing-target", changedTargetID, changedTargetPlan.planDigest, [reversalMutationID]),
            ("compensating-id", targetRequest.mutationID, targetPlan.planDigest, [changedCompensatingMutationID]),
        ]
        for (label, variantTarget, variantPlanDigest, variantCompensatingIDs) in replayVariants {
            let variantContainer = try MutationJournalHarnessV1.makeContainer(
                name: "V10_02SemanticReplay-\(label)"
            )
            let variantStore = try MutationJournalStoreV1(
                modelContext: variantContainer.mainContext,
                identity: reversalHarness.identity,
                generationID: reversalHarness.generationID
            )
            try variantStore.replaceHistory(
                with: acceptedSemanticSnapshot,
                identityDisposition: .preserve
            )
            let conflictingReplaySHA256 = try SemanticReversalReplayIdentityV1(
                request: reversalRequest,
                identity: reversalHarness.identity,
                targetMutationID: variantTarget,
                planDigest: variantPlanDigest,
                compensatingMutationIDs: variantCompensatingIDs
            ).canonicalSHA256()
            XCTAssertThrowsError(try variantStore.resolveSemanticReversalReplay(
                request: reversalRequest,
                replayIdentitySHA256: conflictingReplaySHA256,
                detectedAt: reversalHarness.date(64)
            )) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined, label)
            }
            let quarantinedVariant = try variantStore.exportSnapshot()
            let quarantine = try XCTUnwrap(quarantinedVariant.quarantines.first, label)
            XCTAssertEqual(quarantine.identityDomain, .semanticReversalReplayIdentity, label)
            XCTAssertEqual(quarantine.acceptedIdentitySHA256, acceptedSemanticReplaySHA256, label)
            XCTAssertEqual(quarantine.conflictingIdentitySHA256, conflictingReplaySHA256, label)

            let restoredContainer = try MutationJournalHarnessV1.makeContainer(
                name: "V10_02SemanticReplayRestore-\(label)"
            )
            let restoredStore = try MutationJournalStoreV1(
                modelContext: restoredContainer.mainContext,
                identity: reversalHarness.identity,
                generationID: reversalHarness.generationID
            )
            try restoredStore.replaceHistory(
                with: quarantinedVariant,
                identityDisposition: .preserve
            )
            XCTAssertEqual(
                try restoredStore.exportSnapshot().quarantines,
                quarantinedVariant.quarantines,
                label
            )
        }
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: changedTargetID,
            plan: changedTargetPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: targetPlan,
            compensatingMutationIDs: [changedCompensatingMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }

        let multiCommandPlan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [reversalHarness.site, reversalHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "target")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensatingCommand, compensatingCommand]
        )
        XCTAssertThrowsError(try reversalHarness.writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: multiCommandPlan,
            compensatingMutationIDs: [reversalMutationID]
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(
            try reversalHarness.writer.durableReceipt(mutationID: reversalMutationID),
            try reversalHarness.writer.durableReceipt(mutationID: acceptedReversal.mutationID)
        )
        XCTAssertEqual(
            try reversalHarness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
            1
        )
        XCTAssertEqual(reversalHarness.adapter.applyCount, 2)
        let replayRelaunchContext = ModelContext(reversalHarness.container)
        replayRelaunchContext.autosaveEnabled = false
        XCTAssertEqual(
            try replayRelaunchContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
            1
        )
        XCTAssertEqual(
            try replayRelaunchContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            2
        )
        let reversalRow = try XCTUnwrap(
            try reversalHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == reversalMutationID.rawValue }
        )
        let originalSemanticData = try XCTUnwrap(reversalRow.semanticReversalData)
        let semanticReceipt = try SemanticReversalReceiptV1.decodeCanonical(
            from: originalSemanticData
        )
        let mismatchedResultingRevision = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: semanticReceipt.resultingRevision.workspaceID,
                generationID: semanticReceipt.resultingRevision.generationID,
                writerInstanceID: MutationJournalHarnessV1.id(66),
                workspaceRevision: semanticReceipt.resultingRevision.workspaceRevision + 1,
                entityRevisions: semanticReceipt.resultingRevision.entityRevisions
            )
        )
        let mismatchedSemanticReceipt = try SemanticReversalReceiptV1(
            reversalReceiptIdentity: semanticReceipt.reversalReceiptIdentity,
            reversesMutationID: semanticReceipt.reversesMutationID,
            targetReceiptIdentity: semanticReceipt.targetReceiptIdentity,
            reversalBasisSHA256: semanticReceipt.reversalBasisSHA256,
            planDigest: semanticReceipt.planDigest,
            compensatingMutationIDs: semanticReceipt.compensatingMutationIDs,
            resultingRevision: mismatchedResultingRevision
        )
        reversalRow.semanticReversalData = try mismatchedSemanticReceipt.canonicalData()
        try reversalHarness.context.save()
        XCTAssertThrowsError(try reversalHarness.store.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        reversalRow.semanticReversalData = originalSemanticData
        try reversalHarness.context.save()
        XCTAssertNoThrow(try reversalHarness.store.validateAll())

        let planReplayHarness = try MutationJournalHarnessV1()
        let plannedRequest = try planReplayHarness.request(mutation: 64, label: "Planned")
        let plannedCompensation = try planReplayHarness.request(
            mutation: 65,
            label: "Planned compensation",
            expected: plannedRequest.expectedRevision
        ).command
        let acceptedPlan = try SemanticReversalPlanV1(
            mutationID: plannedRequest.mutationID,
            commandKind: plannedRequest.command.kind,
            expectedRevision: plannedRequest.expectedRevision,
            prospectiveTargets: [planReplayHarness.site, planReplayHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "accepted")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [plannedCompensation]
        )
        _ = try planReplayHarness.writer.execute(plannedRequest, reversalPlan: acceptedPlan)
        let divergentPlan = try SemanticReversalPlanV1(
            mutationID: plannedRequest.mutationID,
            commandKind: plannedRequest.command.kind,
            expectedRevision: plannedRequest.expectedRevision,
            prospectiveTargets: [planReplayHarness.site, planReplayHarness.asset],
            requiredSemanticValues: [.init(key: "before", value: "divergent")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [plannedCompensation]
        )
        XCTAssertThrowsError(try planReplayHarness.writer.execute(
            plannedRequest,
            reversalPlan: divergentPlan
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try planReplayHarness.writer.execute(
            plannedRequest,
            reversalPlan: acceptedPlan
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(planReplayHarness.adapter.applyCount, 1)

        let missingTargetHarness = try MutationJournalHarnessV1()
        let missingTargetReplay = try missingTargetHarness.acceptedSemanticReplay(
            targetMutation: 67,
            reversalMutation: 68
        )
        let missingTargetRow = try XCTUnwrap(
            try missingTargetHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == missingTargetReplay.targetMutationID.rawValue }
        )
        missingTargetHarness.context.delete(missingTargetRow)
        try missingTargetHarness.context.save()
        XCTAssertThrowsError(try missingTargetHarness.writer.executeSemanticReversal(
            missingTargetReplay.request,
            targetMutationID: missingTargetReplay.targetMutationID,
            plan: missingTargetReplay.plan,
            compensatingMutationIDs: missingTargetReplay.compensatingMutationIDs
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(missingTargetHarness.adapter.applyCount, 2)

        let corruptBasisHarness = try MutationJournalHarnessV1()
        let corruptBasisReplay = try corruptBasisHarness.acceptedSemanticReplay(
            targetMutation: 69,
            reversalMutation: 70
        )
        let corruptBasisRow = try XCTUnwrap(
            try corruptBasisHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == corruptBasisReplay.targetMutationID.rawValue }
        )
        let corruptBasisData = try XCTUnwrap(corruptBasisRow.reversalBasisData)
        let alteredBasisData = try XCTUnwrap(
            String(data: corruptBasisData, encoding: .utf8)?
                .replacingOccurrences(
                    of: WorkspaceCommandKindV1.createFirstSign.rawValue,
                    with: WorkspaceCommandKindV1.updateSiteTimeZone.rawValue
                )
                .data(using: .utf8)
        )
        let alteredBasis = try ReversalBasisV1.decodeCanonical(from: alteredBasisData)
        corruptBasisRow.reversalBasisData = alteredBasisData
        corruptBasisRow.reversalBasisSHA256 = try alteredBasis.canonicalSHA256()
        try corruptBasisHarness.context.save()
        XCTAssertThrowsError(try corruptBasisHarness.writer.executeSemanticReversal(
            corruptBasisReplay.request,
            targetMutationID: corruptBasisReplay.targetMutationID,
            plan: corruptBasisReplay.plan,
            compensatingMutationIDs: corruptBasisReplay.compensatingMutationIDs
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(corruptBasisHarness.adapter.applyCount, 2)
    }

    @MainActor
    func testV10_02I01EveryAtomicCrashBoundaryRecoversExactlyOnce() throws {
        let logicalBoundaries = try Self.loadCorpus().interruptionBoundaries
        XCTAssertEqual(logicalBoundaries.count, 7)
        XCTAssertEqual(Set(logicalBoundaries).count, logicalBoundaries.count)
        XCTAssertEqual(MutationJournalFaultBoundaryV1.allCases.count, 3)

        for (offset, boundary) in MutationJournalFaultBoundaryV1.allCases.enumerated() {
            let harness = try MutationJournalHarnessV1(failureBoundary: boundary)
            let request = try harness.request(
                mutation: UInt8(40 + offset),
                label: boundary.rawValue
            )
            let envelope = try MutationEnvelopeV1(request: request, identity: harness.identity)
            XCTAssertThrowsError(try harness.writer.execute(request)) {
                XCTAssertEqual($0 as? MutationJournalFailureV1, .injected(boundary))
            }
            XCTAssertEqual(harness.adapter.rollbackCount, 1)

            let relaunchedContext = ModelContext(harness.container)
            relaunchedContext.autosaveEnabled = false
            let relaunched = try MutationJournalStoreV1(
                modelContext: relaunchedContext,
                identity: harness.identity,
                generationID: harness.generationID
            )
            try MutationReceiptRecoveryServiceV1(store: relaunched).recoverBeforeWriterActivation()
            if boundary == .afterSaveBeforeReturn {
                let durable = try XCTUnwrap(relaunched.receipt(mutationID: envelope.mutationID))
                XCTAssertEqual(
                    try relaunched.resolveReplay(envelope: envelope, detectedAt: harness.date(60)),
                    durable
                )
                XCTAssertEqual(try relaunchedContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
                XCTAssertEqual(try relaunched.currentRevision(writerInstanceID: harness.writerInstanceID).revision, 1)
            } else {
                XCTAssertNil(try relaunched.receipt(mutationID: envelope.mutationID))
                XCTAssertEqual(try relaunchedContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
                XCTAssertEqual(try relaunched.currentRevision(writerInstanceID: harness.writerInstanceID).revision, 0)
            }
        }
    }

    @MainActor
    func testV10_02R01MigrationLifecycleAndReplicaIdentityMatrix() throws {
        let corpus = try Self.loadCorpus()
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeRelease, .v9)
        XCTAssertEqual(
            PersistentSchemaReleaseRegistryV1.releases,
            [.v1, .v2, .v3, .v4, .v5, .v6, .v7, .v8, .v9]
        )
        XCTAssertEqual(PersistentSchemaV4.models.count, PersistentSchemaV3.models.count + 4)
        XCTAssertEqual(PersistentSchemaV5.models.count, PersistentSchemaV4.models.count + 1)
        XCTAssertEqual(PersistentSchemaV6.models.count, PersistentSchemaV5.models.count + 6)
        XCTAssertEqual(PersistentSchemaV7.models.count, PersistentSchemaV6.models.count + 1)
        XCTAssertEqual(PersistentSchemaV8.models.count, PersistentSchemaV7.models.count + 1)
        XCTAssertEqual(PersistentSchemaV9.models.count, PersistentSchemaV8.models.count + 5)
        XCTAssertEqual(PersistentSchemaMigrationPlanV3.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV4.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV5.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV6.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaReleaseV1.v5.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v6.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v7.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v8.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v9.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaMigrationPlanV8.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV8.stages.count, 1)

        XCTAssertEqual(corpus.restoreMatrix.map(\.mode), ["empty", "replace", "clone", "fork"])
        XCTAssertTrue(corpus.restoreMatrix.allSatisfy(\.preservesReceiptHistory))
        XCTAssertTrue(corpus.restoreMatrix.filter(\.mintsDestinationReplicaID).allSatisfy {
            !$0.preservesDestinationWorkspaceID
        })
        XCTAssertEqual(corpus.lifecycle.persistentSchemaVersion, 4)
        XCTAssertFalse(corpus.lifecycle.migrationV3ToV4FabricatesHistoricReceipts)

        let harness = try MutationJournalHarnessV1()
        let original = try harness.commit(
            harness.envelope(harness.request(mutation: 50, label: "History")),
            entities: [harness.asset]
        )
        let beforeDelete = try harness.currentExpected()
        let deleteEnvelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: try MutationIDV1(rawValue: MutationJournalHarnessV1.id(51)),
                expectedRevision: beforeDelete,
                command: .deleteAsset(.init(
                    deletionID: MutationJournalHarnessV1.id(52),
                    assetID: harness.asset.id,
                    planDigest: String(repeating: "a", count: 64)
                ))
            ),
            identity: harness.identity,
            correlationID: MutationJournalHarnessV1.id(53)
        )
        let deletionReceipt = try harness.commit(deleteEnvelope, entities: [harness.asset])
        let snapshot = try harness.store.exportSnapshot()
        XCTAssertEqual(snapshot.receipts.count, 2)
        XCTAssertEqual(try harness.store.receipt(mutationID: deletionReceipt.mutationID), deletionReceipt)
        let incomingSequenceAhead: UInt64 = 7
        let aheadSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: snapshot.workspaceRevision,
            lastLocalSequence: incomingSequenceAhead,
            receipts: snapshot.receipts,
            quarantines: snapshot.quarantines,
            entityRevisions: snapshot.entityRevisions
        )

        for (offset, mode) in corpus.restoreMatrix.enumerated() {
            let destinationWorkspace = mode.mintsDestinationReplicaID
                ? MutationJournalHarnessV1.id(UInt8(80 + offset))
                : harness.workspaceID.rawValue
            let destinationReplica = mode.mintsDestinationReplicaID
                ? MutationJournalHarnessV1.id(UInt8(90 + offset))
                : harness.replicaID.rawValue
            let destinationGeneration = mode.mintsDestinationReplicaID
                ? MutationJournalHarnessV1.id(UInt8(100 + offset))
                : harness.generationID
            let destinationIdentity = try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: destinationWorkspace),
                replicaID: ReplicaID(rawValue: destinationReplica)
            )
            let destinationContainer = try MutationJournalHarnessV1.makeContainer(
                name: "V10_02Restore-\(mode.mode)"
            )
            let destinationContext = destinationContainer.mainContext
            destinationContext.autosaveEnabled = false
            let destinationStore = try MutationJournalStoreV1(
                modelContext: destinationContext,
                identity: destinationIdentity,
                generationID: destinationGeneration
            )
            try destinationStore.replaceHistory(
                with: aheadSnapshot,
                identityDisposition: mode.mintsDestinationReplicaID
                    ? .destination(destinationIdentity, generationID: destinationGeneration)
                    : .preserve
            )
            let imported = try destinationStore.exportSnapshot()
            XCTAssertEqual(imported.receipts, snapshot.receipts, mode.mode)
            XCTAssertEqual(imported.workspaceRevision, snapshot.workspaceRevision, mode.mode)
            XCTAssertEqual(
                imported.lastLocalSequence,
                mode.mintsDestinationReplicaID ? 0 : incomingSequenceAhead,
                mode.mode
            )
            if mode.mintsDestinationReplicaID {
                XCTAssertNotEqual(destinationIdentity.replicaID, harness.replicaID, mode.mode)
            } else {
                XCTAssertEqual(destinationIdentity, harness.identity, mode.mode)
            }
            var expectedReceiptCount = 2
            if !mode.mintsDestinationReplicaID {
                destinationContext.insert(Site(
                    id: harness.site.id,
                    label: "Journal site",
                    address: nil,
                    timeZoneID: "UTC",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000)
                ))
                destinationContext.insert(Asset(
                    id: harness.asset.id,
                    siteID: harness.site.id,
                    packID: "test.pack",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    label: "Journal asset",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_001)
                ))
                try destinationContext.save()
                let writerInstanceID = MutationJournalHarnessV1.id(110)
                let importedRevision = try destinationStore.currentRevision(
                    writerInstanceID: writerInstanceID
                )
                let importedByIdentity = Dictionary(uniqueKeysWithValues:
                    importedRevision.entityRevisions.map { ($0.identity, $0.revision) }
                )
                let expected = try WorkspaceExpectedRevisionV1(
                    workspaceID: destinationIdentity.workspaceID,
                    generationID: destinationGeneration,
                    writerInstanceID: writerInstanceID,
                    workspaceRevision: importedRevision.revision,
                    entityRevisions: [.init(
                        identity: harness.asset,
                        revision: importedByIdentity[harness.asset, default: 0]
                    )]
                )
                let localWriter = try WorkspaceWriterV1(
                    identity: destinationIdentity,
                    generationID: destinationGeneration,
                    initialRevision: importedRevision,
                    clock: MutationJournalFixedClockV1(),
                    idSource: MutationJournalFixedIDSourceV1(value: writerInstanceID),
                    fileAuthority: MutationJournalFileAuthorityV1(),
                    adapter: MutationJournalFaultAdapterV1(),
                    journalStore: destinationStore
                )
                let localMutationID = try MutationIDV1(
                    rawValue: MutationJournalHarnessV1.id(111)
                )
                _ = try localWriter.execute(.init(
                    mutationID: localMutationID,
                    expectedRevision: expected,
                    command: .createFirstSign(.init(
                        siteID: harness.site.id,
                        newSite: nil,
                        assetID: harness.asset.id,
                        assetLabel: "Local destination write",
                        packID: "test.pack",
                        packSchemaVersion: 1,
                        packContentVersion: 1,
                        createdAt: Date(timeIntervalSince1970: 1_800_000_111)
                    ))
                ))
                XCTAssertEqual(
                    try XCTUnwrap(
                        localWriter.durableReceipt(mutationID: localMutationID)
                    ).identity.localSequence,
                    incomingSequenceAhead + 1
                )
                let localProjection = try XCTUnwrap(destinationStore.exportSnapshot()
                    .entityRevisions.first { $0.identity == harness.asset })
                XCTAssertNil(localProjection.externalProjectionSHA256)
                let relaunchedContext = ModelContext(destinationContainer)
                relaunchedContext.autosaveEnabled = false
                let relaunchedStore = try MutationJournalStoreV1(
                    modelContext: relaunchedContext,
                    identity: destinationIdentity,
                    generationID: destinationGeneration,
                    allowStateBootstrap: false
                )
                XCTAssertNoThrow(
                    try MutationReceiptRecoveryServiceV1(store: relaunchedStore)
                        .recoverBeforeWriterActivation()
                )
                expectedReceiptCount = 3
            }
            XCTAssertThrowsError(try destinationStore.clearForErase(
                expectedWorkspaceID: WorkspaceID(rawValue: MutationJournalHarnessV1.id(120)),
                expectedGenerationID: MutationJournalHarnessV1.id(121)
            ))
            XCTAssertEqual(
                try destinationStore.exportSnapshot().receipts.count,
                expectedReceiptCount,
                mode.mode
            )
            try destinationStore.clearForErase(
                expectedWorkspaceID: destinationIdentity.workspaceID,
                expectedGenerationID: destinationGeneration
            )
            let erased = try destinationStore.exportSnapshot()
            XCTAssertTrue(erased.receipts.isEmpty, mode.mode)
            XCTAssertTrue(erased.quarantines.isEmpty, mode.mode)
            XCTAssertTrue(erased.entityRevisions.isEmpty, mode.mode)
            XCTAssertEqual(erased.workspaceRevision, 0, mode.mode)
            XCTAssertEqual(erased.lastLocalSequence, 0, mode.mode)
        }
        XCTAssertNotEqual(original.identity.workspaceID.rawValue, harness.replicaID.rawValue)
        XCTAssertEqual(try harness.store.receipt(mutationID: original.mutationID), original)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
    }

    private static func loadCorpus() throws -> MutationEnvelopeReceiptCorpusFixtureV1 {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "V21P02C02MutationEnvelopeReceiptCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/Mutation"
        ) ?? bundle.url(
            forResource: "V21P02C02MutationEnvelopeReceiptCorpusV1",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(
            MutationEnvelopeReceiptCorpusFixtureV1.self,
            from: Data(contentsOf: url)
        )
    }
}

private struct MutationEnvelopeReceiptCorpusFixtureV1: Decodable {
    struct CanonicalVector: Decodable {
        let workspaceID: String
        let mutationID: String
        let commandKind: String
    }

    struct RestoreMode: Decodable {
        let mode: String
        let preservesDestinationWorkspaceID: Bool
        let mintsDestinationReplicaID: Bool
        let preservesReceiptHistory: Bool
    }

    struct Lifecycle: Decodable {
        let persistentSchemaVersion: Int
        let migrationV3ToV4FabricatesHistoricReceipts: Bool
    }

    let canonicalVector: CanonicalVector
    let interruptionBoundaries: [String]
    let restoreMatrix: [RestoreMode]
    let lifecycle: Lifecycle
}

private struct AcceptedSemanticReplayScenarioV1 {
    let request: WorkspaceMutationRequestV1
    let targetMutationID: MutationIDV1
    let plan: SemanticReversalPlanV1
    let compensatingMutationIDs: [MutationIDV1]
}

@MainActor
private final class MutationJournalHarnessV1 {
    let workspaceID = WorkspaceID(rawValue: MutationJournalHarnessV1.id(1))
    let replicaID = ReplicaID(rawValue: MutationJournalHarnessV1.id(2))
    let generationID = MutationJournalHarnessV1.id(3)
    let writerInstanceID = MutationJournalHarnessV1.id(4)
    let site = try! WorkspaceEntityIdentityV1(kind: .site, id: MutationJournalHarnessV1.id(5))
    let asset = try! WorkspaceEntityIdentityV1(kind: .asset, id: MutationJournalHarnessV1.id(6))
    let container: ModelContainer
    let context: ModelContext
    let identity: WorkspaceReplicaIdentityV1
    let store: MutationJournalStoreV1
    let adapter: MutationJournalFaultAdapterV1
    let writer: WorkspaceWriterV1

    init(failureBoundary: MutationJournalFaultBoundaryV1? = nil) throws {
        let installedContainer = try Self.makeContainer(name: "V10_02MutationJournal")
        let installedContext = installedContainer.mainContext
        installedContext.autosaveEnabled = false
        installedContext.insert(Site(
            id: Self.id(5),
            label: "Journal site",
            address: nil,
            timeZoneID: "UTC",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        installedContext.insert(Asset(
            id: Self.id(6),
            siteID: Self.id(5),
            packID: "test.pack",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Journal asset",
            createdAt: Date(timeIntervalSince1970: 1_800_000_001)
        ))
        try installedContext.save()
        let installedIdentity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: Self.id(1)),
            replicaID: ReplicaID(rawValue: Self.id(2))
        )
        let journalStore = try MutationJournalStoreV1(
            modelContext: installedContext,
            identity: installedIdentity,
            generationID: Self.id(3),
            failureInjection: failureBoundary.map {
                MutationJournalFailureInjectionV1(failOnceAt: $0)
            }
        )
        let faultAdapter = MutationJournalFaultAdapterV1()
        container = installedContainer
        context = installedContext
        identity = installedIdentity
        store = journalStore
        adapter = faultAdapter
        writer = try WorkspaceWriterV1(
            identity: installedIdentity,
            generationID: Self.id(3),
            initialRevision: journalStore.currentRevision(writerInstanceID: Self.id(4)),
            clock: MutationJournalFixedClockV1(),
            idSource: MutationJournalFixedIDSourceV1(value: Self.id(4)),
            fileAuthority: MutationJournalFileAuthorityV1(),
            adapter: faultAdapter,
            journalStore: journalStore
        )
    }

    static func makeContainer(name: String) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV5.models,
            version: PersistentSchemaV5.versionIdentifier
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                name,
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
    }

    func date(_ offset: UInt8) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(offset))
    }

    func currentExpected() throws -> WorkspaceExpectedRevisionV1 {
        let current = try store.currentRevision(writerInstanceID: writerInstanceID)
        let known = Dictionary(
            uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) }
        )
        return try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [site, asset].map {
                WorkspaceEntityRevisionV1(identity: $0, revision: known[$0, default: 0])
            }
        )
    }

    func request(
        mutation: UInt8,
        label: String,
        expected: WorkspaceExpectedRevisionV1? = nil
    ) throws -> WorkspaceMutationRequestV1 {
        WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: Self.id(mutation)),
            expectedRevision: expected ?? (try currentExpected()),
            command: .createFirstSign(.init(
                siteID: site.id,
                newSite: .init(id: site.id, label: "Site", address: nil, timeZoneID: "UTC"),
                assetID: asset.id,
                assetLabel: label,
                packID: "test.pack",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: date(1)
            ))
        )
    }

    func envelope(_ request: WorkspaceMutationRequestV1) throws -> MutationEnvelopeV1 {
        try MutationEnvelopeV1(
            request: request,
            identity: identity,
            contentDependencyIDs: ["content-b", "content-a"],
            correlationID: Self.id(7)
        )
    }

    func acceptedSemanticReplay(
        targetMutation: UInt8,
        reversalMutation: UInt8
    ) throws -> AcceptedSemanticReplayScenarioV1 {
        let targetRequest = try request(mutation: targetMutation, label: "Replay target")
        let compensation = try request(
            mutation: reversalMutation,
            label: "Replay compensation",
            expected: targetRequest.expectedRevision
        ).command
        let plan = try SemanticReversalPlanV1(
            mutationID: targetRequest.mutationID,
            commandKind: targetRequest.command.kind,
            expectedRevision: targetRequest.expectedRevision,
            prospectiveTargets: [site, asset],
            requiredSemanticValues: [.init(key: "before", value: "replay")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [compensation]
        )
        _ = try writer.execute(targetRequest, reversalPlan: plan)
        let reversalID = try MutationIDV1(rawValue: Self.id(reversalMutation))
        let reversalRequest = WorkspaceMutationRequestV1(
            mutationID: reversalID,
            expectedRevision: try currentExpected(),
            command: compensation
        )
        _ = try writer.executeSemanticReversal(
            reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: plan,
            compensatingMutationIDs: [reversalID]
        )
        return AcceptedSemanticReplayScenarioV1(
            request: reversalRequest,
            targetMutationID: targetRequest.mutationID,
            plan: plan,
            compensatingMutationIDs: [reversalID]
        )
    }

    func commit(
        _ envelope: MutationEnvelopeV1,
        entities: [WorkspaceEntityIdentityV1]
    ) throws -> MutationReceiptV1 {
        try store.commit(
            envelope: envelope,
            writerInstanceID: writerInstanceID,
            affectedEntities: entities,
            committedAt: date(70)
        )
    }

    func reversalPlan(mutation: UInt8) throws -> SemanticReversalPlanV1 {
        try SemanticReversalPlanV1(
            mutationID: try MutationIDV1(rawValue: Self.id(mutation)),
            commandKind: .updateSiteTimeZone,
            expectedRevision: currentExpected(),
            prospectiveTargets: [site],
            requiredSemanticValues: [.init(key: "before", value: "UTC")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [.updateSiteTimeZone(.init(
                siteID: site.id,
                timeZoneID: "UTC",
                confirmedAt: date(60)
            ))]
        )
    }

    static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private final class MutationJournalFaultAdapterV1: WorkspaceWriterAdapterPortV1 {
    private(set) var applyCount = 0
    private(set) var rollbackCount = 0

    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        applyCount += 1
        guard case let .createFirstSign(value) = command else {
            throw WorkspaceMutationFailureV1.unsupportedCommand
        }
        var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        if let site = value.newSite {
            identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )
    }

    func rollback() {
        rollbackCount += 1
    }
}

private struct MutationJournalFixedClockV1: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_080) }
}

private struct MutationJournalFixedIDSourceV1: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct MutationJournalFileAuthorityV1: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

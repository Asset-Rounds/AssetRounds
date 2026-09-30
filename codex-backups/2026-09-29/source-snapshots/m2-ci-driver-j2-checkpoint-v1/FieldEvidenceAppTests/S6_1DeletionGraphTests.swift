import CryptoKit
import Darwin
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_S6_1DeletionGraphTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

final class C45DeletionGraphCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityAddsOneWorkspaceScopedDurableLeaf() {
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentFamilies, ["AcceptedLabelGenerationSnapshotRow"])
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.durableModelCount, 1)
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("ManualShortCodeV1"))
    }
}

final class C51S61DeletionGraphAnchorTests: XCTestCase {
    func testV23P03C51DeletionPreservesOrErasesTheCompleteScheduleClosure() {
        XCTAssertTrue(ScheduleDeletionIntentBoundaryV1.validate())
        XCTAssertTrue(ScheduleDeletionIntentBoundaryV1.ordinaryDeletionPreservesCalendarOverrideBasisAndReceiptClosure)
        XCTAssertTrue(ScheduleDeletionIntentBoundaryV1.workspaceEraseRemovesEmbeddedCalendarOverrideAndBasisClosure)
        XCTAssertFalse(ScheduleDeletionIntentBoundaryV1.notificationStateIsTruth)
    }
}

final class C30EvidenceContextAnchorS6_1DeletionGraph: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S6_1DeletionGraphTests: XCTestCase {
    func testDeletionInventoriesUseValidatedEmptyValuesAndExactLocatorClosure() throws {
        let emptyLocators = try AssetLocatorDeletionInventoryV1(locators: [], receipts: [])
        let emptySchedules = try ScheduleDeletionInventoryV1(
            definitions: [], history: [], calendars: [], overrides: [])
        XCTAssertEqual(emptyLocators, .empty)
        XCTAssertEqual(emptySchedules, .empty)
        XCTAssertTrue(emptyLocators.locatorIDs.isEmpty)
        XCTAssertTrue(emptyLocators.receiptIDs.isEmpty)
        XCTAssertTrue(emptyLocators.assetIDs.isEmpty)
        XCTAssertTrue(emptySchedules.releaseIDs.isEmpty)
        XCTAssertTrue(emptySchedules.occurrenceEventIDs.isEmpty)
        XCTAssertTrue(emptySchedules.exceptionCalendarReleaseIDs.isEmpty)
        XCTAssertTrue(emptySchedules.scheduleOverrideEventIDs.isEmpty)
        for isErase in [false, true] {
            try WholeSignDeletionRule.validateAssetLocatorLifecycle(
                before: emptyLocators, after: emptyLocators, workspaceErase: isErase)
            try WholeSignDeletionRule.validateScheduleLifecycle(
                before: emptySchedules, after: emptySchedules, workspaceErase: isErase)
        }

        let workspace = WorkspaceID(rawValue: UUID())
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let mutation = try MutationIDV1(rawValue: UUID())
        let locator = try AssetLocatorV1(locatorID: UUID(), workspaceID: workspace, assetID: UUID(),
            representation: .externalKey(try ExternalKeyV1(namespaceID: "asset",
                normalization: .asciiCaseInsensitive, suppliedValue: "deletion-inventory")),
            state: .active, replacedByLocatorID: nil, predecessorLocatorSHA256: nil,
            revision: 1, mutationID: mutation, recordedAt: instant)
        let preview = try LocatorBindingPreviewV1(workspaceID: workspace, action: .bind,
            before: nil, after: locator.reference, replacement: nil, generatedAt: instant)
        try preview.validate(before: nil, after: locator, replacement: nil)
        let actorReference = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspace,
            displayName: "Inventory recorder")
        let actor = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspace, actor: actorReference,
            responsibility: .recordedBy, displayNameAtTime: actorReference.displayName, capturedAt: instant)
        let receipt = try LocatorBindingReceiptV1(receiptID: UUID(), preview: preview, recordedBy: actor,
            predecessor: nil, revision: 1, mutationID: mutation, recordedAt: instant)
        let sourceLocatorBytes = try AssetLocatorCanonicalCodecV1.encode(locator)
        let sourceReceiptBytes = try AssetLocatorCanonicalCodecV1.encode(receipt)
        let populated = try AssetLocatorDeletionInventoryV1(locators: [locator], receipts: [receipt])
        XCTAssertEqual(populated.locatorIDs, [locator.locatorID])
        XCTAssertEqual(populated.receiptIDs, [receipt.receiptID])
        XCTAssertEqual(populated.assetIDs, [locator.assetID])
        XCTAssertNotEqual(populated, .empty)
        try WholeSignDeletionRule.validateAssetLocatorLifecycle(
            before: populated, after: populated, workspaceErase: false)
        // Ordinary asset deletion may remove its exact locator subset; it may
        // not introduce another locator. Workspace erase must remove all rows.
        try WholeSignDeletionRule.validateAssetLocatorLifecycle(
            before: populated, after: emptyLocators, workspaceErase: false)
        try WholeSignDeletionRule.validateAssetLocatorLifecycle(
            before: populated, after: emptyLocators, workspaceErase: true)
        XCTAssertThrowsError(try WholeSignDeletionRule.validateAssetLocatorLifecycle(
            before: emptyLocators, after: populated, workspaceErase: false))
        XCTAssertThrowsError(try WholeSignDeletionRule.validateAssetLocatorLifecycle(
            before: populated, after: populated, workspaceErase: true))
        XCTAssertThrowsError(try AssetLocatorDeletionInventoryV1(locators: [locator], receipts: []))
        XCTAssertThrowsError(try AssetLocatorDeletionInventoryV1(locators: [], receipts: [receipt]))
        XCTAssertThrowsError(try AssetLocatorDeletionInventoryV1(locators: [locator, locator], receipts: [receipt]))
        XCTAssertEqual(try AssetLocatorCanonicalCodecV1.encode(locator), sourceLocatorBytes)
        XCTAssertEqual(try AssetLocatorCanonicalCodecV1.encode(receipt), sourceReceiptBytes)
    }

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

    @MainActor
    func testDeletesClosedGraphKeepsCountedTombstoneAndUnrelatedBytes() async throws {
        let harness = try makeHarness(counted: true, uncounted: true)

        let retained = harness.generationRootURL.appendingPathComponent("unrelated.bin")
        let retainedBytes = Data("retained".utf8)
        try retainedBytes.write(to: retained)

        let result = try await harness.service.delete(assetID: harness.assetID)

        XCTAssertEqual(result.countedTombstoneCount, 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)
        let packets = try harness.context.fetch(FetchDescriptor<Packet>())
        XCTAssertEqual(packets.count, 1)
        XCTAssertTrue(packets[0].evaluationCounted)
        XCTAssertNil(packets[0].currentRecordID)
        XCTAssertNotNil(packets[0].contentDeletedAt)
        XCTAssertEqual(try Data(contentsOf: retained), retainedBytes)
        let ledger = try DeletionLedgerStore(context: harness.context).snapshot()
        XCTAssertEqual(
            Set(ledger.entries.map(\.identity.kind)),
            Set([.asset, .workflowRecord, .packet])
        )
        XCTAssertEqual(ledger.entries.filter { $0.identity.kind == .asset }.count, 1)
        XCTAssertEqual(ledger.entries.filter { $0.identity.kind == .workflowRecord }.count, 2)
        XCTAssertEqual(ledger.entries.filter { $0.identity.kind == .packet }.count, 2)
        XCTAssertFalse(ledger.entries.contains { $0.identity.kind == .site })
        XCTAssertEqual(
            ledger.entries.first(where: {
                $0.identity.kind == .packet && $0.identity.id == packets[0].id
            })?.deletedAt,
            packets[0].contentDeletedAt
        )
    }

    @MainActor
    func testDirtyContextAndInjectedSaveRollbackRestoreHeldPacket() async throws {
        let harness = try makeHarness(counted: true)

        let dirty = Site(label: "Unsaved")
        harness.context.insert(dirty)
        await assertThrows(.contextHasChanges) {
            _ = try await harness.service.delete(assetID: harness.assetID)
        }
        harness.context.rollback()

        let held = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<Packet>()).first
        )
        let originalRecordID = try XCTUnwrap(held.currentRecordID)
        let injected = WholeSignDeletionService(
            modelContext: harness.context,
            generationRootURL: harness.generationRootURL,
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .databaseSave)
        )
        await assertThrows(.injectedFailure) {
            _ = try await injected.delete(assetID: harness.assetID)
        }
        XCTAssertEqual(held.currentRecordID, originalRecordID)
        XCTAssertNil(held.contentDeletedAt)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try DeletionLedgerStore(context: harness.context).snapshot(), .empty)
        XCTAssertEqual(try deletionJournalNames(harness), [])
    }

    @MainActor
    func testPreparedCancelsAndPostCommitRecoversWhileMismatchFailsClosed() async throws {
        let prepared = try makeHarness(counted: true)

        let before = WholeSignDeletionService(
            modelContext: prepared.context,
            generationRootURL: prepared.generationRootURL,
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .preparedJournal)
        )
        await assertThrows(.injectedFailure) {
            _ = try await before.delete(assetID: prepared.assetID)
        }
        let interruptedReplay = WholeSignDeletionService(
            modelContext: prepared.context,
            generationRootURL: prepared.generationRootURL,
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .databaseSave)
        )
        await assertThrows(.injectedFailure) {
            _ = try await interruptedReplay.reconcile()
        }
        XCTAssertEqual(try prepared.context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try DeletionLedgerStore(context: prepared.context).snapshot(), .empty)
        XCTAssertEqual(try deletionJournalNames(prepared).count, 1)
        let replayed = try await prepared.service.reconcile()
        XCTAssertEqual(replayed.cancelledPreparedCount, 0)
        XCTAssertEqual(replayed.completedCommittedCount, 1)
        XCTAssertEqual(try prepared.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try prepared.context.fetchCount(FetchDescriptor<Site>()), 1)

        let legacy = try makeHarness(counted: true)

        let legacyDeletionID = UUID()
        let legacyInterrupted = WholeSignDeletionService(
            modelContext: legacy.context,
            generationRootURL: legacy.generationRootURL,
            makeUUID: { legacyDeletionID },
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .preparedJournal)
        )
        await assertThrows(.injectedFailure) {
            _ = try await legacyInterrupted.delete(assetID: legacy.assetID)
        }
        let legacyURL = deletionJournalURL(legacy).appendingPathComponent(
            "\(legacyDeletionID.uuidString.lowercased()).json"
        )
        let currentIntent = try DeletionIntentDecoderV1().decode(Data(contentsOf: legacyURL))
        let legacyIntent = DeletionIntentV1(
            assetID: currentIntent.assetID,
            countedPacketTombstones: currentIntent.countedPacketTombstones,
            deletionID: currentIntent.deletionID,
            generationID: currentIntent.generationID,
            ledgerEntries: [],
            phase: currentIntent.phase,
            relativePaths: currentIntent.relativePaths,
            schemaVersion: 1
        )
        let legacyBytes = try DeletionIntentEncoderV1().encode(legacyIntent).data
        let legacyHandle = try FileHandle(forWritingTo: legacyURL)
        try legacyHandle.truncate(atOffset: 0)
        try legacyHandle.write(contentsOf: legacyBytes)
        try legacyHandle.synchronize()
        try legacyHandle.close()
        let legacySummary = try await legacy.service.reconcile()
        XCTAssertEqual(legacySummary.cancelledPreparedCount, 1)
        XCTAssertEqual(legacySummary.completedCommittedCount, 0)
        XCTAssertEqual(try legacy.context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try DeletionLedgerStore(context: legacy.context).snapshot(), .empty)

        let committed = try makeHarness(counted: true)

        let after = WholeSignDeletionService(
            modelContext: committed.context,
            generationRootURL: committed.generationRootURL,
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .committedPhase)
        )
        await assertThrows(.injectedFailure) {
            _ = try await after.delete(assetID: committed.assetID)
        }
        let recovered = try await committed.service.reconcile()
        XCTAssertEqual(recovered.completedCommittedCount, 1)
        XCTAssertEqual(try deletionJournalNames(committed), [])

        let phasePair = try makeHarness(counted: true)

        let deletionID = UUID()
        let interruptedPair = WholeSignDeletionService(
            modelContext: phasePair.context,
            generationRootURL: phasePair.generationRootURL,
            makeUUID: { deletionID },
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .committedPhase)
        )
        await assertThrows(.injectedFailure) {
            _ = try await interruptedPair.delete(assetID: phasePair.assetID)
        }
        let preparedURL = deletionJournalURL(phasePair)
            .appendingPathComponent("\(deletionID.uuidString.lowercased()).json")
        let preparedIntent = try DeletionIntentDecoderV1().decode(
            Data(contentsOf: preparedURL)
        )
        let replacementData = try DeletionIntentEncoderV1().encode(
            preparedIntent.withPhase(.databaseCommitted)
        ).data
        try replacementData.write(
            to: deletionJournalURL(phasePair).appendingPathComponent(
                ".\(deletionID.uuidString.lowercased()).tmp"
            )
        )
        let pairedRecovery = try await phasePair.service.reconcile()
        XCTAssertEqual(pairedRecovery.completedCommittedCount, 1)
        XCTAssertEqual(try deletionJournalNames(phasePair), [])

        let mismatch = try makeHarness(counted: true)

        let interrupted = WholeSignDeletionService(
            modelContext: mismatch.context,
            generationRootURL: mismatch.generationRootURL,
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .committedPhase)
        )
        await assertThrows(.injectedFailure) {
            _ = try await interrupted.delete(assetID: mismatch.assetID)
        }
        let tombstone = try XCTUnwrap(mismatch.context.fetch(FetchDescriptor<Packet>()).first)
        tombstone.contentDeletedAt = Date(timeIntervalSince1970: 1)
        try mismatch.context.save()
        await assertThrows(.journalInvalid) {
            _ = try await mismatch.service.reconcile()
        }
        XCTAssertEqual(try deletionJournalNames(mismatch).count, 1)
    }

    @MainActor
    func testCommittedRecoveryRejectsCanonicalIntentPathsOwnedByLiveRows() async throws {
        let foreignBytes = Data("foreign-evidence".utf8)
        let foreignSnapshot = Data("foreign-snapshot".utf8)
        let foreignPDF = Data("%PDF-foreign".utf8)

        for kind in ["original", "thumbnail", "snapshot", "pdf"] {
            let harness = try makeHarness(counted: true)

            let site = try XCTUnwrap(
                harness.context.fetch(FetchDescriptor<Site>()).first
            )
            let fixturePlacement = try XCTUnwrap(
                harness.context.fetch(FetchDescriptor<AssetPlacementEventRow>())
                    .first { $0.assetID == harness.assetID }
            ).value()
            XCTAssertEqual(fixturePlacement.siteID, site.id)
            let liveAsset = Asset(
                siteID: site.id,
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: 1,
                packContentVersion: 1,
                label: "Live foreign owner",
                createdAt: Date(timeIntervalSince1970: 1_759_999_880)
            )
            harness.context.insert(liveAsset)
            // The retained foreign owner needs the same genuine typed location
            // closure as the deletion target, without inventing writer authority.
            let livePlacement = try AssetPlacementEventV1(
                id: UUID(), workspaceID: fixturePlacement.workspaceID,
                assetID: liveAsset.id, siteID: site.id,
                locationNodeID: nil, predecessorEventID: nil,
                source: .migratedBaseline,
                physicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID()),
                continuity: .samePhysicalInstallation,
                pathSnapshot: try LocationPathSnapshotV1(
                    siteID: site.id, siteDisplay: site.label, nodes: []
                ),
                mutationID: try MutationIDV1(rawValue: UUID()),
                occurredAt: liveAsset.createdAt
            )
            try AssetPlacementHistoryV1.validate([livePlacement])
            harness.context.insert(try AssetPlacementEventRow(livePlacement))
            try insertRoot(
                assetID: liveAsset.id,
                counted: true,
                context: harness.context,
                generationRootURL: harness.generationRootURL,
                evidenceBytes: foreignBytes,
                report: .ready(snapshot: foreignSnapshot, pdf: foreignPDF)
            )
            try V906Integration.adoptSeededDeletionBaseline(harness.session)
            let placements = try harness.context.fetch(FetchDescriptor<AssetPlacementEventRow>())
                .map { try $0.value() }
            XCTAssertEqual(placements.filter { $0.assetID == liveAsset.id }, [livePlacement])
            XCTAssertEqual(Set(placements.map(\.assetID)),
                           Set(try harness.context.fetch(FetchDescriptor<Asset>()).map(\.id)))
            XCTAssertNoThrow(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
                deletingAssetID: harness.assetID, deletingSiteID: nil,
                liveAssetSiteByID: [harness.assetID: site.id, liveAsset.id: site.id],
                locationNodes: [], placementEvents: placements, compositionEdges: []
            ))

            let interrupted = WholeSignDeletionService(
                modelContext: harness.context,
                generationRootURL: harness.generationRootURL,
                failureInjection: WholeSignDeletionFailureInjection(
                    failOnceAt: .committedPhase
                )
            )
            await assertThrows(.injectedFailure) {
                _ = try await interrupted.delete(assetID: harness.assetID)
            }

            let evidence = try XCTUnwrap(
                harness.context.fetch(FetchDescriptor<EvidenceFile>()).first
            )
            let report = try XCTUnwrap(
                harness.context.fetch(FetchDescriptor<Report>()).first
            )
            let foreignPath: String
            let expectedBytes: Data
            switch kind {
            case "original":
                foreignPath = evidence.relativePath
                expectedBytes = foreignBytes
            case "thumbnail":
                foreignPath = evidence.thumbnailRelativePath
                expectedBytes = foreignBytes
            case "snapshot":
                foreignPath = report.snapshotRelativePath
                expectedBytes = foreignSnapshot
            case "pdf":
                foreignPath = try XCTUnwrap(report.pdfRelativePath)
                expectedBytes = foreignPDF
            default:
                XCTFail("Unexpected foreign path kind")
                return
            }

            let journalURL = try XCTUnwrap(
                deletionJournalNames(harness).first.map {
                    deletionJournalURL(harness).appendingPathComponent($0)
                }
            )
            let intent = try DeletionIntentDecoderV1().decode(
                Data(contentsOf: journalURL)
            )
            let substituted = DeletionIntentV1(
                acceptedLabelOutputCleanups: intent.acceptedLabelOutputCleanups,
                assetID: intent.assetID,
                countedPacketTombstones: intent.countedPacketTombstones,
                deletionID: intent.deletionID,
                generationID: intent.generationID,
                ledgerEntries: intent.ledgerEntries,
                phase: intent.phase,
                relativePaths: [foreignPath],
                schemaVersion: intent.schemaVersion
            )
            try DeletionIntentEncoderV1().encode(substituted).data.write(to: journalURL)

            await assertThrows(.journalInvalid) {
                _ = try await harness.service.reconcile()
            }
            XCTAssertEqual(try Data(contentsOf: harness.generationRootURL
                .appendingPathComponent(foreignPath)), expectedBytes)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
            XCTAssertEqual(try deletionJournalNames(harness).count, 1)
        }
    }

    @MainActor
    func testOrphanCleanupIsCanonicalBoundedAndPreservesTombstones() async throws {
        let harness = try makeHarness(counted: true)

        _ = try await harness.service.delete(assetID: harness.assetID)
        let tombstone = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<Packet>()).first
        )

        let referencedEvidenceID = UUID()
        let orphanEvidenceID = UUID()
        for id in [referencedEvidenceID, orphanEvidenceID] {
            let directory = harness.generationRootURL.appendingPathComponent(
                "evidence/\(id.uuidString.lowercased())",
                isDirectory: true
            )
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("original".utf8).write(
                to: directory.appendingPathComponent("original.jpg")
            )
            try Data("thumbnail".utf8).write(
                to: directory.appendingPathComponent("thumbnail.jpg")
            )
        }
        let referencedSnapshotID = UUID()
        let orphanSnapshotID = UUID()
        let snapshots = harness.generationRootURL.appendingPathComponent(
            "snapshots", isDirectory: true
        )
        try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try Data("referenced".utf8).write(to: snapshots.appendingPathComponent(
            "\(referencedSnapshotID.uuidString.lowercased()).json"
        ))
        try Data("orphan".utf8).write(to: snapshots.appendingPathComponent(
            "\(orphanSnapshotID.uuidString.lowercased()).json"
        ))
        let unrelated = harness.generationRootURL.appendingPathComponent("unrelated.bin")
        try Data("untouched".utf8).write(to: unrelated)

        let cleanup = try OrphanFileCleanupService(
            generationRootURL: harness.generationRootURL
        )
        let evidenceID = referencedEvidenceID.uuidString.lowercased()
        let summary = try cleanup.reconcile(referencedRelativePaths: [
            "evidence/\(evidenceID)/original.jpg",
            "evidence/\(evidenceID)/thumbnail.jpg",
            "snapshots/\(referencedSnapshotID.uuidString.lowercased()).json",
        ])

        XCTAssertEqual(summary.removedFileCount, 3)
        XCTAssertEqual(summary.removedDirectoryCount, 1)
        XCTAssertTrue(fileManager.fileExists(atPath: unrelated.path))
        XCTAssertTrue(fileManager.fileExists(atPath: snapshots.appendingPathComponent(
            "\(referencedSnapshotID.uuidString.lowercased()).json"
        ).path))
        XCTAssertFalse(fileManager.fileExists(atPath: snapshots.appendingPathComponent(
            "\(orphanSnapshotID.uuidString.lowercased()).json"
        ).path))
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<Packet>()).first?.id,
            tombstone.id
        )
        XCTAssertNotNil(
            try harness.context.fetch(FetchDescriptor<Packet>()).first?.contentDeletedAt
        )

        XCTAssertThrowsError(
            try cleanup.reconcile(referencedRelativePaths: ["../model.sqlite"])
        )
    }

    @MainActor
    func testRuleLedgerCoversEveryDeletedDependentKindAndLegacyCodecIsExact() throws {
        let siteID = UUID()
        let assetID = UUID()
        let recordID = UUID()
        let evidenceID = UUID()
        let issueID = UUID()
        let packetID = UUID()
        let reportID = UUID()
        let created = Date(timeIntervalSince1970: 1_760_000_000)
        let deleted = created.addingTimeInterval(120)
        let record = completedRecord(id: recordID, assetID: assetID, packetID: packetID)
        let input = WholeSignDeletionRuleInput(
            assetID: assetID,
            deletionID: UUID(),
            deletedAt: deleted,
            generationID: UUID(),
            sites: [.init(id: siteID, schemaVersion: 1)],
            assets: [.init(id: assetID, schemaVersion: 1, siteID: siteID)],
            records: [payload(record)],
            evidence: [.init(
                id: evidenceID,
                schemaVersion: 1,
                recordID: recordID,
                purposeKey: "wide_context",
                relativePath: "evidence/\(evidenceID.uuidString.lowercased())/original.jpg",
                mimeType: "image/jpeg",
                byteCount: 1,
                sha256: String(repeating: "a", count: 64),
                thumbnailRelativePath:
                    "evidence/\(evidenceID.uuidString.lowercased())/thumbnail.jpg",
                thumbnailByteCount: 1,
                thumbnailSHA256: String(repeating: "b", count: 64)
            )],
            issues: [.init(
                id: issueID,
                schemaVersion: 1,
                assetID: assetID,
                openedByRecordID: recordID,
                labelKey: "dark_section",
                labelDisplaySnapshot: "Section appears dark",
                status: IssueStatus.open.rawValue,
                resolvedByRecordID: nil,
                createdAt: created,
                updatedAt: created
            )],
            packets: [.init(
                id: packetID,
                schemaVersion: 1,
                stableRootID: UUID(),
                currentRecordID: recordID,
                evaluationCounted: true,
                contentDeletedAt: nil,
                createdAt: created
            )],
            reports: [.init(
                id: reportID,
                schemaVersion: 1,
                packetID: packetID,
                sourceRecordID: recordID,
                snapshotSchemaVersion: 1,
                snapshotRelativePath: "snapshots/\(reportID.uuidString.lowercased()).json",
                snapshotSHA256: String(repeating: "c", count: 64),
                pdfState: ReportPDFState.pending.rawValue,
                pdfRelativePath: nil,
                pdfSHA256: nil,
                createdAt: created,
                replacesReportID: nil
            )]
        )
        let plan = try WholeSignDeletionRule.makePlan(input)
        XCTAssertEqual(
            Set(plan.intent.ledgerEntries.map(\.identity.kind)),
            Set([.asset, .workflowRecord, .evidenceFile, .issue, .packet, .report])
        )
        XCTAssertEqual(plan.intent.schemaVersion, 2)
        XCTAssertEqual(
            plan.intent.ledgerEntries.first(where: { $0.identity.kind == .packet })?.deletedAt,
            deleted
        )
        let sitePreview = try WholeSignDeletionRule.makeExplicitSiteDeletionPreview(
            ExplicitSiteDeletionInputV1(
                siteID: siteID,
                generationID: plan.intent.generationID,
                deletionID: plan.intent.deletionID,
                deletedAt: deleted,
                siteSchemaVersion: 1,
                label: "Site",
                address: nil,
                timeZoneID: nil,
                createdAt: created,
                updatedAt: created,
                siteAssets: input.assets,
                assetPlans: [plan]
            )
        )
        XCTAssertEqual(
            Set(sitePreview.ledgerEntries.map(\.identity.kind)),
            Set(DeletionRecordKindV2.allCases).subtracting([
                .acceptedLabelGenerationSnapshot,
            ]),
            "This legacy preview has no accepted C45 snapshot to tombstone"
        )

        let legacy = DeletionIntentV1(
            assetID: plan.intent.assetID,
            countedPacketTombstones: plan.intent.countedPacketTombstones,
            deletionID: plan.intent.deletionID,
            generationID: plan.intent.generationID,
            ledgerEntries: [],
            phase: plan.intent.phase,
            relativePaths: plan.intent.relativePaths,
            schemaVersion: 1
        )
        let legacyBytes = try DeletionIntentEncoderV1().encode(legacy).data
        XCTAssertFalse(String(decoding: legacyBytes, as: UTF8.self).contains("ledgerEntries"))
        let decoded = try DeletionIntentDecoderV1().decode(legacyBytes)
        XCTAssertEqual(decoded, legacy)
        XCTAssertEqual(try DeletionIntentEncoderV1().encode(decoded).data, legacyBytes)
    }

    @MainActor
    func testExplicitPreviewBoundSiteDeletionIsSeparateAndLedgered() async throws {
        let assetDeletion = try makeHarness(counted: false)

        let siteID = try XCTUnwrap(
            assetDeletion.context.fetch(FetchDescriptor<Site>()).first?.id
        )
        _ = try await assetDeletion.service.delete(assetID: assetDeletion.assetID)
        XCTAssertEqual(try assetDeletion.context.fetchCount(FetchDescriptor<Site>()), 1)

        // Explicitly seed the uncounted historical work graph whose ledger
        // entries this test has always required; no site cascade may delete it.
        let siteDeletion = try makeHarness(counted: false, uncounted: true)

        let explicitSiteID = try XCTUnwrap(
            siteDeletion.context.fetch(FetchDescriptor<Site>()).first?.id
        )
        let placements = try siteDeletion.context.fetch(
            FetchDescriptor<AssetPlacementEventRow>()
        ).map { try $0.value() }
        let retained = siteDeletion.generationRootURL.appendingPathComponent("unrelated.bin")
        let retainedBytes = Data("site-deletion-retained".utf8)
        try retainedBytes.write(to: retained)
        let initialLedger = try DeletionLedgerStore(context: siteDeletion.context).snapshot()
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertThrowsError(try siteDeletion.service.previewSiteDeletion(siteID: explicitSiteID)) {
            XCTAssertEqual($0 as? WholeSignDeletionServiceError, .graphInvalid)
        }
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try DeletionLedgerStore(context: siteDeletion.context).snapshot(), initialLedger)
        XCTAssertEqual(try Data(contentsOf: retained), retainedBytes)

        _ = try await siteDeletion.service.delete(assetID: siteDeletion.assetID)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Packet>()), 0)
        let assetLedger = try DeletionLedgerStore(context: siteDeletion.context).snapshot()
        XCTAssertEqual(Set(assetLedger.entries.map(\.identity.kind)),
                       Set([.asset, .workflowRecord, .packet]))
        XCTAssertEqual(try siteDeletion.context.fetch(FetchDescriptor<AssetPlacementEventRow>())
            .map { try $0.value() }, placements)
        let preview = try siteDeletion.service.previewSiteDeletion(siteID: explicitSiteID)
        // Frozen C35: site removal is independent and cannot cascade work.
        XCTAssertEqual(preview.assetPlans.map(\.assetID), [])
        XCTAssertEqual(Set(preview.ledgerEntries.map(\.identity.kind)), Set([.site]))
        XCTAssertTrue(preview.ledgerEntries.contains {
            $0.identity.kind == .site && $0.identity.id == explicitSiteID
        })
        let site = try XCTUnwrap(
            siteDeletion.context.fetch(FetchDescriptor<Site>()).first
        )
        site.label = "Changed after preview"
        try V906Integration.adoptSeededDeletionBaseline(siteDeletion.session)
        await assertThrows(.graphInvalid) {
            _ = try await siteDeletion.service.deleteSite(preview: preview)
        }
        XCTAssertEqual(try DeletionLedgerStore(context: siteDeletion.context).snapshot(), assetLedger)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try Data(contentsOf: retained), retainedBytes)
        site.label = "Site"
        try V906Integration.adoptSeededDeletionBaseline(siteDeletion.session)
        let result = try await siteDeletion.service.deleteSite(preview: preview)
        XCTAssertEqual(result.siteID, explicitSiteID)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Site>()), 0)
        XCTAssertEqual(try siteDeletion.context.fetchCount(FetchDescriptor<Asset>()), 0)
        let ledger = try DeletionLedgerStore(context: siteDeletion.context).snapshot()
        XCTAssertTrue(ledger.entries.contains {
            $0.identity.kind == .site && $0.identity.id == explicitSiteID
        })
        XCTAssertEqual(
            Set(ledger.entries.map(\.identity.kind)),
            Set([.site, .asset, .workflowRecord, .packet])
        )
        XCTAssertEqual(Set(ledger.entries).subtracting(Set(assetLedger.entries)),
                       Set(preview.ledgerEntries))
        XCTAssertEqual(try siteDeletion.context.fetch(FetchDescriptor<AssetPlacementEventRow>())
            .map { try $0.value() }, placements)
        XCTAssertEqual(try Data(contentsOf: retained), retainedBytes)
        XCTAssertEqual(try assetDeletion.context.fetch(FetchDescriptor<Site>()).map(\.id), [siteID])
    }

    func testOrphanReplacementRaceFailsBeforeDeletingReplacement() throws {
        let snapshotRegistration = try KernelDeletionEraseRegistryV4.registration(
            for: .completedActivitySnapshot
        )
        XCTAssertEqual(snapshotRegistration.orphanCleanup, .preserveCanonicalRecord)
        XCTAssertFalse(snapshotRegistration.clearsTombstonesOnDelete)
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "orphan-race-\(UUID().uuidString)", isDirectory: true
        )
        defer { try? fileManager.removeItem(at: root) }
        let generationID = UUID()
        let generation = root
            .appendingPathComponent("FieldEvidenceData/generations", isDirectory: true)
            .appendingPathComponent(generationID.uuidString.lowercased(), isDirectory: true)
        let snapshots = generation.appendingPathComponent("snapshots", isDirectory: true)
        try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let target = snapshots.appendingPathComponent("\(UUID().uuidString.lowercased()).json")
        let parked = generation.appendingPathComponent("parked-original.json")
        try Data("original".utf8).write(to: target)
        let injection = OrphanFileCleanupReplacementInjection { url in
            try self.fileManager.moveItem(at: url, to: parked)
            try Data("replacement".utf8).write(to: url)
        }
        let service = try OrphanFileCleanupService(
            generationRootURL: generation,
            replacementInjection: injection
        )
        XCTAssertThrowsError(try service.reconcile(referencedRelativePaths: [])) { error in
            XCTAssertEqual(error as? OrphanFileCleanupServiceError, .identityChanged)
        }
        XCTAssertEqual(try Data(contentsOf: target), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: parked), Data("original".utf8))
    }

    @MainActor
    func testExplicitSitePostcommitCleanupInterruptionLeavesOnlyOrphans() async throws {
        let harness = try makeHarness(counted: false)

        let siteID = try XCTUnwrap(harness.context.fetch(FetchDescriptor<Site>()).first?.id)
        let placements = try harness.context.fetch(FetchDescriptor<AssetPlacementEventRow>())
            .map { try $0.value() }
        XCTAssertThrowsError(try harness.service.previewSiteDeletion(siteID: siteID)) {
            XCTAssertEqual($0 as? WholeSignDeletionServiceError, .graphInvalid)
        }
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertTrue(try DeletionLedgerStore(context: harness.context).snapshot().entries.isEmpty)
        _ = try await harness.service.delete(assetID: harness.assetID)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Asset>()), 0)
        let assetLedger = try DeletionLedgerStore(context: harness.context).snapshot()
        XCTAssertEqual(Set(assetLedger.entries.map(\.identity.kind)), Set([.asset]))
        // Create the orphan only after ordinary asset deletion has settled.
        let snapshots = harness.generationRootURL.appendingPathComponent(
            "snapshots", isDirectory: true
        )
        try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let orphan = snapshots.appendingPathComponent(
            "\(UUID().uuidString.lowercased()).json"
        )
        try Data("orphan".utf8).write(to: orphan)
        let service = WholeSignDeletionService(
            modelContext: harness.context,
            generationRootURL: harness.generationRootURL,
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .fileCleanup)
        )
        XCTAssertEqual(try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<Site>()).first?.id
        ), siteID)
        let preview = try service.previewSiteDeletion(siteID: siteID)
        XCTAssertTrue(preview.assetPlans.isEmpty)
        XCTAssertEqual(Set(preview.ledgerEntries.map(\.identity.kind)), Set([.site]))
        await assertThrows(.injectedFailure) {
            _ = try await service.deleteSite(preview: preview)
        }

        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Site>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertTrue(try DeletionLedgerStore(context: harness.context).snapshot().entries.contains {
            $0.identity.kind == .site && $0.identity.id == siteID
        })
        // The committed site marker retains projection-purge recovery until
        // reconciliation; the injected cleanup failure must not discard it.
        XCTAssertEqual(try deletionJournalNames(harness),
                       ["site-\(preview.deletionID.uuidString.lowercased()).json"])
        XCTAssertTrue(fileManager.fileExists(atPath: orphan.path))
        let committedLedger = try DeletionLedgerStore(context: harness.context).snapshot()
        XCTAssertEqual(Set(committedLedger.entries).subtracting(Set(assetLedger.entries)),
                       Set(preview.ledgerEntries))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<AssetPlacementEventRow>())
            .map { try $0.value() }, placements)

        let recovery = try await harness.service.reconcile()
        XCTAssertEqual(recovery.cancelledPreparedCount, 0)
        XCTAssertEqual(recovery.completedCommittedCount, 1)
        XCTAssertEqual(try deletionJournalNames(harness), [])
        let repeatedRecovery = try await harness.service.reconcile()
        XCTAssertEqual(repeatedRecovery.cancelledPreparedCount, 0)
        XCTAssertEqual(repeatedRecovery.completedCommittedCount, 0)
        XCTAssertEqual(try DeletionLedgerStore(context: harness.context).snapshot(), committedLedger)
        XCTAssertTrue(fileManager.fileExists(atPath: orphan.path))

        let summary = try OrphanFileCleanupService(
            generationRootURL: harness.generationRootURL
        ).reconcile(referencedRelativePaths: [])
        XCTAssertEqual(summary.removedFileCount, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: orphan.path))
        XCTAssertEqual(try DeletionLedgerStore(context: harness.context).snapshot(), committedLedger)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<AssetPlacementEventRow>())
            .map { try $0.value() }, placements)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Site>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Asset>()), 0)
    }

    @MainActor
    func testDeepEvidenceSnapshotAndPDFAuthorityFailBeforeMutation() async throws {
        let evidence = try makeHarness(counted: true, evidenceBytes: Data("not-jpeg".utf8))

        await assertThrows(.fileInvalid) {
            _ = try await evidence.service.delete(assetID: evidence.assetID)
        }
        XCTAssertEqual(try evidence.context.fetchCount(FetchDescriptor<Asset>()), 1)

        let snapshot = try makeHarness(
            counted: true,
            report: .pending(snapshot: Data("not-canonical-json".utf8))
        )

        await assertThrows(.fileInvalid) {
            _ = try await snapshot.service.delete(assetID: snapshot.assetID)
        }
        XCTAssertEqual(try snapshot.context.fetchCount(FetchDescriptor<Report>()), 1)

        let pdf = try makeHarness(
            counted: true,
            report: .ready(
                snapshot: Data("also-invalid-snapshot".utf8),
                pdf: Data("not-a-pdf".utf8)
            )
        )

        await assertThrows(.fileInvalid) {
            _ = try await pdf.service.delete(assetID: pdf.assetID)
        }
        XCTAssertEqual(try pdf.context.fetchCount(FetchDescriptor<Asset>()), 1)
    }

    @MainActor
    func testMalformedJournalAndPinnedAncestorReplacementEnterClosedFailure() async throws {
        let malformed = try makeHarness(counted: false)

        let journal = deletionJournalURL(malformed)
        try Data("{}".utf8).write(
            to: journal.appendingPathComponent("00000000-0000-0000-0000-000000000001.json")
        )
        await assertThrows(.journalInvalid) {
            _ = try await malformed.service.reconcile()
        }
        XCTAssertEqual(try malformed.context.fetchCount(FetchDescriptor<Asset>()), 1)

        let replaced = try makeHarness(counted: false)

        let operations = replaced.applicationSupportURL
            .appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
        let original = replaced.applicationSupportURL
            .appendingPathComponent("FieldEvidenceOperations.pinned", isDirectory: true)
        replaced.cleanupEligibility.namespaceRestored = false
        var originalIdentity = stat()
        _ = try XCTUnwrap(
            lstat(operations.path, &originalIdentity) == 0
                && (originalIdentity.st_mode & S_IFMT) == S_IFDIR ? true : nil,
            "Retaining hostile fixture: original Operations identity unavailable"
        )
        try fileManager.moveItem(at: operations, to: original)
        try fileManager.createSymbolicLink(at: operations, withDestinationURL: original)
        var linkIdentity = stat()
        _ = try XCTUnwrap(
            lstat(operations.path, &linkIdentity) == 0
                && (linkIdentity.st_mode & S_IFMT) == S_IFLNK ? true : nil,
            "Retaining hostile fixture: replacement symlink identity unavailable"
        )
        await assertThrows(.invalidGeneration) {
            _ = try await replaced.service.reconcile()
        }
        XCTAssertEqual(try replaced.context.fetchCount(FetchDescriptor<Asset>()), 1)
        // The hostile operation has completed. Restore only this test's exact
        // namespace so genuine reader/writer handles can close during teardown.
        // Any unexpected identity retains the private root instead of bypassing drain.
        var retainedOriginal = stat()
        var retainedLink = stat()
        _ = try XCTUnwrap(
            lstat(original.path, &retainedOriginal) == 0
                && (retainedOriginal.st_mode & S_IFMT) == S_IFDIR
                && retainedOriginal.st_dev == originalIdentity.st_dev
                && retainedOriginal.st_ino == originalIdentity.st_ino
                && lstat(operations.path, &retainedLink) == 0
                && (retainedLink.st_mode & S_IFMT) == S_IFLNK
                && retainedLink.st_dev == linkIdentity.st_dev
                && retainedLink.st_ino == linkIdentity.st_ino ? true : nil,
            "Retaining hostile fixture: namespace changed before restoration"
        )
        _ = try XCTUnwrap(
            unlink(operations.path) == 0 ? true : nil,
            "Retaining hostile fixture: exact symlink removal failed"
        )
        _ = try XCTUnwrap(
            rename(original.path, operations.path) == 0 ? true : nil,
            "Retaining hostile fixture: original namespace restoration failed"
        )
        var restoredIdentity = stat()
        _ = try XCTUnwrap(
            lstat(operations.path, &restoredIdentity) == 0
                && (restoredIdentity.st_mode & S_IFMT) == S_IFDIR
                && restoredIdentity.st_dev == originalIdentity.st_dev
                && restoredIdentity.st_ino == originalIdentity.st_ino ? true : nil,
            "Retaining hostile fixture: restored namespace identity differs"
        )
        replaced.cleanupEligibility.namespaceRestored = true
    }
}

final class C27S61TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(PersistentSchemaV26.models.count, 94)
        XCTAssertEqual(AssetLocatorLimitsV1.maximumCandidates, 32)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

extension S6_1DeletionGraphTests {
    func testV23P03C18DeleteEraseBoundaryRemainsTyped() throws {
        XCTAssertTrue(PackageSandboxCheckKindV1.allCases.contains(.deleteErase))
        XCTAssertTrue(PackageEvolutionLifecycleV1.deleteEraseRequired)
        XCTAssertEqual(
            PackageRollbackCompatibilityV1.activatedForwardFixRequired.rawValue,
            "ACTIVATED_FORWARD_FIX_REQUIRED"
        )
    }
}

extension S6_1DeletionGraphTests {
    func testV23P03C36OrdinaryDeletionPreservesCompleteDraftGraph() throws {
        let ids = (0..<6).map { _ in UUID() }
        let inventory = FieldDraftDeletionInventoryV1(draftIDs:[ids[0]],stageIDs:[ids[1]],sagaIDs:[ids[2]],reservationIDs:[ids[3]],commitReceiptIDs:[ids[4]],discardReceiptIDs:[ids[5]])
        XCTAssertNoThrow(try WholeSignDeletionRule.validateFieldDraftLifecycle(authority:.ordinaryAssetOrSiteDelete,before:inventory,after:inventory))
        XCTAssertThrowsError(try WholeSignDeletionRule.validateFieldDraftLifecycle(authority:.ordinaryAssetOrSiteDelete,before:inventory,after:.init(draftIDs:[],stageIDs:[],sagaIDs:[],reservationIDs:[],commitReceiptIDs:[],discardReceiptIDs:[])))
    }
}

extension S6_1DeletionGraphTests {
    func testV23P03C15ReleaseGraphRequiresValidatedClaimLeaseAndHandoff() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_161)
        try fixture.completedRelease.validate(claim: fixture.claim, lease: fixture.lease)
        try fixture.handoffRelease.validate(claim: fixture.claim, lease: fixture.lease)
        try fixture.handoff.validate(release: fixture.handoffRelease)
        XCTAssertEqual(fixture.handoff.releaseID, fixture.handoffRelease.releaseID)
        XCTAssertEqual(fixture.handoff.item, fixture.itemReference)
    }
}

private extension S6_1DeletionGraphTests {
    enum ReportFixture {
        case pending(snapshot: Data)
        case ready(snapshot: Data, pdf: Data)
    }

    final class CleanupEligibility {
        var namespaceRestored = true
    }

    struct Harness {
        let cleanupEligibility: CleanupEligibility
        let applicationSupportURL: URL
        let generationRootURL: URL
        let session: StoreGenerationSession
        let container: ModelContainer
        let context: ModelContext
        let assetID: UUID
        let service: WholeSignDeletionService
    }

    @MainActor
    func makeHarness(
        counted: Bool,
        uncounted: Bool = false,
        evidenceBytes: Data? = nil,
        report: ReportFixture? = nil
    ) throws -> Harness {
        let owned = try V906Integration.makeHarness("s6-1", withAsset: false)
        let applicationSupportURL = owned.support
        let session = owned.session
        let generationRootURL = session.generationRootURL
        let context = session.modelContext
        let container = context.container
        let cleanupEligibility = CleanupEligibility()
        addTeardownBlock { @MainActor [weak session, weak context, weak container, cleanupEligibility,
                                      root = owned.root, support = owned.support] in
            _ = try XCTUnwrap(
                cleanupEligibility.namespaceRestored ? true : nil,
                "Retaining S6_1 fixture: hostile namespace restoration incomplete"
            )
            _ = try XCTUnwrap(
                session == nil && context == nil && container == nil ? true : nil,
                "Retaining S6_1 fixture: store owners have not drained"
            )
            let registry = try StoreGenerationFactory(applicationSupportURL: support)
                .makeGenerationLeaseRegistry()
            _ = try XCTUnwrap(
                try registry.activeEpochs().isEmpty ? true : nil,
                "Retaining S6_1 fixture: durable leases have not drained"
            )
            try FileManager.default.removeItem(at: root)
        }
        let site = Site(label: "Site")
        let asset = Asset(
            siteID: site.id, packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: 1, packContentVersion: 1, label: "Sign",
            // Integral seconds survive the canonical placement millisecond codec
            // exactly and precede this fixture's historical work start.
            createdAt: Date(timeIntervalSince1970: 1_759_999_880)
        )
        context.insert(site)
        context.insert(asset)
        // Seed historical rows into the actual bootstrapped session, using its
        // real workspace identity and the production semantic baseline helper.
        let fixtureWorkspaceID = session.workspaceIdentity.workspaceID
        let placement = try AssetPlacementEventV1(
            id: UUID(), workspaceID: fixtureWorkspaceID,
            assetID: asset.id, siteID: site.id,
            locationNodeID: nil, predecessorEventID: nil,
            source: .migratedBaseline,
            physicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID()),
            continuity: .samePhysicalInstallation,
            pathSnapshot: try LocationPathSnapshotV1(
                siteID: site.id, siteDisplay: site.label, nodes: []
            ),
            mutationID: try MutationIDV1(rawValue: UUID()),
            occurredAt: asset.createdAt
        )
        try AssetPlacementHistoryV1.validate([placement])
        context.insert(try AssetPlacementEventRow(placement))

        if counted || uncounted {
            if counted {
                try insertRoot(
                    assetID: asset.id, counted: true, context: context,
                    generationRootURL: generationRootURL,
                    evidenceBytes: evidenceBytes, report: report
                )
            }
            if uncounted {
                try insertRoot(
                    assetID: asset.id, counted: false, context: context,
                    generationRootURL: generationRootURL,
                    evidenceBytes: nil, report: nil
                )
            }
        }
        try V906Integration.adoptSeededDeletionBaseline(session)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<AssetPlacementEventRow>()).map { try $0.value() },
            [placement]
        )
        XCTAssertNoThrow(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
            deletingAssetID: asset.id, deletingSiteID: nil,
            liveAssetSiteByID: [asset.id: site.id], locationNodes: [],
            placementEvents: [placement], compositionEdges: []
        ))
        XCTAssertEqual(
            Set(try ObservationAndTimeRowStoreV1.validatedIndex(in: context).keys),
            Set(try context.fetch(FetchDescriptor<WorkflowRecord>()).map(\.id))
        )
        return Harness(
            cleanupEligibility: cleanupEligibility,
            applicationSupportURL: applicationSupportURL,
            generationRootURL: generationRootURL,
            session: session,
            container: container,
            context: context,
            assetID: asset.id,
            service: WholeSignDeletionService(
                modelContext: context, generationRootURL: generationRootURL
            )
        )
    }

    @MainActor
    func insertRoot(
        assetID: UUID,
        counted: Bool,
        context: ModelContext,
        generationRootURL: URL,
        evidenceBytes: Data?,
        report: ReportFixture?
    ) throws {
        let recordID = UUID()
        let packetID = UUID()
        let completed = Date(timeIntervalSince1970: 1_760_000_000)
        let record = completedRecord(id: recordID, assetID: assetID, packetID: packetID)
        let packet = Packet(
            id: packetID, stableRootID: UUID(), currentRecordID: recordID,
            evaluationCounted: counted, contentDeletedAt: nil,
            createdAt: completed
        )
        context.insert(record)
        context.insert(packet)
        // Preserve the historical record bytes and use the real migration
        // conversion; an absent old observation basis stays unknown.
        let basis = try XCTUnwrap(ObservationAndTimeLegacyMigrationV1.observationBasis(
            couldNotVerifyKey: record.couldNotVerifyKey,
            displaySnapshot: record.couldNotVerifyDisplaySnapshot,
            registryVersion: record.couldNotVerifyRegistryVersion
        ))
        let temporal = try XCTUnwrap(ObservationAndTimeLegacyMigrationV1.temporalContext(
            observedAtUTC: record.observedAtUTC,
            recordedAtUTC: record.completedAt ?? record.startedAt,
            timeZoneID: record.timeZoneID,
            utcOffsetMinutes: record.utcOffsetMinutes,
            localDate: record.localDate,
            localTime: record.localTime
        ))
        let companion = try ObservationAndTimeRow(
            recordID: record.id, observationBasis: basis, temporalContext: temporal
        )
        try companion.validate()
        context.insert(companion)
        XCTAssertEqual(try companion.observationBasisV1(), basis)
        XCTAssertEqual(try companion.temporalContextV1(), temporal)

        if let bytes = evidenceBytes {
            let evidenceID = UUID()
            let id = evidenceID.uuidString.lowercased()
            let directory = generationRootURL.appendingPathComponent("evidence/\(id)", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: directory.appendingPathComponent("original.jpg"))
            try bytes.write(to: directory.appendingPathComponent("thumbnail.jpg"))
            context.insert(EvidenceFile(
                id: evidenceID, recordID: recordID, purposeKey: "wide_context",
                relativePath: "evidence/\(id)/original.jpg", mimeType: "image/jpeg",
                byteCount: bytes.count, sha256: digest(bytes), createdAt: completed,
                thumbnailRelativePath: "evidence/\(id)/thumbnail.jpg",
                thumbnailByteCount: bytes.count, thumbnailSHA256: digest(bytes)
            ))
        }

        if let report {
            let reportID = UUID()
            let id = reportID.uuidString.lowercased()
            let snapshotBytes: Data
            let pdfState: ReportPDFState
            let pdfPath: String?
            let pdfHash: String?
            switch report {
            case .pending(let snapshot):
                snapshotBytes = snapshot
                pdfState = .pending
                pdfPath = nil
                pdfHash = nil
            case .ready(let snapshot, let pdf):
                snapshotBytes = snapshot
                pdfState = .ready
                pdfPath = "pdfs/\(id).pdf"
                pdfHash = digest(pdf)
                let pdfURL = generationRootURL.appendingPathComponent("pdfs", isDirectory: true)
                try fileManager.createDirectory(at: pdfURL, withIntermediateDirectories: true)
                try pdf.write(to: pdfURL.appendingPathComponent("\(id).pdf"))
            }
            let snapshots = generationRootURL.appendingPathComponent("snapshots", isDirectory: true)
            try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)
            try snapshotBytes.write(to: snapshots.appendingPathComponent("\(id).json"))
            context.insert(Report(
                id: reportID, packetID: packetID, sourceRecordID: recordID,
                snapshotSchemaVersion: 1, snapshotRelativePath: "snapshots/\(id).json",
                snapshotSHA256: digest(snapshotBytes), pdfState: pdfState,
                pdfRelativePath: pdfPath, pdfSHA256: pdfHash,
                createdAt: completed, replacesReportID: nil
            ))
        }
    }

    func completedRecord(id: UUID, assetID: UUID, packetID: UUID) -> WorkflowRecord {
        let completed = Date(timeIntervalSince1970: 1_760_000_000)
        return WorkflowRecord(
            id: id, assetID: assetID, packetID: packetID, issueID: nil,
            parentRecordID: nil, recordRevisionRootID: id,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: .original, stage: .check, state: .completed,
            draftStepKey: nil, startedAt: completed.addingTimeInterval(-60),
            completedAt: completed, observedAtUTC: completed,
            timeZoneID: "America/New_York", utcOffsetMinutes: -240,
            localDate: "2025-10-09", localTime: "04:53:20",
            afterDarkAcknowledgementKey: "after_dark", afterDarkAcknowledgementCopy: "After dark",
            afterDarkAcknowledgementVersion: "1", afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: "safe_position",
            safePositionAcknowledgementCopy: "Safe position",
            safePositionAcknowledgementVersion: "1",
            safePositionAcknowledgementAccepted: true,
            packID: SignPack.illuminatedSignV1.packID, packSchemaVersion: 1,
            packContentVersion: 1, pdfTemplateID: "field.evidence.pdf.worklight.v1",
            pdfTemplateVersion: 1, outcomeKey: "no_issue_found",
            couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil, workPerformedLocalDate: nil,
            workDescription: nil, note: nil, finalizationMutationID: UUID()
        )
    }

    func payload(_ row: WorkflowRecord) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
            id: row.id,
            schemaVersion: row.schemaVersion,
            assetID: row.assetID,
            packetID: row.packetID,
            issueID: row.issueID,
            parentRecordID: row.parentRecordID,
            recordRevisionRootID: row.recordRevisionRootID,
            revisesRecordID: row.revisesRecordID,
            evidenceSourceRecordID: row.evidenceSourceRecordID,
            revisionKind: row.revisionKind,
            stage: row.stage,
            state: row.state,
            draftStepKey: row.draftStepKey,
            startedAt: row.startedAt,
            completedAt: row.completedAt,
            observedAtUTC: row.observedAtUTC,
            timeZoneID: row.timeZoneID,
            utcOffsetMinutes: row.utcOffsetMinutes,
            localDate: row.localDate,
            localTime: row.localTime,
            afterDarkAcknowledgementKey: row.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: row.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: row.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: row.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: row.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: row.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: row.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: row.safePositionAcknowledgementAccepted,
            packID: row.packID,
            packSchemaVersion: row.packSchemaVersion,
            packContentVersion: row.packContentVersion,
            pdfTemplateID: row.pdfTemplateID,
            pdfTemplateVersion: row.pdfTemplateVersion,
            outcomeKey: row.outcomeKey,
            couldNotVerifyKey: row.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: row.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: row.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: row.workPerformedLocalDate,
            workDescription: row.workDescription,
            note: row.note,
            finalizationMutationID: row.finalizationMutationID
        )
    }

    func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func deletionJournalURL(_ harness: Harness) -> URL {
        harness.applicationSupportURL
            .appendingPathComponent("FieldEvidenceOperations/deletion", isDirectory: true)
    }

    func deletionJournalNames(_ harness: Harness) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: deletionJournalURL(harness).path).sorted()
    }

    @MainActor
    func assertThrows<T>(
        _ expected: WholeSignDeletionServiceError,
        operation: @MainActor () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as WholeSignDeletionServiceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

extension S6_1DeletionGraphTests {
    func testV23P03C41DeletionGraphPreviewIsExplicitAndZeroWrite() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_610)
        let preview = try FunctionalRelationshipDispositionPreviewEngineV1.preview(
            change: .deleted,
            relationship: fixture.added,
            descriptor: fixture.descriptor,
            currentSiteID: C41FunctionalRelationshipTestSupportV1.id(41_611)
        )

        XCTAssertEqual(preview.disposition, .end)
        XCTAssertEqual(preview.reasonCode, "endpoint_or_package_no_longer_current_review_end")
        XCTAssertFalse(preview.persistentWriteOccurred)
        XCTAssertEqual(preview.relationshipID, fixture.relationshipID)
        try preview.validate()
    }
}

extension S6_1DeletionGraphTests {
    func testV23P03C13DeletionPreviewKeepsAssuranceProjectionNonPersistent() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_610)
        let preview = fixture.customerPreview

        try preview.validate()
        XCTAssertEqual(preview.includedLinks.count, 1)
        XCTAssertEqual(preview.excludedLinks.count, 1)
        XCTAssertTrue(preview.excludedLinks.allSatisfy { $0.decision.disposition == .excluded })
        XCTAssertFalse(preview.includedLinks.contains { $0.evidenceID == "evidence.internal-canary" })
        XCTAssertEqual(preview.snapshotSHA256, fixture.customerManifest.snapshotSHA256)
    }
}

extension S6_1DeletionGraphTests {
    func testV23P03C14SuccessorGraphRetainsReviewSubjectBinding() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_161)
        try fixture.supersedingTransition.validateSuccessor(of: fixture.transitions.last!)
        XCTAssertEqual(fixture.supersedingTransition.subject, fixture.subject)
        XCTAssertEqual(fixture.supersedingTransition.successorSubject?.workspaceID, fixture.workspaceID)
        XCTAssertNotEqual(
            fixture.supersedingTransition.successorSubject?.subjectID,
            fixture.supersedingTransition.subject.subjectID
        )
    }
}

extension S6_1DeletionGraphTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension S6_1DeletionGraphTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertNoThrow(try V22FieldReferenceImportBoundaryV1.validate(persistent: 22, records: 21))
        XCTAssertEqual(PersistentSchemaV22.models.count, PersistentSchemaV21.models.count + 2)
    }
}

extension S6_1DeletionGraphTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
final class C31LightingAnchorS61DeletionGraphTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class C33TemporalEvidenceAnchorS61DeletionGraph: XCTestCase {
    func testC33S61DeletionGraphCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "deletion.temporal-content-graph",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "deletion.temporal-content-graph",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

final class C32AssistanceAnchorS61DeletionGraph: XCTestCase {
    func testC32S61DeletionGraphCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .evidenceFile,
            fieldID: "deletion.source-expiry",
            value: .text("source-bound candidate")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .evidenceFile,
            fieldID: "deletion.source-expiry",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
final class C46S61DeletionGraphCompatibilityTests: XCTestCase {
    func testC46DeletionGraphKeepsSiteDeletionNoncascading() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "deletion-graph",
            kind: .phone,
            handoff: .directions,
            slot: 46601
        )
    }
}

extension S6_1DeletionGraphTests {
    func testV23P03C34DeletedTargetFallsBackWithoutMutation() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x08)))
        let stableID = UUID()
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .work, stableEntityID: stableID)
        let result = try RouteRegistryV1().resolve(target, context: .init(currentWorkspaceID: workspace, currentRevision: 0, unavailableStableIDs: [stableID]))
        XCTAssertEqual(result.disposition, .safeFallback)
        XCTAssertEqual(result.reason, .deletedOrTombstoned)
        XCTAssertEqual(result.target.destination, .today)
        XCTAssertEqual(result.canonicalMutationCount, 0)
        XCTAssertFalse(result.startsAutomaticWork)
    }
}

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class S3_4ResumeRecoveryTests: XCTestCase {
    private let fileManager = FileManager.default

    private enum OriginalFixtureStop: Error { case inspected }

    /// Unlike the source-only hostile tests below, this returns from the real
    /// startup recovery callback and completes every released migration. The
    /// final process-ID change is a unit analogue, not a real cold launch.
    @MainActor
    func testOriginalRecoveryThroughActiveUpgradePreservesReportsPDFAndMedia() async throws {
        let root = try makeTemporaryDirectory("Original-full-recovery-upgrade")
        defer { try? fileManager.removeItem(at: root) }
        let fixture = try await seedOriginalV1(root: root, phase: .databaseCommitted)
        let correction = try await seedOriginalCorrection(root: root, fixture: fixture)
        let sourceRoot = fixture.snapshotURL.deletingLastPathComponent().deletingLastPathComponent()
        let originalSnapshot = try ReportSnapshotEncoderV1().decode(fixture.snapshotBytes)
        let correctionSnapshotPath = "snapshots/\(correction.ids.reportID.uuidString.lowercased()).json"
        let priorPDFPath = "pdfs/\(fixture.intent.reportID.uuidString.lowercased()).pdf"
        var retainedBytes = [fixture.intent.snapshotFinalRelativePath: fixture.snapshotBytes,
                             correctionSnapshotPath: try Data(contentsOf: sourceRoot.appendingPathComponent(correctionSnapshotPath)),
                             priorPDFPath: try Data(contentsOf: sourceRoot.appendingPathComponent(priorPDFPath))]
        for evidence in originalSnapshot.evidence {
            for path in [evidence.relativePath, evidence.thumbnailRelativePath] {
                retainedBytes[path] = try Data(contentsOf: sourceRoot.appendingPathComponent(path))
            }
        }
        XCTAssertEqual(originalSnapshot.evidence.count, 2)
        let residue = try await seedOriginalAggregateResidue(root: root, sourceRoot: sourceRoot,
            generationID: fixture.generationID, pendingReportID: correction.ids.reportID)
        for url in residue { XCTAssertTrue(fileManager.fileExists(atPath: url.path)) }
        let pointerURL = root.appendingPathComponent("FieldEvidenceData/current.json")
        let originalPointer = try Data(contentsOf: pointerURL)

        // The router owns the actual recovery service ordering and scopes all
        // source contexts/actors to its callback. No test-owned callback holds
        // the released seven-model container open during the aggregate drain.
        var router: StartupRouter? = StartupRouter(applicationSupportURL: root)
        weak var releasedRouter = router
        await router?.startIfNeeded()
        guard case .awaitingIndependentValidation(let pending)? = router?.route else {
            return XCTFail("Real startup recovery must migrate and await independent validation")
        }
        let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: root))
        let journal = try XCTUnwrap(control.load())
        XCTAssertEqual(journal.phase, .awaitingIndependentValidation)
        XCTAssertEqual(journal.transitions.map { $0.targetRelease.versionIdentifier.major }, Array(2...53))
        XCTAssertEqual(journal.sourceGenerationID, fixture.generationID)
        XCTAssertEqual(journal.targetGenerationID, pending.targetGenerationID)
        XCTAssertNotEqual(pending.targetGenerationID, fixture.generationID)
        for url in residue { XCTAssertFalse(fileManager.fileExists(atPath: url.path)) }
        for (path, bytes) in retainedBytes {
            XCTAssertEqual(try Data(contentsOf: sourceRoot.appendingPathComponent(path)), bytes)
        }
        // Only a value snapshot crosses this scope. The factory's provider and
        // restore authority both retain a registry, whose deinit releases its
        // owner flock; do not keep either alive for the simulated next process.
        weak var releasedSnapshotRegistry: GenerationLeaseRegistryV1?
        let frozenSource = try autoreleasepool {
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            releasedSnapshotRegistry = try factory.makeGenerationLeaseRegistry()
            let authority = try factory.makeRestoreGenerationAuthority()
            XCTAssertFalse(try authority.retiredGenerationIDs().contains(fixture.generationID))
            return try authority.snapshotInstalledGeneration(id: fixture.generationID)
        }
        guard releasedSnapshotRegistry == nil else {
            return XCTFail("Snapshot factory and authority must release their registry")
        }
        let publishedPointer = try Data(contentsOf: pointerURL)
        XCTAssertNotEqual(publishedPointer, originalPointer)
        XCTAssertEqual(try CurrentGenerationPointerV3.decodeCanonical(from: publishedPointer).storeSchemaVersion, 53)
        await router?.retryChecks()
        guard case .awaitingIndependentValidation? = router?.route else {
            return XCTFail("Same process cannot admit the upgraded writer")
        }
        XCTAssertEqual(try control.load(), journal)
        XCTAssertEqual(try Data(contentsOf: pointerURL), publishedPointer)

        // A changed process ID is not owner-death proof. Drop the actual router
        // (and its private factory/provider) before a different registry asks
        // the unchanged flock-based gate to transfer the durable reservation.
        router = nil
        await Task.yield()
        guard releasedRouter == nil else {
            return XCTFail("Original router must deallocate before owner takeover")
        }

        let independentProcessID = UUID()
        let independentFactory = StoreGenerationFactory(applicationSupportURL: root,
            migrationIdentitySource: StoreMigrationIdentitySourceV1(makeMigrationID: UUID.init,
                makeGenerationID: UUID.init, makeProcessID: { independentProcessID }))
        let opened = try await independentFactory.openForStartup { _ in
            XCTFail("Published aggregate must not recover the original source twice")
        }
        guard case .ready(let session) = opened else {
            return XCTFail("Independent unit process must validate and admit the active target")
        }
        XCTAssertEqual(session.generationID, pending.targetGenerationID)
        let context = session.modelContext
        let reports = try context.fetch(FetchDescriptor<Report>())
        XCTAssertEqual(Set(reports.map(\.id)), Set([fixture.intent.reportID, correction.ids.reportID]))
        let prior = try XCTUnwrap(reports.first { $0.id == fixture.intent.reportID })
        let successor = try XCTUnwrap(reports.first { $0.id == correction.ids.reportID })
        XCTAssertEqual(prior.sourceRecordID, fixture.intent.recordID)
        XCTAssertEqual(prior.snapshotSHA256, fixture.intent.snapshotSHA256)
        XCTAssertEqual(prior.pdfState, ReportPDFState.ready.rawValue)
        XCTAssertEqual(prior.pdfRelativePath, priorPDFPath)
        XCTAssertEqual(prior.pdfSHA256, CanonicalJSONV1.sha256(try XCTUnwrap(retainedBytes[priorPDFPath])))
        XCTAssertEqual(successor.sourceRecordID, correction.ids.recordID)
        XCTAssertEqual(successor.replacesReportID, prior.id)
        XCTAssertEqual(successor.packetID, fixture.intent.packetID)
        XCTAssertEqual(successor.snapshotRelativePath, correctionSnapshotPath)
        XCTAssertEqual(successor.snapshotSHA256, CanonicalJSONV1.sha256(try XCTUnwrap(retainedBytes[correctionSnapshotPath])))
        XCTAssertEqual(successor.pdfState, ReportPDFState.pending.rawValue)
        XCTAssertNil(successor.pdfRelativePath)
        XCTAssertNil(successor.pdfSHA256)
        let records = try context.fetch(FetchDescriptor<WorkflowRecord>())
        XCTAssertEqual(Set(records.map(\.id)), Set([fixture.intent.recordID, correction.ids.recordID]))
        let correctedRecord = try XCTUnwrap(records.first { $0.id == correction.ids.recordID })
        XCTAssertEqual(correctedRecord.revisesRecordID, fixture.intent.recordID)
        XCTAssertEqual(correctedRecord.evidenceSourceRecordID, fixture.intent.recordID)
        XCTAssertEqual(correctedRecord.assetID, fixture.intent.finalizationPayload.workflowRecordAfter.assetID)
        let packets = try context.fetch(FetchDescriptor<Packet>())
        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first)
        XCTAssertEqual(packet.id, fixture.intent.packetID)
        XCTAssertEqual(packet.stableRootID, fixture.intent.stableRootID)
        XCTAssertEqual(packet.currentRecordID, correction.ids.recordID)
        let assets = try context.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.id, correctedRecord.assetID)
        let sites = try context.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(sites.first?.id, assets.first?.siteID)
        let evidenceRows = try context.fetch(FetchDescriptor<EvidenceFile>())
        XCTAssertEqual(Set(evidenceRows.map(\.id)), Set(originalSnapshot.evidence.map(\.evidenceID)))
        for expected in originalSnapshot.evidence {
            let row = try XCTUnwrap(evidenceRows.first { $0.id == expected.evidenceID })
            XCTAssertEqual(row.recordID, expected.recordID)
            XCTAssertEqual(row.relativePath, expected.relativePath)
            XCTAssertEqual(row.sha256, expected.sha256)
            XCTAssertEqual(row.byteCount, expected.byteCount)
            XCTAssertEqual(row.thumbnailRelativePath, expected.thumbnailRelativePath)
            XCTAssertEqual(row.thumbnailSHA256, expected.thumbnailSHA256)
            XCTAssertEqual(row.thumbnailByteCount, expected.thumbnailByteCount)
        }
        for (path, bytes) in retainedBytes {
            XCTAssertEqual(try Data(contentsOf: session.generationRootURL.appendingPathComponent(path)), bytes)
            XCTAssertEqual(try Data(contentsOf: sourceRoot.appendingPathComponent(path)), bytes)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>()).first?.schemaVersion, 53)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try control.load()?.phase, .complete)
        let restoreAuthority = try independentFactory.makeRestoreGenerationAuthority()
        XCTAssertTrue(try restoreAuthority.retiredGenerationIDs().contains(fixture.generationID))
        let preserved = try restoreAuthority.snapshotInstalledGeneration(id: fixture.generationID)
        XCTAssertEqual(preserved.files, frozenSource.files)
        XCTAssertEqual(preserved.frozenIdentityDigest, frozenSource.frozenIdentityDigest)
        XCTAssertEqual(try Data(contentsOf: pointerURL), publishedPointer)
    }

    /// All residue exists before startup; the deletion journal binds actual
    /// owned bytes, and the media orphans were produced by the real actor.
    @MainActor
    private func seedOriginalAggregateResidue(root: URL, sourceRoot: URL,
        generationID: UUID, pendingReportID: UUID) async throws -> [URL] {
        let deletedPDFPath = "pdfs/\(UUID().uuidString.lowercased()).pdf"
        let deletedPDF = sourceRoot.appendingPathComponent(deletedPDFPath)
        try Data("%PDF-1.4\ncommitted deletion residue\n%%EOF".utf8).write(to: deletedPDF)
        let deletion = DeletionIntentV1(assetID: UUID(), countedPacketTombstones: [],
            deletionID: UUID(), generationID: generationID, ledgerEntries: [],
            phase: .databaseCommitted, relativePaths: [deletedPDFPath], schemaVersion: 1)
        let deletionURL = root.appendingPathComponent("FieldEvidenceOperations/deletion/\(deletion.deletionID.uuidString.lowercased()).json")
        try fileManager.createDirectory(at: deletionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DeletionIntentEncoderV1().encode(deletion).data.write(to: deletionURL)
        let media = EvidenceBundleStore(generationRootURL: sourceRoot)
        let normalized = try MediaNormalizerV1().normalize(makePNG(seed: 197))
        let staged = try await media.stage(evidenceID: UUID(), normalized: normalized)
        let toPromote = try await media.stage(evidenceID: UUID(), normalized: normalized)
        let promoted = try await media.promote(toPromote)
        let attempt = sourceRoot.appendingPathComponent(".staging/pdfs/\(pendingReportID.uuidString.lowercased()).pdf")
        try fileManager.createDirectory(at: attempt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("%PDF-1.4\ninterrupted pending render".utf8).write(to: attempt)
        return [deletedPDF, deletionURL, attempt,
                sourceRoot.appendingPathComponent(staged.stagingDirectoryRelativePath),
                sourceRoot.appendingPathComponent(promoted.originalRelativePath),
                sourceRoot.appendingPathComponent(promoted.thumbnailRelativePath)]
    }

    @MainActor
    func testOriginalSevenModelCorrectionRetainsHistoricalReportAndRejectsOrphan() async throws {
        let root = try makeTemporaryDirectory("Original-correction-chain")
        defer { try? fileManager.removeItem(at: root) }
        let fixture = try await seedOriginalV1(root: root, phase: .databaseCommitted)
        let correction = try await seedOriginalCorrection(root: root, fixture: fixture)
        let correctionID = correction.ids
        let generationRoot = fixture.snapshotURL.deletingLastPathComponent().deletingLastPathComponent()
        let pdfURL = generationRoot.appendingPathComponent("pdfs/\(fixture.intent.reportID.uuidString.lowercased()).pdf")
        let pdfBytes = try Data(contentsOf: pdfURL)
        var visited = false
        do {
            _ = try await StoreGenerationFactory(applicationSupportURL: root).openForStartup { authority in
                visited = true
                let service = try FinalizationRecoveryService(sourceRecoveryAuthority: authority)
                let recovered = try await service.reconcile()
                XCTAssertEqual(recovered.completedRecordIDs, [correctionID.recordID])
                let context = try authority.recoveryContext()
                let reports = try context.fetch(FetchDescriptor<Report>())
                XCTAssertEqual(reports.count, 2)
                let validator = try SnapshotValidatorV1(sourceRecoveryAuthority: authority)
                for report in reports { _ = try validator.validateOriginalSource(report: report) }
                let pendingName = correctionID.reportID.uuidString.lowercased() + ".pdf"
                let attemptURL = generationRoot.appendingPathComponent(".staging/pdfs/" + pendingName)
                let ambiguousURL = generationRoot.appendingPathComponent("pdfs/" + pendingName)
                try fileManager.createDirectory(at: attemptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let interruptedBytes = Data("%PDF-1.4 interrupted original attempt".utf8)
                try interruptedBytes.write(to: attemptURL)
                try interruptedBytes.write(to: ambiguousURL)
                XCTAssertThrowsError(try ReportRecoveryService.settleOriginalSourcePDFs(authority: authority))
                XCTAssertEqual(try Data(contentsOf: attemptURL), interruptedBytes)
                XCTAssertEqual(try Data(contentsOf: ambiguousURL), interruptedBytes)
                XCTAssertEqual(try Data(contentsOf: pdfURL), pdfBytes)
                try fileManager.removeItem(at: ambiguousURL)
                try ReportRecoveryService.settleOriginalSourcePDFs(authority: authority)
                XCTAssertFalse(fileManager.fileExists(atPath: attemptURL.path))
                XCTAssertFalse(fileManager.fileExists(atPath: ambiguousURL.path))
                try ReportRecoveryService.verifyOriginalRecoverySettled(authority: authority)
                XCTAssertEqual(try Data(contentsOf: fixture.snapshotURL), fixture.snapshotBytes)
                XCTAssertEqual(try Data(contentsOf: pdfURL), pdfBytes)
                let prior = try XCTUnwrap(reports.first { $0.id == fixture.intent.reportID })
                let successor = try XCTUnwrap(reports.first { $0.id == correctionID.reportID })
                let fork = correction.fork
                insertOriginalCorrectionRecord(fork.recordAfter, context: context)
                let forkReport = fork.reportInsert
                context.insert(Report(id: forkReport.id, packetID: forkReport.packetID, sourceRecordID: forkReport.sourceRecordID,
                    snapshotSchemaVersion: forkReport.snapshotSchemaVersion, snapshotRelativePath: forkReport.snapshotRelativePath,
                    snapshotSHA256: forkReport.snapshotSHA256, pdfState: .pending, pdfRelativePath: nil, pdfSHA256: nil,
                    createdAt: forkReport.createdAt, replacesReportID: forkReport.replacesReportID))
                let forkURL = generationRoot.appendingPathComponent(forkReport.snapshotRelativePath)
                try ReportSnapshotEncoderV1().encode(fork.snapshot).data.write(to: forkURL)
                XCTAssertThrowsError(try validator.validateOriginalSource(report: successor))
                context.rollback()
                try fileManager.removeItem(at: forkURL)
                // Removing the actual predecessor produces a dangling replacement
                // edge; an archived-row bypass must not silently admit it.
                context.delete(prior)
                XCTAssertThrowsError(try validator.validateOriginalSource(report: successor))
                context.rollback()
                for report in try context.fetch(FetchDescriptor<Report>()) {
                    _ = try validator.validateOriginalSource(report: report)
                }
                XCTAssertEqual(try Data(contentsOf: fixture.snapshotURL), fixture.snapshotBytes)
                XCTAssertEqual(try Data(contentsOf: pdfURL), pdfBytes)
                throw OriginalFixtureStop.inspected
            }
            XCTFail("fixture must stop before migration")
        } catch OriginalFixtureStop.inspected {} catch { throw error }
        XCTAssertTrue(visited)
    }

    @MainActor
    private func seedOriginalCorrection(root: URL, fixture: OriginalV1Fixture) async throws
        -> (ids: ReportCorrectionIdentifiers, fork: ReportCorrectionRulePlan) {
        let generationRoot = fixture.snapshotURL.deletingLastPathComponent().deletingLastPathComponent()
        let schema = PersistentSchemaV1.makeSchema()
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration(
            "S3_4OriginalV1", schema: schema, url: generationRoot.appendingPathComponent("model.sqlite"),
            allowsSave: true, cloudKitDatabase: .none
        )])
        let context = container.mainContext
        let prior = try XCTUnwrap(try context.fetch(FetchDescriptor<Report>()).first)
        let pdfPath = "pdfs/\(prior.id.uuidString.lowercased()).pdf"
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { page in
            page.beginPage()
            ("Synthetic released original report" as NSString).draw(at: CGPoint(x: 40, y: 40))
        }
        try fileManager.createDirectory(at: generationRoot.appendingPathComponent("pdfs"), withIntermediateDirectories: true)
        try pdf.write(to: generationRoot.appendingPathComponent(pdfPath))
        prior.pdfState = ReportPDFState.ready.rawValue
        prior.pdfRelativePath = pdfPath
        prior.pdfSHA256 = CanonicalJSONV1.sha256(pdf)
        try context.save()
        let priorPayload = ReportPayloadV1(id: prior.id, schemaVersion: prior.schemaVersion,
            packetID: prior.packetID, sourceRecordID: prior.sourceRecordID, snapshotSchemaVersion: prior.snapshotSchemaVersion,
            snapshotRelativePath: prior.snapshotRelativePath, snapshotSHA256: prior.snapshotSHA256,
            pdfState: prior.pdfState, pdfRelativePath: prior.pdfRelativePath, pdfSHA256: prior.pdfSHA256,
            createdAt: prior.createdAt, replacesReportID: prior.replacesReportID)
        let original = try ReportSnapshotEncoderV1().decode(fixture.snapshotBytes)
        let ids = ReportCorrectionIdentifiers(mutationID: UUID(), recordID: UUID(), reportID: UUID())
        let source = ReportCorrectionRuleSource(
            currentRecord: fixture.intent.finalizationPayload.workflowRecordAfter,
            packet: fixture.intent.finalizationPayload.packetAfter, currentReport: priorPayload, currentSnapshot: original
        )
        let plan = try ReportCorrectionRule().makePlan(source: source,
            request: ReportCorrectionRuleRequest(note: "Original source correction", snapshotCreatedAt: original.snapshotCreatedAt.addingTimeInterval(1),
                                               sourceApp: original.sourceApp, identifiers: ids))
        let fork = try ReportCorrectionRule().makePlan(source: source,
            request: ReportCorrectionRuleRequest(note: "Independent hostile fork", snapshotCreatedAt: original.snapshotCreatedAt.addingTimeInterval(2),
                sourceApp: original.sourceApp, identifiers: ReportCorrectionIdentifiers(mutationID: UUID(), recordID: UUID(), reportID: UUID())))
        let snapshot = try ReportSnapshotEncoderV1().encode(plan.snapshot)
        let payload = FinalizationPayloadV1(issueInsert: nil, issueTransition: nil, packetAfter: plan.packetAfter,
            packetBefore: plan.packetBefore, reportInsert: plan.reportInsert, workflowRecordAfter: plan.recordAfter)
        let intent = FinalizationIntentV1(completedAt: try XCTUnwrap(plan.recordAfter.completedAt),
            finalizationMutationID: ids.mutationID, finalizationPayload: payload,
            finalizationPayloadSHA256: try FinalizationContractEncoderV1().encodePayload(payload).sha256,
            generationID: fixture.generationID, packetID: plan.packetAfter.id, phase: .prepared,
            recordID: ids.recordID, reportID: ids.reportID, schemaVersion: 1,
            snapshotCreatedAt: plan.snapshot.snapshotCreatedAt, snapshotFinalRelativePath: plan.reportInsert.snapshotRelativePath,
            snapshotSHA256: snapshot.sha256, snapshotStagingRelativePath: ".staging/\(plan.reportInsert.snapshotRelativePath)",
            stableRootID: plan.packetAfter.stableRootID)
        let store = FinalizationIntentStore(generationRootURL: generationRoot)
        for committed in try await store.discoverRecoverableFinalizations() {
            try await store.cleanupCommittedForRecovery(committed)
        }
        let prepared = try await store.prepare(intent: intent, snapshot: snapshot)
        let promoted = try await store.promoteSnapshot(prepared)
        _ = try await store.advance(promoted, to: .snapshotPromoted)
        return (ids, fork)
    }

    @MainActor
    private func insertOriginalCorrectionRecord(_ value: WorkflowRecordPayloadV1, context: ModelContext) {
        context.insert(WorkflowRecord(id: value.id, assetID: value.assetID, packetID: value.packetID, issueID: value.issueID,
            parentRecordID: value.parentRecordID, recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID, evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: .clericalCorrection, stage: .check, state: .completed, draftStepKey: nil,
            startedAt: value.startedAt, completedAt: value.completedAt, observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID, utcOffsetMinutes: value.utcOffsetMinutes, localDate: value.localDate, localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey, afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion, afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey, safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion, safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion, packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID, pdfTemplateVersion: value.pdfTemplateVersion, outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey, couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion, workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note, finalizationMutationID: value.finalizationMutationID))
    }

    @MainActor
    func testOriginalCommittedDeletionPreflightsLateFIFOAndSymlinkBeforeAnyEffect() async throws {
        for hostileKind in ["fifo", "symlink", "extra-bundle-member"] {
            let root = try makeTemporaryDirectory("Original-deletion-\(hostileKind)")
            defer { try? fileManager.removeItem(at: root) }
            let fixture = try await seedOriginalV1(root: root, phase: .prepared)
            let generationRoot = fixture.snapshotURL.deletingLastPathComponent().deletingLastPathComponent()
            let bundle = hostileKind == "extra-bundle-member"
            let paths = bundle
                ? ["evidence/00000000-0000-0000-0000-000000000003/original.jpg",
                   "evidence/00000000-0000-0000-0000-000000000003/thumbnail.jpg"]
                : ["pdfs/00000000-0000-0000-0000-000000000001.pdf",
                   "pdfs/00000000-0000-0000-0000-000000000002.pdf"]
            let first = generationRoot.appendingPathComponent(paths[0])
            let second = generationRoot.appendingPathComponent(paths[1])
            let hostile = bundle ? first.deletingLastPathComponent().appendingPathComponent("zz.bin") : second
            try fileManager.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = Data("%PDF-1.4\nowned deletion fixture\n%%EOF".utf8)
            try original.write(to: first)
            if hostileKind == "fifo" { XCTAssertEqual(Darwin.mkfifo(hostile.path, 0o600), 0) }
            else if bundle { try original.write(to: second); try original.write(to: hostile) }
            else { try fileManager.createSymbolicLink(at: hostile, withDestinationURL: first) }
            let intent = DeletionIntentV1(assetID: UUID(), countedPacketTombstones: [],
                deletionID: UUID(), generationID: fixture.generationID, ledgerEntries: [],
                phase: .databaseCommitted, relativePaths: paths, schemaVersion: 1)
            let journalURL = root.appendingPathComponent("FieldEvidenceOperations/deletion/\(intent.deletionID.uuidString.lowercased()).json")
            try fileManager.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let journalBytes = try DeletionIntentEncoderV1().encode(intent).data
            try journalBytes.write(to: journalURL)
            var visited = false
            do {
                _ = try await StoreGenerationFactory(applicationSupportURL: root).openForStartup { authority in
                    visited = true
                    XCTAssertThrowsError(try WholeSignDeletionService.reconcileOriginalSource(authority: authority))
                    XCTAssertEqual(try Data(contentsOf: first), original)
                    if bundle { XCTAssertEqual(try Data(contentsOf: second), original) }
                    XCTAssertEqual(try Data(contentsOf: journalURL), journalBytes)
                    // Repair only the synthetic hostile fixture, then exercise the
                    // same original committed intent and duplicate-free retry.
                    try fileManager.removeItem(at: hostile)
                    if !bundle { try original.write(to: hostile) }
                    let summary = try WholeSignDeletionService.reconcileOriginalSource(authority: authority)
                    XCTAssertEqual(summary.completedCommittedCount, 1)
                    XCTAssertFalse(fileManager.fileExists(atPath: first.path))
                    XCTAssertFalse(fileManager.fileExists(atPath: hostile.path))
                    XCTAssertFalse(fileManager.fileExists(atPath: journalURL.path))
                    XCTAssertEqual(try WholeSignDeletionService.reconcileOriginalSource(authority: authority).completedCommittedCount, 0)
                    if bundle {
                        XCTAssertFalse(fileManager.fileExists(atPath: first.deletingLastPathComponent().path))
                        // Crash after directory cleanup but before journal cleanup.
                        try journalBytes.write(to: journalURL)
                        XCTAssertEqual(try WholeSignDeletionService.reconcileOriginalSource(authority: authority).completedCommittedCount, 1)
                        XCTAssertFalse(fileManager.fileExists(atPath: journalURL.path))
                    }
                    throw OriginalFixtureStop.inspected
                }
                XCTFail("fixture must stop before migration")
            } catch OriginalFixtureStop.inspected {} catch { throw error }
            XCTAssertTrue(visited)
        }
    }

    @MainActor
    func testOriginalSevenModelFinalizationRecoveryAndRevokedActors() async throws {
        for phase in [FinalizationPhaseV1.prepared, .snapshotPromoted, .databaseCommitted] {
            let root = try makeTemporaryDirectory("Original-\(phase.rawValue)")
            defer { try? fileManager.removeItem(at: root) }
            let fixture = try await seedOriginalV1(root: root, phase: phase)
            let pointerURL = root.appendingPathComponent("FieldEvidenceData/current.json")
            let pointerBytes = try Data(contentsOf: pointerURL)
            var retainedStore: FinalizationIntentStore?
            var retainedMedia: EvidenceBundleStore?
            var originalMedia: [URL: Data] = [:]
            var visited = false
            do {
                _ = try await StoreGenerationFactory(applicationSupportURL: root).openForStartup { authority in
                    visited = true
                    XCTAssertEqual(authority.sourceRelease, .v1)
                    XCTAssertEqual(authority.sourceGenerationID, fixture.generationID)
                    let context = try authority.recoveryContext()
                    let service = try FinalizationRecoveryService(sourceRecoveryAuthority: authority)
                    let summary = try await service.reconcile()
                    XCTAssertEqual(summary.completedRecordIDs, [fixture.intent.recordID])
                    let report = try XCTUnwrap(try context.fetch(FetchDescriptor<Report>()).first)
                    _ = try SnapshotValidatorV1(sourceRecoveryAuthority: authority).validateOriginalSource(report: report)
                    XCTAssertEqual(try Data(contentsOf: fixture.snapshotURL), fixture.snapshotBytes)
                    try await service.verifyOriginalRecoverySettled()
                    let repeated = try await service.reconcile()
                    XCTAssertTrue(repeated.completedRecordIDs.isEmpty)
                    XCTAssertTrue(repeated.recoveredDraftRecordIDs.isEmpty)
                    if phase == .prepared {
                        let foreign = root.appendingPathComponent("foreign-source-root")
                        let moved = root.appendingPathComponent("retained-original-root")
                        try fileManager.createDirectory(at: foreign, withIntermediateDirectories: false)
                        let sentinel = Data("foreign root must remain untouched".utf8)
                        try sentinel.write(to: foreign.appendingPathComponent("sentinel"))
                        try fileManager.moveItem(at: authority.generationRootURL, to: moved)
                        do {
                            defer {
                                try? fileManager.removeItem(at: authority.generationRootURL)
                                try? fileManager.moveItem(at: moved, to: authority.generationRootURL)
                            }
                            try fileManager.createSymbolicLink(at: authority.generationRootURL, withDestinationURL: foreign)
                            XCTAssertThrowsError(try FinalizationIntentStore(sourceRecoveryAuthority: authority))
                            XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: foreign.path), ["sentinel"])
                            XCTAssertEqual(try Data(contentsOf: foreign.appendingPathComponent("sentinel")), sentinel)
                        }
                    }
                    let actor = try FinalizationIntentStore(sourceRecoveryAuthority: authority)
                    retainedStore = actor
                    let media = try EvidenceBundleStore(sourceRecoveryAuthority: authority)
                    retainedMedia = media
                    let mediaRows = try context.fetch(FetchDescriptor<EvidenceFile>())
                    let mediaAuthority = mediaRows.map { row in
                        EvidenceBundleAuthority(schemaVersion: row.schemaVersion, id: row.id, recordID: row.recordID,
                            purposeKey: row.purposeKey, relativePath: row.relativePath, mimeType: row.mimeType,
                            byteCount: row.byteCount, sha256: row.sha256, thumbnailRelativePath: row.thumbnailRelativePath,
                            thumbnailByteCount: row.thumbnailByteCount, thumbnailSHA256: row.thumbnailSHA256)
                    }
                    for row in mediaRows {
                        for path in [row.relativePath, row.thumbnailRelativePath] {
                            let url = authority.generationRootURL.appendingPathComponent(path)
                            originalMedia[url] = try Data(contentsOf: url)
                        }
                    }
                    try await media.reconcile(authorities: mediaAuthority)
                    try await media.verifyOriginalRecoverySettled(authorities: mediaAuthority)
                    do {
                        try await media.discardStaging(evidenceID: try XCTUnwrap(mediaRows.first).id)
                        XCTFail("source media actor cannot use ordinary producer cleanup")
                    } catch {}
                    do {
                        _ = try await actor.prepare(intent: fixture.intent, snapshot: fixture.encodedSnapshot)
                        XCTFail("source authority cannot publish a new intent")
                    } catch {}
                    XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBytes)
                    throw OriginalFixtureStop.inspected
                }
                XCTFail("fixture callback must stop before migration")
            } catch OriginalFixtureStop.inspected {} catch { throw error }
            XCTAssertTrue(visited)
            let revoked = try XCTUnwrap(retainedStore)
            do {
                _ = try await revoked.discoverRecoverableFinalizations()
                XCTFail("revoked source actor cannot inspect original journals")
            } catch {}
            let revokedMedia = try XCTUnwrap(retainedMedia)
            do {
                try await revokedMedia.reconcile(authorities: [])
                XCTFail("revoked media actor cannot erase original bundles")
            } catch {}
            for (url, data) in originalMedia { XCTAssertEqual(try Data(contentsOf: url), data) }
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBytes)
        }
    }

    private struct OriginalV1Fixture {
        let generationID: UUID
        let intent: FinalizationIntentV1
        let encodedSnapshot: EncodedReportSnapshotV1
        let snapshotURL: URL
        var snapshotBytes: Data { encodedSnapshot.data }
    }

    /// Create the actual released seven-model disk store, never a current-schema
    /// session with its modern rows omitted. Return only value/file authority.
    @MainActor
    private func seedOriginalV1(root: URL, phase: FinalizationPhaseV1) async throws -> OriginalV1Fixture {
        let generationID = UUID()
        let dataRoot = root.appendingPathComponent("FieldEvidenceData")
        let generationRoot = dataRoot.appendingPathComponent("generations/\(generationID.uuidString.lowercased())")
        try fileManager.createDirectory(at: generationRoot, withIntermediateDirectories: true)
        let schema = PersistentSchemaV1.makeSchema()
        let configuration = ModelConfiguration(
            "S3_4OriginalV1", schema: schema,
            url: generationRoot.appendingPathComponent("model.sqlite"),
            allowsSave: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [configuration])
        let context = container.mainContext
        let site = Site(label: "North Campus", timeZoneID: "America/New_York")
        let asset = Asset(siteID: site.id, packID: SignPack.illuminatedSignV1.packID,
                          packSchemaVersion: 1, packContentVersion: 1, label: "Monument Sign")
        let draft = makeDraft(assetID: asset.id)
        context.insert(site); context.insert(asset); context.insert(draft)
        let evidence = try await makeEvidenceAuthority(recordID: draft.id, context: context, generationRootURL: generationRoot)
        try context.save()
        let packetID = UUID(), reportID = UUID(), stableRootID = UUID()
        let date = Date(timeIntervalSince1970: 1_768_438_926)
        let snapshot = try ReportSnapshotEncoderV1().encode(makeSnapshot(
            recordID: draft.id, packetID: packetID, reportID: reportID,
            stableRootID: stableRootID, snapshotCreatedAt: date, evidence: evidence,
            issues: [], isVisibleIssue: false
        ))
        let intent = try makeIntent(draft: draft, generationID: generationID, snapshot: snapshot,
                                    packetID: packetID, reportID: reportID, stableRootID: stableRootID,
                                    snapshotCreatedAt: date, issueInsert: nil)
        let store = FinalizationIntentStore(generationRootURL: generationRoot)
        let prepared = try await store.prepare(intent: intent, snapshot: snapshot)
        if phase != .prepared {
            let promoted = try await store.promoteSnapshot(prepared)
            let recorded = try await store.advance(promoted, to: .snapshotPromoted)
            if phase == .databaseCommitted {
                try applyCommittedRows(intent.finalizationPayload, context: context)
                _ = try await store.advance(recorded, to: .databaseCommitted)
            }
        }
        try StoreMigrationCanonicalJSONV1.encode(CurrentPointerV1(
            generationID: generationID.uuidString.lowercased(), schemaVersion: 1
        )).write(to: dataRoot.appendingPathComponent("current.json"))
        struct Retired: Codable { let generationIDs: [String]; let schemaVersion: Int }
        try StoreMigrationCanonicalJSONV1.encode(Retired(generationIDs: [], schemaVersion: 1))
            .write(to: dataRoot.appendingPathComponent("retired.json"))
        return OriginalV1Fixture(generationID: generationID, intent: intent, encodedSnapshot: snapshot,
                                 snapshotURL: generationRoot.appendingPathComponent(intent.snapshotFinalRelativePath))
    }

    @MainActor
    func testBeginEvidenceAndFinalizationReplayReturnExactPriorAuthority() async throws {
        let applicationSupportURL = try makeTemporaryDirectory("Replay")
        defer { try? fileManager.removeItem(at: applicationSupportURL) }
        let session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let storeCoordinator = try StoreSessionCoordinator(validatingSession: session)
        let siteID = UUID()
        let assetID = UUID()
        let placementMutationID = try MutationIDV1(rawValue: UUID())
        _ = try storeCoordinator.workspaceWriter.execute(
            .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(
                    id: siteID,
                    label: "North Campus",
                    address: nil,
                    timeZoneID: "America/New_York"
                ),
                assetID: assetID,
                assetLabel: "Monument Sign",
                packID: pack.packID,
                packSchemaVersion: pack.schemaVersion,
                packContentVersion: pack.contentVersion,
                createdAt: Date(timeIntervalSince1970: 1_768_438_922),
                initialPlacementMutationID: placementMutationID,
                initialPlacementEventID: UUID(),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
            )),
            mutationID: placementMutationID
        )
        let asset = try XCTUnwrap(
            context.fetch(FetchDescriptor<Asset>()).first { $0.id == assetID }
        )
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: pack
        )
        let dependencies = try storeCoordinator.packageLifecycleDependencies(
            profileRegistry: WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        )
        let diagnostics = DiagnosticsStore(applicationSupportURL: applicationSupportURL)
        let coordinator = try CheckRunnerCoordinator(
            modelContext: context,
            packageLifecycleDependencies: dependencies,
            packageLifecycleProfile: profile,
            diagnosticsStore: diagnostics
        )
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        let observedAt = Date(timeIntervalSince1970: 1_768_438_923)
        let firstDraft = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: observedAt
        )
        let replayedDraft = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: observedAt
        )
        XCTAssertTrue(firstDraft === replayedDraft)
        XCTAssertEqual(firstDraft.id, replayedDraft.id)
        XCTAssertEqual(firstDraft.observedAtUTC, observedAt)

        let retainedPNG = try makePNG(seed: 37)
        let wideCandidate = try await coordinator.importCandidate(
            assetID: asset.id,
            sourceData: retainedPNG,
            createdAt: observedAt.addingTimeInterval(1)
        )
        let wide = try await coordinator.accept(
            candidate: wideCandidate,
            assetID: asset.id
        )
        let replayedWide = try await coordinator.accept(
            candidate: wideCandidate,
            assetID: asset.id
        )
        XCTAssertTrue(wide === replayedWide)
        XCTAssertEqual(wide.id, replayedWide.id)
        XCTAssertEqual(wide.relativePath, replayedWide.relativePath)
        XCTAssertEqual(wide.sha256, replayedWide.sha256)
        XCTAssertEqual(wide.thumbnailRelativePath, replayedWide.thumbnailRelativePath)
        XCTAssertEqual(wide.thumbnailSHA256, replayedWide.thumbnailSHA256)
        XCTAssertEqual(firstDraft.draftStepKey, WorkflowDraftStep.close.rawValue)

        let closeCandidate = try await coordinator.importCandidate(
            assetID: asset.id,
            sourceData: retainedPNG,
            createdAt: observedAt.addingTimeInterval(2)
        )
        _ = try await coordinator.accept(candidate: closeCandidate, assetID: asset.id)
        let identifiers = FinalizationIdentifiers(
            mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
            reportID: UUID(), issueID: nil
        )
        let completedAt = observedAt.addingTimeInterval(3)
        let snapshotCreatedAt = observedAt.addingTimeInterval(4)
        let firstResult = try await coordinator.finalize(
            assetID: asset.id,
            selection: .noVisibleIssue,
            completedAt: completedAt,
            snapshotCreatedAt: snapshotCreatedAt,
            sourceApp: SourceAppSnapshotV1(build: "34", version: "1.0"),
            identifiers: identifiers
        )
        let snapshotURL = session.generationRootURL.appendingPathComponent(
            firstResult.snapshotRelativePath
        )
        let firstSnapshotBytes = try Data(contentsOf: snapshotURL)
        let replayedResult = try await coordinator.finalize(
            assetID: asset.id,
            selection: .noVisibleIssue,
            completedAt: completedAt,
            snapshotCreatedAt: snapshotCreatedAt,
            sourceApp: SourceAppSnapshotV1(build: "34", version: "1.0"),
            identifiers: identifiers
        )
        XCTAssertEqual(replayedResult, firstResult)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), firstSnapshotBytes)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Issue>()), 0)
        XCTAssertNotNil(try storeCoordinator.workspaceWriter.durableReceipt(
            mutationID: MutationIDV1(rawValue: identifiers.mutationID)
        ))
        try MutationJournalStoreV1(
            modelContext: context,
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            allowStateBootstrap: false
        ).validateAll()
        let diagnosticCounters = await diagnostics.snapshot()
        XCTAssertEqual(diagnosticCounters.reportSaved, 1)
        let firstWriterInstanceID = try storeCoordinator.workspaceWriter
            .currentRevision().writerInstanceID
        try storeCoordinator.invalidateAndReleaseWriter()

        let reopened = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let restartedCoordinator = try StoreSessionCoordinator(validatingSession: reopened)
        defer { try? restartedCoordinator.invalidateAndReleaseWriter() }
        XCTAssertNotEqual(
            try restartedCoordinator.workspaceWriter.currentRevision().writerInstanceID,
            firstWriterInstanceID
        )
        XCTAssertNotNil(try restartedCoordinator.workspaceWriter.durableReceipt(
            mutationID: MutationIDV1(rawValue: identifiers.mutationID)
        ))
        XCTAssertEqual(
            try reopened.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            1
        )
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Report>()), 1)
        withExtendedLifetime(reopened) {}
        withExtendedLifetime(session) {}
    }

    @MainActor
    func testCurrentV2PreparedPromotedAndCommittedInterruptionsRecoverThroughNewWriter() async throws {
        struct InterruptionCase {
            let label: String
            let selection: CheckOutcomeSelection
            let identifiers: FinalizationIdentifiers
            let failure: FinalizationIntentStoreFailurePoint
            let expectedPhase: FinalizationPhaseV1
            let effectsCommittedBeforeRecovery: Bool
            let expectedIssueCount: Int
        }
        let cases = [
            InterruptionCase(
                label: "v2-prepared-promoted-file",
                selection: .noVisibleIssue,
                identifiers: FinalizationIdentifiers(
                    mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
                    reportID: UUID(), issueID: nil
                ),
                failure: .intentPhaseWrite(.snapshotPromoted),
                expectedPhase: .prepared,
                effectsCommittedBeforeRecovery: false,
                expectedIssueCount: 0
            ),
            InterruptionCase(
                label: "v2-committed-before-phase-marker-visible",
                selection: .visibleIssue(labelKey: "dark_section"),
                identifiers: FinalizationIdentifiers(
                    mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
                    reportID: UUID(), issueID: UUID()
                ),
                failure: .intentPhaseWrite(.databaseCommitted),
                expectedPhase: .snapshotPromoted,
                effectsCommittedBeforeRecovery: true,
                expectedIssueCount: 1
            ),
        ]

        for testCase in cases {
            let harness = try await makeCurrentV2Producer(
                testCase.label,
                failure: testCase.failure
            )
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            var firstWriterClosed = false
            defer {
                if !firstWriterClosed {
                    try? harness.storeCoordinator.invalidateAndReleaseWriter()
                }
            }

            await assertThrowsErrorAsync(
                try await harness.runner.finalize(
                    assetID: harness.asset.id,
                    selection: testCase.selection,
                    completedAt: harness.observedAt.addingTimeInterval(3),
                    snapshotCreatedAt: harness.observedAt.addingTimeInterval(4),
                    sourceApp: SourceAppSnapshotV1(build: "34", version: "1.0"),
                    identifiers: testCase.identifiers
                )
            ) { error in
                XCTAssertEqual(error as? CheckRunnerCoordinatorError, .finalizationFailed)
            }

            let intentURL = harness.applicationSupportURL.appendingPathComponent(
                "FieldEvidenceOperations/finalization/\(testCase.identifiers.mutationID.uuidString.lowercased()).json"
            )
            let intentData = try Data(contentsOf: intentURL)
            let intent = try FinalizationContractDecoderV1().decodeIntent(intentData)
            XCTAssertEqual(intent.schemaVersion, 2, testCase.label)
            XCTAssertEqual(intent.phase, testCase.expectedPhase, testCase.label)
            let binding = try XCTUnwrap(intent.writerCommitBinding, testCase.label)
            let envelope = try binding.envelope()
            XCTAssertEqual(envelope.mutationID.rawValue, testCase.identifiers.mutationID)
            XCTAssertTrue(fileManager.fileExists(
                atPath: harness.session.generationRootURL.appendingPathComponent(
                    intent.snapshotFinalRelativePath
                ).path
            ))
            XCTAssertEqual(
                try harness.context.fetchCount(FetchDescriptor<Packet>()),
                testCase.effectsCommittedBeforeRecovery ? 1 : 0,
                testCase.label
            )
            XCTAssertEqual(
                try harness.context.fetchCount(FetchDescriptor<Report>()),
                testCase.effectsCommittedBeforeRecovery ? 1 : 0,
                testCase.label
            )
            XCTAssertEqual(
                try harness.context.fetchCount(FetchDescriptor<Issue>()),
                testCase.effectsCommittedBeforeRecovery ? testCase.expectedIssueCount : 0,
                testCase.label
            )
            XCTAssertEqual(
                try harness.storeCoordinator.workspaceWriter.durableReceipt(
                    mutationID: MutationIDV1(rawValue: testCase.identifiers.mutationID)
                ) != nil,
                testCase.effectsCommittedBeforeRecovery,
                testCase.label
            )

            let firstWriterID = try harness.storeCoordinator.workspaceWriter
                .currentRevision().writerInstanceID
            try harness.storeCoordinator.invalidateAndReleaseWriter()
            firstWriterClosed = true
            let reopened = try StoreGenerationFactory(
                applicationSupportURL: harness.applicationSupportURL
            ).openOrBootstrapCurrent()
            let restarted = try StoreSessionCoordinator(validatingSession: reopened)
            defer { try? restarted.invalidateAndReleaseWriter() }
            XCTAssertNotEqual(
                try restarted.workspaceWriter.currentRevision().writerInstanceID,
                firstWriterID,
                testCase.label
            )
            let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
                package: .illuminatedSignV1
            )
            let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
            let recovery = FinalizationRecoveryService(
                modelContext: reopened.modelContext,
                generationRootURL: reopened.generationRootURL,
                workspaceWriter: restarted.workspaceWriter,
                lifecycleProfileRegistry: registry
            )
            let summary = try await recovery.reconcile()
            XCTAssertEqual(summary.completedRecordIDs, [harness.draftID], testCase.label)
            XCTAssertFalse(fileManager.fileExists(atPath: intentURL.path), testCase.label)
            XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Packet>()), 1)
            XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Report>()), 1)
            XCTAssertEqual(
                try reopened.modelContext.fetchCount(FetchDescriptor<Issue>()),
                testCase.expectedIssueCount,
                testCase.label
            )
            let recoveredEnvelope = try XCTUnwrap(
                restarted.workspaceWriter.finalizationEnvelope(
                    mutationID: MutationIDV1(rawValue: testCase.identifiers.mutationID)
                ),
                testCase.label
            )
            XCTAssertEqual(try recoveredEnvelope.canonicalData(), binding.envelopeData)
            let repeated = try await recovery.reconcile()
            XCTAssertTrue(repeated.completedRecordIDs.isEmpty, testCase.label)
            XCTAssertEqual(
                try reopened.modelContext.fetch(FetchDescriptor<Issue>())
                    .filter { $0.id == testCase.identifiers.issueID }.count,
                testCase.expectedIssueCount,
                testCase.label
            )
            withExtendedLifetime(reopened) {}
        }
    }

    @MainActor
    func testCurrentV1PresenceMatrixNeverReplaysRawEffectsOrStampsReceipts() async throws {
        for matrixCase in RecoveryMatrixCase.allCases {
            let applicationSupportURL = try makeTemporaryDirectory(matrixCase.rawValue)
            defer { try? fileManager.removeItem(at: applicationSupportURL) }
            let seeded = try await seedRecoveryCase(
                matrixCase,
                applicationSupportURL: applicationSupportURL
            )
            let service = FinalizationRecoveryService(
                modelContext: seeded.session.modelContext,
                generationRootURL: seeded.session.generationRootURL
            )

            let beforeRecords = try seeded.session.modelContext.fetchCount(
                FetchDescriptor<WorkflowRecord>()
            )
            let beforePackets = try seeded.session.modelContext.fetchCount(FetchDescriptor<Packet>())
            let beforeReports = try seeded.session.modelContext.fetchCount(FetchDescriptor<Report>())
            let beforeReceipts = try seeded.session.modelContext.fetchCount(
                FetchDescriptor<MutationReceiptRow>()
            )
            do {
                _ = try await service.reconcile()
                XCTFail("current schema-1 recovery must remain maintenance for \(matrixCase.rawValue)")
            } catch {
                XCTAssertEqual(
                    error as? FinalizationRecoveryServiceError,
                    .inconsistent,
                    matrixCase.rawValue
                )
            }
            XCTAssertEqual(
                try seeded.session.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
                beforeRecords
            )
            XCTAssertEqual(
                try seeded.session.modelContext.fetchCount(FetchDescriptor<Packet>()),
                beforePackets
            )
            XCTAssertEqual(
                try seeded.session.modelContext.fetchCount(FetchDescriptor<Report>()),
                beforeReports
            )
            XCTAssertEqual(
                try seeded.session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
                beforeReceipts
            )
            XCTAssertTrue(fileManager.fileExists(atPath: seeded.intentURL.path))
            withExtendedLifetime(seeded.session) {}
        }
    }

    @MainActor
    func testRecoveryRejectsMalformedSemanticMismatchAndCrossIntentCollision() async throws {
        for failureCase in RecoveryFailureCase.allCases {
            let applicationSupportURL = try makeTemporaryDirectory(failureCase.rawValue)
            defer { try? fileManager.removeItem(at: applicationSupportURL) }
            let seeded = try await seedRecoveryCase(
                .snapshotPromotedFinal,
                applicationSupportURL: applicationSupportURL
            )
            switch failureCase {
            case .noncanonicalIntent:
                var bytes = try Data(contentsOf: seeded.intentURL)
                bytes.append(0x0a)
                try bytes.write(to: seeded.intentURL, options: .atomic)
            case .snapshotEvidenceMismatch:
                let evidence = try XCTUnwrap(
                    seeded.session.modelContext.fetch(FetchDescriptor<EvidenceFile>()).first
                )
                evidence.sha256 = String(repeating: "0", count: 64)
                try seeded.session.modelContext.save()
            case .originalShapeMismatch:
                let malformed = try rebuiltIntent(
                    seeded.intent,
                    mutationID: seeded.intent.finalizationMutationID,
                    parentRecordID: UUID()
                )
                let bytes = try FinalizationContractEncoderV1()
                    .encodeIntent(malformed).data
                try bytes.write(to: seeded.intentURL, options: .atomic)
            case .crossIntentCollision:
                let colliding = try intentByReplacingMutationID(
                    seeded.intent,
                    with: UUID()
                )
                let collidingURL = seeded.intentURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        colliding.finalizationMutationID.uuidString.lowercased() + ".json"
                    )
                let bytes = try FinalizationContractEncoderV1().encodeIntent(colliding).data
                try bytes.write(to: collidingURL, options: .atomic)
            }

            let service = FinalizationRecoveryService(
                modelContext: seeded.session.modelContext,
                generationRootURL: seeded.session.generationRootURL
            )
            do {
                _ = try await service.reconcile()
                XCTFail("Expected fail-closed recovery for \(failureCase.rawValue)")
            } catch {
                XCTAssertEqual(
                    error as? FinalizationRecoveryServiceError,
                    .inconsistent,
                    failureCase.rawValue
                )
            }
            XCTAssertEqual(
                try seeded.session.modelContext.fetchCount(FetchDescriptor<Packet>()),
                0
            )
            XCTAssertEqual(
                try seeded.session.modelContext.fetchCount(FetchDescriptor<Report>()),
                0
            )
            withExtendedLifetime(seeded.session) {}
        }
    }

    @MainActor
    func testCurrentV1VisibleIssueRecoveryRejectsRawApplicationForEveryPayload() async throws {
        for issueCase in VisibleIssueRecoveryCase.allCases {
            let applicationSupportURL = try makeTemporaryDirectory(issueCase.rawValue)
            defer { try? fileManager.removeItem(at: applicationSupportURL) }
            let seeded = try await seedRecoveryCase(
                .snapshotPromotedFinal,
                applicationSupportURL: applicationSupportURL,
                visibleIssueCase: issueCase
            )
            let service = FinalizationRecoveryService(
                modelContext: seeded.session.modelContext,
                generationRootURL: seeded.session.generationRootURL
            )
            do {
                _ = try await service.reconcile()
                XCTFail("current schema-1 issue payload must never apply for \(issueCase.rawValue)")
            } catch {
                XCTAssertEqual(
                    error as? FinalizationRecoveryServiceError,
                    .inconsistent,
                    issueCase.rawValue
                )
            }
            XCTAssertEqual(
                try seeded.session.modelContext.fetchCount(FetchDescriptor<Issue>()),
                0
            )
            XCTAssertTrue(fileManager.fileExists(atPath: seeded.intentURL.path))
            withExtendedLifetime(seeded.session) {}
        }
    }

    @MainActor
    func testMediaReconcileRemovesOrphansAndPreservesMismatchForMaintenance() async throws {
        let applicationSupportURL = try makeTemporaryDirectory("MediaReconcile")
        defer { try? fileManager.removeItem(at: applicationSupportURL) }
        let session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let store = EvidenceBundleStore(generationRootURL: session.generationRootURL)
        let normalized = try MediaNormalizerV1().normalize(makePNG(seed: 177))

        let orphanID = UUID()
        let orphanStaged = try await store.stage(
            evidenceID: orphanID,
            normalized: normalized
        )
        let orphan = try await store.promote(orphanStaged)
        try await store.reconcile(authorities: [])
        XCTAssertFalse(fileManager.fileExists(atPath:
            session.generationRootURL.appendingPathComponent(orphan.originalRelativePath).path
        ))

        let stagingOrphanID = UUID()
        let stagingOrphan = try await store.stage(
            evidenceID: stagingOrphanID,
            normalized: normalized
        )
        try await store.reconcile(authorities: [])
        XCTAssertFalse(fileManager.fileExists(atPath:
            session.generationRootURL
                .appendingPathComponent(stagingOrphan.stagingDirectoryRelativePath).path
        ))

        let retainedID = UUID()
        let retainedStaged = try await store.stage(
            evidenceID: retainedID,
            normalized: normalized
        )
        let retained = try await store.promote(retainedStaged)
        let mismatch = EvidenceBundleAuthority(
            schemaVersion: 1,
            id: retainedID,
            recordID: UUID(),
            purposeKey: "wide_context",
            relativePath: retained.originalRelativePath,
            mimeType: MediaContractV1.durableMIMEType,
            byteCount: retained.originalByteCount,
            sha256: String(repeating: "0", count: 64),
            thumbnailRelativePath: retained.thumbnailRelativePath,
            thumbnailByteCount: retained.thumbnailByteCount,
            thumbnailSHA256: retained.thumbnailSHA256
        )
        do {
            try await store.reconcile(authorities: [mismatch])
            XCTFail("Expected exact media authority mismatch")
        } catch {
            XCTAssertEqual(error as? EvidenceBundleStoreError, .bundleFactsMismatch)
        }
        XCTAssertTrue(fileManager.fileExists(atPath:
            session.generationRootURL.appendingPathComponent(retained.originalRelativePath).path
        ))
        withExtendedLifetime(session) {}
    }

    @MainActor
    func testRelaunchAfterWideKeepsExactEvidenceAuthorityAndResumesClose() async throws {
        let applicationSupportURL = try makeTemporaryDirectory("Relaunch")
        defer { try? fileManager.removeItem(at: applicationSupportURL) }
        let factory = StoreGenerationFactory(applicationSupportURL: applicationSupportURL)
        let retainedPNG = try makePNG(seed: 91)
        var capturedAssetID: UUID?
        var capturedEvidenceID: UUID?
        var originalPath = ""
        var thumbnailPath = ""
        var originalHash = ""
        var thumbnailHash = ""

        do {
            let session = try factory.openOrBootstrapCurrent()
            let context = session.modelContext
            let pack = SignPack.illuminatedSignV1
            let site = Site(label: "North Campus", timeZoneID: "America/New_York")
            let asset = Asset(
                siteID: site.id, packID: pack.packID,
                packSchemaVersion: pack.schemaVersion,
                packContentVersion: pack.contentVersion, label: "Monument Sign"
            )
            context.insert(site); context.insert(asset); try context.save()
            capturedAssetID = asset.id
            let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
            coordinator.configureCapture(generationRootURL: session.generationRootURL)
            _ = try coordinator.beginCheck(
                assetID: asset.id, timeZoneID: nil, isTimeZoneConfirmed: false,
                afterDarkAccepted: true, safePositionAccepted: true,
                observedAt: Date(timeIntervalSince1970: 1_768_438_923)
            )
            let candidate = try await coordinator.importCandidate(
                assetID: asset.id, sourceData: retainedPNG,
                createdAt: Date(timeIntervalSince1970: 1_768_438_924)
            )
            let evidence = try await coordinator.accept(candidate: candidate, assetID: asset.id)
            capturedEvidenceID = evidence.id
            originalPath = evidence.relativePath
            thumbnailPath = evidence.thumbnailRelativePath
            originalHash = evidence.sha256
            thumbnailHash = evidence.thumbnailSHA256
            withExtendedLifetime(session) {}
        }

        do {
            let assetID = try XCTUnwrap(capturedAssetID)
            let evidenceID = try XCTUnwrap(capturedEvidenceID)
            let reopened = try factory.openOrBootstrapCurrent()
            let context = reopened.modelContext
            let evidence = try XCTUnwrap(
                context.fetch(FetchDescriptor<EvidenceFile>()).first
            )
            XCTAssertEqual(evidence.id, evidenceID)
            XCTAssertEqual(evidence.relativePath, originalPath)
            XCTAssertEqual(evidence.thumbnailRelativePath, thumbnailPath)
            XCTAssertEqual(evidence.sha256, originalHash)
            XCTAssertEqual(evidence.thumbnailSHA256, thumbnailHash)
            let coordinator = CheckRunnerCoordinator(
                modelContext: context,
                signPack: .illuminatedSignV1
            )
            coordinator.configureCapture(generationRootURL: reopened.generationRootURL)
            let preparation = try coordinator.prepareCapture(assetID: assetID)
            XCTAssertEqual(preparation.step, .close)
            XCTAssertEqual(preparation.purpose?.key, "close_detail")
            XCTAssertEqual(
                try Data(contentsOf: reopened.generationRootURL.appendingPathComponent(originalPath)),
                try Data(contentsOf: reopened.generationRootURL.appendingPathComponent(evidence.relativePath))
            )
            withExtendedLifetime(reopened) {}
        }
    }

    @MainActor
    private func seedRecoveryCase(
        _ matrixCase: RecoveryMatrixCase,
        applicationSupportURL: URL,
        visibleIssueCase: VisibleIssueRecoveryCase? = nil
    ) async throws -> SeededRecovery {
        let session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let context = session.modelContext
        let site = Site(label: "North Campus", timeZoneID: "America/New_York")
        let asset = Asset(
            siteID: site.id,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Monument Sign"
        )
        let draft = makeDraft(assetID: asset.id)
        context.insert(site)
        context.insert(asset)
        context.insert(draft)
        let evidence = try await makeEvidenceAuthority(
            recordID: draft.id,
            context: context,
            generationRootURL: session.generationRootURL
        )
        try context.save()
        let packetID = UUID()
        let reportID = UUID()
        let stableRootID = UUID()
        let snapshotCreatedAt = Date(timeIntervalSince1970: 1_768_438_926)
        let issuePayload: IssuePayloadV1? = visibleIssueCase.map { issueCase in
            IssuePayloadV1(
                id: UUID(),
                schemaVersion: 1,
                assetID: issueCase == .wrongAsset ? UUID() : asset.id,
                openedByRecordID: draft.id,
                labelKey: "face_out",
                labelDisplaySnapshot: "Face out",
                status: IssueStatus.open.rawValue,
                resolvedByRecordID: nil,
                createdAt: snapshotCreatedAt,
                updatedAt: issueCase == .wrongTime
                    ? snapshotCreatedAt.addingTimeInterval(1)
                    : snapshotCreatedAt
            )
        }
        let issueSnapshots = issuePayload.map { issue in
            [IssueSnapshotV1(
                createdAt: issue.createdAt,
                display: issue.labelDisplaySnapshot,
                issueID: issue.id,
                key: issue.labelKey,
                openedByRecordID: issue.openedByRecordID,
                resolvedByRecordID: issue.resolvedByRecordID,
                status: issue.status,
                updatedAt: issue.updatedAt
            )]
        } ?? []
        let encodedSnapshot = try ReportSnapshotEncoderV1().encode(
            makeSnapshot(
                recordID: draft.id,
                packetID: packetID,
                reportID: reportID,
                stableRootID: stableRootID,
                snapshotCreatedAt: snapshotCreatedAt,
                evidence: evidence,
                issues: issueSnapshots,
                isVisibleIssue: issuePayload != nil
            )
        )
        let intent = try makeIntent(
            draft: draft,
            generationID: session.generationID,
            snapshot: encodedSnapshot,
            packetID: packetID,
            reportID: reportID,
            stableRootID: stableRootID,
            snapshotCreatedAt: snapshotCreatedAt,
            issueInsert: issuePayload
        )
        let store = FinalizationIntentStore(generationRootURL: session.generationRootURL)
        let prepared = try await store.prepare(intent: intent, snapshot: encodedSnapshot)
        var promoted: PromotedFinalization?

        switch matrixCase.phase {
        case .prepared:
            break
        case .snapshotPromoted, .databaseCommitted:
            let value = try await store.promoteSnapshot(prepared)
            promoted = try await store.advance(value, to: .snapshotPromoted)
        }

        let finalURL = session.generationRootURL.appendingPathComponent(
            intent.snapshotFinalRelativePath
        )
        let stagingURL = session.generationRootURL.appendingPathComponent(
            intent.snapshotStagingRelativePath
        )
        if matrixCase.phase == .prepared {
            if matrixCase.hasFinal {
                try fileManager.createDirectory(
                    at: finalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: false
                )
                try encodedSnapshot.data.write(to: finalURL)
            }
            if !matrixCase.hasStaging {
                try fileManager.removeItem(at: stagingURL)
            }
        } else {
            if !matrixCase.hasFinal && matrixCase.phase == .snapshotPromoted {
                try fileManager.removeItem(at: finalURL)
            }
            if matrixCase.hasStaging {
                try fileManager.createDirectory(
                    at: stagingURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try encodedSnapshot.data.write(to: stagingURL)
            }
        }

        if matrixCase.hasMatchingRows {
            try applyCommittedRows(intent.finalizationPayload, context: context)
        } else if matrixCase.hasPartialRows {
            let packet = intent.finalizationPayload.packetAfter
            context.insert(Packet(
                id: packet.id, stableRootID: packet.stableRootID,
                currentRecordID: packet.currentRecordID,
                evaluationCounted: packet.evaluationCounted,
                contentDeletedAt: packet.contentDeletedAt,
                createdAt: packet.createdAt
            ))
            try context.save()
        } else if matrixCase.hasFailedPrecondition {
            draft.note = "changed after intent freeze"
            try context.save()
        }
        if matrixCase.phase == .databaseCommitted {
            let value = try XCTUnwrap(promoted)
            _ = try await store.advance(value, to: .databaseCommitted)
            if !matrixCase.hasFinal {
                try fileManager.removeItem(at: finalURL)
            }
        }
        if matrixCase.corruptFinal {
            try Data("mismatch".utf8).write(to: finalURL, options: .atomic)
        }
        if matrixCase.corruptStaging {
            try Data("mismatch".utf8).write(to: stagingURL, options: .atomic)
        }

        let intentURL = applicationSupportURL.appendingPathComponent(
            "FieldEvidenceOperations/finalization/\(intent.finalizationMutationID.uuidString.lowercased()).json"
        )
        return SeededRecovery(
            session: session,
            intent: intent,
            intentURL: intentURL,
            stagingSnapshotURL: stagingURL,
            finalSnapshotURL: finalURL
        )
    }

    @MainActor
    private func applyCommittedRows(
        _ payload: FinalizationPayloadV1,
        context: ModelContext
    ) throws {
        let records = try context.fetch(FetchDescriptor<WorkflowRecord>())
        let record = try XCTUnwrap(records.first { $0.id == payload.workflowRecordAfter.id })
        let value = payload.workflowRecordAfter
        record.packetID = value.packetID
        record.issueID = value.issueID
        record.state = value.state
        record.draftStepKey = value.draftStepKey
        record.completedAt = value.completedAt
        record.outcomeKey = value.outcomeKey
        record.finalizationMutationID = value.finalizationMutationID
        let packet = payload.packetAfter
        context.insert(Packet(
            id: packet.id, stableRootID: packet.stableRootID,
            currentRecordID: packet.currentRecordID,
            evaluationCounted: packet.evaluationCounted,
            contentDeletedAt: packet.contentDeletedAt,
            createdAt: packet.createdAt
        ))
        let report = try XCTUnwrap(payload.reportInsert)
        context.insert(Report(
            id: report.id, packetID: report.packetID,
            sourceRecordID: report.sourceRecordID,
            snapshotSchemaVersion: report.snapshotSchemaVersion,
            snapshotRelativePath: report.snapshotRelativePath,
            snapshotSHA256: report.snapshotSHA256,
            pdfState: try XCTUnwrap(ReportPDFState(rawValue: report.pdfState)),
            pdfRelativePath: report.pdfRelativePath, pdfSHA256: report.pdfSHA256,
            createdAt: report.createdAt, replacesReportID: report.replacesReportID
        ))
        try context.save()
    }

    @MainActor
    private func makeCurrentV2Producer(
        _ label: String,
        failure: FinalizationIntentStoreFailurePoint
    ) async throws -> CurrentV2ProducerHarness {
        let applicationSupportURL = try makeTemporaryDirectory(label)
        let session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let context = session.modelContext
        let storeCoordinator = try StoreSessionCoordinator(validatingSession: session)
        let pack = SignPack.illuminatedSignV1
        let siteID = UUID()
        let assetID = UUID()
        let placementMutationID = try MutationIDV1(rawValue: UUID())
        do {
            _ = try storeCoordinator.workspaceWriter.execute(
                .createFirstSign(.init(
                    siteID: siteID,
                    newSite: .init(
                        id: siteID,
                        label: "North Campus",
                        address: "10 Main",
                        timeZoneID: "America/New_York"
                    ),
                    assetID: assetID,
                    assetLabel: "Monument Sign",
                    packID: pack.packID,
                    packSchemaVersion: pack.schemaVersion,
                    packContentVersion: pack.contentVersion,
                    createdAt: Date(timeIntervalSince1970: 1_768_450_000),
                    initialPlacementMutationID: placementMutationID,
                    initialPlacementEventID: UUID(),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
                )),
                mutationID: placementMutationID
            )
            let asset = try XCTUnwrap(
                context.fetch(FetchDescriptor<Asset>()).first { $0.id == assetID }
            )
            let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
                package: pack
            )
            let dependencies = try storeCoordinator.packageLifecycleDependencies(
                profileRegistry: WorkspacePackageLifecycleProfileRegistryV1(
                    profiles: [profile]
                )
            )
            let failureInjection = FinalizationIntentStoreFailureInjection(
                failOnceAt: failure
            )
            let runner = try CheckRunnerCoordinator(
                modelContext: context,
                packageLifecycleDependencies: dependencies,
                packageLifecycleProfile: profile,
                finalizationStoreFailureInjection: failureInjection
            )
            runner.configureCapture(generationRootURL: session.generationRootURL)
            let observedAt = Date(timeIntervalSince1970: 1_768_450_010)
            let draft = try runner.beginCheck(
                assetID: asset.id,
                timeZoneID: nil,
                isTimeZoneConfirmed: false,
                afterDarkAccepted: true,
                safePositionAccepted: true,
                observedAt: observedAt
            )
            let wide = try await runner.importCandidate(
                assetID: asset.id,
                sourceData: try makePNG(seed: 43),
                createdAt: observedAt.addingTimeInterval(1)
            )
            _ = try await runner.accept(candidate: wide, assetID: asset.id)
            let close = try await runner.importCandidate(
                assetID: asset.id,
                sourceData: try makePNG(seed: 83),
                createdAt: observedAt.addingTimeInterval(2)
            )
            _ = try await runner.accept(candidate: close, assetID: asset.id)
            return CurrentV2ProducerHarness(
                applicationSupportURL: applicationSupportURL,
                session: session,
                storeCoordinator: storeCoordinator,
                context: context,
                runner: runner,
                asset: asset,
                draftID: draft.id,
                observedAt: observedAt
            )
        } catch {
            try? storeCoordinator.invalidateAndReleaseWriter()
            try? fileManager.removeItem(at: applicationSupportURL)
            throw error
        }
    }

    @MainActor
    private func makeEvidenceAuthority(
        recordID: UUID,
        context: ModelContext,
        generationRootURL: URL
    ) async throws -> [EvidenceSnapshotV1] {
        let normalized = try MediaNormalizerV1().normalize(makePNG(seed: 113))
        let store = EvidenceBundleStore(generationRootURL: generationRootURL)
        let purposes = [
            ("wide_context", "Wide view", Date(timeIntervalSince1970: 1_768_438_924)),
            ("close_detail", "Close view", Date(timeIntervalSince1970: 1_768_438_925)),
        ]
        var snapshots: [EvidenceSnapshotV1] = []
        for (key, display, createdAt) in purposes {
            let evidenceID = UUID()
            let staged = try await store.stage(evidenceID: evidenceID, normalized: normalized)
            let promoted = try await store.promote(staged)
            let row = EvidenceFile(
                id: evidenceID,
                recordID: recordID,
                purposeKey: key,
                relativePath: promoted.originalRelativePath,
                mimeType: MediaContractV1.durableMIMEType,
                byteCount: promoted.originalByteCount,
                sha256: promoted.originalSHA256,
                createdAt: createdAt,
                thumbnailRelativePath: promoted.thumbnailRelativePath,
                thumbnailByteCount: promoted.thumbnailByteCount,
                thumbnailSHA256: promoted.thumbnailSHA256
            )
            context.insert(row)
            snapshots.append(EvidenceSnapshotV1(
                byteCount: row.byteCount,
                createdAt: row.createdAt,
                evidenceID: row.id,
                mimeType: row.mimeType,
                purposeDisplay: display,
                purposeKey: row.purposeKey,
                recordID: row.recordID,
                relativePath: row.relativePath,
                sha256: row.sha256,
                thumbnailByteCount: row.thumbnailByteCount,
                thumbnailRelativePath: row.thumbnailRelativePath,
                thumbnailSHA256: row.thumbnailSHA256
            ))
        }
        return snapshots
    }

    private func makeDraft(assetID: UUID = UUID()) -> WorkflowRecord {
        let id = UUID()
        return WorkflowRecord(
            id: id, assetID: assetID, packetID: nil, issueID: nil,
            parentRecordID: nil, recordRevisionRootID: id,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: .original, stage: .check, state: .draft,
            draftStepKey: .outcome,
            startedAt: Date(timeIntervalSince1970: 1_768_438_923),
            completedAt: nil,
            observedAtUTC: Date(timeIntervalSince1970: 1_768_438_923),
            timeZoneID: "America/New_York", utcOffsetMinutes: -300,
            localDate: "2026-01-14", localTime: "15:02:03",
            afterDarkAcknowledgementKey: "after_dark",
            afterDarkAcknowledgementCopy: "After dark", afterDarkAcknowledgementVersion: "v1",
            afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: "safe_authorized_position",
            safePositionAcknowledgementCopy: "Safe position",
            safePositionAcknowledgementVersion: "v1",
            safePositionAcknowledgementAccepted: true,
            packID: "field.evidence.illuminated_sign.v1",
            packSchemaVersion: 1, packContentVersion: 1,
            pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1,
            outcomeKey: nil, couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil, note: nil,
            finalizationMutationID: nil
        )
    }

    private func makeIntent(
        draft: WorkflowRecord,
        generationID: UUID,
        snapshot: EncodedReportSnapshotV1,
        packetID: UUID,
        reportID: UUID,
        stableRootID: UUID,
        snapshotCreatedAt: Date,
        issueInsert: IssuePayloadV1?
    ) throws -> FinalizationIntentV1 {
        let completedAt = snapshotCreatedAt
        let mutationID = UUID()
        let record = WorkflowRecordPayloadV1(
            id: draft.id, schemaVersion: 1, assetID: draft.assetID,
            packetID: packetID, issueID: issueInsert?.id, parentRecordID: nil,
            recordRevisionRootID: draft.recordRevisionRootID,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: draft.revisionKind, stage: draft.stage,
            state: WorkflowState.completed.rawValue, draftStepKey: nil,
            startedAt: draft.startedAt, completedAt: completedAt,
            observedAtUTC: draft.observedAtUTC, timeZoneID: draft.timeZoneID,
            utcOffsetMinutes: draft.utcOffsetMinutes, localDate: draft.localDate,
            localTime: draft.localTime,
            afterDarkAcknowledgementKey: draft.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: draft.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: draft.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: draft.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: draft.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: draft.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: draft.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: draft.safePositionAcknowledgementAccepted,
            packID: draft.packID, packSchemaVersion: draft.packSchemaVersion,
            packContentVersion: draft.packContentVersion,
            pdfTemplateID: draft.pdfTemplateID,
            pdfTemplateVersion: draft.pdfTemplateVersion,
            outcomeKey: issueInsert == nil ? "no_visible_issue" : "visible_issue",
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil, note: nil,
            finalizationMutationID: mutationID
        )
        let snapshotPath = "snapshots/\(reportID.uuidString.lowercased()).json"
        let packet = PacketPayloadV1(
            id: packetID, schemaVersion: 1, stableRootID: stableRootID,
            currentRecordID: draft.id, evaluationCounted: true,
            contentDeletedAt: nil, createdAt: completedAt
        )
        let report = ReportPayloadV1(
            id: reportID, schemaVersion: 1, packetID: packetID,
            sourceRecordID: draft.id, snapshotSchemaVersion: 1,
            snapshotRelativePath: snapshotPath, snapshotSHA256: snapshot.sha256,
            pdfState: ReportPDFState.pending.rawValue,
            pdfRelativePath: nil, pdfSHA256: nil,
            createdAt: completedAt, replacesReportID: nil
        )
        let payload = FinalizationPayloadV1(
            issueInsert: issueInsert, issueTransition: nil,
            packetAfter: packet, packetBefore: nil,
            reportInsert: report, workflowRecordAfter: record
        )
        let payloadHash = try FinalizationContractEncoderV1().encodePayload(payload).sha256
        return FinalizationIntentV1(
            completedAt: completedAt, finalizationMutationID: mutationID,
            finalizationPayload: payload, finalizationPayloadSHA256: payloadHash,
            generationID: generationID, packetID: packetID, phase: .prepared,
            recordID: draft.id, reportID: reportID, schemaVersion: 1,
            snapshotCreatedAt: snapshotCreatedAt,
            snapshotFinalRelativePath: snapshotPath,
            snapshotSHA256: snapshot.sha256,
            snapshotStagingRelativePath: ".staging/\(snapshotPath)",
            stableRootID: stableRootID
        )
    }

    private func intentByReplacingMutationID(
        _ intent: FinalizationIntentV1,
        with mutationID: UUID
    ) throws -> FinalizationIntentV1 {
        try rebuiltIntent(
            intent,
            mutationID: mutationID,
            parentRecordID: intent.finalizationPayload.workflowRecordAfter.parentRecordID
        )
    }

    private func rebuiltIntent(
        _ intent: FinalizationIntentV1,
        mutationID: UUID,
        parentRecordID: UUID?
    ) throws -> FinalizationIntentV1 {
        let old = intent.finalizationPayload.workflowRecordAfter
        let record = WorkflowRecordPayloadV1(
            id: old.id,
            schemaVersion: old.schemaVersion,
            assetID: old.assetID,
            packetID: old.packetID,
            issueID: old.issueID,
            parentRecordID: parentRecordID,
            recordRevisionRootID: old.recordRevisionRootID,
            revisesRecordID: old.revisesRecordID,
            evidenceSourceRecordID: old.evidenceSourceRecordID,
            revisionKind: old.revisionKind,
            stage: old.stage,
            state: old.state,
            draftStepKey: old.draftStepKey,
            startedAt: old.startedAt,
            completedAt: old.completedAt,
            observedAtUTC: old.observedAtUTC,
            timeZoneID: old.timeZoneID,
            utcOffsetMinutes: old.utcOffsetMinutes,
            localDate: old.localDate,
            localTime: old.localTime,
            afterDarkAcknowledgementKey: old.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: old.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: old.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: old.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: old.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: old.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: old.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: old.safePositionAcknowledgementAccepted,
            packID: old.packID,
            packSchemaVersion: old.packSchemaVersion,
            packContentVersion: old.packContentVersion,
            pdfTemplateID: old.pdfTemplateID,
            pdfTemplateVersion: old.pdfTemplateVersion,
            outcomeKey: old.outcomeKey,
            couldNotVerifyKey: old.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: old.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: old.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: old.workPerformedLocalDate,
            workDescription: old.workDescription,
            note: old.note,
            finalizationMutationID: mutationID
        )
        let oldPayload = intent.finalizationPayload
        let payload = FinalizationPayloadV1(
            issueInsert: oldPayload.issueInsert,
            issueTransition: oldPayload.issueTransition,
            packetAfter: oldPayload.packetAfter,
            packetBefore: oldPayload.packetBefore,
            reportInsert: oldPayload.reportInsert,
            workflowRecordAfter: record
        )
        let payloadHash = try FinalizationContractEncoderV1()
            .encodePayload(payload).sha256
        return FinalizationIntentV1(
            completedAt: intent.completedAt,
            finalizationMutationID: mutationID,
            finalizationPayload: payload,
            finalizationPayloadSHA256: payloadHash,
            generationID: intent.generationID,
            packetID: intent.packetID,
            phase: intent.phase,
            recordID: intent.recordID,
            reportID: intent.reportID,
            schemaVersion: intent.schemaVersion,
            snapshotCreatedAt: intent.snapshotCreatedAt,
            snapshotFinalRelativePath: intent.snapshotFinalRelativePath,
            snapshotSHA256: intent.snapshotSHA256,
            snapshotStagingRelativePath: intent.snapshotStagingRelativePath,
            stableRootID: intent.stableRootID
        )
    }

    private func makeSnapshot(
        recordID: UUID,
        packetID: UUID,
        reportID: UUID,
        stableRootID: UUID,
        snapshotCreatedAt: Date,
        evidence: [EvidenceSnapshotV1],
        issues: [IssueSnapshotV1],
        isVisibleIssue: Bool
    ) -> ReportSnapshotV1 {
        ReportSnapshotV1(
            acknowledgements: [
                AcknowledgementSnapshotV1(accepted: true, copy: "After dark", key: "after_dark", version: "v1"),
                AcknowledgementSnapshotV1(accepted: true, copy: "Safe position", key: "safe_authorized_position", version: "v1"),
            ],
            asset: AssetSnapshotV1(label: "Monument Sign"), couldNotVerify: nil,
            disclaimer: "Visible evidence only.",
            display: DisplaySnapshotV1(assetSingular: "sign", checkSingular: "check", issueSingular: "visible issue", outcome: isVisibleIssue ? "Visible issue" : "No visible issue", stage: "Check"),
            evidence: evidence, evidenceSourceRecordID: recordID, history: [], issues: issues,
            note: nil, outcome: isVisibleIssue ? "visible_issue" : "no_visible_issue",
            pack: PackSnapshotV1(contentVersion: 1, id: "field.evidence.illuminated_sign.v1", schemaVersion: 1),
            packetID: packetID,
            pdfTemplate: PDFTemplateReferenceV1(id: "field.evidence.pdf.worklight.v1", version: 1),
            reportID: reportID, site: SiteSnapshotV1(address: nil, label: "North Campus"),
            snapshotCreatedAt: snapshotCreatedAt,
            snapshotSchemaVersion: 1,
            sourceApp: SourceAppSnapshotV1(build: "34", version: "1.0"),
            sourceRecordID: recordID, stableRootID: stableRootID, stage: "check",
            timeContext: TimeContextSnapshotV1(localDate: "2026-01-14", localTime: "15:02:03", observedAtUTC: Date(timeIntervalSince1970: 1_768_438_923), timeZoneID: "America/New_York", utcOffsetMinutes: -300)
        )
    }

    private func makeTemporaryDirectory(_ name: String) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S3_4ResumeRecoveryTests-\(name)-\(UUID().uuidString)", isDirectory: true
        )
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makePNG(seed: UInt8) throws -> Data {
        let width = 32, height = 24
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = seed; pixels[index + 1] = UInt8(index % 251)
            pixels[index + 2] = UInt8((index / 4) % 251); pixels[index + 3] = 255
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { throw ResumeFixtureError.image }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw ResumeFixtureError.image }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ResumeFixtureError.image }
        return output as Data
    }
}

private enum RecoveryMatrixCase: String, CaseIterable {
    case preparedStageOnly
    case preparedFinalOnly
    case preparedBothIdentical
    case preparedNeither
    case preparedBothMismatch
    case preparedNeitherWithRows
    case snapshotPromotedFinal
    case snapshotPromotedFinalAndStage
    case snapshotPromotedCrashAfterSave
    case snapshotPromotedMissingFinal
    case snapshotPromotedPartialRows
    case snapshotPromotedPreconditionFailed
    case databaseCommittedFinal
    case databaseCommittedFinalAndStage
    case databaseCommittedMissingFinal
    case databaseCommittedMissingRows
    case databaseCommittedStageMismatch
    case snapshotPromotedCorruptFinal

    var phase: FinalizationPhaseV1 {
        switch self {
        case .preparedStageOnly, .preparedFinalOnly, .preparedBothIdentical,
             .preparedNeither, .preparedBothMismatch, .preparedNeitherWithRows:
            .prepared
        case .databaseCommittedFinal, .databaseCommittedFinalAndStage,
             .databaseCommittedMissingFinal, .databaseCommittedMissingRows,
             .databaseCommittedStageMismatch:
            .databaseCommitted
        default:
            .snapshotPromoted
        }
    }

    var hasStaging: Bool {
        self == .preparedStageOnly || self == .preparedBothIdentical
            || self == .preparedBothMismatch
            || self == .snapshotPromotedFinalAndStage
            || self == .databaseCommittedFinalAndStage
            || self == .databaseCommittedStageMismatch
    }

    var hasFinal: Bool {
        self != .preparedStageOnly && self != .preparedNeither
            && self != .preparedNeitherWithRows
            && self != .snapshotPromotedMissingFinal
            && self != .databaseCommittedMissingFinal
    }
    var hasMatchingRows: Bool {
        self == .preparedNeitherWithRows
            || self == .snapshotPromotedCrashAfterSave
            || self == .databaseCommittedFinal
            || self == .databaseCommittedFinalAndStage
            || self == .databaseCommittedMissingFinal
            || self == .databaseCommittedStageMismatch
    }
    var hasPartialRows: Bool { self == .snapshotPromotedPartialRows }
    var hasFailedPrecondition: Bool { self == .snapshotPromotedPreconditionFailed }
    var corruptFinal: Bool {
        self == .preparedBothMismatch || self == .snapshotPromotedCorruptFinal
    }
    var corruptStaging: Bool { self == .databaseCommittedStageMismatch }
    var expectsDraft: Bool {
        self == .preparedNeither || self == .snapshotPromotedPreconditionFailed
    }
    var expectsMaintenance: Bool {
        corruptFinal || corruptStaging || self == .preparedNeitherWithRows
            || self == .snapshotPromotedMissingFinal
            || self == .snapshotPromotedPartialRows
            || self == .databaseCommittedMissingFinal
            || self == .databaseCommittedMissingRows
    }
}

private enum RecoveryFailureCase: String, CaseIterable {
    case noncanonicalIntent
    case snapshotEvidenceMismatch
    case originalShapeMismatch
    case crossIntentCollision
}

private enum VisibleIssueRecoveryCase: String, CaseIterable {
    case valid
    case wrongAsset
    case wrongTime
}

@MainActor
@MainActor
private struct CurrentV2ProducerHarness {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let storeCoordinator: StoreSessionCoordinator
    let context: ModelContext
    let runner: CheckRunnerCoordinator
    let asset: Asset
    let draftID: UUID
    let observedAt: Date
}

private struct SeededRecovery {
    let session: StoreGenerationSession
    let intent: FinalizationIntentV1
    let intentURL: URL
    let stagingSnapshotURL: URL
    let finalSnapshotURL: URL
}

private enum ResumeFixtureError: Error { case image }

extension S3_4ResumeRecoveryTests {
    func testC36RestorePublicationReceiptRequiresCanonicalDisjointStageOrder() throws {
        let ids = (1...4).map {
            UUID(uuidString: "20000000-0000-0000-0000-00000000000\($0)")!
        }
        func receipt(_ adopted: [UUID], _ reused: [UUID]) throws -> DraftAttachmentRestorePublicationReceiptV1 {
            try DraftAttachmentRestorePublicationReceiptV1(
                restoreID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                workspaceID: WorkspaceID(rawValue: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!),
                sourceManifestSHA256: String(repeating: "c", count: 64),
                adoptedStageIDs: adopted,
                reusedStageIDs: reused,
                publishedAt: Date(timeIntervalSince1970: 2)
            )
        }
        let valid = try receipt([ids[0], ids[2]], [ids[1], ids[3]])
        try valid.validate()
        XCTAssertEqual(valid.adoptedStageIDs, [ids[0], ids[2]])
        XCTAssertEqual(valid.reusedStageIDs, [ids[1], ids[3]])
        XCTAssertFalse(valid.atomicAcrossRoots)
        XCTAssertTrue(valid.canonicalCommitRequired)
        XCTAssertThrowsError(try receipt([ids[2], ids[0]], [ids[1], ids[3]]))
        XCTAssertThrowsError(try receipt([ids[0], ids[2]], [ids[3], ids[1]]))
        XCTAssertThrowsError(try receipt([ids[0], ids[0]], []))
        XCTAssertThrowsError(try receipt([], [ids[1], ids[1]]))
        XCTAssertThrowsError(try receipt([ids[0]], [ids[0]]))
    }

    func testC36AttachmentProcessingJobResumesFromDurableCheckpoint() throws {
        let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!)
        let draftID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let stageID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        let request = try DraftAttachmentJobRequestV1(
            workspaceID: workspaceID,
            draftID: draftID,
            stageID: stageID,
            stageSHA256: String(repeating: "b", count: 64),
            stagingRelativePath: "draft-(draftID.uuidString.lowercased())/stage-(stageID.uuidString.lowercased())/payload.bin",
            totalUnitCount: 3,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let job = try ResumableLocalJobV1.draftAttachmentProcessing(request)

        try job.validate()
        XCTAssertTrue(job.isDraftAttachmentProcessing)
        XCTAssertEqual(job.checkpoint.completedUnitCount, 0)
        XCTAssertEqual(job.checkpoint.totalUnitCount, 3)

        let restoreReceipt = try DraftAttachmentRestorePublicationReceiptV1(
            restoreID: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!,
            workspaceID: workspaceID,
            sourceManifestSHA256: String(repeating: "c", count: 64),
            adoptedStageIDs: [stageID],
            reusedStageIDs: [],
            publishedAt: Date(timeIntervalSince1970: 2)
        )
        try restoreReceipt.validate()
        XCTAssertFalse(restoreReceipt.atomicAcrossRoots)
        XCTAssertTrue(restoreReceipt.canonicalCommitRequired)
    }
}

extension S3_4ResumeRecoveryTests {
    func testV23P03C34IncompleteRecoveryPrecedesExplicitIngressWithoutWriter() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x03)))
        let recovery = try NavigationTargetV1(workspaceID: workspace, destination: .mutationRecovery, requestedMode: .resume)
        let ingress = try NavigationTargetV1(workspaceID: workspace, destination: .reports)
        let receipt = try RouteCoordinatorV1(registry: try RouteRegistryV1()).restore(.init(
            context: .init(currentWorkspaceID: workspace, currentRevision: 0),
            startupMaintenanceTarget: nil,
            incompleteMutationRecoveryTarget: recovery,
            explicitIngressTarget: ingress,
            sceneSnapshot: nil,
            discardedSnapshotReason: nil,
            evidenceKind: .alternate,
            receiptID: UUID()
        ))
        XCTAssertEqual(receipt.source, .incompleteMutationRecovery)
        XCTAssertEqual(receipt.result.target.destination, .mutationRecovery)
        XCTAssertEqual(receipt.canonicalMutationCount, 0)
        XCTAssertFalse(receipt.startsAutomaticWork)
    }
}

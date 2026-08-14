import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S6_1DeletionGraphTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testDeletesClosedGraphKeepsCountedTombstoneAndUnrelatedBytes() async throws {
        let harness = try makeHarness(counted: true, uncounted: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let retained = harness.generationRootURL.appendingPathComponent("unrelated.bin")
        let retainedBytes = Data("retained".utf8)
        try retainedBytes.write(to: retained)

        let result = try await harness.service.delete(assetID: harness.assetID)

        XCTAssertEqual(result.countedTombstoneCount, 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Site>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)
        let packets = try harness.context.fetch(FetchDescriptor<Packet>())
        XCTAssertEqual(packets.count, 1)
        XCTAssertTrue(packets[0].evaluationCounted)
        XCTAssertNil(packets[0].currentRecordID)
        XCTAssertNotNil(packets[0].contentDeletedAt)
        XCTAssertEqual(try Data(contentsOf: retained), retainedBytes)
    }

    @MainActor
    func testDirtyContextAndInjectedSaveRollbackRestoreHeldPacket() async throws {
        let harness = try makeHarness(counted: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
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
        XCTAssertEqual(try deletionJournalNames(harness), [])
    }

    @MainActor
    func testPreparedCancelsAndPostCommitRecoversWhileMismatchFailsClosed() async throws {
        let prepared = try makeHarness(counted: true)
        defer { try? fileManager.removeItem(at: prepared.applicationSupportURL) }
        let before = WholeSignDeletionService(
            modelContext: prepared.context,
            generationRootURL: prepared.generationRootURL,
            failureInjection: WholeSignDeletionFailureInjection(failOnceAt: .preparedJournal)
        )
        await assertThrows(.injectedFailure) {
            _ = try await before.delete(assetID: prepared.assetID)
        }
        let cancelled = try await prepared.service.reconcile()
        XCTAssertEqual(cancelled.cancelledPreparedCount, 1)
        XCTAssertEqual(try prepared.context.fetchCount(FetchDescriptor<Asset>()), 1)

        let committed = try makeHarness(counted: true)
        defer { try? fileManager.removeItem(at: committed.applicationSupportURL) }
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
        defer { try? fileManager.removeItem(at: phasePair.applicationSupportURL) }
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
        defer { try? fileManager.removeItem(at: mismatch.applicationSupportURL) }
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
    func testDeepEvidenceSnapshotAndPDFAuthorityFailBeforeMutation() async throws {
        let evidence = try makeHarness(counted: true, evidenceBytes: Data("not-jpeg".utf8))
        defer { try? fileManager.removeItem(at: evidence.applicationSupportURL) }
        await assertThrows(.fileInvalid) {
            _ = try await evidence.service.delete(assetID: evidence.assetID)
        }
        XCTAssertEqual(try evidence.context.fetchCount(FetchDescriptor<Asset>()), 1)

        let snapshot = try makeHarness(
            counted: true,
            report: .pending(snapshot: Data("not-canonical-json".utf8))
        )
        defer { try? fileManager.removeItem(at: snapshot.applicationSupportURL) }
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
        defer { try? fileManager.removeItem(at: pdf.applicationSupportURL) }
        await assertThrows(.fileInvalid) {
            _ = try await pdf.service.delete(assetID: pdf.assetID)
        }
        XCTAssertEqual(try pdf.context.fetchCount(FetchDescriptor<Asset>()), 1)
    }

    @MainActor
    func testMalformedJournalAndPinnedAncestorReplacementEnterClosedFailure() async throws {
        let malformed = try makeHarness(counted: false)
        defer { try? fileManager.removeItem(at: malformed.applicationSupportURL) }
        let journal = deletionJournalURL(malformed)
        try Data("{}".utf8).write(
            to: journal.appendingPathComponent("00000000-0000-0000-0000-000000000001.json")
        )
        await assertThrows(.journalInvalid) {
            _ = try await malformed.service.reconcile()
        }
        XCTAssertEqual(try malformed.context.fetchCount(FetchDescriptor<Asset>()), 1)

        let replaced = try makeHarness(counted: false)
        defer { try? fileManager.removeItem(at: replaced.applicationSupportURL) }
        let operations = replaced.applicationSupportURL
            .appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
        let original = replaced.applicationSupportURL
            .appendingPathComponent("FieldEvidenceOperations.pinned", isDirectory: true)
        try fileManager.moveItem(at: operations, to: original)
        try fileManager.createSymbolicLink(at: operations, withDestinationURL: original)
        await assertThrows(.invalidGeneration) {
            _ = try await replaced.service.reconcile()
        }
        XCTAssertEqual(try replaced.context.fetchCount(FetchDescriptor<Asset>()), 1)
    }
}

private extension S6_1DeletionGraphTests {
    enum ReportFixture {
        case pending(snapshot: Data)
        case ready(snapshot: Data, pdf: Data)
    }

    struct Harness {
        let applicationSupportURL: URL
        let generationRootURL: URL
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
        let applicationSupportURL = fileManager.temporaryDirectory.appendingPathComponent(
            "s6-1-\(UUID().uuidString)", isDirectory: true
        )
        let generationID = UUID()
        let generationRootURL = applicationSupportURL
            .appendingPathComponent("FieldEvidenceData/generations", isDirectory: true)
            .appendingPathComponent(generationID.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(at: generationRootURL, withIntermediateDirectories: true)
        let schema = Schema([
            Site.self, Asset.self, WorkflowRecord.self, EvidenceFile.self,
            Issue.self, Packet.self, Report.self,
        ], version: Schema.Version(1, 0, 0))
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "S6_1", schema: schema,
                url: generationRootURL.appendingPathComponent("model.sqlite"),
                allowsSave: true, cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let site = Site(label: "Site")
        let asset = Asset(
            siteID: site.id, packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: 1, packContentVersion: 1, label: "Sign"
        )
        context.insert(site)
        context.insert(asset)

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
        try context.save()
        return Harness(
            applicationSupportURL: applicationSupportURL,
            generationRootURL: generationRootURL,
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
            localDate: "2025-10-09", localTime: "16:53",
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

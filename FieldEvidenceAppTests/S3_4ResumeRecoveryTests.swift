import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S3_4ResumeRecoveryTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testBeginEvidenceAndFinalizationReplayReturnExactPriorAuthority() async throws {
        let applicationSupportURL = try makeTemporaryDirectory("Replay")
        defer { try? fileManager.removeItem(at: applicationSupportURL) }
        let session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let site = Site(label: "North Campus", timeZoneID: "America/New_York")
        let asset = Asset(
            siteID: site.id,
            packID: pack.packID,
            packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            label: "Monument Sign"
        )
        context.insert(site)
        context.insert(asset)
        try context.save()
        let diagnostics = DiagnosticsStore(applicationSupportURL: applicationSupportURL)
        let coordinator = CheckRunnerCoordinator(
            modelContext: context,
            signPack: pack,
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
        let diagnosticCounters = await diagnostics.snapshot()
        XCTAssertEqual(diagnosticCounters.reportSaved, 1)
        withExtendedLifetime(session) {}
    }

    @MainActor
    func testPreparedSnapshotPromotedAndCommittedPresenceMatrix() async throws {
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

            if matrixCase.expectsMaintenance {
                do {
                    _ = try await service.reconcile()
                    XCTFail("Expected maintenance for \(matrixCase.rawValue)")
                } catch {
                    XCTAssertEqual(
                        error as? FinalizationRecoveryServiceError,
                        .inconsistent,
                        matrixCase.rawValue
                    )
                }
                withExtendedLifetime(seeded.session) {}
                continue
            }

            let summary = try await service.reconcile()
            if matrixCase.expectsDraft {
                XCTAssertEqual(summary.recoveredDraftRecordIDs, [seeded.intent.recordID])
                XCTAssertTrue(summary.completedRecordIDs.isEmpty)
                XCTAssertEqual(
                    try seeded.session.modelContext.fetchCount(FetchDescriptor<Packet>()),
                    0
                )
                XCTAssertEqual(
                    try seeded.session.modelContext.fetchCount(FetchDescriptor<Report>()),
                    0
                )
                XCTAssertFalse(
                    fileManager.fileExists(atPath: seeded.finalSnapshotURL.path)
                )
            } else {
                XCTAssertTrue(summary.recoveredDraftRecordIDs.isEmpty)
                XCTAssertEqual(summary.completedRecordIDs, [seeded.intent.recordID])
                XCTAssertEqual(
                    try seeded.session.modelContext.fetchCount(FetchDescriptor<Packet>()),
                    1
                )
                XCTAssertEqual(
                    try seeded.session.modelContext.fetchCount(FetchDescriptor<Report>()),
                    1
                )
                XCTAssertTrue(
                    fileManager.fileExists(atPath: seeded.finalSnapshotURL.path)
                )
            }
            XCTAssertFalse(fileManager.fileExists(atPath: seeded.intentURL.path))
            XCTAssertFalse(fileManager.fileExists(atPath: seeded.stagingSnapshotURL.path))

            let second = try await service.reconcile()
            XCTAssertTrue(second.recoveredDraftRecordIDs.isEmpty)
            XCTAssertTrue(second.completedRecordIDs.isEmpty)
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
                let record = try XCTUnwrap(
                    seeded.session.modelContext.fetch(FetchDescriptor<WorkflowRecord>()).first
                )
                record.parentRecordID = UUID()
                try seeded.session.modelContext.save()
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
    func testVisibleIssueRecoveryCommitsExactIssueAndRejectsWrongAssetOrTime() async throws {
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
            if issueCase == .valid {
                let summary = try await service.reconcile()
                XCTAssertEqual(summary.completedRecordIDs, [seeded.intent.recordID])
                let issue = try XCTUnwrap(
                    seeded.session.modelContext.fetch(FetchDescriptor<Issue>()).first
                )
                let expected = try XCTUnwrap(seeded.intent.finalizationPayload.issueInsert)
                XCTAssertEqual(issue.id, expected.id)
                XCTAssertEqual(issue.assetID, expected.assetID)
                XCTAssertEqual(issue.openedByRecordID, expected.openedByRecordID)
                XCTAssertEqual(issue.createdAt, expected.createdAt)
                XCTAssertEqual(issue.updatedAt, expected.updatedAt)
                XCTAssertFalse(fileManager.fileExists(atPath: seeded.intentURL.path))
            } else {
                do {
                    _ = try await service.reconcile()
                    XCTFail("Expected visible-issue maintenance for \(issueCase.rawValue)")
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
                XCTAssertEqual(
                    try seeded.session.modelContext.fetchCount(FetchDescriptor<Packet>()),
                    0
                )
                XCTAssertEqual(
                    try seeded.session.modelContext.fetchCount(FetchDescriptor<Report>()),
                    0
                )
                XCTAssertTrue(fileManager.fileExists(atPath: seeded.intentURL.path))
            }
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
        let oldValue = intent.finalizationMutationID.uuidString.lowercased()
        let newValue = mutationID.uuidString.lowercased()
        let encoded = try FinalizationContractEncoderV1().encodeIntent(intent).data
        let source = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let replaced = source.replacingOccurrences(of: oldValue, with: newValue)
        let provisional = try FinalizationContractDecoderV1().decodeIntent(
            Data(replaced.utf8)
        )
        let payloadHash = try FinalizationContractEncoderV1()
            .encodePayload(provisional.finalizationPayload).sha256
        return FinalizationIntentV1(
            completedAt: provisional.completedAt,
            finalizationMutationID: mutationID,
            finalizationPayload: provisional.finalizationPayload,
            finalizationPayloadSHA256: payloadHash,
            generationID: provisional.generationID,
            packetID: provisional.packetID,
            phase: provisional.phase,
            recordID: provisional.recordID,
            reportID: provisional.reportID,
            schemaVersion: provisional.schemaVersion,
            snapshotCreatedAt: provisional.snapshotCreatedAt,
            snapshotFinalRelativePath: provisional.snapshotFinalRelativePath,
            snapshotSHA256: provisional.snapshotSHA256,
            snapshotStagingRelativePath: provisional.snapshotStagingRelativePath,
            stableRootID: provisional.stableRootID
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
private struct SeededRecovery {
    let session: StoreGenerationSession
    let intent: FinalizationIntentV1
    let intentURL: URL
    let stagingSnapshotURL: URL
    let finalSnapshotURL: URL
}

private enum ResumeFixtureError: Error { case image }

import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S4_5CorrectionTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testFirstAndSecondCorrectionCopyOnlyFiveSnapshotFieldsAndKeepEveryPriorPDF() async throws {
        let harness = try await makeHarness("two-generations")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let originalSnapshot = try snapshot(report: harness.originalReport, in: harness)
        let initialDiagnostics = await harness.diagnostics.snapshot()
        let initialCounts = try counts(in: harness)
        harness.site.label = "Renamed live site"
        harness.asset.label = "Renamed live sign"
        let liveIssue = try XCTUnwrap(
            try harness.context.fetch(FetchDescriptor<Issue>()).first
        )
        liveIssue.status = IssueStatus.recheckDue.rawValue
        liveIssue.updatedAt = Fixture.baseDate.addingTimeInterval(50)
        try harness.context.save()
        let originalAuthority = try preservedAuthority(
            recordIDs: [harness.originalRecord.id],
            reportIDs: [harness.originalReport.id],
            in: harness
        )

        let firstIDs = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )
        let firstDate = originalSnapshot.snapshotCreatedAt.addingTimeInterval(10)
        let firstApp = SourceAppSnapshotV1(build: "451", version: "1.1")
        let originalSource = try harness.coordinator.correctionSource(
            reportID: harness.originalReport.id
        )
        XCTAssertEqual(originalSource.sourceReportID, harness.originalReport.id)
        XCTAssertEqual(originalSource.sourceRecordID, harness.originalRecord.id)
        XCTAssertNil(originalSource.currentNote)
        XCTAssertEqual(originalSource.chain.current.reportID, harness.originalReport.id)
        XCTAssertTrue(originalSource.chain.ancestors.isEmpty)

        let firstChain = try readyChain(
            await harness.coordinator.submitCorrection(
                from: originalSource,
                note: "First clerical correction",
                snapshotCreatedAt: firstDate,
                sourceApp: firstApp,
                identifiers: firstIDs
            )
        )
        XCTAssertEqual(firstChain.current.reportID, firstIDs.reportID)
        XCTAssertEqual(firstChain.ancestors.map(\.reportID), [harness.originalReport.id])
        let firstRecord = try record(id: firstIDs.recordID, in: harness)
        let firstReport = try report(id: firstIDs.reportID, in: harness)
        let firstSnapshot = try snapshot(report: firstReport, in: harness)
        XCTAssertEqual(firstSnapshot.site.label, "North Campus")
        XCTAssertEqual(firstSnapshot.asset.label, "Monument Sign")
        XCTAssertEqual(firstSnapshot.issues, originalSnapshot.issues)
        XCTAssertEqual(
            firstSnapshot,
            correctedSnapshot(
                from: originalSnapshot,
                reportID: firstIDs.reportID,
                recordID: firstIDs.recordID,
                note: "First clerical correction",
                snapshotCreatedAt: firstDate,
                sourceApp: firstApp
            )
        )
        try assertCorrectionRecord(
            firstRecord,
            revises: harness.originalRecord,
            originalEvidenceOwnerID: harness.originalRecord.id,
            note: "First clerical correction",
            mutationID: firstIDs.mutationID
        )
        try assertPreserved(originalAuthority, in: harness)

        let beforeStaleRace = try domainSnapshot(in: harness)
        await assertThrowsErrorAsync(
            try await harness.coordinator.submitCorrection(
                from: originalSource,
                note: "Stale source must not win",
                snapshotCreatedAt: firstDate.addingTimeInterval(1),
                sourceApp: firstApp,
                identifiers: ReportCorrectionIdentifiers(
                    mutationID: UUID(), recordID: UUID(), reportID: UUID()
                )
            )
        )
        XCTAssertEqual(try domainSnapshot(in: harness), beforeStaleRace)

        let firstAuthority = try preservedAuthority(
            recordIDs: [harness.originalRecord.id, firstRecord.id],
            reportIDs: [harness.originalReport.id, firstReport.id],
            in: harness
        )
        let secondIDs = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )
        let secondDate = firstDate.addingTimeInterval(10)
        let secondApp = SourceAppSnapshotV1(build: "452", version: "1.2")
        let firstSource = try harness.coordinator.correctionSource(reportID: firstReport.id)
        XCTAssertEqual(firstSource.currentNote, "First clerical correction")
        let secondChain = try readyChain(
            await harness.coordinator.submitCorrection(
                from: firstSource,
                note: "Second clerical correction",
                snapshotCreatedAt: secondDate,
                sourceApp: secondApp,
                identifiers: secondIDs
            )
        )
        XCTAssertEqual(secondChain.current.reportID, secondIDs.reportID)
        XCTAssertEqual(
            secondChain.ancestors.map(\.reportID),
            [firstIDs.reportID, harness.originalReport.id]
        )
        let secondRecord = try record(id: secondIDs.recordID, in: harness)
        let secondReport = try report(id: secondIDs.reportID, in: harness)
        let secondSnapshot = try snapshot(report: secondReport, in: harness)
        XCTAssertEqual(
            secondSnapshot,
            correctedSnapshot(
                from: firstSnapshot,
                reportID: secondIDs.reportID,
                recordID: secondIDs.recordID,
                note: "Second clerical correction",
                snapshotCreatedAt: secondDate,
                sourceApp: secondApp
            )
        )
        try assertCorrectionRecord(
            secondRecord,
            revises: firstRecord,
            originalEvidenceOwnerID: harness.originalRecord.id,
            note: "Second clerical correction",
            mutationID: secondIDs.mutationID
        )
        XCTAssertEqual(secondSnapshot.evidenceSourceRecordID, harness.originalRecord.id)
        XCTAssertEqual(secondSnapshot.evidence, originalSnapshot.evidence)
        XCTAssertEqual(secondSnapshot.history, originalSnapshot.history)
        XCTAssertEqual(secondSnapshot.issues, originalSnapshot.issues)
        try assertPreserved(firstAuthority, in: harness)

        let finalCounts = try counts(in: harness)
        XCTAssertEqual(finalCounts.records, initialCounts.records + 2)
        XCTAssertEqual(finalCounts.reports, initialCounts.reports + 2)
        XCTAssertEqual(finalCounts.sites, initialCounts.sites)
        XCTAssertEqual(finalCounts.assets, initialCounts.assets)
        XCTAssertEqual(finalCounts.evidence, initialCounts.evidence)
        XCTAssertEqual(finalCounts.issues, initialCounts.issues)
        XCTAssertEqual(finalCounts.packets, initialCounts.packets)
        XCTAssertEqual(harness.packet.stableRootID, harness.stableRootID)
        XCTAssertEqual(harness.packet.currentRecordID, secondIDs.recordID)
        XCTAssertTrue(harness.packet.evaluationCounted)
        let finalDiagnostics = await harness.diagnostics.snapshot()
        XCTAssertEqual(finalDiagnostics, initialDiagnostics)

        let beforeLaunchRecovery = try domainSnapshot(in: harness)
        let launchRecovery = try ReportRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        try launchRecovery.reconcileAtStartup()
        XCTAssertEqual(try domainSnapshot(in: harness), beforeLaunchRecovery)
        let cold = try makeCoordinator(in: harness)
        let coldChain = try cold.readyDeliveryChain(currentReportID: secondIDs.reportID)
        XCTAssertEqual(coldChain, secondChain)
        XCTAssertEqual(
            try cold.readyDeliveryChain(
                containingReportID: harness.originalReport.id
            ),
            secondChain
        )
        XCTAssertEqual(
            try cold.onlyReadyReport(assetID: harness.asset.id)?.reportID,
            secondIDs.reportID
        )
        for id in [harness.originalReport.id, firstIDs.reportID, secondIDs.reportID] {
            let delivery = try cold.loadReadyReport(id: id)
            XCTAssertEqual(delivery.pdfSHA256, delivery.pdfData.sha256)
            XCTAssertGreaterThan(try XCTUnwrap(PDFDocument(data: delivery.pdfData)).pageCount, 0)
        }
        let history = ReportHistoryCoordinator(
            modelContext: harness.context,
            deliveryCoordinator: cold
        )
        XCTAssertEqual(try history.index().visits.map(\.reportID), [secondIDs.reportID])
        XCTAssertEqual(
            try history.index().visits.first?.completedAt,
            try XCTUnwrap(harness.originalRecord.completedAt)
        )
        XCTAssertThrowsError(try cold.correctionSource(reportID: harness.originalReport.id))
    }

    @MainActor
    func testPureRuleRejectsNoopMalformedUnknownAndNoncurrentAuthority() async throws {
        let harness = try await makeHarness("pure-rule")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let snapshot = try snapshot(report: harness.originalReport, in: harness)
        let source = ReportCorrectionRuleSource(
            currentRecord: recordPayload(harness.originalRecord),
            packet: packetPayload(harness.packet),
            currentReport: reportPayload(harness.originalReport),
            currentSnapshot: snapshot
        )
        let identifiers = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )
        let request = ReportCorrectionRuleRequest(
            note: "Corrected note",
            snapshotCreatedAt: snapshot.snapshotCreatedAt.addingTimeInterval(1),
            sourceApp: SourceAppSnapshotV1(build: "45", version: "1.0"),
            identifiers: identifiers
        )
        let plan = try ReportCorrectionRule().makePlan(source: source, request: request)
        XCTAssertEqual(plan.recordAfter.revisesRecordID, harness.originalRecord.id)
        XCTAssertEqual(plan.recordAfter.recordRevisionRootID, harness.originalRecord.id)
        XCTAssertEqual(plan.recordAfter.evidenceSourceRecordID, harness.originalRecord.id)
        XCTAssertEqual(plan.packetBefore.currentRecordID, harness.originalRecord.id)
        XCTAssertEqual(plan.packetAfter.currentRecordID, identifiers.recordID)
        XCTAssertEqual(plan.reportInsert.replacesReportID, harness.originalReport.id)
        XCTAssertEqual(
            plan.snapshot,
            correctedSnapshot(
                from: snapshot,
                reportID: identifiers.reportID,
                recordID: identifiers.recordID,
                note: "Corrected note",
                snapshotCreatedAt: request.snapshotCreatedAt,
                sourceApp: request.sourceApp
            )
        )
        XCTAssertNotEqual(plan.snapshot.reportID, snapshot.reportID)
        XCTAssertNotEqual(plan.snapshot.sourceRecordID, snapshot.sourceRecordID)
        XCTAssertNotEqual(plan.snapshot.snapshotCreatedAt, snapshot.snapshotCreatedAt)
        XCTAssertNotEqual(plan.snapshot.sourceApp, snapshot.sourceApp)
        XCTAssertNotEqual(plan.snapshot.note, snapshot.note)
        XCTAssertEqual(plan.snapshot.evidenceSourceRecordID, snapshot.evidenceSourceRecordID)
        XCTAssertEqual(plan.snapshot.acknowledgements, snapshot.acknowledgements)
        XCTAssertEqual(plan.snapshot.asset, snapshot.asset)
        XCTAssertEqual(plan.snapshot.couldNotVerify, snapshot.couldNotVerify)
        XCTAssertEqual(plan.snapshot.disclaimer, snapshot.disclaimer)
        XCTAssertEqual(plan.snapshot.display, snapshot.display)
        XCTAssertEqual(plan.snapshot.evidence, snapshot.evidence)
        XCTAssertEqual(plan.snapshot.history, snapshot.history)
        XCTAssertEqual(plan.snapshot.issues, snapshot.issues)
        XCTAssertEqual(plan.snapshot.outcome, snapshot.outcome)
        XCTAssertEqual(plan.snapshot.pack, snapshot.pack)
        XCTAssertEqual(plan.snapshot.packetID, snapshot.packetID)
        XCTAssertEqual(plan.snapshot.pdfTemplate, snapshot.pdfTemplate)
        XCTAssertEqual(plan.snapshot.site, snapshot.site)
        XCTAssertEqual(plan.snapshot.snapshotSchemaVersion, snapshot.snapshotSchemaVersion)
        XCTAssertEqual(plan.snapshot.stableRootID, snapshot.stableRootID)
        XCTAssertEqual(plan.snapshot.stage, snapshot.stage)
        XCTAssertEqual(plan.snapshot.timeContext, snapshot.timeContext)

        let malformed: [String?] = [nil, "", " leading", "trailing ", String(repeating: "x", count: 1001)]
        for note in malformed {
            XCTAssertThrowsError(
                try ReportCorrectionRule().makePlan(
                    source: source,
                    request: ReportCorrectionRuleRequest(
                        note: note,
                        snapshotCreatedAt: request.snapshotCreatedAt,
                        sourceApp: request.sourceApp,
                        identifiers: identifiers
                    )
                )
            ) {
                XCTAssertEqual($0 as? ReportCorrectionRuleError, .invalidNote)
            }
        }
        for collidingIDs in [
            ReportCorrectionIdentifiers(
                mutationID: try XCTUnwrap(source.currentRecord.finalizationMutationID),
                recordID: UUID(),
                reportID: UUID()
            ),
            ReportCorrectionIdentifiers(
                mutationID: UUID(),
                recordID: source.currentRecord.id,
                reportID: UUID()
            ),
            ReportCorrectionIdentifiers(
                mutationID: UUID(),
                recordID: UUID(),
                reportID: source.currentReport.id
            ),
        ] {
            XCTAssertThrowsError(
                try ReportCorrectionRule().makePlan(
                    source: source,
                    request: ReportCorrectionRuleRequest(
                        note: request.note,
                        snapshotCreatedAt: request.snapshotCreatedAt,
                        sourceApp: request.sourceApp,
                        identifiers: collidingIDs
                    )
                )
            ) {
                XCTAssertEqual($0 as? ReportCorrectionRuleError, .invalidAuthority)
            }
        }
        let unknownReport = ReportPayloadV1(
            id: source.currentReport.id,
            schemaVersion: 2,
            packetID: source.currentReport.packetID,
            sourceRecordID: source.currentReport.sourceRecordID,
            snapshotSchemaVersion: source.currentReport.snapshotSchemaVersion,
            snapshotRelativePath: source.currentReport.snapshotRelativePath,
            snapshotSHA256: source.currentReport.snapshotSHA256,
            pdfState: source.currentReport.pdfState,
            pdfRelativePath: source.currentReport.pdfRelativePath,
            pdfSHA256: source.currentReport.pdfSHA256,
            createdAt: source.currentReport.createdAt,
            replacesReportID: source.currentReport.replacesReportID
        )
        XCTAssertThrowsError(
            try ReportCorrectionRule().makePlan(
                source: ReportCorrectionRuleSource(
                    currentRecord: source.currentRecord,
                    packet: source.packet,
                    currentReport: unknownReport,
                    currentSnapshot: source.currentSnapshot
                ),
                request: request
            )
        ) {
            XCTAssertEqual($0 as? ReportCorrectionRuleError, .invalidAuthority)
        }
        let unknownPackRecord = recordPayload(
            source.currentRecord,
            packContentVersion: 999
        )
        XCTAssertThrowsError(
            try ReportCorrectionRule().makePlan(
                source: ReportCorrectionRuleSource(
                    currentRecord: unknownPackRecord,
                    packet: source.packet,
                    currentReport: source.currentReport,
                    currentSnapshot: source.currentSnapshot
                ),
                request: request
            )
        ) {
            XCTAssertEqual($0 as? ReportCorrectionRuleError, .invalidAuthority)
        }
        let unknownTemplateRecord = recordPayload(
            source.currentRecord,
            pdfTemplateVersion: 999
        )
        XCTAssertThrowsError(
            try ReportCorrectionRule().makePlan(
                source: ReportCorrectionRuleSource(
                    currentRecord: unknownTemplateRecord,
                    packet: source.packet,
                    currentReport: source.currentReport,
                    currentSnapshot: source.currentSnapshot
                ),
                request: request
            )
        ) {
            XCTAssertEqual($0 as? ReportCorrectionRuleError, .invalidAuthority)
        }
        XCTAssertFalse(harness.context.hasChanges)
        XCTAssertEqual(
            recordPayload(try record(id: source.currentRecord.id, in: harness)),
            source.currentRecord
        )
    }

    @MainActor
    func testSubmillisecondProductionDateCanonicalizesOnceAndColdRecoveryAcceptsIt() async throws {
        let substantiveDate = Date(timeIntervalSince1970: 1_768_940_000.123456)
        let harness = try await makeHarness(
            "date-precision",
            substantiveDate: substantiveDate
        )
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let originalRecord = recordPayload(harness.originalRecord)
        let originalEvidence = try harness.context.fetch(FetchDescriptor<EvidenceFile>())
            .map(evidenceFact).sorted { $0.id.uuidString < $1.id.uuidString }
        let originalIssues = try harness.context.fetch(FetchDescriptor<Issue>())
            .map(issuePayload).sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(harness.originalRecord.completedAt, substantiveDate)
        XCTAssertEqual(
            harness.originalRecord.observedAtUTC,
            substantiveDate.addingTimeInterval(-20)
        )
        XCTAssertTrue(originalEvidence.allSatisfy {
            $0.createdAt.timeIntervalSince1970.rounded(.towardZero)
                != $0.createdAt.timeIntervalSince1970
        })
        XCTAssertTrue(originalIssues.allSatisfy {
            $0.createdAt.timeIntervalSince1970.rounded(.towardZero)
                != $0.createdAt.timeIntervalSince1970
        })
        let source = try harness.coordinator.correctionSource(
            reportID: harness.originalReport.id
        )
        let identifiers = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )
        let requested = Date(timeIntervalSince1970: 1_768_940_010.654321)
        let expected = Date(timeIntervalSince1970: 1_768_940_010.654)
        let chain = try readyChain(
            await harness.coordinator.submitCorrection(
                from: source,
                note: "Submillisecond timestamp correction",
                snapshotCreatedAt: requested,
                sourceApp: Fixture.sourceApp,
                identifiers: identifiers
            )
        )
        XCTAssertEqual(chain.current.reportID, identifiers.reportID)
        let correctedReport = try report(id: identifiers.reportID, in: harness)
        let correctedSnapshot = try snapshot(report: correctedReport, in: harness)
        XCTAssertNotEqual(requested, expected)
        XCTAssertEqual(correctedReport.createdAt, expected)
        XCTAssertEqual(correctedSnapshot.snapshotCreatedAt, expected)
        let correctedRecord = try record(id: identifiers.recordID, in: harness)
        XCTAssertEqual(correctedRecord.startedAt, originalRecord.startedAt)
        XCTAssertEqual(correctedRecord.completedAt, originalRecord.completedAt)
        XCTAssertEqual(correctedRecord.observedAtUTC, originalRecord.observedAtUTC)
        XCTAssertEqual(recordPayload(harness.originalRecord), originalRecord)
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<EvidenceFile>())
                .map(evidenceFact).sorted { $0.id.uuidString < $1.id.uuidString },
            originalEvidence
        )
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<Issue>())
                .map(issuePayload).sorted { $0.id.uuidString < $1.id.uuidString },
            originalIssues
        )

        let beforeRecovery = try domainSnapshot(in: harness)
        let recovery = try ReportRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        try recovery.reconcileAtStartup()
        XCTAssertEqual(try domainSnapshot(in: harness), beforeRecovery)
        let cold = try makeCoordinator(in: harness)
        XCTAssertEqual(
            try cold.readyDeliveryChain(currentReportID: identifiers.reportID),
            chain
        )
        _ = try cold.loadReadyReport(id: harness.originalReport.id)
        _ = try cold.loadReadyReport(id: identifiers.reportID)
    }

    @MainActor
    func testPrecommitJournalAndSaveFailuresLeaveNoPartialAuthorityThenRetryOnce() async throws {
        for fault in CorrectionPrecommitFault.allCases {
            let harness = try await makeHarness("precommit-\(fault)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let identifiers = ReportCorrectionIdentifiers(
                mutationID: UUID(), recordID: UUID(), reportID: UUID()
            )
            let injection = fault.injections()
            let coordinator = try makeCoordinator(
                in: harness,
                storeFailure: injection.store,
                serviceFailure: injection.service
            )
            let source = try coordinator.correctionSource(reportID: harness.originalReport.id)
            let before = try domainSnapshot(in: harness)
            let diagnostics = await harness.diagnostics.snapshot()

            do {
                _ = try await coordinator.submitCorrection(
                    from: source,
                    note: "Retry-safe correction",
                    snapshotCreatedAt: Fixture.correctionDate,
                    sourceApp: Fixture.sourceApp,
                    identifiers: identifiers
                )
                XCTFail("\(fault) must interrupt correction before database commit")
            } catch {
                XCTAssertEqual(
                    error as? ReportDeliveryCoordinatorError,
                    .correctionFinalizationFailed
                )
            }
            XCTAssertEqual(try domainSnapshot(in: harness), before)
            let afterFailureDiagnostics = await harness.diagnostics.snapshot()
            XCTAssertEqual(afterFailureDiagnostics, diagnostics)
            XCTAssertFalse(fileManager.fileExists(atPath: intentURL(identifiers, in: harness).path))
            XCTAssertFalse(fileManager.fileExists(atPath: stagingSnapshotURL(identifiers, in: harness).path))
            XCTAssertFalse(fileManager.fileExists(atPath: finalSnapshotURL(identifiers, in: harness).path))

            injection.store?.removeFailure()
            injection.service?.removeFailure()
            let ready = try readyChain(
                await coordinator.submitCorrection(
                    from: source,
                    note: "Retry-safe correction",
                    snapshotCreatedAt: Fixture.correctionDate,
                    sourceApp: Fixture.sourceApp,
                    identifiers: identifiers
                )
            )
            XCTAssertEqual(ready.current.reportID, identifiers.reportID)
            XCTAssertEqual(try counts(in: harness).records, before.records.count + 1)
            XCTAssertEqual(try counts(in: harness).reports, before.reports.count + 1)
            XCTAssertFalse(fileManager.fileExists(atPath: intentURL(identifiers, in: harness).path))
        }
    }

    @MainActor
    func testSnapshotPromotedCrashRecoveryPreservesRawSubmillisecondVisitDates() async throws {
        let substantiveDate = Date(timeIntervalSince1970: 1_768_940_000.123456)
        let harness = try await makeHarness(
            "snapshot-promoted-recovery-date",
            substantiveDate: substantiveDate
        )
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let priorSnapshot = try snapshot(report: harness.originalReport, in: harness)
        let priorRecord = recordPayload(harness.originalRecord)
        let identifiers = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )
        let plan = try ReportCorrectionRule().makePlan(
            source: ReportCorrectionRuleSource(
                currentRecord: priorRecord,
                packet: packetPayload(harness.packet),
                currentReport: reportPayload(harness.originalReport),
                currentSnapshot: priorSnapshot
            ),
            request: ReportCorrectionRuleRequest(
                note: "Recovered promoted correction",
                snapshotCreatedAt: Date(timeIntervalSince1970: 1_768_940_100.987654),
                sourceApp: Fixture.sourceApp,
                identifiers: identifiers
            )
        )
        let encodedSnapshot = try ReportSnapshotEncoderV1().encode(plan.snapshot)
        let payload = FinalizationPayloadV1(
            issueInsert: nil,
            issueTransition: nil,
            packetAfter: plan.packetAfter,
            packetBefore: plan.packetBefore,
            reportInsert: plan.reportInsert,
            workflowRecordAfter: plan.recordAfter
        )
        let encodedPayload = try FinalizationContractEncoderV1().encodePayload(payload)
        let intent = FinalizationIntentV1(
            completedAt: try XCTUnwrap(plan.recordAfter.completedAt),
            finalizationMutationID: identifiers.mutationID,
            finalizationPayload: payload,
            finalizationPayloadSHA256: encodedPayload.sha256,
            generationID: harness.session.generationID,
            packetID: harness.packet.id,
            phase: .prepared,
            recordID: identifiers.recordID,
            reportID: identifiers.reportID,
            schemaVersion: 1,
            snapshotCreatedAt: plan.snapshot.snapshotCreatedAt,
            snapshotFinalRelativePath: plan.reportInsert.snapshotRelativePath,
            snapshotSHA256: encodedSnapshot.sha256,
            snapshotStagingRelativePath: ".staging/\(plan.reportInsert.snapshotRelativePath)",
            stableRootID: harness.packet.stableRootID
        )
        let store = FinalizationIntentStore(
            generationRootURL: harness.session.generationRootURL
        )
        let prepared = try await store.prepare(intent: intent, snapshot: encodedSnapshot)
        let promoted = try await store.promoteSnapshot(prepared)
        _ = try await store.advance(promoted, to: .snapshotPromoted)
        XCTAssertEqual(try counts(in: harness).records, 1)
        XCTAssertEqual(try counts(in: harness).reports, 1)

        let recovery = FinalizationRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        let summary = try await recovery.reconcile()
        XCTAssertEqual(summary.completedRecordIDs, [identifiers.recordID])
        let recoveredRecord = try record(id: identifiers.recordID, in: harness)
        XCTAssertEqual(recoveredRecord.startedAt, priorRecord.startedAt)
        XCTAssertEqual(recoveredRecord.completedAt, priorRecord.completedAt)
        XCTAssertEqual(recoveredRecord.observedAtUTC, priorRecord.observedAtUTC)
        XCTAssertEqual(recoveredRecord.completedAt, substantiveDate)
        XCTAssertEqual(harness.packet.currentRecordID, identifiers.recordID)
        XCTAssertFalse(fileManager.fileExists(atPath: intentURL(identifiers, in: harness).path))
        guard case .ready = try makeCoordinator(in: harness)
            .prepareFinalizedReport(id: identifiers.reportID) else {
            return XCTFail("recovered promoted correction must use the shared renderer")
        }
        let cold = try makeCoordinator(in: harness)
        XCTAssertEqual(
            try cold.readyDeliveryChain(currentReportID: identifiers.reportID)
                .ancestors.map(\.reportID),
            [harness.originalReport.id]
        )
    }

    @MainActor
    func testCommittedJournalRecoveryAndSameIdentifierReplayAreDuplicateFree() async throws {
        let harness = try await makeHarness(
            "committed-recovery",
            substantiveDate: Date(timeIntervalSince1970: 1_768_940_000.123456)
        )
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let correctionDate = Date(timeIntervalSince1970: 1_768_940_100.987654)
        let storeFailure = FinalizationIntentStoreFailureInjection(
            failOnceAt: .intentPhaseWrite(.databaseCommitted)
        )
        let coordinator = try makeCoordinator(in: harness, storeFailure: storeFailure)
        let source = try coordinator.correctionSource(reportID: harness.originalReport.id)
        let identifiers = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )
        let prior = try preservedAuthority(
            recordIDs: [harness.originalRecord.id],
            reportIDs: [harness.originalReport.id],
            in: harness
        )

        let committedResult = try await coordinator.submitCorrection(
            from: source,
            note: "Recovered correction",
            snapshotCreatedAt: correctionDate,
            sourceApp: Fixture.sourceApp,
            identifiers: identifiers
        )
        guard case .pdfUnavailable(let unavailableID, let priorDelivery) =
                committedResult else {
            return XCTFail(
                "database-committed intent failure must return honest persisted authority"
            )
        }
        XCTAssertEqual(unavailableID, identifiers.reportID)
        XCTAssertEqual(priorDelivery.reportID, harness.originalReport.id)
        XCTAssertEqual(try counts(in: harness).records, 2)
        XCTAssertEqual(try counts(in: harness).reports, 2)
        XCTAssertEqual(harness.packet.currentRecordID, identifiers.recordID)
        XCTAssertTrue(fileManager.fileExists(atPath: intentURL(identifiers, in: harness).path))
        XCTAssertTrue(fileManager.fileExists(atPath: finalSnapshotURL(identifiers, in: harness).path))
        try assertPreserved(prior, in: harness)

        let recovery = FinalizationRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        let operationURL = intentURL(identifiers, in: harness)
        let canonicalIntent = try Data(contentsOf: operationURL)
        var tamperedIntent = canonicalIntent
        tamperedIntent.append(0x0A)
        try tamperedIntent.write(to: operationURL, options: .atomic)
        let beforeTamperedRecovery = try domainSnapshot(in: harness)
        do {
            _ = try await recovery.reconcile()
            XCTFail("noncanonical recovery intent must fail closed")
        } catch {
            XCTAssertEqual(error as? FinalizationRecoveryServiceError, .inconsistent)
        }
        XCTAssertEqual(try domainSnapshot(in: harness), beforeTamperedRecovery)
        XCTAssertEqual(try Data(contentsOf: operationURL), tamperedIntent)

        try canonicalIntent.write(to: operationURL, options: .atomic)
        harness.site.label = "Unsaved recovery collision"
        do {
            _ = try await recovery.reconcile()
            XCTFail("dirty recovery context must fail closed")
        } catch {
            XCTAssertEqual(error as? FinalizationRecoveryServiceError, .inconsistent)
        }
        XCTAssertEqual(try Data(contentsOf: operationURL), canonicalIntent)
        harness.context.rollback()

        let summary = try await recovery.reconcile()
        XCTAssertEqual(summary.completedRecordIDs, [identifiers.recordID])
        XCTAssertFalse(fileManager.fileExists(atPath: intentURL(identifiers, in: harness).path))
        let recoveredRecord = try record(id: identifiers.recordID, in: harness)
        XCTAssertEqual(recoveredRecord.startedAt, harness.originalRecord.startedAt)
        XCTAssertEqual(recoveredRecord.completedAt, harness.originalRecord.completedAt)
        XCTAssertEqual(recoveredRecord.observedAtUTC, harness.originalRecord.observedAtUTC)
        let fresh = try makeCoordinator(in: harness)
        guard case .ready = try fresh.prepareFinalizedReport(id: identifiers.reportID) else {
            return XCTFail("recovered pending correction must render exactly once")
        }
        let afterRecovery = try domainSnapshot(in: harness)
        storeFailure.removeFailure()
        let replay = try readyChain(
            await coordinator.submitCorrection(
                from: source,
                note: "Recovered correction",
                snapshotCreatedAt: correctionDate,
                sourceApp: Fixture.sourceApp,
                identifiers: identifiers
            )
        )
        XCTAssertEqual(replay.current.reportID, identifiers.reportID)
        XCTAssertEqual(try domainSnapshot(in: harness), afterRecovery)
        XCTAssertEqual(try counts(in: harness).records, 2)
        XCTAssertEqual(try counts(in: harness).reports, 2)

        await assertThrowsErrorAsync(
            try await coordinator.submitCorrection(
                from: source,
                note: "Different replay payload",
                snapshotCreatedAt: correctionDate,
                sourceApp: Fixture.sourceApp,
                identifiers: identifiers
            )
        )
        XCTAssertEqual(try domainSnapshot(in: harness), afterRecovery)
    }

    @MainActor
    func testPostcommitDirtyInterleavingReturnsPersistedAuthorityWithoutSavingOrRollingBackUnrelatedEdit() async throws {
        let harness = try await makeHarness("postcommit-dirty-interleaving")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let originalSiteLabel = harness.site.label
        let dirtySiteLabel = "Unsaved concurrent site label"
        let initialCounts = try counts(in: harness)
        let initialDiagnostics = await harness.diagnostics.snapshot()
        var barrierHits = 0
        let barrier = FinalizationServiceOperationBarrier { boundary in
            XCTAssertEqual(boundary, .afterCorrectionDatabaseCommit)
            barrierHits += 1
            harness.site.label = dirtySiteLabel
        }
        let coordinator = try makeCoordinator(
            in: harness,
            serviceOperationBarrier: barrier
        )
        let source = try coordinator.correctionSource(
            reportID: harness.originalReport.id
        )
        let identifiers = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )

        let result = try await coordinator.submitCorrection(
            from: source,
            note: "Postcommit dirty interleaving",
            snapshotCreatedAt: Fixture.correctionDate.addingTimeInterval(30),
            sourceApp: Fixture.sourceApp,
            identifiers: identifiers
        )
        guard case .pdfUnavailable(let reportID, let prior) = result else {
            return XCTFail("committed authority must not be described as a precommit failure")
        }
        XCTAssertEqual(reportID, identifiers.reportID)
        XCTAssertEqual(prior.reportID, harness.originalReport.id)
        XCTAssertEqual(barrierHits, 1)
        XCTAssertTrue(harness.context.hasChanges)
        XCTAssertEqual(harness.site.label, dirtySiteLabel)
        XCTAssertEqual(try counts(in: harness).records, initialCounts.records + 1)
        XCTAssertEqual(try counts(in: harness).reports, initialCounts.reports + 1)
        XCTAssertEqual(try counts(in: harness).evidence, initialCounts.evidence)
        XCTAssertEqual(try counts(in: harness).issues, initialCounts.issues)
        XCTAssertEqual(try counts(in: harness).packets, initialCounts.packets)
        XCTAssertEqual(harness.packet.currentRecordID, identifiers.recordID)
        XCTAssertEqual(
            try report(id: identifiers.reportID, in: harness).pdfState,
            ReportPDFState.pending.rawValue
        )
        XCTAssertTrue(fileManager.fileExists(
            atPath: intentURL(identifiers, in: harness).path
        ))
        XCTAssertTrue(fileManager.fileExists(
            atPath: finalSnapshotURL(identifiers, in: harness).path
        ))

        // Restore the held reference explicitly before rollback; SwiftData does
        // not promise that rollback refreshes already-held model instances.
        harness.site.label = originalSiteLabel
        harness.context.rollback()
        XCTAssertFalse(harness.context.hasChanges)
        XCTAssertEqual(harness.site.label, originalSiteLabel)
        XCTAssertEqual(try counts(in: harness).records, initialCounts.records + 1)
        XCTAssertEqual(try counts(in: harness).reports, initialCounts.reports + 1)
        XCTAssertEqual(harness.packet.currentRecordID, identifiers.recordID)

        let recovery = FinalizationRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        let summary = try await recovery.reconcile()
        XCTAssertEqual(summary.completedRecordIDs, [identifiers.recordID])
        XCTAssertFalse(fileManager.fileExists(
            atPath: intentURL(identifiers, in: harness).path
        ))
        let cold = try makeCoordinator(in: harness)
        guard case .ready = try cold.prepareFinalizedReport(id: identifiers.reportID) else {
            return XCTFail("recovered committed correction must use the shared renderer")
        }
        XCTAssertEqual(
            try cold.readyDeliveryChain(currentReportID: identifiers.reportID)
                .ancestors.map(\.reportID),
            [harness.originalReport.id]
        )
        XCTAssertEqual(try counts(in: harness).records, initialCounts.records + 1)
        XCTAssertEqual(try counts(in: harness).reports, initialCounts.reports + 1)
        XCTAssertEqual(harness.site.label, originalSiteLabel)
        let finalDiagnostics = await harness.diagnostics.snapshot()
        XCTAssertEqual(finalDiagnostics, initialDiagnostics)
    }

    @MainActor
    func testRenderFailurePersistsOneRecoverableCorrectionWithoutResubmitOrCounterMutation() async throws {
        let harness = try await makeHarness("render-failure")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let renderFailure = ReportRenderFailureInjection(failOnceAt: .render)
        let recovery = try ReportRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        let coordinator = try makeCoordinator(in: harness, renderFailure: renderFailure)
        let source = try coordinator.correctionSource(reportID: harness.originalReport.id)
        let identifiers = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )
        let diagnostics = await harness.diagnostics.snapshot()
        let prior = try preservedAuthority(
            recordIDs: [harness.originalRecord.id],
            reportIDs: [harness.originalReport.id],
            in: harness
        )
        let result = try await coordinator.submitCorrection(
            from: source,
            note: "Correction with failed delivery",
            snapshotCreatedAt: Fixture.correctionDate,
            sourceApp: Fixture.sourceApp,
            identifiers: identifiers
        )
        guard case .pdfUnavailable(let failedID, let priorDelivery) = result else {
            return XCTFail("render injection must persist an honest failed correction")
        }
        XCTAssertEqual(failedID, identifiers.reportID)
        XCTAssertEqual(priorDelivery.reportID, harness.originalReport.id)
        let failed = try report(id: identifiers.reportID, in: harness)
        XCTAssertEqual(failed.pdfState, ReportPDFState.failed.rawValue)
        XCTAssertNil(failed.pdfRelativePath)
        XCTAssertNil(failed.pdfSHA256)
        XCTAssertEqual(try counts(in: harness).records, 2)
        XCTAssertEqual(try counts(in: harness).reports, 2)
        XCTAssertEqual(try counts(in: harness).evidence, 2)
        let failedDiagnostics = await harness.diagnostics.snapshot()
        XCTAssertEqual(failedDiagnostics, diagnostics)
        try assertPreserved(prior, in: harness)
        do {
            _ = try await coordinator.submitCorrection(
                from: source,
                note: "Correction with failed delivery",
                snapshotCreatedAt: Fixture.correctionDate,
                sourceApp: Fixture.sourceApp,
                identifiers: identifiers
            )
            XCTFail("a persisted failed correction must use Retry, not resubmit")
        } catch {
            XCTAssertEqual(
                error as? ReportDeliveryCoordinatorError,
                .invalidCorrection
            )
        }
        XCTAssertEqual(try counts(in: harness).records, 2)
        XCTAssertEqual(try counts(in: harness).reports, 2)
        let replayDiagnostics = await harness.diagnostics.snapshot()
        XCTAssertEqual(replayDiagnostics, diagnostics)

        XCTAssertEqual(recovery.failedReportIDs, [])
        try coordinator.acknowledgePersistedPDFUnavailable(
            reportID: identifiers.reportID
        )
        for _ in 0..<8 where recovery.failedReportIDs != [identifiers.reportID] {
            await Task.yield()
        }
        XCTAssertEqual(recovery.failedReportIDs, [identifiers.reportID])
        guard case .ready = try await recovery.retryFailedReport(id: identifiers.reportID) else {
            return XCTFail("existing bounded retry must ready the same correction")
        }
        XCTAssertEqual(recovery.failedReportIDs, [])
        let cold = try makeCoordinator(in: harness)
        XCTAssertEqual(
            try cold.readyDeliveryChain(currentReportID: identifiers.reportID)
                .ancestors.map(\.reportID),
            [harness.originalReport.id]
        )
        _ = try cold.loadReadyReport(id: harness.originalReport.id)
        _ = try cold.loadReadyReport(id: identifiers.reportID)
        let retriedDiagnostics = await harness.diagnostics.snapshot()
        XCTAssertEqual(retriedDiagnostics, diagnostics)
    }

    @MainActor
    func testDirtyCollisionMalformedAndUnsafeAuthorityFailClosedWithoutMutationOrLinkFollowing() async throws {
        for invalid in InvalidCorrectionAuthority.allCases {
            let harness = try await makeHarness("invalid-\(invalid)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let sourceReportID = harness.originalReport.id
            let sentinel = try apply(invalid, to: harness)
            let before = try domainSnapshot(in: harness)
            let diagnostics = await harness.diagnostics.snapshot()
            let coordinator = try makeCoordinator(in: harness)
            XCTAssertThrowsError(
                try coordinator.correctionSource(reportID: sourceReportID)
            ) { error in
                if invalid.expectsDirtyContext {
                    XCTAssertEqual(error as? ReportDeliveryCoordinatorError, .contextHasChanges)
                } else {
                    XCTAssertTrue(
                        (error as? ReportDeliveryCoordinatorError) == .invalidAuthority
                            || (error as? ReportDeliveryCoordinatorError) == .invalidCorrection
                    )
                }
            }
            XCTAssertEqual(try domainSnapshot(in: harness), before)
            let afterInvalidDiagnostics = await harness.diagnostics.snapshot()
            XCTAssertEqual(afterInvalidDiagnostics, diagnostics)
            if !invalid.expectsDirtyContext {
                XCTAssertEqual(try counts(in: harness).records, before.records.count)
                XCTAssertEqual(try counts(in: harness).reports, before.reports.count)
            }
            if let sentinel {
                XCTAssertEqual(try Data(contentsOf: sentinel.target), sentinel.data)
                XCTAssertEqual(
                    try fileManager.attributesOfItem(atPath: sentinel.link.path)[.type]
                        as? FileAttributeType,
                    sentinel.linkType
                )
            }
            harness.context.rollback()
        }
    }

    @MainActor
    func testGenerationRootIdentityReplacementFailsClosedWithoutTouchingRetainedBytes() async throws {
        let harness = try await makeHarness("generation-root-replacement")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let coordinator = harness.coordinator
        let sourceReportID = harness.originalReport.id
        let root = harness.session.generationRootURL
        let retainedRoot = harness.applicationSupportURL.appendingPathComponent(
            "retained-generation-\(UUID())",
            isDirectory: true
        )
        let retainedSnapshotRelativePath = harness.originalReport.snapshotRelativePath
        let retainedPDFRelativePath = try XCTUnwrap(harness.originalReport.pdfRelativePath)
        let snapshotBytes = try Data(
            contentsOf: root.appendingPathComponent(retainedSnapshotRelativePath)
        )
        let pdfBytes = try Data(
            contentsOf: root.appendingPathComponent(retainedPDFRelativePath)
        )
        try fileManager.moveItem(at: root, to: retainedRoot)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.moveItem(at: retainedRoot, to: root)
        }

        XCTAssertThrowsError(try coordinator.correctionSource(reportID: sourceReportID)) {
            XCTAssertEqual($0 as? ReportDeliveryCoordinatorError, .invalidAuthority)
        }
        XCTAssertEqual(
            try Data(
                contentsOf: retainedRoot.appendingPathComponent(retainedSnapshotRelativePath)
            ),
            snapshotBytes
        )
        XCTAssertEqual(
            try Data(contentsOf: retainedRoot.appendingPathComponent(retainedPDFRelativePath)),
            pdfBytes
        )
        XCTAssertTrue((try fileManager.contentsOfDirectory(atPath: root.path)).isEmpty)
    }

    @MainActor
    func testIntentStorePersistentSwapAndJournalABAKeepMutationOwnedBytesAnchored() async throws {
        let harness = try await makeHarness("intent-store-barrier")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let before = try domainSnapshot(in: harness)
        let root = harness.session.generationRootURL
        let barrierFileManager = fileManager
        let expectedRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)

        let persistentInput = try correctionStoreInput(
            in: harness,
            note: "Persistent swap",
            snapshotCreatedAt: Fixture.correctionDate.addingTimeInterval(10)
        )
        let heldGeneration = harness.applicationSupportURL.appendingPathComponent(
            "held-generation-\(UUID())",
            isDirectory: true
        )
        let replacementGeneration = harness.applicationSupportURL.appendingPathComponent(
            "replacement-generation-\(UUID())",
            isDirectory: true
        )
        let replacementSentinel = Data("unowned-generation".utf8)
        let persistentAction = StoreBarrierAction(
            boundary: .afterLeafMutation,
            hit: 1
        ) {
            try barrierFileManager.moveItem(at: root, to: heldGeneration)
            try barrierFileManager.createDirectory(
                at: root,
                withIntermediateDirectories: false
            )
            try replacementSentinel.write(
                to: root.appendingPathComponent("unowned.txt"),
                options: .withoutOverwriting
            )
        }
        let persistentStore = FinalizationIntentStore(
            generationRootURL: root,
            expectedGenerationRootIdentity: expectedRootIdentity,
            authorityBarrier: FinalizationIntentStoreAuthorityBarrier {
                persistentAction.reach($0)
            }
        )
        do {
            _ = try await persistentStore.prepare(
                intent: persistentInput.intent,
                snapshot: persistentInput.snapshot
            )
            XCTFail("persistent generation replacement must fail closed")
        } catch {
            XCTAssertEqual(error as? FinalizationIntentStoreError, .generationRootInvalid)
        }
        XCTAssertNil(persistentAction.errorDescription)
        XCTAssertEqual(try regularFiles(at: heldGeneration), before.generationFiles)
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: heldGeneration.appendingPathComponent(
                    persistentInput.intent.snapshotStagingRelativePath
                ).path
            )
        )
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: root.appendingPathComponent(
                    persistentInput.intent.snapshotStagingRelativePath
                ).path
            )
        )
        XCTAssertFalse(fileManager.fileExists(
            atPath: intentURL(persistentInput.identifiers, in: harness).path
        ))
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("unowned.txt")),
            replacementSentinel
        )
        XCTAssertEqual(
            try regularFiles(at: root),
            ["unowned.txt": replacementSentinel]
        )

        try fileManager.moveItem(at: root, to: replacementGeneration)
        try fileManager.moveItem(at: heldGeneration, to: root)
        let preparedAfterRestore = try await persistentStore.prepare(
            intent: persistentInput.intent,
            snapshot: persistentInput.snapshot
        )
        let promotedAfterRestore = try await persistentStore.promoteSnapshot(
            preparedAfterRestore
        )
        try await persistentStore.rollbackUncommitted(promotedAfterRestore)
        XCTAssertEqual(try domainSnapshot(in: harness), before)
        XCTAssertEqual(
            try Data(contentsOf: replacementGeneration.appendingPathComponent("unowned.txt")),
            replacementSentinel
        )

        let snapshotInput = try correctionStoreInput(
            in: harness,
            note: "Snapshot ancestor swap",
            snapshotCreatedAt: Fixture.correctionDate.addingTimeInterval(15)
        )
        let baselineStore = FinalizationIntentStore(
            generationRootURL: root,
            expectedGenerationRootIdentity: expectedRootIdentity,
            authorityBarrier: FinalizationIntentStoreAuthorityBarrier { _ in }
        )
        let snapshotPrepared = try await baselineStore.prepare(
            intent: snapshotInput.intent,
            snapshot: snapshotInput.snapshot
        )
        let snapshotsRoot = root.appendingPathComponent("snapshots", isDirectory: true)
        let heldSnapshots = harness.applicationSupportURL.appendingPathComponent(
            "held-snapshots-\(UUID())",
            isDirectory: true
        )
        let replacementSnapshots = harness.applicationSupportURL.appendingPathComponent(
            "replacement-snapshots-\(UUID())",
            isDirectory: true
        )
        let snapshotSentinel = Data("unowned-snapshots".utf8)
        let retainedSnapshotFiles = try regularFiles(at: snapshotsRoot)
        let snapshotAction = StoreBarrierAction(
            boundary: .afterLeafMutation,
            hit: 1
        ) {
            try barrierFileManager.moveItem(at: snapshotsRoot, to: heldSnapshots)
            try barrierFileManager.createDirectory(
                at: snapshotsRoot,
                withIntermediateDirectories: false
            )
            try snapshotSentinel.write(
                to: snapshotsRoot.appendingPathComponent("unowned.txt"),
                options: .withoutOverwriting
            )
        }
        let snapshotStore = FinalizationIntentStore(
            generationRootURL: root,
            expectedGenerationRootIdentity: expectedRootIdentity,
            authorityBarrier: FinalizationIntentStoreAuthorityBarrier {
                snapshotAction.reach($0)
            }
        )
        do {
            _ = try await snapshotStore.promoteSnapshot(snapshotPrepared)
            XCTFail("persistent snapshots ancestor replacement must fail closed")
        } catch {
            XCTAssertTrue(error is FinalizationIntentStoreError)
        }
        XCTAssertNil(snapshotAction.errorDescription)
        XCTAssertEqual(try regularFiles(at: heldSnapshots), retainedSnapshotFiles)
        XCTAssertFalse(fileManager.fileExists(
            atPath: heldSnapshots.appendingPathComponent(
                snapshotInput.intent.snapshotFinalRelativePath
                    .replacingOccurrences(of: "snapshots/", with: "")
            ).path
        ))
        XCTAssertEqual(
            try Data(contentsOf: snapshotsRoot.appendingPathComponent("unowned.txt")),
            snapshotSentinel
        )
        XCTAssertEqual(
            try regularFiles(at: snapshotsRoot),
            ["unowned.txt": snapshotSentinel]
        )
        XCTAssertFalse(fileManager.fileExists(
            atPath: stagingSnapshotURL(snapshotInput.identifiers, in: harness).path
        ))
        XCTAssertFalse(fileManager.fileExists(
            atPath: intentURL(snapshotInput.identifiers, in: harness).path
        ))
        let duringSnapshotSwap = try domainSnapshot(in: harness)
        XCTAssertEqual(duringSnapshotSwap.sites, before.sites)
        XCTAssertEqual(duringSnapshotSwap.assets, before.assets)
        XCTAssertEqual(duringSnapshotSwap.records, before.records)
        XCTAssertEqual(duringSnapshotSwap.evidence, before.evidence)
        XCTAssertEqual(duringSnapshotSwap.issues, before.issues)
        XCTAssertEqual(duringSnapshotSwap.packets, before.packets)
        XCTAssertEqual(duringSnapshotSwap.reports, before.reports)

        try fileManager.moveItem(at: snapshotsRoot, to: replacementSnapshots)
        try fileManager.moveItem(at: heldSnapshots, to: snapshotsRoot)
        let snapshotRetryPrepared = try await snapshotStore.prepare(
            intent: snapshotInput.intent,
            snapshot: snapshotInput.snapshot
        )
        let snapshotPromoted = try await snapshotStore.promoteSnapshot(
            snapshotRetryPrepared
        )
        try await snapshotStore.rollbackUncommitted(snapshotPromoted)
        XCTAssertEqual(
            try Data(contentsOf: replacementSnapshots.appendingPathComponent("unowned.txt")),
            snapshotSentinel
        )
        XCTAssertFalse(fileManager.fileExists(
            atPath: intentURL(snapshotInput.identifiers, in: harness).path
        ))
        XCTAssertFalse(fileManager.fileExists(
            atPath: stagingSnapshotURL(snapshotInput.identifiers, in: harness).path
        ))
        XCTAssertFalse(fileManager.fileExists(
            atPath: finalSnapshotURL(snapshotInput.identifiers, in: harness).path
        ))
        XCTAssertEqual(try domainSnapshot(in: harness), before)

        let abaInput = try correctionStoreInput(
            in: harness,
            note: "Journal ABA",
            snapshotCreatedAt: Fixture.correctionDate.addingTimeInterval(20)
        )
        let finalizationRoot = harness.applicationSupportURL.appendingPathComponent(
            "FieldEvidenceOperations/finalization",
            isDirectory: true
        )
        let heldFinalization = harness.applicationSupportURL.appendingPathComponent(
            "held-finalization-\(UUID())",
            isDirectory: true
        )
        let replacementFinalization = harness.applicationSupportURL.appendingPathComponent(
            "replacement-finalization-\(UUID())",
            isDirectory: true
        )
        let journalSentinel = Data("unowned-journal".utf8)
        let abaAction = StoreBarrierAction(
            boundary: .afterLeafMutation,
            hit: 2
        ) {
            try barrierFileManager.moveItem(at: finalizationRoot, to: heldFinalization)
            try barrierFileManager.createDirectory(
                at: finalizationRoot,
                withIntermediateDirectories: false
            )
            try journalSentinel.write(
                to: finalizationRoot.appendingPathComponent("unowned.txt"),
                options: .withoutOverwriting
            )
            try barrierFileManager.moveItem(
                at: finalizationRoot,
                to: replacementFinalization
            )
            try barrierFileManager.moveItem(at: heldFinalization, to: finalizationRoot)
        }
        let abaStore = FinalizationIntentStore(
            generationRootURL: root,
            expectedGenerationRootIdentity: expectedRootIdentity,
            authorityBarrier: FinalizationIntentStoreAuthorityBarrier {
                abaAction.reach($0)
            }
        )
        let abaPrepared = try await abaStore.prepare(
            intent: abaInput.intent,
            snapshot: abaInput.snapshot
        )
        XCTAssertNil(abaAction.errorDescription)
        XCTAssertTrue(fileManager.fileExists(
            atPath: intentURL(abaInput.identifiers, in: harness).path
        ))
        XCTAssertTrue(fileManager.fileExists(
            atPath: stagingSnapshotURL(abaInput.identifiers, in: harness).path
        ))
        XCTAssertFalse(fileManager.fileExists(
            atPath: replacementFinalization.appendingPathComponent(
                "\(abaInput.identifiers.mutationID.uuidString.lowercased()).json"
            ).path
        ))
        XCTAssertEqual(
            try Data(contentsOf: replacementFinalization.appendingPathComponent("unowned.txt")),
            journalSentinel
        )
        XCTAssertEqual(
            try regularFiles(at: replacementFinalization),
            ["unowned.txt": journalSentinel]
        )
        let abaPromoted = try await abaStore.promoteSnapshot(abaPrepared)
        try await abaStore.rollbackUncommitted(abaPromoted)
        XCTAssertFalse(fileManager.fileExists(
            atPath: intentURL(abaInput.identifiers, in: harness).path
        ))
        XCTAssertFalse(fileManager.fileExists(
            atPath: stagingSnapshotURL(abaInput.identifiers, in: harness).path
        ))
        XCTAssertFalse(fileManager.fileExists(
            atPath: finalSnapshotURL(abaInput.identifiers, in: harness).path
        ))
        XCTAssertEqual(try domainSnapshot(in: harness), before)
    }
}

extension S4_5CorrectionTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

@MainActor
private struct CorrectionHarness {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let context: ModelContext
    let diagnostics: DiagnosticsStore
    let site: Site
    let asset: Asset
    let originalRecord: WorkflowRecord
    let packet: Packet
    let stableRootID: UUID
    let originalReport: Report
    let coordinator: ReportDeliveryCoordinator
}

private struct RowCounts: Equatable {
    let sites: Int
    let assets: Int
    let records: Int
    let evidence: Int
    let issues: Int
    let packets: Int
    let reports: Int
}

private struct EvidenceFact: Equatable {
    let id: UUID
    let schemaVersion: Int
    let recordID: UUID
    let purposeKey: String
    let relativePath: String
    let mimeType: String
    let byteCount: Int
    let sha256: String
    let createdAt: Date
    let thumbnailRelativePath: String
    let thumbnailByteCount: Int
    let thumbnailSHA256: String
}

private struct SiteFact: Equatable {
    let id: UUID
    let schemaVersion: Int
    let label: String
    let address: String?
    let timeZoneID: String?
    let createdAt: Date
}

private struct AssetFact: Equatable {
    let id: UUID
    let schemaVersion: Int
    let siteID: UUID
    let packID: String
    let packSchemaVersion: Int
    let packContentVersion: Int
    let label: String
    let createdAt: Date
}

private struct DomainSnapshot: Equatable {
    let sites: [SiteFact]
    let assets: [AssetFact]
    let records: [WorkflowRecordPayloadV1]
    let evidence: [EvidenceFact]
    let issues: [IssuePayloadV1]
    let packets: [PacketPayloadV1]
    let reports: [ReportPayloadV1]
    let generationFiles: [String: Data]
}

private struct PreservedAuthority {
    let records: [UUID: WorkflowRecordPayloadV1]
    let reports: [UUID: ReportPayloadV1]
    let evidence: [EvidenceFact]
    let issues: [IssuePayloadV1]
    let packetID: UUID
    let packetStableRootID: UUID
    let packetEvaluationCounted: Bool
    let packetCreatedAt: Date
    let files: [String: Data]
}

private struct UnsafeSentinel {
    let link: URL
    let target: URL
    let data: Data
    let linkType: FileAttributeType
}

private struct CorrectionFailureInjections {
    let store: FinalizationIntentStoreFailureInjection?
    let service: FinalizationServiceFailureInjection?
}

private struct CorrectionStoreInput {
    let identifiers: ReportCorrectionIdentifiers
    let intent: FinalizationIntentV1
    let snapshot: EncodedReportSnapshotV1
}

private final class StoreBarrierAction: @unchecked Sendable {
    private let lock = NSLock()
    private let boundary: FinalizationIntentStoreAuthorityBarrier.Boundary
    private let hit: Int
    private let action: () throws -> Void
    private var seen = 0
    private var storedErrorDescription: String?

    init(
        boundary: FinalizationIntentStoreAuthorityBarrier.Boundary,
        hit: Int,
        action: @escaping () throws -> Void
    ) {
        self.boundary = boundary
        self.hit = hit
        self.action = action
    }

    func reach(_ value: FinalizationIntentStoreAuthorityBarrier.Boundary) {
        lock.lock()
        defer { lock.unlock() }
        guard value == boundary else { return }
        seen += 1
        guard seen == hit else { return }
        do {
            try action()
        } catch {
            storedErrorDescription = String(describing: error)
        }
    }

    var errorDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedErrorDescription
    }
}

private enum CorrectionPrecommitFault: CaseIterable {
    case snapshotWrite
    case snapshotMove
    case snapshotPromotedIntent
    case modelSave

    @MainActor
    func injections() -> CorrectionFailureInjections {
        switch self {
        case .snapshotWrite:
            return CorrectionFailureInjections(
                store: .init(failOnceAt: .snapshotStagingWrite), service: nil
            )
        case .snapshotMove:
            return CorrectionFailureInjections(
                store: .init(failOnceAt: .snapshotPromotionMove), service: nil
            )
        case .snapshotPromotedIntent:
            return CorrectionFailureInjections(
                store: .init(failOnceAt: .intentPhaseWrite(.snapshotPromoted)), service: nil
            )
        case .modelSave:
            return CorrectionFailureInjections(
                store: nil, service: .init(failOnceAt: .modelSave)
            )
        }
    }
}

private enum InvalidCorrectionAuthority: CaseIterable {
    case dirtyUniqueCollisions
    case pending
    case failed
    case noncurrent
    case nonterminal
    case currentRecordCollision
    case sourceReportCollision
    case replacementCollision
    case brokenRevision
    case cyclicReplacement
    case snapshotPath
    case snapshotHash
    case snapshotBytes
    case evidencePath
    case evidenceHash
    case evidenceBytes
    case pdfPath
    case pdfHash
    case pdfBytes
    case evidenceAncestorSymlink
    case evidenceSpecialLeaf
    case pdfAncestorSymlink
    case pdfSpecialLeaf

    var expectsDirtyContext: Bool {
        self == .dirtyUniqueCollisions
    }
}

private enum CorrectionFixtureError: Error {
    case couldNotCreateImage
    case unexpectedSubmission
}

private enum Fixture {
    static let baseDate = Date(timeIntervalSince1970: 1_768_940_000)
    static let correctionDate = Date(timeIntervalSince1970: 1_768_940_100)
    static let sourceApp = SourceAppSnapshotV1(build: "45", version: "1.0")
}

private extension S4_5CorrectionTests {
    @MainActor
    func correctionStoreInput(
        in harness: CorrectionHarness,
        note: String,
        snapshotCreatedAt: Date
    ) throws -> CorrectionStoreInput {
        let identifiers = ReportCorrectionIdentifiers(
            mutationID: UUID(),
            recordID: UUID(),
            reportID: UUID()
        )
        let plan = try ReportCorrectionRule().makePlan(
            source: ReportCorrectionRuleSource(
                currentRecord: recordPayload(harness.originalRecord),
                packet: packetPayload(harness.packet),
                currentReport: reportPayload(harness.originalReport),
                currentSnapshot: snapshot(report: harness.originalReport, in: harness)
            ),
            request: ReportCorrectionRuleRequest(
                note: note,
                snapshotCreatedAt: snapshotCreatedAt,
                sourceApp: Fixture.sourceApp,
                identifiers: identifiers
            )
        )
        let encodedSnapshot = try ReportSnapshotEncoderV1().encode(plan.snapshot)
        let payload = FinalizationPayloadV1(
            issueInsert: nil,
            issueTransition: nil,
            packetAfter: plan.packetAfter,
            packetBefore: plan.packetBefore,
            reportInsert: plan.reportInsert,
            workflowRecordAfter: plan.recordAfter
        )
        let encodedPayload = try FinalizationContractEncoderV1().encodePayload(payload)
        let intent = FinalizationIntentV1(
            completedAt: try XCTUnwrap(plan.recordAfter.completedAt),
            finalizationMutationID: identifiers.mutationID,
            finalizationPayload: payload,
            finalizationPayloadSHA256: encodedPayload.sha256,
            generationID: harness.session.generationID,
            packetID: harness.packet.id,
            phase: .prepared,
            recordID: identifiers.recordID,
            reportID: identifiers.reportID,
            schemaVersion: 1,
            snapshotCreatedAt: plan.snapshot.snapshotCreatedAt,
            snapshotFinalRelativePath: plan.reportInsert.snapshotRelativePath,
            snapshotSHA256: encodedSnapshot.sha256,
            snapshotStagingRelativePath: ".staging/\(plan.reportInsert.snapshotRelativePath)",
            stableRootID: harness.packet.stableRootID
        )
        return CorrectionStoreInput(
            identifiers: identifiers,
            intent: intent,
            snapshot: encodedSnapshot
        )
    }

    @MainActor
    func makeHarness(
        _ label: String,
        substantiveDate: Date = Fixture.baseDate
    ) async throws -> CorrectionHarness {
        let applicationSupport = fileManager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(
                "S4_5CorrectionTests-\(label)-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let session = try StoreGenerationFactory(applicationSupportURL: applicationSupport)
            .openOrBootstrapCurrent()
        let context = session.modelContext
        let diagnostics = DiagnosticsStore(applicationSupportURL: applicationSupport)
        await diagnostics.prepare()
        let site = Site(
            id: UUID(),
            label: "North Campus",
            address: "10 Main",
            timeZoneID: "America/New_York",
            createdAt: substantiveDate.addingTimeInterval(-100)
        )
        let asset = Asset(
            id: UUID(),
            siteID: site.id,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Monument Sign",
            createdAt: substantiveDate.addingTimeInterval(-90)
        )
        context.insert(site)
        context.insert(asset)
        try context.save()

        let runner = CheckRunnerCoordinator(
            modelContext: context,
            signPack: .illuminatedSignV1,
            diagnosticsStore: diagnostics
        )
        runner.configureCapture(generationRootURL: session.generationRootURL)
        let record = try runner.beginCheck(
            assetID: asset.id,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: substantiveDate.addingTimeInterval(-20)
        )
        let wide = try await runner.importCandidate(
            assetID: asset.id,
            sourceData: try makePNG(seed: 41),
            createdAt: substantiveDate.addingTimeInterval(-15)
        )
        _ = try await runner.accept(candidate: wide, assetID: asset.id)
        let close = try await runner.importCandidate(
            assetID: asset.id,
            sourceData: try makePNG(seed: 77),
            createdAt: substantiveDate.addingTimeInterval(-14)
        )
        _ = try await runner.accept(candidate: close, assetID: asset.id)
        let originalIDs = FinalizationIdentifiers(
            mutationID: UUID(),
            packetID: UUID(),
            stableRootID: UUID(),
            reportID: UUID(),
            issueID: UUID()
        )
        let result = try await runner.finalize(
            assetID: asset.id,
            selection: .visibleIssue(labelKey: "dark_section"),
            completedAt: substantiveDate,
            snapshotCreatedAt: substantiveDate.addingTimeInterval(1),
            sourceApp: SourceAppSnapshotV1(build: "440", version: "1.0"),
            identifiers: originalIDs
        )
        let coordinator = try ReportDeliveryCoordinator(
            modelContext: context,
            generationRootURL: session.generationRootURL,
            diagnosticsStore: diagnostics
        )
        guard case .ready = try coordinator.prepareFinalizedReport(id: result.reportID) else {
            throw CorrectionFixtureError.unexpectedSubmission
        }
        let packet = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Packet>()).first { $0.id == originalIDs.packetID }
        )
        let report = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Report>()).first { $0.id == result.reportID }
        )
        return CorrectionHarness(
            applicationSupportURL: applicationSupport,
            session: session,
            context: context,
            diagnostics: diagnostics,
            site: site,
            asset: asset,
            originalRecord: record,
            packet: packet,
            stableRootID: packet.stableRootID,
            originalReport: report,
            coordinator: coordinator
        )
    }

    @MainActor
    func makeCoordinator(
        in harness: CorrectionHarness,
        storeFailure: FinalizationIntentStoreFailureInjection? = nil,
        serviceFailure: FinalizationServiceFailureInjection? = nil,
        renderFailure: ReportRenderFailureInjection? = nil,
        serviceOperationBarrier: FinalizationServiceOperationBarrier? = nil
    ) throws -> ReportDeliveryCoordinator {
        try ReportDeliveryCoordinator(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            diagnosticsStore: harness.diagnostics,
            renderFailureInjection: renderFailure,
            finalizationStoreFailureInjection: storeFailure,
            finalizationServiceFailureInjection: serviceFailure,
            finalizationServiceOperationBarrier: serviceOperationBarrier
        )
    }

    @MainActor
    func readyChain(
        _ result: ReportCorrectionSubmissionResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ReportDeliveryChainValue {
        guard case .ready(let chain) = result else {
            XCTFail("Expected ready correction", file: file, line: line)
            throw CorrectionFixtureError.unexpectedSubmission
        }
        return chain
    }

    @MainActor
    func record(id: UUID, in harness: CorrectionHarness) throws -> WorkflowRecord {
        try XCTUnwrap(
            try harness.context.fetch(FetchDescriptor<WorkflowRecord>()).first {
                $0.id == id
            }
        )
    }

    @MainActor
    func report(id: UUID, in harness: CorrectionHarness) throws -> Report {
        try XCTUnwrap(
            try harness.context.fetch(FetchDescriptor<Report>()).first { $0.id == id }
        )
    }

    @MainActor
    func snapshot(report: Report, in harness: CorrectionHarness) throws -> ReportSnapshotV1 {
        let data = try Data(
            contentsOf: harness.session.generationRootURL.appendingPathComponent(
                report.snapshotRelativePath
            )
        )
        XCTAssertEqual(data.sha256, report.snapshotSHA256)
        return try ReportSnapshotEncoderV1().decode(data)
    }

    func correctedSnapshot(
        from prior: ReportSnapshotV1,
        reportID: UUID,
        recordID: UUID,
        note: String?,
        snapshotCreatedAt: Date,
        sourceApp: SourceAppSnapshotV1
    ) -> ReportSnapshotV1 {
        ReportSnapshotV1(
            acknowledgements: prior.acknowledgements,
            asset: prior.asset,
            couldNotVerify: prior.couldNotVerify,
            disclaimer: prior.disclaimer,
            display: prior.display,
            evidence: prior.evidence,
            evidenceSourceRecordID: prior.evidenceSourceRecordID,
            history: prior.history,
            issues: prior.issues,
            note: note,
            outcome: prior.outcome,
            pack: prior.pack,
            packetID: prior.packetID,
            pdfTemplate: prior.pdfTemplate,
            reportID: reportID,
            site: prior.site,
            snapshotCreatedAt: snapshotCreatedAt,
            snapshotSchemaVersion: prior.snapshotSchemaVersion,
            sourceApp: sourceApp,
            sourceRecordID: recordID,
            stableRootID: prior.stableRootID,
            stage: prior.stage,
            timeContext: prior.timeContext
        )
    }

    @MainActor
    func assertCorrectionRecord(
        _ correction: WorkflowRecord,
        revises prior: WorkflowRecord,
        originalEvidenceOwnerID: UUID,
        note: String?,
        mutationID: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(correction.schemaVersion, 1, file: file, line: line)
        XCTAssertEqual(correction.assetID, prior.assetID, file: file, line: line)
        XCTAssertEqual(correction.packetID, prior.packetID, file: file, line: line)
        XCTAssertEqual(correction.issueID, prior.issueID, file: file, line: line)
        XCTAssertEqual(correction.parentRecordID, prior.parentRecordID, file: file, line: line)
        XCTAssertEqual(
            correction.recordRevisionRootID,
            originalEvidenceOwnerID,
            file: file,
            line: line
        )
        XCTAssertEqual(correction.revisesRecordID, prior.id, file: file, line: line)
        XCTAssertEqual(
            correction.evidenceSourceRecordID,
            originalEvidenceOwnerID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.revisionKind,
            WorkflowRevisionKind.clericalCorrection.rawValue,
            file: file,
            line: line
        )
        XCTAssertEqual(correction.stage, prior.stage, file: file, line: line)
        XCTAssertEqual(correction.state, WorkflowState.completed.rawValue, file: file, line: line)
        XCTAssertNil(correction.draftStepKey, file: file, line: line)
        XCTAssertEqual(correction.startedAt, prior.startedAt, file: file, line: line)
        XCTAssertEqual(correction.completedAt, prior.completedAt, file: file, line: line)
        XCTAssertEqual(correction.observedAtUTC, prior.observedAtUTC, file: file, line: line)
        XCTAssertEqual(correction.timeZoneID, prior.timeZoneID, file: file, line: line)
        XCTAssertEqual(correction.utcOffsetMinutes, prior.utcOffsetMinutes, file: file, line: line)
        XCTAssertEqual(correction.localDate, prior.localDate, file: file, line: line)
        XCTAssertEqual(correction.localTime, prior.localTime, file: file, line: line)
        XCTAssertEqual(
            correction.afterDarkAcknowledgementKey,
            prior.afterDarkAcknowledgementKey,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.afterDarkAcknowledgementCopy,
            prior.afterDarkAcknowledgementCopy,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.afterDarkAcknowledgementVersion,
            prior.afterDarkAcknowledgementVersion,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.afterDarkAcknowledgementAccepted,
            prior.afterDarkAcknowledgementAccepted,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.safePositionAcknowledgementKey,
            prior.safePositionAcknowledgementKey,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.safePositionAcknowledgementCopy,
            prior.safePositionAcknowledgementCopy,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.safePositionAcknowledgementVersion,
            prior.safePositionAcknowledgementVersion,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.safePositionAcknowledgementAccepted,
            prior.safePositionAcknowledgementAccepted,
            file: file,
            line: line
        )
        XCTAssertEqual(correction.packID, prior.packID, file: file, line: line)
        XCTAssertEqual(correction.packSchemaVersion, prior.packSchemaVersion, file: file, line: line)
        XCTAssertEqual(correction.packContentVersion, prior.packContentVersion, file: file, line: line)
        XCTAssertEqual(correction.pdfTemplateID, prior.pdfTemplateID, file: file, line: line)
        XCTAssertEqual(correction.pdfTemplateVersion, prior.pdfTemplateVersion, file: file, line: line)
        XCTAssertEqual(correction.outcomeKey, prior.outcomeKey, file: file, line: line)
        XCTAssertEqual(correction.couldNotVerifyKey, prior.couldNotVerifyKey, file: file, line: line)
        XCTAssertEqual(
            correction.couldNotVerifyDisplaySnapshot,
            prior.couldNotVerifyDisplaySnapshot,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.couldNotVerifyRegistryVersion,
            prior.couldNotVerifyRegistryVersion,
            file: file,
            line: line
        )
        XCTAssertEqual(
            correction.workPerformedLocalDate,
            prior.workPerformedLocalDate,
            file: file,
            line: line
        )
        XCTAssertEqual(correction.workDescription, prior.workDescription, file: file, line: line)
        XCTAssertEqual(correction.note, note, file: file, line: line)
        XCTAssertEqual(correction.finalizationMutationID, mutationID, file: file, line: line)
    }

    @MainActor
    func counts(in harness: CorrectionHarness) throws -> RowCounts {
        RowCounts(
            sites: try harness.context.fetchCount(FetchDescriptor<Site>()),
            assets: try harness.context.fetchCount(FetchDescriptor<Asset>()),
            records: try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()),
            evidence: try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()),
            issues: try harness.context.fetchCount(FetchDescriptor<Issue>()),
            packets: try harness.context.fetchCount(FetchDescriptor<Packet>()),
            reports: try harness.context.fetchCount(FetchDescriptor<Report>())
        )
    }

    @MainActor
    func domainSnapshot(in harness: CorrectionHarness) throws -> DomainSnapshot {
        DomainSnapshot(
            sites: sortedByIDAndValue(
                try harness.context.fetch(FetchDescriptor<Site>()).map(siteFact),
                id: \.id
            ),
            assets: sortedByIDAndValue(
                try harness.context.fetch(FetchDescriptor<Asset>()).map(assetFact),
                id: \.id
            ),
            records: sortedByIDAndValue(
                try harness.context.fetch(FetchDescriptor<WorkflowRecord>()).map(recordPayload),
                id: \.id
            ),
            evidence: sortedByIDAndValue(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>()).map(evidenceFact),
                id: \.id
            ),
            issues: sortedByIDAndValue(
                try harness.context.fetch(FetchDescriptor<Issue>()).map(issuePayload),
                id: \.id
            ),
            packets: sortedByIDAndValue(
                try harness.context.fetch(FetchDescriptor<Packet>()).map(packetPayload),
                id: \.id
            ),
            reports: sortedByIDAndValue(
                try harness.context.fetch(FetchDescriptor<Report>()).map(reportPayload),
                id: \.id
            ),
            generationFiles: try generationFiles(in: harness)
        )
    }

    func sortedByIDAndValue<Value>(
        _ values: [Value],
        id: (Value) -> UUID
    ) -> [Value] {
        values.sorted { left, right in
            let leftID = id(left).uuidString.lowercased()
            let rightID = id(right).uuidString.lowercased()
            if leftID != rightID { return leftID < rightID }
            return String(reflecting: left) < String(reflecting: right)
        }
    }

    @MainActor
    func preservedAuthority(
        recordIDs: [UUID],
        reportIDs: [UUID],
        in harness: CorrectionHarness
    ) throws -> PreservedAuthority {
        let records = try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
        let reports = try harness.context.fetch(FetchDescriptor<Report>())
        let selectedRecords = records.filter { recordIDs.contains($0.id) }
        let selectedReports = reports.filter { reportIDs.contains($0.id) }
        XCTAssertEqual(selectedRecords.count, recordIDs.count)
        XCTAssertEqual(selectedReports.count, reportIDs.count)
        var paths = selectedReports.flatMap {
            [$0.snapshotRelativePath, $0.pdfRelativePath].compactMap { $0 }
        }
        let evidence = try harness.context.fetch(FetchDescriptor<EvidenceFile>())
            .map(evidenceFact).sorted { $0.id.uuidString < $1.id.uuidString }
        let evidenceRows = try harness.context.fetch(FetchDescriptor<EvidenceFile>())
        paths.append(contentsOf: evidenceRows.flatMap { [$0.relativePath, $0.thumbnailRelativePath] })
        var files: [String: Data] = [:]
        for path in Set(paths) {
            files[path] = try Data(
                contentsOf: harness.session.generationRootURL.appendingPathComponent(path)
            )
        }
        return PreservedAuthority(
            records: Dictionary(uniqueKeysWithValues: selectedRecords.map { ($0.id, recordPayload($0)) }),
            reports: Dictionary(uniqueKeysWithValues: selectedReports.map { ($0.id, reportPayload($0)) }),
            evidence: evidence,
            issues: try harness.context.fetch(FetchDescriptor<Issue>())
                .map(issuePayload).sorted { $0.id.uuidString < $1.id.uuidString },
            packetID: harness.packet.id,
            packetStableRootID: harness.packet.stableRootID,
            packetEvaluationCounted: harness.packet.evaluationCounted,
            packetCreatedAt: harness.packet.createdAt,
            files: files
        )
    }

    @MainActor
    func assertPreserved(
        _ expected: PreservedAuthority,
        in harness: CorrectionHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let records = try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
        let reports = try harness.context.fetch(FetchDescriptor<Report>())
        for (id, payload) in expected.records {
            XCTAssertEqual(
                records.filter { $0.id == id }.map(recordPayload),
                [payload],
                file: file,
                line: line
            )
        }
        for (id, payload) in expected.reports {
            XCTAssertEqual(
                reports.filter { $0.id == id }.map(reportPayload),
                [payload],
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<EvidenceFile>())
                .map(evidenceFact).sorted { $0.id.uuidString < $1.id.uuidString },
            expected.evidence,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<Issue>())
                .map(issuePayload).sorted { $0.id.uuidString < $1.id.uuidString },
            expected.issues,
            file: file,
            line: line
        )
        XCTAssertEqual(harness.packet.id, expected.packetID, file: file, line: line)
        XCTAssertEqual(
            harness.packet.stableRootID,
            expected.packetStableRootID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            harness.packet.evaluationCounted,
            expected.packetEvaluationCounted,
            file: file,
            line: line
        )
        XCTAssertEqual(harness.packet.createdAt, expected.packetCreatedAt, file: file, line: line)
        for (path, data) in expected.files {
            XCTAssertEqual(
                try Data(
                    contentsOf: harness.session.generationRootURL.appendingPathComponent(path)
                ),
                data,
                file: file,
                line: line
            )
        }
    }

    func siteFact(_ value: Site) -> SiteFact {
        SiteFact(
            id: value.id,
            schemaVersion: value.schemaVersion,
            label: value.label,
            address: value.address,
            timeZoneID: value.timeZoneID,
            createdAt: value.createdAt
        )
    }

    func assetFact(_ value: Asset) -> AssetFact {
        AssetFact(
            id: value.id,
            schemaVersion: value.schemaVersion,
            siteID: value.siteID,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            label: value.label,
            createdAt: value.createdAt
        )
    }

    func recordPayload(_ value: WorkflowRecord) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
            id: value.id,
            schemaVersion: value.schemaVersion,
            assetID: value.assetID,
            packetID: value.packetID,
            issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind,
            stage: value.stage,
            state: value.state,
            draftStepKey: value.draftStepKey,
            startedAt: value.startedAt,
            completedAt: value.completedAt,
            observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription,
            note: value.note,
            finalizationMutationID: value.finalizationMutationID
        )
    }

    func recordPayload(
        _ value: WorkflowRecordPayloadV1,
        packContentVersion: Int? = nil,
        pdfTemplateVersion: Int? = nil
    ) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
            id: value.id,
            schemaVersion: value.schemaVersion,
            assetID: value.assetID,
            packetID: value.packetID,
            issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind,
            stage: value.stage,
            state: value.state,
            draftStepKey: value.draftStepKey,
            startedAt: value.startedAt,
            completedAt: value.completedAt,
            observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: packContentVersion ?? value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: pdfTemplateVersion ?? value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription,
            note: value.note,
            finalizationMutationID: value.finalizationMutationID
        )
    }

    func packetPayload(_ value: Packet) -> PacketPayloadV1 {
        PacketPayloadV1(
            id: value.id,
            schemaVersion: value.schemaVersion,
            stableRootID: value.stableRootID,
            currentRecordID: value.currentRecordID,
            evaluationCounted: value.evaluationCounted,
            contentDeletedAt: value.contentDeletedAt,
            createdAt: value.createdAt
        )
    }

    func reportPayload(_ value: Report) -> ReportPayloadV1 {
        ReportPayloadV1(
            id: value.id,
            schemaVersion: value.schemaVersion,
            packetID: value.packetID,
            sourceRecordID: value.sourceRecordID,
            snapshotSchemaVersion: value.snapshotSchemaVersion,
            snapshotRelativePath: value.snapshotRelativePath,
            snapshotSHA256: value.snapshotSHA256,
            pdfState: value.pdfState,
            pdfRelativePath: value.pdfRelativePath,
            pdfSHA256: value.pdfSHA256,
            createdAt: value.createdAt,
            replacesReportID: value.replacesReportID
        )
    }

    func evidenceFact(_ value: EvidenceFile) -> EvidenceFact {
        EvidenceFact(
            id: value.id,
            schemaVersion: value.schemaVersion,
            recordID: value.recordID,
            purposeKey: value.purposeKey,
            relativePath: value.relativePath,
            mimeType: value.mimeType,
            byteCount: value.byteCount,
            sha256: value.sha256,
            createdAt: value.createdAt,
            thumbnailRelativePath: value.thumbnailRelativePath,
            thumbnailByteCount: value.thumbnailByteCount,
            thumbnailSHA256: value.thumbnailSHA256
        )
    }

    func issuePayload(_ value: Issue) -> IssuePayloadV1 {
        IssuePayloadV1(
            id: value.id,
            schemaVersion: value.schemaVersion,
            assetID: value.assetID,
            openedByRecordID: value.openedByRecordID,
            labelKey: value.labelKey,
            labelDisplaySnapshot: value.labelDisplaySnapshot,
            status: value.status,
            resolvedByRecordID: value.resolvedByRecordID,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
    }

    @MainActor
    func generationFiles(in harness: CorrectionHarness) throws -> [String: Data] {
        try regularFiles(at: harness.session.generationRootURL)
    }

    func regularFiles(at root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        while let url = enumerator?.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
                continue
            }
            let prefix = root.path + "/"
            let relative = url.path.hasPrefix(prefix)
                ? String(url.path.dropFirst(prefix.count))
                : url.lastPathComponent
            files[relative] = try Data(contentsOf: url)
        }
        return files
    }

    @MainActor
    func apply(
        _ invalid: InvalidCorrectionAuthority,
        to harness: CorrectionHarness
    ) throws -> UnsafeSentinel? {
        switch invalid {
        case .dirtyUniqueCollisions:
            harness.site.label = "Unsaved site label"
            harness.context.insert(Asset(
                id: harness.asset.id,
                siteID: harness.site.id,
                packID: harness.asset.packID,
                packSchemaVersion: harness.asset.packSchemaVersion,
                packContentVersion: harness.asset.packContentVersion,
                label: "Colliding sign",
                createdAt: harness.asset.createdAt
            ))
            harness.context.insert(Packet(
                id: UUID(),
                stableRootID: harness.packet.stableRootID,
                currentRecordID: UUID(),
                evaluationCounted: true,
                contentDeletedAt: nil,
                createdAt: Fixture.baseDate
            ))
            harness.context.insert(Report(
                id: harness.originalReport.id,
                packetID: UUID(),
                sourceRecordID: UUID(),
                snapshotSchemaVersion: 1,
                snapshotRelativePath: "snapshots/collision.json",
                snapshotSHA256: String(repeating: "a", count: 64),
                pdfState: .failed,
                pdfRelativePath: nil,
                pdfSHA256: nil,
                createdAt: Fixture.baseDate,
                replacesReportID: nil
            ))
        case .pending:
            harness.originalReport.pdfState = ReportPDFState.pending.rawValue
            harness.originalReport.pdfRelativePath = nil
            harness.originalReport.pdfSHA256 = nil
            try harness.context.save()
        case .failed:
            harness.originalReport.pdfState = ReportPDFState.failed.rawValue
            harness.originalReport.pdfRelativePath = nil
            harness.originalReport.pdfSHA256 = nil
            try harness.context.save()
        case .noncurrent:
            harness.packet.currentRecordID = UUID()
            try harness.context.save()
        case .nonterminal:
            harness.originalRecord.state = WorkflowState.draft.rawValue
            harness.originalRecord.draftStepKey = WorkflowDraftStep.outcome.rawValue
            try harness.context.save()
        case .currentRecordCollision:
            harness.context.insert(Packet(
                id: UUID(),
                stableRootID: UUID(),
                currentRecordID: harness.originalRecord.id,
                evaluationCounted: true,
                contentDeletedAt: nil,
                createdAt: Fixture.baseDate
            ))
            try harness.context.save()
        case .sourceReportCollision:
            harness.context.insert(Report(
                id: UUID(),
                packetID: UUID(),
                sourceRecordID: harness.originalRecord.id,
                snapshotSchemaVersion: 1,
                snapshotRelativePath: "snapshots/foreign-source.json",
                snapshotSHA256: String(repeating: "a", count: 64),
                pdfState: .failed,
                pdfRelativePath: nil,
                pdfSHA256: nil,
                createdAt: Fixture.baseDate,
                replacesReportID: nil
            ))
            try harness.context.save()
        case .replacementCollision:
            harness.context.insert(Report(
                id: UUID(),
                packetID: UUID(),
                sourceRecordID: UUID(),
                snapshotSchemaVersion: 1,
                snapshotRelativePath: "snapshots/foreign.json",
                snapshotSHA256: String(repeating: "a", count: 64),
                pdfState: .failed,
                pdfRelativePath: nil,
                pdfSHA256: nil,
                createdAt: Fixture.baseDate,
                replacesReportID: harness.originalReport.id
            ))
            try harness.context.save()
        case .brokenRevision:
            harness.originalRecord.revisesRecordID = UUID()
            try harness.context.save()
        case .cyclicReplacement:
            try replaceCurrentReport(in: harness, replaces: harness.originalReport.id)
        case .snapshotPath:
            try replaceCurrentReport(
                in: harness,
                snapshotRelativePath: "../outside.json"
            )
        case .snapshotHash:
            try replaceCurrentReport(
                in: harness,
                snapshotSHA256: String(repeating: "0", count: 64)
            )
        case .snapshotBytes:
            let snapshotURL = harness.session.generationRootURL.appendingPathComponent(
                harness.originalReport.snapshotRelativePath
            )
            var data = try Data(contentsOf: snapshotURL)
            data.append(0x0A)
            try data.write(to: snapshotURL, options: .atomic)
            try replaceCurrentReport(in: harness, snapshotSHA256: data.sha256)
        case .evidencePath:
            let evidence = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>()).first
            )
            evidence.relativePath = "../outside.jpg"
            try harness.context.save()
        case .evidenceHash:
            let evidence = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>()).first
            )
            evidence.sha256 = String(repeating: "0", count: 64)
            try harness.context.save()
        case .evidenceBytes:
            let evidence = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>()).first
            )
            let url = harness.session.generationRootURL.appendingPathComponent(
                evidence.relativePath
            )
            var data = try Data(contentsOf: url)
            data[data.startIndex] ^= 0x01
            try data.write(to: url, options: .atomic)
        case .pdfPath:
            harness.originalReport.pdfRelativePath = "../outside.pdf"
            try harness.context.save()
        case .pdfHash:
            harness.originalReport.pdfSHA256 = String(repeating: "0", count: 64)
            try harness.context.save()
        case .pdfBytes:
            let url = harness.session.generationRootURL.appendingPathComponent(
                try XCTUnwrap(harness.originalReport.pdfRelativePath)
            )
            var data = try Data(contentsOf: url)
            data[data.startIndex] ^= 0x01
            try data.write(to: url, options: .atomic)
        case .evidenceAncestorSymlink:
            let evidence = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>()).first
            )
            return try replaceAncestorWithSymlink(
                relativePath: evidence.relativePath,
                label: "unowned-evidence-ancestor",
                in: harness
            )
        case .evidenceSpecialLeaf:
            let evidence = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>()).first
            )
            return try replaceWithDirectory(
                relativePath: evidence.relativePath,
                label: "retained-evidence",
                in: harness
            )
        case .pdfAncestorSymlink:
            return try replaceAncestorWithSymlink(
                relativePath: try XCTUnwrap(harness.originalReport.pdfRelativePath),
                label: "unowned-pdf-ancestor",
                in: harness
            )
        case .pdfSpecialLeaf:
            return try replaceWithDirectory(
                relativePath: try XCTUnwrap(harness.originalReport.pdfRelativePath),
                label: "retained-pdf",
                in: harness
            )
        }
        return nil
    }

    @MainActor
    func replaceAncestorWithSymlink(
        relativePath: String,
        label: String,
        in harness: CorrectionHarness
    ) throws -> UnsafeSentinel {
        let leaf = harness.session.generationRootURL.appendingPathComponent(relativePath)
        let ancestor = leaf.deletingLastPathComponent()
        let retained = harness.applicationSupportURL.appendingPathComponent(
            "\(label)-\(UUID())",
            isDirectory: true
        )
        let data = try Data(contentsOf: leaf)
        try fileManager.moveItem(at: ancestor, to: retained)
        try fileManager.createSymbolicLink(at: ancestor, withDestinationURL: retained)
        return UnsafeSentinel(
            link: ancestor,
            target: retained.appendingPathComponent(leaf.lastPathComponent),
            data: data,
            linkType: .typeSymbolicLink
        )
    }

    @MainActor
    func replaceWithDirectory(
        relativePath: String,
        label: String,
        in harness: CorrectionHarness
    ) throws -> UnsafeSentinel {
        let leaf = harness.session.generationRootURL.appendingPathComponent(relativePath)
        let retained = harness.applicationSupportURL.appendingPathComponent(
            "\(label)-\(UUID()).bin"
        )
        let data = try Data(contentsOf: leaf)
        try fileManager.moveItem(at: leaf, to: retained)
        try fileManager.createDirectory(at: leaf, withIntermediateDirectories: false)
        return UnsafeSentinel(
            link: leaf,
            target: retained,
            data: data,
            linkType: .typeDirectory
        )
    }

    @MainActor
    func replaceCurrentReport(
        in harness: CorrectionHarness,
        snapshotRelativePath: String? = nil,
        snapshotSHA256: String? = nil,
        replaces replacementID: UUID? = nil
    ) throws {
        let report = try XCTUnwrap(
            try harness.context.fetch(FetchDescriptor<Report>()).first {
                $0.sourceRecordID == harness.packet.currentRecordID
            }
        )
        let payload = reportPayload(report)
        harness.context.delete(report)
        try harness.context.save()
        harness.context.insert(Report(
            id: payload.id,
            packetID: payload.packetID,
            sourceRecordID: payload.sourceRecordID,
            snapshotSchemaVersion: payload.snapshotSchemaVersion,
            snapshotRelativePath: snapshotRelativePath ?? payload.snapshotRelativePath,
            snapshotSHA256: snapshotSHA256 ?? payload.snapshotSHA256,
            pdfState: try XCTUnwrap(ReportPDFState(rawValue: payload.pdfState)),
            pdfRelativePath: payload.pdfRelativePath,
            pdfSHA256: payload.pdfSHA256,
            createdAt: payload.createdAt,
            replacesReportID: replacementID
        ))
        try harness.context.save()
    }

    @MainActor
    func intentURL(
        _ identifiers: ReportCorrectionIdentifiers,
        in harness: CorrectionHarness
    ) -> URL {
        harness.applicationSupportURL.appendingPathComponent(
            "FieldEvidenceOperations/finalization/\(identifiers.mutationID.uuidString.lowercased()).json"
        )
    }

    @MainActor
    func stagingSnapshotURL(
        _ identifiers: ReportCorrectionIdentifiers,
        in harness: CorrectionHarness
    ) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            ".staging/snapshots/\(identifiers.reportID.uuidString.lowercased()).json"
        )
    }

    @MainActor
    func finalSnapshotURL(
        _ identifiers: ReportCorrectionIdentifiers,
        in harness: CorrectionHarness
    ) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            "snapshots/\(identifiers.reportID.uuidString.lowercased()).json"
        )
    }

    func makePNG(seed: UInt8) throws -> Data {
        let width = 48
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = seed &+ UInt8(truncatingIfNeeded: x)
                pixels[index + 1] = seed &+ UInt8(truncatingIfNeeded: y)
                pixels[index + 2] = seed &+ UInt8(truncatingIfNeeded: x ^ y)
                pixels[index + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw CorrectionFixtureError.couldNotCreateImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CorrectionFixtureError.couldNotCreateImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CorrectionFixtureError.couldNotCreateImage
        }
        return output as Data
    }

    @MainActor
    func assertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            // The caller separately proves that authority did not change.
        }
    }
}

private extension Data {
    var sha256: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

extension S4_5CorrectionTests {
    func testV23P03C14CorrectionClosesOnlyWithResolvedRequestAndEvidence() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_245)
        try fixture.resolvedChangeRequest.validateSuccessor(of: fixture.changeRequest)
        try fixture.actions[3].validateSuccessor(of: fixture.actions[2], policy: fixture.policy)
        XCTAssertEqual(fixture.resolvedChangeRequest.state, .resolved)
        XCTAssertEqual(fixture.actions[3].state, .closed)
        XCTAssertEqual(fixture.actions[3].closureEvidence.count, 2)
    }
}

private final class C48PortableReviewS45CorrectionTests: XCTestCase {
    func testC48ExternalResponseDoesNotFinalizeOrRewriteHistoricSnapshot() {
        XCTAssertTrue(C48PortableReviewFinalizationBoundaryV1.externalReviewCannotFinalize)
        XCTAssertTrue(C48PortableReviewReportSnapshotBoundaryV1.externalReviewCannotRewriteHistoricSnapshot)
        XCTAssertTrue(C48PortableReviewWorkflowBoundaryV1.acceptanceDoesNotAutoFinalize)
    }
}
private final class C49WorkResourceCorrectionBoundaryTests: XCTestCase {
    func testCorrectionIsSuccessorNotInPlaceEdit() {
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.appendOnly)
        XCTAssertEqual(WorkResourceDispositionV1.superseded.rawValue, "SUPERSEDED")
    }
}

private final class C50IncumbentAdapterS45CorrectionBoundaryTests: XCTestCase {
    func testCorrectionCannotCreateASecondProductionProfileOrCanonicalDeletionReceipt() {
        XCTAssertTrue(C50IncumbentFileExchangeKernelDeletionEnrollmentV1.ordinaryDeletionPreservesCanonicalHistory)
        XCTAssertEqual(C50IncumbentFileExchangeKernelDeletionEnrollmentV1.canonicalRowRegistrationCount, 0)
        XCTAssertTrue(C50IncumbentFileExchangeWholeSignDeletionServiceBoundaryV1.createsNoAdapterDeletionReceipt)
    }
}

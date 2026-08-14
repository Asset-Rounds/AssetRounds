import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S5_3DifferentIssueTests: XCTestCase {
    private let fileManager = FileManager.default
    private let pack = SignPack.illuminatedSignV1

    @MainActor
    func testDifferentIssueCreatesOneRootResolvesOriginalAndFreezesBothIssues() async throws {
        let harness = try await makeHarness()
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }

        let beforePackets = try harness.context.fetchCount(FetchDescriptor<Packet>())
        let beforeReports = try harness.context.fetchCount(FetchDescriptor<Report>())
        let result = try await harness.runner.finalize(
            assetID: harness.assetID,
            selection: .originalResolvedDifferentIssue(
                labelKey: "physical_damage",
                note: "New damage remains visible."
            ),
            completedAt: harness.completedAt,
            snapshotCreatedAt: harness.completedAt,
            sourceApp: SourceAppSnapshotV1(build: "1", version: "1")
        )

        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), beforePackets + 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), beforeReports + 1)
        let original = try onlyIssue(id: harness.issueID, context: harness.context)
        XCTAssertEqual(original.status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(original.resolvedByRecordID, result.recordID)
        XCTAssertEqual(original.updatedAt, harness.completedAt)
        let newIssueID = try XCTUnwrap(result.newIssueID)
        let inserted = try onlyIssue(id: newIssueID, context: harness.context)
        XCTAssertEqual(inserted.assetID, harness.assetID)
        XCTAssertEqual(inserted.openedByRecordID, result.recordID)
        XCTAssertEqual(inserted.labelKey, "physical_damage")
        XCTAssertEqual(inserted.labelDisplaySnapshot, "Visible physical damage")
        XCTAssertEqual(inserted.status, IssueStatus.open.rawValue)
        XCTAssertNil(inserted.resolvedByRecordID)
        XCTAssertEqual(inserted.createdAt, harness.completedAt)
        XCTAssertEqual(inserted.updatedAt, harness.completedAt)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 2)
        let workCoordinator = try WorkCoordinator(
            modelContext: harness.context,
            signPack: pack,
            generationRootURL: harness.generationRootURL,
            checkRunnerCoordinator: harness.runner
        )
        let activeIssue = try await workCoordinator.activeIssue(assetID: harness.assetID)
        XCTAssertEqual(activeIssue?.id, newIssueID)
        XCTAssertEqual(activeIssue?.status, .open)
        XCTAssertTrue(activeIssue?.canRecordWork == true)
        let record = try onlyRecord(id: result.recordID, context: harness.context)
        XCTAssertEqual(record.stage, WorkflowStage.recheck.rawValue)
        XCTAssertEqual(record.parentRecordID, harness.workRecordID)
        XCTAssertEqual(record.issueID, harness.issueID)
        XCTAssertEqual(record.outcomeKey, "original_resolved_different_issue")
        XCTAssertEqual(record.note, "New damage remains visible.")
        XCTAssertEqual(record.packetID, result.packetID)
        XCTAssertNil(record.workPerformedLocalDate)
        XCTAssertNil(record.workDescription)

        let snapshotData = try ReportPDFAnchoredFile.readRegularFile(
            at: harness.generationRootURL.appendingPathComponent(result.snapshotRelativePath),
            within: harness.generationRootURL,
            rootIdentity: try ReportPDFAnchoredFile.rootIdentity(at: harness.generationRootURL)
        )
        let snapshot = try ReportSnapshotEncoderV1().decode(snapshotData)
        XCTAssertEqual(snapshot.stage, "recheck")
        XCTAssertEqual(snapshot.outcome, "original_resolved_different_issue")
        XCTAssertEqual(snapshot.history.map(\.recordID), [harness.openingRecordID, harness.workRecordID])
        XCTAssertEqual(snapshot.evidence.prefix(2).map(\.recordID), [result.recordID, result.recordID])
        XCTAssertEqual(snapshot.issues.count, 2)
        XCTAssertEqual(snapshot.issues[0].status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(snapshot.issues[0].resolvedByRecordID, result.recordID)
        XCTAssertEqual(snapshot.issues[1].issueID, newIssueID)
        XCTAssertEqual(snapshot.issues[1].key, "physical_damage")
        XCTAssertEqual(snapshot.issues[1].status, IssueStatus.open.rawValue)
        XCTAssertNil(snapshot.issues[1].resolvedByRecordID)
        let counters = await harness.diagnostics.snapshot()
        XCTAssertEqual(counters.reportSaved, 1)
        XCTAssertEqual(counters.recheckCompleted, 1)
    }

    @MainActor
    func testSameIdentifierReplayReturnsSameTwoIssueAuthorityWithoutAnotherRoot() async throws {
        let harness = try await makeHarness()
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let identifiers = FinalizationIdentifiers(
            mutationID: UUID(),
            packetID: UUID(),
            stableRootID: UUID(),
            reportID: UUID(),
            issueID: harness.issueID,
            newIssueID: UUID()
        )
        let selection = CheckOutcomeSelection.originalResolvedDifferentIssue(
            labelKey: "color_mismatch",
            note: nil
        )
        let sourceApp = SourceAppSnapshotV1(build: "1", version: "1")

        let result = try await harness.runner.finalize(
            assetID: harness.assetID,
            selection: selection,
            completedAt: harness.completedAt,
            snapshotCreatedAt: harness.completedAt,
            sourceApp: sourceApp,
            identifiers: identifiers
        )
        let coldRunner = CheckRunnerCoordinator(
            modelContext: harness.context,
            signPack: pack,
            diagnosticsStore: harness.diagnostics
        )
        coldRunner.configureCapture(generationRootURL: harness.generationRootURL)
        let replay = try await coldRunner.finalize(
            assetID: harness.assetID,
            selection: selection,
            completedAt: harness.completedAt,
            snapshotCreatedAt: harness.completedAt,
            sourceApp: sourceApp,
            identifiers: identifiers
        )
        XCTAssertEqual(result, replay)
        XCTAssertEqual(result.newIssueID, identifiers.newIssueID)
        let original = try onlyIssue(id: harness.issueID, context: harness.context)
        XCTAssertEqual(original.status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(original.resolvedByRecordID, result.recordID)
        let inserted = try onlyIssue(
            id: try XCTUnwrap(identifiers.newIssueID),
            context: harness.context
        )
        XCTAssertEqual(inserted.labelKey, "color_mismatch")
        XCTAssertEqual(inserted.status, IssueStatus.open.rawValue)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<Issue>()).count, 2)
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
                .filter { $0.finalizationMutationID == identifiers.mutationID }.count,
            1
        )
        let counters = await harness.diagnostics.snapshot()
        XCTAssertEqual(counters.reportSaved, 1)
        XCTAssertEqual(counters.recheckCompleted, 1)
    }

    func testPureRuleCreatesExactTwoIssuePlanAndRejectsUnknownLabelOrStaleIssue() throws {
        let fixture = ruleFixture()
        let valid = try DifferentIssueOutcomeRule.makePlan(fixture.input)
        XCTAssertEqual(valid.originalIssueAfter.status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(valid.originalIssueAfter.resolvedByRecordID, fixture.input.draft.id)
        XCTAssertEqual(valid.newIssue.id, fixture.input.newIssueID)
        XCTAssertEqual(valid.newIssue.openedByRecordID, fixture.input.draft.id)
        XCTAssertEqual(valid.newIssue.status, IssueStatus.open.rawValue)

        XCTAssertThrowsError(try DifferentIssueOutcomeRule.makePlan(DifferentIssueOutcomeRuleInput(
            draft: fixture.input.draft,
            parent: fixture.input.parent,
            originalIssue: fixture.input.originalIssue,
            outcomeKey: fixture.input.outcomeKey,
            newIssueID: fixture.input.newIssueID,
            newIssueLabelKey: "unknown_label",
            newIssueLabelDisplaySnapshot: "Unknown",
            note: fixture.input.note,
            completedAt: fixture.input.completedAt,
            mutationID: fixture.input.mutationID,
            packetID: fixture.input.packetID
        )))
        var wrongIssue = fixture.input.originalIssue
        wrongIssue = IssuePayloadV1(
            id: wrongIssue.id, schemaVersion: wrongIssue.schemaVersion,
            assetID: wrongIssue.assetID, openedByRecordID: wrongIssue.openedByRecordID,
            labelKey: wrongIssue.labelKey,
            labelDisplaySnapshot: wrongIssue.labelDisplaySnapshot,
            status: IssueStatus.open.rawValue, resolvedByRecordID: nil,
            createdAt: wrongIssue.createdAt, updatedAt: wrongIssue.updatedAt
        )
        XCTAssertThrowsError(try DifferentIssueOutcomeRule.makePlan(DifferentIssueOutcomeRuleInput(
            draft: fixture.input.draft, parent: fixture.input.parent,
            originalIssue: wrongIssue, outcomeKey: fixture.input.outcomeKey,
            newIssueID: fixture.input.newIssueID,
            newIssueLabelKey: fixture.input.newIssueLabelKey,
            newIssueLabelDisplaySnapshot: fixture.input.newIssueLabelDisplaySnapshot,
            note: fixture.input.note, completedAt: fixture.input.completedAt,
            mutationID: fixture.input.mutationID, packetID: fixture.input.packetID
        )))
    }

    @MainActor
    func testDirtyContextAndStaleIssueFailClosedWithoutPartialAuthority() async throws {
        let harness = try await makeHarness()
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let issue = try onlyIssue(id: harness.issueID, context: harness.context)
        issue.status = IssueStatus.open.rawValue
        await XCTAssertThrowsErrorAsync {
            _ = try await harness.runner.finalize(
                assetID: harness.assetID,
                selection: .originalResolvedDifferentIssue(
                    labelKey: "physical_damage",
                    note: nil
                ),
                completedAt: harness.completedAt,
                snapshotCreatedAt: harness.completedAt,
                sourceApp: SourceAppSnapshotV1(build: "1", version: "1")
            )
        }
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
                .filter { $0.stage == WorkflowStage.recheck.rawValue
                    && $0.state == WorkflowState.completed.rawValue }.count,
            0
        )
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        harness.context.rollback()
    }

    @MainActor
    func testExistingIssueOpenedByDraftCollisionFailsBeforeAnyAuthorityMutation() async throws {
        let harness = try await makeHarness()
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let records = try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
        let draft = try XCTUnwrap(records.first {
            $0.stage == WorkflowStage.recheck.rawValue
                && $0.state == WorkflowState.draft.rawValue
        })
        harness.context.insert(Issue(
            id: UUID(),
            assetID: harness.assetID,
            openedByRecordID: draft.id,
            labelKey: "physical_damage",
            labelDisplaySnapshot: "Visible physical damage",
            status: .resolved,
            resolvedByRecordID: draft.id,
            createdAt: harness.completedAt,
            updatedAt: harness.completedAt
        ))
        try harness.context.save()

        await XCTAssertThrowsErrorAsync {
            try await harness.runner.finalize(
                assetID: harness.assetID,
                selection: .originalResolvedDifferentIssue(
                    labelKey: "physical_damage",
                    note: nil
                ),
                completedAt: harness.completedAt,
                snapshotCreatedAt: harness.completedAt,
                sourceApp: SourceAppSnapshotV1(build: "1", version: "1")
            )
        }
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertEqual(draft.state, WorkflowState.draft.rawValue)
        XCTAssertNil(draft.packetID)
        XCTAssertNil(draft.finalizationMutationID)
    }

    @MainActor
    func testModelSaveFailureRestoresBothIssueSidesAndSameIdentifiersRetryOnce() async throws {
        let harness = try await makeHarness(
            serviceFailure: FinalizationServiceFailureInjection(failOnceAt: .modelSave)
        )
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let identifiers = FinalizationIdentifiers(
            mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
            reportID: UUID(), issueID: harness.issueID, newIssueID: UUID()
        )
        let selection = CheckOutcomeSelection.originalResolvedDifferentIssue(
            labelKey: "physical_damage",
            note: nil
        )
        let sourceApp = SourceAppSnapshotV1(build: "1", version: "1")

        await XCTAssertThrowsErrorAsync {
            try await harness.runner.finalize(
                assetID: harness.assetID,
                selection: selection,
                completedAt: harness.completedAt,
                snapshotCreatedAt: harness.completedAt,
                sourceApp: sourceApp,
                identifiers: identifiers
            )
        }
        let originalBeforeRetry = try onlyIssue(
            id: harness.issueID,
            context: harness.context
        )
        XCTAssertEqual(originalBeforeRetry.status, IssueStatus.recheckDue.rawValue)
        XCTAssertNil(originalBeforeRetry.resolvedByRecordID)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        let recordsAfterFailure = try harness.context.fetch(
            FetchDescriptor<WorkflowRecord>()
        )
        let draft = recordsAfterFailure.first {
            $0.stage == WorkflowStage.recheck.rawValue
                && $0.state == WorkflowState.draft.rawValue
        }
        XCTAssertNotNil(draft)
        let failedCounters = await harness.diagnostics.snapshot()
        XCTAssertEqual(failedCounters.reportSaved, 0)
        XCTAssertEqual(failedCounters.recheckCompleted, 0)

        let retry = try await harness.runner.finalize(
            assetID: harness.assetID,
            selection: selection,
            completedAt: harness.completedAt,
            snapshotCreatedAt: harness.completedAt,
            sourceApp: sourceApp,
            identifiers: identifiers
        )
        XCTAssertEqual(retry.newIssueID, identifiers.newIssueID)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 2)
    }

    @MainActor
    func testCommittedRecheckJournalRecoversWithoutIssueDriftOrDuplicateRoot() async throws {
        let harness = try await makeHarness(
            storeFailure: FinalizationIntentStoreFailureInjection(
                failOnceAt: .intentPhaseWrite(.databaseCommitted)
            )
        )
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let identifiers = FinalizationIdentifiers(
            mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
            reportID: UUID(), issueID: harness.issueID, newIssueID: UUID()
        )

        await XCTAssertThrowsErrorAsync {
            try await harness.runner.finalize(
                assetID: harness.assetID,
                selection: .originalResolvedDifferentIssue(
                    labelKey: "physical_damage",
                    note: nil
                ),
                completedAt: harness.completedAt,
                snapshotCreatedAt: harness.completedAt,
                sourceApp: SourceAppSnapshotV1(build: "1", version: "1"),
                identifiers: identifiers
            )
        }
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 2)

        let summary = try await FinalizationRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.generationRootURL
        ).reconcile()
        XCTAssertEqual(summary.completedRecordIDs.count, 1)
        XCTAssertTrue(summary.recoveredDraftRecordIDs.isEmpty)
        let issue = try onlyIssue(id: harness.issueID, context: harness.context)
        XCTAssertEqual(issue.status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(issue.resolvedByRecordID, summary.completedRecordIDs[0])
        let inserted = try onlyIssue(
            id: try XCTUnwrap(identifiers.newIssueID),
            context: harness.context
        )
        XCTAssertEqual(inserted.openedByRecordID, summary.completedRecordIDs[0])
        XCTAssertEqual(inserted.status, IssueStatus.open.rawValue)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 2)
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
                $0.finalizationMutationID == identifiers.mutationID
            }.count,
            1
        )
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 2)
    }

    private struct Harness {
        let applicationSupportURL: URL
        let session: StoreGenerationSession
        let generationRootURL: URL
        let context: ModelContext
        let runner: CheckRunnerCoordinator
        let diagnostics: DiagnosticsStore
        let assetID: UUID
        let issueID: UUID
        let openingRecordID: UUID
        let workRecordID: UUID
        let completedAt: Date
    }

    @MainActor
    private func makeHarness(
        storeFailure: FinalizationIntentStoreFailureInjection? = nil,
        serviceFailure: FinalizationServiceFailureInjection? = nil
    ) async throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent(
            "S5_3DifferentIssueTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(
            applicationSupportURL: support
        ).openOrBootstrapCurrent()
        let context = session.modelContext
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        let siteID = UUID()
        let assetID = UUID()
        let issueID = UUID()
        let openingID = UUID()
        let workID = UUID()
        let openingPacketID = UUID()
        let observedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let openingCompleted = observedAt.addingTimeInterval(60)
        let workStarted = openingCompleted.addingTimeInterval(60)
        let workCompleted = workStarted.addingTimeInterval(30)
        let recheckObserved = workCompleted.addingTimeInterval(60)
        let recheckCompleted = recheckObserved.addingTimeInterval(60)
        let frozen = try TimeContextRule.freeze(
            observedAtUTC: observedAt,
            confirmedTimeZoneID: "America/New_York"
        )
        context.insert(Site(
            id: siteID, label: "North Campus", address: "10 Main Street",
            timeZoneID: "America/New_York", createdAt: observedAt.addingTimeInterval(-120)
        ))
        context.insert(Asset(
            id: assetID, siteID: siteID,
            packID: pack.packID, packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            label: "Monument Sign", createdAt: observedAt.addingTimeInterval(-100)
        ))
        let opening = WorkflowRecord(
            id: openingID, assetID: assetID, packetID: openingPacketID,
            issueID: issueID, parentRecordID: nil,
            recordRevisionRootID: openingID, revisesRecordID: nil,
            evidenceSourceRecordID: nil, revisionKind: .original,
            stage: .check, state: .completed, draftStepKey: nil,
            startedAt: observedAt, completedAt: openingCompleted,
            observedAtUTC: frozen.observedAtUTC, timeZoneID: frozen.timeZoneID,
            utcOffsetMinutes: frozen.utcOffsetMinutes,
            localDate: frozen.localDate, localTime: frozen.localTime,
            afterDarkAcknowledgementKey: pack.acknowledgements[0].key,
            afterDarkAcknowledgementCopy: pack.acknowledgements[0].copy,
            afterDarkAcknowledgementVersion: pack.acknowledgements[0].version,
            afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: pack.acknowledgements[1].key,
            safePositionAcknowledgementCopy: pack.acknowledgements[1].copy,
            safePositionAcknowledgementVersion: pack.acknowledgements[1].version,
            safePositionAcknowledgementAccepted: true,
            packID: pack.packID, packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1,
            outcomeKey: "visible_issue", couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil, note: nil,
            finalizationMutationID: UUID()
        )
        let work = WorkflowRecord(
            id: workID, assetID: assetID, packetID: nil, issueID: issueID,
            parentRecordID: openingID, recordRevisionRootID: workID,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: .original, stage: .work, state: .completed,
            draftStepKey: nil, startedAt: workStarted, completedAt: workCompleted,
            observedAtUTC: nil, timeZoneID: nil, utcOffsetMinutes: nil,
            localDate: nil, localTime: nil,
            afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: nil,
            packID: pack.packID, packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1,
            outcomeKey: "work_recorded", couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: "2026-08-13",
            workDescription: "Replaced failed power supply", note: "Work saved.",
            finalizationMutationID: UUID()
        )
        context.insert(opening)
        context.insert(work)
        context.insert(Issue(
            id: issueID, assetID: assetID, openedByRecordID: openingID,
            labelKey: "dark_section", labelDisplaySnapshot: "Section appears dark",
            status: .recheckDue, resolvedByRecordID: nil,
            createdAt: openingCompleted, updatedAt: workCompleted
        ))
        context.insert(Packet(
            id: openingPacketID, stableRootID: UUID(), currentRecordID: openingID,
            evaluationCounted: true, contentDeletedAt: nil, createdAt: openingCompleted
        ))
        context.insert(Report(
            id: UUID(), packetID: openingPacketID, sourceRecordID: openingID,
            snapshotSchemaVersion: 1, snapshotRelativePath: "snapshots/opening.json",
            snapshotSHA256: String(repeating: "a", count: 64), pdfState: .pending,
            pdfRelativePath: nil, pdfSHA256: nil, createdAt: openingCompleted,
            replacesReportID: nil
        ))
        let store = EvidenceBundleStore(generationRootURL: session.generationRootURL)
        context.insert(try await makeEvidence(
            id: UUID(), recordID: openingID, purposeKey: "wide_context",
            source: try makePNG(width: 80, height: 60, seed: 10),
            createdAt: observedAt.addingTimeInterval(10), store: store
        ))
        context.insert(try await makeEvidence(
            id: UUID(), recordID: openingID, purposeKey: "close_detail",
            source: try makePNG(width: 72, height: 72, seed: 20),
            createdAt: observedAt.addingTimeInterval(20), store: store
        ))
        context.insert(try await makeEvidence(
            id: UUID(), recordID: workID, purposeKey: "work_context",
            source: try makePNG(width: 88, height: 66, seed: 30),
            createdAt: workStarted.addingTimeInterval(10), store: store
        ))
        try context.save()
        let runner = CheckRunnerCoordinator(
            modelContext: context,
            signPack: pack,
            diagnosticsStore: diagnostics,
            finalizationStoreFailureInjection: storeFailure,
            finalizationServiceFailureInjection: serviceFailure
        )
        let draft = try runner.beginOrResumeDraft(BeginDraftSubmission(
            assetID: assetID, requestedStage: .recheck, issueID: issueID,
            observedAtUTC: recheckObserved,
            confirmedTimeZoneID: "America/New_York",
            afterDarkAccepted: true, safePositionAccepted: true
        ))
        context.insert(try await makeEvidence(
            id: UUID(), recordID: draft.id, purposeKey: "wide_context",
            source: try makePNG(width: 96, height: 72, seed: 40),
            createdAt: recheckObserved.addingTimeInterval(10), store: store
        ))
        context.insert(try await makeEvidence(
            id: UUID(), recordID: draft.id, purposeKey: "close_detail",
            source: try makePNG(width: 84, height: 84, seed: 50),
            createdAt: recheckObserved.addingTimeInterval(20), store: store
        ))
        draft.draftStepKey = WorkflowDraftStep.outcome.rawValue
        try context.save()
        runner.configureCapture(generationRootURL: session.generationRootURL)
        return Harness(
            applicationSupportURL: support,
            session: session,
            generationRootURL: session.generationRootURL,
            context: context, runner: runner, diagnostics: diagnostics,
            assetID: assetID, issueID: issueID,
            openingRecordID: openingID, workRecordID: workID,
            completedAt: recheckCompleted
        )
    }

    @MainActor
    private func makeEvidence(
        id: UUID,
        recordID: UUID,
        purposeKey: String,
        source: Data,
        createdAt: Date,
        store: EvidenceBundleStore
    ) async throws -> EvidenceFile {
        let normalized = try MediaNormalizerV1().normalize(source)
        let staged = try await store.stage(evidenceID: id, normalized: normalized)
        let promoted = try await store.promote(staged)
        return EvidenceFile(
            id: id, recordID: recordID, purposeKey: purposeKey,
            relativePath: promoted.originalRelativePath, mimeType: "image/jpeg",
            byteCount: promoted.originalByteCount, sha256: promoted.originalSHA256,
            createdAt: createdAt,
            thumbnailRelativePath: promoted.thumbnailRelativePath,
            thumbnailByteCount: promoted.thumbnailByteCount,
            thumbnailSHA256: promoted.thumbnailSHA256
        )
    }

    private func onlyIssue(id: UUID, context: ModelContext) throws -> Issue {
        let values = try context.fetch(FetchDescriptor<Issue>()).filter { $0.id == id }
        XCTAssertEqual(values.count, 1)
        return try XCTUnwrap(values.first)
    }

    private func onlyRecord(id: UUID, context: ModelContext) throws -> WorkflowRecord {
        let values = try context.fetch(FetchDescriptor<WorkflowRecord>()).filter { $0.id == id }
        XCTAssertEqual(values.count, 1)
        return try XCTUnwrap(values.first)
    }

    private func ruleFixture() -> (input: DifferentIssueOutcomeRuleInput, issueID: UUID) {
        let assetID = UUID()
        let issueID = UUID()
        let openingID = UUID()
        let parentID = UUID()
        let draftID = UUID()
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let parentCompleted = started.addingTimeInterval(-60)
        let frozen = try! TimeContextRule.freeze(
            observedAtUTC: started,
            confirmedTimeZoneID: "America/New_York"
        )
        let draft = WorkflowRecordPayloadV1(
            id: draftID, schemaVersion: 1, assetID: assetID, packetID: nil,
            issueID: issueID, parentRecordID: parentID,
            recordRevisionRootID: draftID, revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: WorkflowRevisionKind.original.rawValue,
            stage: WorkflowStage.recheck.rawValue,
            state: WorkflowState.draft.rawValue,
            draftStepKey: WorkflowDraftStep.outcome.rawValue,
            startedAt: started, completedAt: nil,
            observedAtUTC: frozen.observedAtUTC, timeZoneID: frozen.timeZoneID,
            utcOffsetMinutes: frozen.utcOffsetMinutes,
            localDate: frozen.localDate, localTime: frozen.localTime,
            afterDarkAcknowledgementKey: pack.acknowledgements[0].key,
            afterDarkAcknowledgementCopy: pack.acknowledgements[0].copy,
            afterDarkAcknowledgementVersion: pack.acknowledgements[0].version,
            afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: pack.acknowledgements[1].key,
            safePositionAcknowledgementCopy: pack.acknowledgements[1].copy,
            safePositionAcknowledgementVersion: pack.acknowledgements[1].version,
            safePositionAcknowledgementAccepted: true,
            packID: pack.packID, packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1,
            outcomeKey: nil, couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil,
            note: nil, finalizationMutationID: nil
        )
        let parent = WorkflowRecordPayloadV1(
            id: parentID, schemaVersion: 1, assetID: assetID, packetID: nil,
            issueID: issueID, parentRecordID: openingID,
            recordRevisionRootID: parentID, revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: WorkflowRevisionKind.original.rawValue,
            stage: WorkflowStage.work.rawValue,
            state: WorkflowState.completed.rawValue, draftStepKey: nil,
            startedAt: parentCompleted.addingTimeInterval(-30), completedAt: parentCompleted,
            observedAtUTC: nil, timeZoneID: nil, utcOffsetMinutes: nil,
            localDate: nil, localTime: nil,
            afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: nil,
            packID: pack.packID, packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1,
            outcomeKey: "work_recorded", couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: "2026-08-13", workDescription: "Replaced supply",
            note: nil, finalizationMutationID: UUID()
        )
        return (DifferentIssueOutcomeRuleInput(
            draft: draft, parent: parent,
            originalIssue: IssuePayloadV1(
                id: issueID, schemaVersion: 1, assetID: assetID,
                openedByRecordID: openingID, labelKey: "dark_section",
                labelDisplaySnapshot: "Section appears dark",
                status: IssueStatus.recheckDue.rawValue, resolvedByRecordID: nil,
                createdAt: parentCompleted.addingTimeInterval(-120),
                updatedAt: parentCompleted
            ),
            outcomeKey: "original_resolved_different_issue",
            newIssueID: UUID(),
            newIssueLabelKey: "physical_damage",
            newIssueLabelDisplaySnapshot: "Visible physical damage",
            note: nil,
            completedAt: started.addingTimeInterval(60),
            mutationID: UUID(), packetID: UUID()
        ), issueID)
    }

    private func makePNG(width: Int, height: Int, seed: UInt8) throws -> Data {
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
              let image = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
              ),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                destinationData,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw FixtureError.imageEncoding
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.imageEncoding
        }
        return destinationData as Data
    }

    private enum FixtureError: Error { case imageEncoding }
}

private extension XCTestCase {
    @MainActor
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected async expression to throw", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}

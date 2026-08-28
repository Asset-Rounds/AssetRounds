import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S5_4RecheckCNVTests: XCTestCase {
    private let fileManager = FileManager.default
    private let pack = SignPack.illuminatedSignV1

    @MainActor
    func testPartialConditionsChangedCreatesOneIncompleteRootAndPreservesIssue() async throws {
        let harness = try await makeHarness(acceptsWide: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let issueBefore = issuePayload(try onlyIssue(id: harness.issueID, context: harness.context))
        let packetCount = try harness.context.fetchCount(FetchDescriptor<Packet>())
        let reportCount = try harness.context.fetchCount(FetchDescriptor<Report>())
        let selection = CheckOutcomeSelection.couldNotVerify(
            reasonKey: "conditions_changed",
            note: "The close view changed before capture."
        )

        let review = try harness.runner.prepareReview(
            assetID: harness.assetID,
            selection: selection
        )
        XCTAssertEqual(review.outcomeKey, "could_not_verify")
        XCTAssertEqual(review.couldNotVerifyReasonDisplay, "Conditions changed")
        XCTAssertNotNil(review.wideEvidence)
        XCTAssertNil(review.closeEvidence)
        XCTAssertEqual(review.missingPurposeDisplays, ["Close view"])

        let result = try await harness.runner.finalize(
            assetID: harness.assetID,
            selection: selection,
            completedAt: harness.completedAt,
            snapshotCreatedAt: harness.completedAt,
            sourceApp: SourceAppSnapshotV1(build: "1", version: "1")
        )

        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), packetCount + 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), reportCount + 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 1)
        let packet = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<Packet>()).first { $0.id == result.packetID }
        )
        XCTAssertEqual(packet.currentRecordID, result.recordID)
        XCTAssertTrue(packet.evaluationCounted)
        let report = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<Report>()).first { $0.id == result.reportID }
        )
        XCTAssertEqual(report.packetID, result.packetID)
        XCTAssertEqual(report.sourceRecordID, result.recordID)
        XCTAssertEqual(report.pdfState, ReportPDFState.pending.rawValue)
        XCTAssertEqual(
            issuePayload(try onlyIssue(id: harness.issueID, context: harness.context)),
            issueBefore
        )
        let record = try onlyRecord(id: result.recordID, context: harness.context)
        XCTAssertEqual(record.stage, WorkflowStage.recheck.rawValue)
        XCTAssertEqual(record.state, WorkflowState.completed.rawValue)
        XCTAssertEqual(record.parentRecordID, harness.workRecordID)
        XCTAssertEqual(record.issueID, harness.issueID)
        XCTAssertEqual(record.outcomeKey, "could_not_verify")
        XCTAssertEqual(record.couldNotVerifyKey, "conditions_changed")
        XCTAssertEqual(record.couldNotVerifyDisplaySnapshot, "Conditions changed")
        XCTAssertEqual(record.couldNotVerifyRegistryVersion, "cnv.reason.en-US.v1")
        XCTAssertEqual(record.note, "The close view changed before capture.")

        let snapshot = try snapshot(for: result, harness: harness)
        XCTAssertEqual(snapshot.stage, "recheck")
        XCTAssertEqual(snapshot.outcome, "could_not_verify")
        XCTAssertEqual(snapshot.couldNotVerify?.key, "conditions_changed")
        XCTAssertEqual(snapshot.couldNotVerify?.display, "Conditions changed")
        XCTAssertEqual(snapshot.couldNotVerify?.registryVersion, "cnv.reason.en-US.v1")
        XCTAssertEqual(snapshot.evidence.prefix(1).map(\.purposeKey), ["wide_context"])
        XCTAssertEqual(snapshot.evidence.prefix(1).map(\.recordID), [result.recordID])
        XCTAssertEqual(
            snapshot.evidence.dropFirst().map(\.recordID),
            [harness.openingRecordID, harness.openingRecordID, harness.workRecordID]
        )
        XCTAssertEqual(snapshot.history.map(\.recordID), [harness.openingRecordID, harness.workRecordID])
        XCTAssertEqual(snapshot.issues.count, 1)
        XCTAssertEqual(snapshot.issues[0].issueID, harness.issueID)
        XCTAssertEqual(snapshot.issues[0].status, IssueStatus.recheckDue.rawValue)
        XCTAssertNil(snapshot.issues[0].resolvedByRecordID)
        let counters = await harness.diagnostics.snapshot()
        XCTAssertEqual(counters.reportSaved, 1)
        XCTAssertEqual(counters.recheckCompleted, 1)
    }

    @MainActor
    func testZeroEvidenceUnsafeToContinueReplaysWithoutIssueDriftOrDuplicateRoot() async throws {
        let harness = try await makeHarness(acceptsWide: false)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let issueBefore = issuePayload(try onlyIssue(id: harness.issueID, context: harness.context))
        let identifiers = FinalizationIdentifiers(
            mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
            reportID: UUID(), issueID: harness.issueID
        )
        let selection = CheckOutcomeSelection.couldNotVerify(
            reasonKey: "unsafe_to_continue",
            note: nil
        )
        let sourceApp = SourceAppSnapshotV1(build: "1", version: "1")

        let review = try harness.runner.prepareReview(assetID: harness.assetID, selection: selection)
        XCTAssertNil(review.wideEvidence)
        XCTAssertNil(review.closeEvidence)
        XCTAssertEqual(review.missingPurposeDisplays, ["Wide view", "Close view"])
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
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 1)
        XCTAssertEqual(
            issuePayload(try onlyIssue(id: harness.issueID, context: harness.context)),
            issueBefore
        )
        let record = try onlyRecord(id: result.recordID, context: harness.context)
        XCTAssertEqual(record.couldNotVerifyKey, "unsafe_to_continue")
        XCTAssertEqual(record.couldNotVerifyDisplaySnapshot, "It became unsafe to continue")
        XCTAssertEqual(record.couldNotVerifyRegistryVersion, "cnv.reason.en-US.v1")
        XCTAssertTrue(
            try snapshot(for: result, harness: harness).evidence
                .filter { $0.recordID == result.recordID }.isEmpty
        )
        let counters = await harness.diagnostics.snapshot()
        XCTAssertEqual(counters.reportSaved, 1)
        XCTAssertEqual(counters.recheckCompleted, 1)
    }

    func testPureRulePreservesIssueAndRejectsInvalidCNVAuthority() throws {
        let fixture = ruleFixture()
        let valid = try RecheckOutcomeRule.makePlan(fixture.input)
        XCTAssertEqual(valid.issueBefore, fixture.input.issue)
        XCTAssertEqual(valid.issueAfter, fixture.input.issue)
        XCTAssertEqual(valid.recordAfter.outcomeKey, "could_not_verify")
        XCTAssertEqual(valid.recordAfter.couldNotVerifyKey, "conditions_changed")
        XCTAssertEqual(valid.recordAfter.couldNotVerifyDisplaySnapshot, "Conditions changed")
        XCTAssertEqual(valid.recordAfter.couldNotVerifyRegistryVersion, "cnv.reason.en-US.v1")

        for invalid in [
            RecheckCouldNotVerifySelection(
                key: "conditions_changed", display: "Wrong display",
                registryVersion: "cnv.reason.en-US.v1"
            ),
            RecheckCouldNotVerifySelection(
                key: "unknown", display: "Conditions changed",
                registryVersion: "cnv.reason.en-US.v1"
            ),
            RecheckCouldNotVerifySelection(
                key: "conditions_changed", display: "Conditions changed",
                registryVersion: "cnv.reason.en-US.v2"
            ),
        ] {
            XCTAssertThrowsError(try RecheckOutcomeRule.makePlan(RecheckOutcomeRuleInput(
                draft: fixture.input.draft,
                parent: fixture.input.parent,
                issue: fixture.input.issue,
                outcomeKey: "could_not_verify",
                note: nil,
                completedAt: fixture.input.completedAt,
                mutationID: UUID(),
                packetID: UUID(),
                couldNotVerify: invalid
            )))
        }
        XCTAssertThrowsError(try RecheckOutcomeRule.makePlan(RecheckOutcomeRuleInput(
            draft: fixture.input.draft,
            parent: fixture.input.parent,
            issue: fixture.input.issue,
            outcomeKey: "could_not_verify",
            note: nil,
            completedAt: fixture.input.completedAt,
            mutationID: UUID(),
            packetID: UUID()
        )))
        XCTAssertThrowsError(try RecheckOutcomeRule.makePlan(RecheckOutcomeRuleInput(
            draft: fixture.input.draft,
            parent: fixture.input.parent,
            issue: fixture.input.issue,
            outcomeKey: "resolved",
            note: nil,
            completedAt: fixture.input.completedAt,
            mutationID: UUID(),
            packetID: UUID(),
            couldNotVerify: fixture.input.couldNotVerify
        )))
    }

    @MainActor
    func testStaleIssueAndUnknownReasonFailClosedWithoutPartialAuthority() async throws {
        let harness = try await makeHarness(acceptsWide: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        XCTAssertThrowsError(try harness.runner.prepareReview(
            assetID: harness.assetID,
            selection: .couldNotVerify(reasonKey: "not_in_registry", note: nil)
        ))
        let issue = try onlyIssue(id: harness.issueID, context: harness.context)
        issue.status = IssueStatus.open.rawValue
        await XCTAssertThrowsErrorAsync {
            _ = try await harness.runner.finalize(
                assetID: harness.assetID,
                selection: .couldNotVerify(reasonKey: "conditions_changed", note: nil),
                completedAt: harness.completedAt,
                snapshotCreatedAt: harness.completedAt,
                sourceApp: SourceAppSnapshotV1(build: "1", version: "1")
            )
        }
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
                $0.stage == WorkflowStage.recheck.rawValue
                    && $0.state == WorkflowState.completed.rawValue
            }.count,
            0
        )
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 1)
        let counters = await harness.diagnostics.snapshot()
        XCTAssertEqual(counters.reportSaved, 0)
        XCTAssertEqual(counters.recheckCompleted, 0)
        harness.context.rollback()
    }

    @MainActor
    func testCommittedCNVJournalRecoversAndReplayKeepsOneUnchangedIssueAndRoot() async throws {
        let injection = FinalizationIntentStoreFailureInjection(
            failOnceAt: .intentPhaseWrite(.databaseCommitted)
        )
        let harness = try await makeHarness(acceptsWide: true, storeFailure: injection)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let issueBefore = issuePayload(try onlyIssue(id: harness.issueID, context: harness.context))
        let identifiers = FinalizationIdentifiers(
            mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
            reportID: UUID(), issueID: harness.issueID
        )
        let selection = CheckOutcomeSelection.couldNotVerify(
            reasonKey: "conditions_changed",
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
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 2)
        XCTAssertEqual(
            issuePayload(try onlyIssue(id: harness.issueID, context: harness.context)),
            issueBefore
        )

        let summary = try await FinalizationRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.generationRootURL
        ).reconcile()
        XCTAssertEqual(summary.completedRecordIDs.count, 1)
        XCTAssertTrue(summary.recoveredDraftRecordIDs.isEmpty)
        XCTAssertEqual(
            issuePayload(try onlyIssue(id: harness.issueID, context: harness.context)),
            issueBefore
        )
        injection.removeFailure()
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
        XCTAssertEqual(replay.recordID, summary.completedRecordIDs[0])
        XCTAssertEqual(replay.packetID, identifiers.packetID)
        XCTAssertEqual(replay.reportID, identifiers.reportID)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 1)
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
                $0.finalizationMutationID == identifiers.mutationID
            }.count,
            1
        )
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
        acceptsWide: Bool,
        storeFailure: FinalizationIntentStoreFailureInjection? = nil
    ) async throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent(
            "S5_4RecheckCNVTests-\(UUID().uuidString)",
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
            finalizationStoreFailureInjection: storeFailure
        )
        let draft = try runner.beginOrResumeDraft(BeginDraftSubmission(
            assetID: assetID, requestedStage: .recheck, issueID: issueID,
            observedAtUTC: recheckObserved,
            confirmedTimeZoneID: "America/New_York",
            afterDarkAccepted: true, safePositionAccepted: true
        ))
        if acceptsWide {
            context.insert(try await makeEvidence(
                id: UUID(), recordID: draft.id, purposeKey: "wide_context",
                source: try makePNG(width: 96, height: 72, seed: 40),
                createdAt: recheckObserved.addingTimeInterval(10), store: store
            ))
        }
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

    private func issuePayload(_ issue: Issue) -> IssuePayloadV1 {
        IssuePayloadV1(
            id: issue.id, schemaVersion: issue.schemaVersion,
            assetID: issue.assetID, openedByRecordID: issue.openedByRecordID,
            labelKey: issue.labelKey,
            labelDisplaySnapshot: issue.labelDisplaySnapshot,
            status: issue.status, resolvedByRecordID: issue.resolvedByRecordID,
            createdAt: issue.createdAt, updatedAt: issue.updatedAt
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

    private func snapshot(
        for result: FinalizationResult,
        harness: Harness
    ) throws -> ReportSnapshotV1 {
        let data = try ReportPDFAnchoredFile.readRegularFile(
            at: harness.generationRootURL.appendingPathComponent(result.snapshotRelativePath),
            within: harness.generationRootURL,
            rootIdentity: try ReportPDFAnchoredFile.rootIdentity(at: harness.generationRootURL)
        )
        return try ReportSnapshotEncoderV1().decode(data)
    }

    private func ruleFixture() -> (input: RecheckOutcomeRuleInput, issueID: UUID) {
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
        return (RecheckOutcomeRuleInput(
            draft: draft,
            parent: parent,
            issue: IssuePayloadV1(
                id: issueID, schemaVersion: 1, assetID: assetID,
                openedByRecordID: openingID, labelKey: "dark_section",
                labelDisplaySnapshot: "Section appears dark",
                status: IssueStatus.recheckDue.rawValue, resolvedByRecordID: nil,
                createdAt: parentCompleted.addingTimeInterval(-120),
                updatedAt: parentCompleted
            ),
            outcomeKey: "could_not_verify",
            note: nil,
            completedAt: started.addingTimeInterval(60),
            mutationID: UUID(),
            packetID: UUID(),
            couldNotVerify: RecheckCouldNotVerifySelection(
                key: "conditions_changed",
                display: "Conditions changed",
                registryVersion: "cnv.reason.en-US.v1"
            )
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
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {}
    }
}

extension S5_4RecheckCNVTests {
    func testV23P03C14RecheckDueStatusIsRecordedWithoutExternalDelivery() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_254)
        try fixture.policy.validate()
        XCTAssertEqual(
            try CorrectiveActionDueCalculatorV1.status(
                fixture.due, at: fixture.due.openedAt
            ),
            .notDue
        )
        XCTAssertEqual(fixture.actions[3].closureEvidence.count, 2)
    }
}

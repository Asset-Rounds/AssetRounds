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
        defer {
            try? harness.fixture.close()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }

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
        assertSameInstantAtPersistedPrecision(original.updatedAt, harness.completedAt)
        let newIssueID = try XCTUnwrap(result.newIssueID)
        let inserted = try onlyIssue(id: newIssueID, context: harness.context)
        XCTAssertEqual(inserted.assetID, harness.assetID)
        XCTAssertEqual(inserted.openedByRecordID, result.recordID)
        XCTAssertEqual(inserted.labelKey, "physical_damage")
        XCTAssertEqual(inserted.labelDisplaySnapshot, "Visible physical damage")
        XCTAssertEqual(inserted.status, IssueStatus.open.rawValue)
        XCTAssertNil(inserted.resolvedByRecordID)
        assertSameInstantAtPersistedPrecision(inserted.createdAt, harness.completedAt)
        assertSameInstantAtPersistedPrecision(inserted.updatedAt, harness.completedAt)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 2)
        let workCoordinator = try WorkCoordinator(
            modelContext: harness.context,
            signPack: pack,
            generationRootURL: harness.generationRootURL,
            checkRunnerCoordinator: harness.runner,
            lifecycleDependencies: harness.fixture.lifecycleDependencies
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
        guard snapshot.issues.count == 2 else {
            XCTFail("snapshot.issues has \(snapshot.issues.count) entries; expected 2")
            return
        }
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
        defer {
            try? harness.fixture.close()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
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
        let coldRunner = try CheckRunnerCoordinator(
            modelContext: harness.context,
            packageLifecycleDependencies: harness.fixture.lifecycleDependencies,
            packageLifecycleProfile: harness.fixture.lifecycleProfile,
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
        defer {
            try? harness.fixture.close()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
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
        defer {
            try? harness.fixture.close()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
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
        defer {
            try? harness.fixture.close()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
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
        defer {
            try? harness.fixture.close()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
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

        // V23 schema-2 finalization intents recover only through the sole
        // workspace writer, as production startup does (StartupRouter).
        let summary = try await FinalizationRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.generationRootURL,
            workspaceWriter: harness.fixture.lifecycleDependencies.writer,
            lifecycleProfileRegistry: harness.fixture.storeCoordinator.lifecycleProfileRegistry
        ).reconcile()
        XCTAssertEqual(summary.completedRecordIDs.count, 1)
        guard summary.completedRecordIDs.count == 1 else {
            XCTFail("summary.completedRecordIDs has \(summary.completedRecordIDs.count) entries; expected 1")
            return
        }
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

    @MainActor
    func testDifferentIssueFirstWorkCommitsOneReceiptAndReplaysAfterReopen() async throws {
        let fixture = try await makeDifferentIssueFirstWorkFixture()
        var activeOwner: StoreSessionCoordinator? = fixture.harness.fixture.storeCoordinator
        defer { if let activeOwner { closeDifferentIssueWorkOwner(activeOwner) } }
        let harness = fixture.harness
        let writer = harness.fixture.lifecycleDependencies.writer
        let beforeRows = try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL)
        let beforeFiles = try differentIssueWorkFiles(root: harness.generationRootURL)
        let beforeHistory = try writer.sourceMutationHistorySnapshot()
        let submission = differentIssueWorkSubmission(draft: fixture.draft)
        let identifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
        fixture.clock.set(submission.completedAt)

        let saved = try await fixture.work.saveWork(draftID: fixture.draft.recordID,
            submission: submission, identifiers: identifiers)
        XCTAssertEqual(saved.id, fixture.newIssueID)
        XCTAssertEqual(saved.status, .recheckDue)
        XCTAssertEqual(saved.records.map(\.id), [fixture.draft.recordID])
        let record = try onlyRecord(id: fixture.draft.recordID, context: harness.context)
        XCTAssertEqual(record.issueID, fixture.newIssueID)
        XCTAssertEqual(record.parentRecordID, fixture.result.recordID)
        XCTAssertEqual(record.state, WorkflowState.completed.rawValue)
        XCTAssertEqual(record.outcomeKey, "work_recorded")
        XCTAssertEqual(record.finalizationMutationID, identifiers.mutationID)
        XCTAssertNil(record.packetID)
        let issue = try onlyIssue(id: fixture.newIssueID, context: harness.context)
        XCTAssertEqual(issue.openedByRecordID, fixture.result.recordID)
        XCTAssertEqual(issue.labelKey, "physical_damage")
        XCTAssertEqual(issue.status, IssueStatus.recheckDue.rawValue)
        XCTAssertNil(issue.resolvedByRecordID)
        assertSameInstantAtPersistedPrecision(issue.updatedAt, submission.completedAt)

        let mutationID = try MutationIDV1(rawValue: identifiers.mutationID)
        let envelope = try XCTUnwrap(writer.workEnvelope(mutationID: mutationID))
        let receipt = try XCTUnwrap(writer.workCommitReceipt(envelope: envelope))
        guard case let .recordWork(command) = envelope.command else {
            XCTFail("Expected the genuine new-Issue Work command")
            return
        }
        let authority = try XCTUnwrap(command.writerAuthority)
        XCTAssertEqual(authority.parentBefore.id, fixture.result.recordID)
        XCTAssertEqual(authority.parentBefore.issueID, harness.issueID)
        XCTAssertNotEqual(authority.parentBefore.issueID, authority.issueBefore.id)
        XCTAssertEqual(authority.issueBefore.openedByRecordID, authority.parentBefore.id)
        XCTAssertEqual(authority.issueBefore.createdAt, authority.parentBefore.completedAt)
        try authority.validate(envelope: envelope)
        try receipt.validate()
        XCTAssertEqual(try MutationEnvelopeV1.decodeCanonical(from: envelope.canonicalData()).canonicalData(),
            try envelope.canonicalData())
        let afterHistory = try writer.sourceMutationHistorySnapshot()
        XCTAssertEqual(afterHistory.receipts.count, beforeHistory.receipts.count + 1)
        XCTAssertEqual(afterHistory.lastLocalSequence, beforeHistory.lastLocalSequence + 1)
        XCTAssertEqual(afterHistory.workspaceRevision, beforeHistory.workspaceRevision + 1)
        let afterRows = try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL)
        let changedKeys: Set<String> = ["record:\(record.id)", "issue:\(fixture.newIssueID)"]
        XCTAssertEqual(differentIssueDomainRows(beforeRows, excluding: changedKeys),
            differentIssueDomainRows(afterRows, excluding: changedKeys))
        XCTAssertEqual(try differentIssueWorkFiles(root: harness.generationRootURL), beforeFiles)

        let replay = try await fixture.work.saveWork(draftID: fixture.draft.recordID,
            submission: submission, identifiers: identifiers)
        XCTAssertEqual(replay, saved)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), afterHistory)
        XCTAssertEqual(try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL), afterRows)

        // Release the real original writer before opening the persisted generation.
        // The private root is retained while all old session/context aliases live.
        activeOwner = nil
        try harness.fixture.storeCoordinator.invalidateAndReleaseWriter()
        let reopened = try StoreGenerationFactory(applicationSupportURL: harness.applicationSupportURL)
            .openOrBootstrapCurrent()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [harness.fixture.lifecycleProfile])
        let owner = try StoreSessionCoordinator(validatingSession: reopened, clock: fixture.clock,
            lifecycleProfileRegistry: registry)
        activeOwner = owner
        let dependencies = try owner.packageLifecycleDependencies(profileRegistry: registry)
        let runner = try CheckRunnerCoordinator(modelContext: reopened.modelContext,
            packageLifecycleDependencies: dependencies, packageLifecycleProfile: harness.fixture.lifecycleProfile)
        runner.configureCapture(generationRootURL: reopened.generationRootURL)
        let coldWork = try WorkCoordinator(modelContext: reopened.modelContext, signPack: pack,
            generationRootURL: reopened.generationRootURL, checkRunnerCoordinator: runner,
            lifecycleDependencies: dependencies)
        let coldReplay = try await coldWork.saveWork(draftID: fixture.draft.recordID,
            submission: submission, identifiers: identifiers)
        XCTAssertEqual(coldReplay, saved)
        XCTAssertEqual(try dependencies.writer.sourceMutationHistorySnapshot(), afterHistory)
        XCTAssertEqual(try dependencies.writer.workEnvelope(mutationID: mutationID)?.canonicalData(),
            try envelope.canonicalData())
        XCTAssertEqual(try dependencies.writer.workCommitReceipt(envelope: envelope)?.canonicalData(),
            try receipt.canonicalData())
        XCTAssertEqual(try differentIssueWorkRows(context: reopened.modelContext, root: reopened.generationRootURL), afterRows)
        XCTAssertEqual(try differentIssueWorkFiles(root: reopened.generationRootURL), beforeFiles)
    }

    @MainActor
    func testDifferentIssueFirstWorkRejectsMalformedAuthorityWithoutEffects() async throws {
        let fixture = try await makeDifferentIssueFirstWorkFixture()
        let harness = fixture.harness
        defer { closeDifferentIssueWorkOwner(harness.fixture.storeCoordinator) }
        let original = try onlyIssue(id: harness.issueID, context: harness.context)
        let issue = try onlyIssue(id: fixture.newIssueID, context: harness.context)
        let opener = try onlyRecord(id: fixture.result.recordID, context: harness.context)
        let oldWork = try onlyRecord(id: harness.workRecordID, context: harness.context)
        let draft = try onlyRecord(id: fixture.draft.recordID, context: harness.context)
        let site = try XCTUnwrap(harness.context.fetch(FetchDescriptor<Site>()).first)
        let cleanRows = try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL)
        let cleanFiles = try differentIssueWorkFiles(root: harness.generationRootURL)
        let originalStatus = original.status
        let originalResolution = original.resolvedByRecordID
        let originalOpening = original.openedByRecordID
        let issueOpening = issue.openedByRecordID
        let issueAsset = issue.assetID
        let issueCreatedAt = issue.createdAt
        let openerIssue = opener.issueID
        let openerParent = opener.parentRecordID
        let openerPacket = opener.packetID
        let openerOutcome = opener.outcomeKey
        let oldWorkParent = oldWork.parentRecordID
        let draftParent = draft.parentRecordID
        let siteLabel = site.label

        for hostile in DifferentIssueWorkHostile.allCases {
            // Each bad value is a deliberate negative vector over genuine
            // canonical history, never a claimed positive seed or receipt.
            switch hostile {
            case .missingResolution: original.resolvedByRecordID = nil
            case .wrongResolution: original.resolvedByRecordID = UUID()
            case .unresolvedOriginal: original.status = IssueStatus.open.rawValue
            case .wrongNewOpener: issue.openedByRecordID = harness.openingRecordID
            case .wrongAsset: issue.assetID = UUID()
            case .wrongCreatedAt: issue.createdAt = issueCreatedAt.addingTimeInterval(-1)
            case .missingOriginalIssue: opener.issueID = UUID()
            case .missingOriginalOpening: original.openedByRecordID = UUID()
            case .forkOriginalChain: opener.parentRecordID = harness.openingRecordID
            case .cycleOriginalChain: oldWork.parentRecordID = opener.id
            case .wrongOpenerOutcome: opener.outcomeKey = "issue_still_visible"
            case .missingOpenerPacket: opener.packetID = nil
            case .wrongDraftParent: draft.parentRecordID = harness.workRecordID
            case .dirtyContext: site.label = "Unsaved operator edit"
            }
            if hostile != .dirtyContext { try harness.context.save() }
            let refusedRows = try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL)
            let wasDirty = harness.context.hasChanges
            let reader = WorkAuthorityReaderV1(modelContext: harness.context, signPack: pack,
                generationRootURL: harness.generationRootURL,
                rootIdentity: try ReportPDFAnchoredFile.rootIdentity(at: harness.generationRootURL))
            XCTAssertThrowsError(try reader.authorityForDraft(draft.id), "\(hostile): full source reader must refuse")
            let identifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
            var attempted = false
            do {
                attempted = true
                _ = try await fixture.work.saveWork(draftID: draft.id,
                    submission: differentIssueWorkSubmission(draft: fixture.draft), identifiers: identifiers)
                XCTFail("Malformed external opener must refuse: \(hostile)")
            } catch {
                XCTAssertTrue(error is WorkCoordinatorError || error is WorkRuleError
                    || error is WorkspaceMutationFailureV1, "\(hostile): unexpected typed failure")
            }
            XCTAssertTrue(attempted)
            XCTAssertEqual(try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL), refusedRows)
            XCTAssertEqual(try differentIssueWorkFiles(root: harness.generationRootURL), cleanFiles)
            XCTAssertEqual(harness.context.hasChanges, wasDirty)
            XCTAssertTrue(try harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).allSatisfy {
                $0.mutationID != identifiers.mutationID
            })
            if hostile == .dirtyContext { harness.context.rollback() }
            original.status = originalStatus
            original.resolvedByRecordID = originalResolution
            original.openedByRecordID = originalOpening
            issue.openedByRecordID = issueOpening
            issue.assetID = issueAsset
            issue.createdAt = issueCreatedAt
            opener.issueID = openerIssue
            opener.parentRecordID = openerParent
            opener.packetID = openerPacket
            opener.outcomeKey = openerOutcome
            oldWork.parentRecordID = oldWorkParent
            draft.parentRecordID = draftParent
            site.label = siteLabel
            if harness.context.hasChanges { try harness.context.save() }
            XCTAssertEqual(try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL), cleanRows)
        }

        let foreignRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "S5_3ForeignWorkOwner-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: foreignRoot, withIntermediateDirectories: false)
        let foreign = try await WorkCanonicalOpenIssueFixtureV1.make(
            applicationSupportURL: foreignRoot, pack: pack, clock: fixture.clock)
        defer { closeDifferentIssueWorkOwner(foreign.storeCoordinator) }
        XCTAssertNotEqual(foreign.lifecycleDependencies.workspaceID, harness.fixture.lifecycleDependencies.workspaceID)
        XCTAssertFalse(foreign.lifecycleDependencies.writer === harness.fixture.lifecycleDependencies.writer)
        let foreignRows = try differentIssueWorkRows(context: foreign.context, root: foreign.session.generationRootURL)
        let foreignWork = try WorkCoordinator(modelContext: harness.context, signPack: pack,
            generationRootURL: harness.generationRootURL, checkRunnerCoordinator: harness.runner,
            lifecycleDependencies: foreign.lifecycleDependencies)
        let foreignIdentifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
        await XCTAssertThrowsErrorAsync {
            _ = try await foreignWork.saveWork(draftID: draft.id,
                submission: differentIssueWorkSubmission(draft: fixture.draft), identifiers: foreignIdentifiers)
        }
        XCTAssertEqual(try differentIssueWorkRows(context: foreign.context, root: foreign.session.generationRootURL), foreignRows)
        XCTAssertEqual(try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL), cleanRows)
        XCTAssertEqual(try differentIssueWorkFiles(root: harness.generationRootURL), cleanFiles)

        harness.fixture.lifecycleDependencies.writer.invalidate()
        XCTAssertThrowsError(try harness.fixture.lifecycleDependencies.writer.currentRevision()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        let invalidatedIdentifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.work.saveWork(draftID: draft.id,
                submission: differentIssueWorkSubmission(draft: fixture.draft), identifiers: invalidatedIdentifiers)
        }
        XCTAssertEqual(try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL), cleanRows)
        XCTAssertEqual(try differentIssueWorkFiles(root: harness.generationRootURL), cleanFiles)
    }

    @MainActor
    func testDifferentIssueFirstWorkRechecksRevisionAfterPromotionWithoutCommitting() async throws {
        let fixture = try await makeDifferentIssueFirstWorkFixture()
        let harness = fixture.harness
        defer { closeDifferentIssueWorkOwner(harness.fixture.storeCoordinator) }
        let writer = harness.fixture.lifecycleDependencies.writer
        let site = try XCTUnwrap(harness.context.fetch(FetchDescriptor<Site>()).first)
        let filesBefore = try differentIssueWorkFiles(root: harness.generationRootURL)
        let revisionBefore = try writer.currentRevision()
        let competingID = try MutationIDV1(rawValue: UUID())
        var expectedRows: [String: Data]?
        var hookReached = false
        let identifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: UUID())
        let submission = differentIssueWorkSubmission(draft: fixture.draft,
            photo: try makePNG(width: 80, height: 64, seed: 93))
        fixture.clock.set(submission.completedAt)
        let injection = WorkCoordinatorFailureInjection(afterEvidencePromotion: {
            // A real separately accepted mutation advances the live revision.
            _ = try writer.execute(.updateSiteTimeZone(.init(siteID: site.id,
                timeZoneID: "America/New_York", confirmedAt: submission.completedAt)),
                mutationID: competingID)
            let reader = WorkAuthorityReaderV1(modelContext: harness.context, signPack: self.pack,
                generationRootURL: harness.generationRootURL,
                rootIdentity: try ReportPDFAnchoredFile.rootIdentity(at: harness.generationRootURL))
            XCTAssertEqual(try reader.authorityForDraft(fixture.draft.recordID).parent.id,
                fixture.result.recordID)
            expectedRows = try self.differentIssueWorkRows(context: harness.context, root: harness.generationRootURL)
            hookReached = true
        })
        let work = try WorkCoordinator(modelContext: harness.context, signPack: pack,
            generationRootURL: harness.generationRootURL, checkRunnerCoordinator: harness.runner,
            lifecycleDependencies: harness.fixture.lifecycleDependencies, failureInjection: injection)
        do {
            _ = try await work.saveWork(draftID: fixture.draft.recordID,
                submission: submission, identifiers: identifiers)
            XCTFail("Changed revision after promotion must refuse the pending Work")
        } catch {
            XCTAssertEqual(error as? WorkCoordinatorError, .invalidAuthority)
        }
        XCTAssertTrue(hookReached)
        XCTAssertEqual(try writer.currentRevision().revision, revisionBefore.revision + 1)
        XCTAssertEqual(try differentIssueWorkRows(context: harness.context, root: harness.generationRootURL),
            try XCTUnwrap(expectedRows))
        XCTAssertEqual(try differentIssueWorkFiles(root: harness.generationRootURL), filesBefore)
        let rows = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>())
        XCTAssertEqual(rows.filter { $0.mutationID == competingID.rawValue }.count, 1)
        XCTAssertTrue(rows.allSatisfy { $0.mutationID != identifiers.mutationID })
        XCTAssertEqual(try onlyRecord(id: fixture.draft.recordID, context: harness.context).state,
            WorkflowState.draft.rawValue)
        XCTAssertEqual(try onlyIssue(id: fixture.newIssueID, context: harness.context).status,
            IssueStatus.open.rawValue)
    }

    private struct DifferentIssueFirstWorkFixture {
        let harness: Harness
        let result: FinalizationResult
        let newIssueID: UUID
        let work: WorkCoordinator
        let draft: WorkDraftValue
        let clock: DifferentIssueWorkClock
    }

    private enum DifferentIssueWorkHostile: CaseIterable, Equatable {
        case missingResolution, wrongResolution, unresolvedOriginal, wrongNewOpener
        case wrongAsset, wrongCreatedAt, missingOriginalIssue, missingOriginalOpening
        case forkOriginalChain, cycleOriginalChain, wrongOpenerOutcome, missingOpenerPacket
        case wrongDraftParent, dirtyContext
    }

    @MainActor
    private func makeDifferentIssueFirstWorkFixture() async throws -> DifferentIssueFirstWorkFixture {
        let clock = DifferentIssueWorkClock(Date(timeIntervalSince1970: 1_780_000_100))
        let harness = try await makeHarness(clock: clock)
        do {
            clock.set(harness.completedAt)
            let result = try await harness.runner.finalize(assetID: harness.assetID,
                selection: .originalResolvedDifferentIssue(labelKey: "physical_damage", note: nil),
                completedAt: harness.completedAt, snapshotCreatedAt: harness.completedAt,
                sourceApp: SourceAppSnapshotV1(build: "different-issue-work", version: "1"))
            let newIssueID = try XCTUnwrap(result.newIssueID)
            let original = try onlyIssue(id: harness.issueID, context: harness.context)
            let issue = try onlyIssue(id: newIssueID, context: harness.context)
            XCTAssertEqual(original.status, IssueStatus.resolved.rawValue)
            XCTAssertEqual(original.resolvedByRecordID, result.recordID)
            XCTAssertEqual(issue.status, IssueStatus.open.rawValue)
            XCTAssertEqual(issue.openedByRecordID, result.recordID)
            clock.set(harness.completedAt.addingTimeInterval(1))
            let work = try WorkCoordinator(modelContext: harness.context, signPack: pack,
                generationRootURL: harness.generationRootURL, checkRunnerCoordinator: harness.runner,
                lifecycleDependencies: harness.fixture.lifecycleDependencies)
            let draft = try work.beginWork(issueID: newIssueID)
            XCTAssertEqual(draft.issueID, newIssueID)
            XCTAssertEqual(draft.assetID, harness.assetID)
            let reader = WorkAuthorityReaderV1(modelContext: harness.context, signPack: pack,
                generationRootURL: harness.generationRootURL,
                rootIdentity: try ReportPDFAnchoredFile.rootIdentity(at: harness.generationRootURL))
            let admitted = try reader.authorityForDraft(draft.recordID)
            XCTAssertEqual(admitted.parent.id, result.recordID)
            XCTAssertEqual(admitted.parent.issueID, harness.issueID)
            XCTAssertNotEqual(admitted.parent.issueID, admitted.issue.id)
            return DifferentIssueFirstWorkFixture(harness: harness, result: result,
                newIssueID: newIssueID, work: work, draft: draft, clock: clock)
        } catch {
            closeDifferentIssueWorkOwner(harness.fixture.storeCoordinator)
            throw error
        }
    }

    private func differentIssueWorkSubmission(draft: WorkDraftValue, photo: Data? = nil) -> WorkSaveSubmission {
        WorkSaveSubmission(performedLocalDate: "2026-08-13", description: "Replaced damaged component",
            note: "New finding only", photos: photo.map { [WorkPhotoSubmission(
                purposeKey: "work_context", sourceData: $0,
                createdAt: draft.startedAt.addingTimeInterval(5))] } ?? [],
            completedAt: draft.startedAt.addingTimeInterval(30))
    }

    @MainActor
    private func closeDifferentIssueWorkOwner(_ owner: StoreSessionCoordinator) {
        do { try owner.invalidateAndReleaseWriter() }
        catch { XCTFail("Different-Issue fixture writer close failed: \(error)") }
        // Session/context/runner aliases still exist; do not unlink the root.
    }

    @MainActor
    private func differentIssueWorkRows(context: ModelContext, root: URL) throws -> [String: Data] {
        let reader = WorkAuthorityReaderV1(modelContext: context, signPack: pack,
            generationRootURL: root, rootIdentity: try ReportPDFAnchoredFile.rootIdentity(at: root))
        var values: [String: Data] = [:]
        for row in try context.fetch(FetchDescriptor<WorkflowRecord>()) {
            values["record:\(row.id)"] = try WorkspaceMutationCanonicalV1.data(reader.payload(row))
            values["binding:\(row.id)"] = try WorkspaceMutationCanonicalV1.data(reader.sourceBinding(recordID: row.id))
        }
        for row in try context.fetch(FetchDescriptor<Issue>()) {
            values["issue:\(row.id)"] = try WorkspaceMutationCanonicalV1.data(reader.payload(row))
        }
        for row in try context.fetch(FetchDescriptor<Packet>()) {
            values["packet:\(row.id)"] = try WorkspaceMutationCanonicalV1.data(PacketPayloadV1(
                id: row.id, schemaVersion: row.schemaVersion, stableRootID: row.stableRootID,
                currentRecordID: row.currentRecordID, evaluationCounted: row.evaluationCounted,
                contentDeletedAt: row.contentDeletedAt, createdAt: row.createdAt))
        }
        for row in try context.fetch(FetchDescriptor<Report>()) {
            values["report:\(row.id)"] = try WorkspaceMutationCanonicalV1.data(ReportPayloadV1(
                id: row.id, schemaVersion: row.schemaVersion, packetID: row.packetID,
                sourceRecordID: row.sourceRecordID, snapshotSchemaVersion: row.snapshotSchemaVersion,
                snapshotRelativePath: row.snapshotRelativePath, snapshotSHA256: row.snapshotSHA256,
                pdfState: row.pdfState, pdfRelativePath: row.pdfRelativePath, pdfSHA256: row.pdfSHA256,
                createdAt: row.createdAt, replacesReportID: row.replacesReportID))
            values["snapshot:\(row.id)"] = try Data(contentsOf: root.appendingPathComponent(row.snapshotRelativePath))
        }
        for row in try context.fetch(FetchDescriptor<EvidenceFile>()) {
            values["evidence:\(row.id)"] = try WorkspaceMutationCanonicalV1.data(reader.evidencePayload(row))
        }
        for row in try context.fetch(FetchDescriptor<Site>()) {
            let fields: [String?] = [row.id.uuidString, String(row.schemaVersion), row.label,
                row.address, row.timeZoneID, String(row.createdAt.timeIntervalSince1970.bitPattern),
                String(row.updatedAt.timeIntervalSince1970.bitPattern)]
            values["site:\(row.id)"] = try WorkspaceMutationCanonicalV1.data(fields)
        }
        for row in try context.fetch(FetchDescriptor<Asset>()) {
            let fields: [String?] = [row.id.uuidString, String(row.schemaVersion), row.siteID.uuidString,
                row.packID, String(row.packSchemaVersion), String(row.packContentVersion), row.label,
                String(row.createdAt.timeIntervalSince1970.bitPattern), String(row.updatedAt.timeIntervalSince1970.bitPattern)]
            values["asset:\(row.id)"] = try WorkspaceMutationCanonicalV1.data(fields)
        }
        for row in try context.fetch(FetchDescriptor<MutationReceiptRow>()) {
            let fields: [String?] = [row.mutationID.uuidString, row.workspaceMutationKey, row.receiptIdentity,
                row.workspaceID.uuidString, row.replicaID.uuidString, String(row.localSequence),
                row.commandKind, row.envelopeSHA256, row.receiptSHA256, row.reversalBasisSHA256]
            values["receipt-metadata:\(row.workspaceMutationKey)"] = try WorkspaceMutationCanonicalV1.data(fields)
            let bytes: [Data?] = [row.envelopeData, row.receiptData, row.reversalBasisData, row.semanticReversalData]
            values["receipt-bytes:\(row.workspaceMutationKey)"] = try WorkspaceMutationCanonicalV1.data(bytes)
        }
        for row in try context.fetch(FetchDescriptor<MutationQuarantineRow>()) {
            let fields: [String?] = [row.workspaceID.uuidString, row.mutationID.uuidString,
                row.workspaceMutationKey, row.identityDomain, row.acceptedIdentitySHA256,
                row.conflictingIdentitySHA256, String(row.detectedAt.timeIntervalSince1970.bitPattern)]
            values["quarantine:\(row.workspaceMutationKey)"] = try WorkspaceMutationCanonicalV1.data(fields)
        }
        for row in try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()) {
            let fields: [String?] = [row.workspaceID.uuidString, row.generationID.uuidString,
                row.activeReplicaID.uuidString, String(row.workspaceRevision), String(row.lastLocalSequence),
                row.mutableSemanticSHA256]
            values["workspace-revision:\(row.workspaceID)"] = try WorkspaceMutationCanonicalV1.data(fields)
        }
        for row in try context.fetch(FetchDescriptor<EntityMutationRevisionRow>()) {
            let fields: [String?] = [row.stableIdentity, row.kind, row.entityID.uuidString,
                String(row.revision), row.externalProjectionSHA256]
            values["entity-revision:\(row.stableIdentity)"] = try WorkspaceMutationCanonicalV1.data(fields)
        }
        return values
    }

    private func differentIssueDomainRows(_ rows: [String: Data], excluding: Set<String>) -> [String: Data] {
        rows.filter { key, _ in
            !excluding.contains(key) && ["record:", "binding:", "issue:", "packet:", "report:",
                "snapshot:", "evidence:", "site:", "asset:"].contains { key.hasPrefix($0) }
        }
    }

    private func differentIssueWorkFiles(root: URL) throws -> [String: Data] {
        var values: [String: Data] = [:]
        for directory in ["evidence", ".staging/evidence"] {
            let parent = root.appendingPathComponent(directory, isDirectory: true)
            guard fileManager.fileExists(atPath: parent.path) else { continue }
            guard let enumerator = fileManager.enumerator(at: parent,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
                throw FixtureError.imageEncoding
            }
            for case let url as URL in enumerator {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                values[relative] = try Data(contentsOf: url)
            }
        }
        return values
    }

    private struct Harness {
        let fixture: WorkCanonicalCurrentRouteFixtureV1
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
        serviceFailure: FinalizationServiceFailureInjection? = nil,
        clock: any ApplicationClock = SystemApplicationClock()
    ) async throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent(
            "S5_3DifferentIssueTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        let fixture = try await WorkCanonicalCurrentRouteFixtureV1.make(
            applicationSupportURL: support,
            pack: pack,
            workPhotoData: try makePNG(width: 88, height: 66, seed: 30),
            clock: clock
        )
        do {
            let runner = try CheckRunnerCoordinator(
                modelContext: fixture.context,
                packageLifecycleDependencies: fixture.lifecycleDependencies,
                packageLifecycleProfile: fixture.lifecycleProfile,
                diagnosticsStore: diagnostics,
                finalizationStoreFailureInjection: storeFailure,
                finalizationServiceFailureInjection: serviceFailure
            )
            try runner.requestRecheck(assetID: fixture.assetID, issueID: fixture.issueID)
            let recheckObserved = fixture.workSubmission.completedAt.addingTimeInterval(60)
            _ = try runner.beginCheck(
                assetID: fixture.assetID,
                timeZoneID: "America/New_York",
                isTimeZoneConfirmed: true,
                afterDarkAccepted: true,
                safePositionAccepted: true,
                observedAt: recheckObserved
            )
            runner.configureCapture(generationRootURL: fixture.session.generationRootURL)
            let wide = try await runner.importCandidate(
                assetID: fixture.assetID,
                sourceData: try makePNG(width: 96, height: 72, seed: 40),
                createdAt: recheckObserved.addingTimeInterval(10)
            )
            _ = try await runner.accept(candidate: wide, assetID: fixture.assetID)
            let close = try await runner.importCandidate(
                assetID: fixture.assetID,
                sourceData: try makePNG(width: 84, height: 84, seed: 50),
                createdAt: recheckObserved.addingTimeInterval(20)
            )
            _ = try await runner.accept(candidate: close, assetID: fixture.assetID)
            return Harness(
                fixture: fixture,
                applicationSupportURL: support,
                session: fixture.session,
                generationRootURL: fixture.session.generationRootURL,
                context: fixture.context,
                runner: runner,
                diagnostics: diagnostics,
                assetID: fixture.assetID,
                issueID: fixture.issueID,
                openingRecordID: fixture.openingRecordID,
                workRecordID: fixture.workRecordID,
                completedAt: recheckObserved.addingTimeInterval(60)
            )
        } catch {
            try? fixture.close()
            throw error
        }
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

    /// Finalized rows are written back through the sole canonical writer, whose
    /// finalization contract persists UTC-millisecond instants; the
    /// completion instant is asserted at that persisted precision.
    private func assertSameInstantAtPersistedPrecision(
        _ actual: Date,
        _ expected: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            FinalizationCanonicalBindingV1.sameInstant(actual, expected),
            "\(actual.timeIntervalSince1970) != \(expected.timeIntervalSince1970) at persisted precision",
            file: file, line: line
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

private final class DifferentIssueWorkClock: ApplicationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func set(_ value: Date) { lock.withLock { self.value = value } }
    func now() -> Date { lock.withLock { value } }
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

import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S5_2RecheckOutcomeTests: XCTestCase {
    private let fileManager = FileManager.default
    private let pack = SignPack.illuminatedSignV1

    @MainActor
    func testResolvedCreatesOneRootTransitionsOriginalIssueAndFreezesNewEvidenceHistory() async throws {
        let harness = try await makeHarness()
        defer {
            try? harness.fixture.close()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }

        let beforePackets = try harness.context.fetchCount(FetchDescriptor<Packet>())
        let beforeReports = try harness.context.fetchCount(FetchDescriptor<Report>())
        let result = try await harness.runner.finalize(
            assetID: harness.assetID,
            selection: .resolved(note: "Illumination remained steady."),
            completedAt: harness.completedAt,
            snapshotCreatedAt: harness.completedAt,
            sourceApp: SourceAppSnapshotV1(build: "1", version: "1")
        )

        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), beforePackets + 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), beforeReports + 1)
        let issue = try onlyIssue(id: harness.issueID, context: harness.context)
        XCTAssertEqual(issue.status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(issue.resolvedByRecordID, result.recordID)
        XCTAssertEqual(issue.updatedAt, harness.completedAt)
        let record = try onlyRecord(id: result.recordID, context: harness.context)
        XCTAssertEqual(record.stage, WorkflowStage.recheck.rawValue)
        XCTAssertEqual(record.parentRecordID, harness.workRecordID)
        XCTAssertEqual(record.issueID, harness.issueID)
        XCTAssertEqual(record.outcomeKey, "resolved")
        XCTAssertEqual(record.note, "Illumination remained steady.")
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
        XCTAssertEqual(snapshot.outcome, "resolved")
        XCTAssertEqual(snapshot.history.map(\.recordID), [harness.openingRecordID, harness.workRecordID])
        XCTAssertEqual(snapshot.evidence.prefix(2).map(\.recordID), [result.recordID, result.recordID])
        XCTAssertEqual(snapshot.issues.count, 1)
        XCTAssertEqual(snapshot.issues[0].status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(snapshot.issues[0].resolvedByRecordID, result.recordID)
        let workReplay = try await harness.fixture.workCoordinator.saveWork(
            draftID: harness.workRecordID,
            submission: harness.fixture.workSubmission,
            identifiers: harness.fixture.workIdentifiers
        )
        XCTAssertEqual(workReplay.status, .resolved)
        XCTAssertEqual(workReplay.records.map(\.id), [harness.workRecordID])
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
                $0.id == harness.workRecordID
            }.count,
            1
        )
        let counters = await harness.diagnostics.snapshot()
        XCTAssertEqual(counters.reportSaved, 1)
        XCTAssertEqual(counters.recheckCompleted, 1)
    }

    @MainActor
    func testIssueStillVisibleReturnsSameIssueOpenAndReplayDoesNotDuplicateOrIncrement() async throws {
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
            issueID: harness.issueID
        )
        let selection = CheckOutcomeSelection.issueStillVisible(note: nil)
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
        let issue = try onlyIssue(id: harness.issueID, context: harness.context)
        XCTAssertEqual(issue.status, IssueStatus.open.rawValue)
        XCTAssertNil(issue.resolvedByRecordID)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<Issue>()).count, 1)
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
                .filter { $0.finalizationMutationID == identifiers.mutationID }.count,
            1
        )
        let counters = await harness.diagnostics.snapshot()
        XCTAssertEqual(counters.reportSaved, 1)
        XCTAssertEqual(counters.recheckCompleted, 1)
    }

    func testPureRuleRejectsImplicitIssueStateWrongParentAndUnsupportedOutcomes() throws {
        let fixture = ruleFixture()
        let valid = try RecheckOutcomeRule.makePlan(fixture.input)
        XCTAssertEqual(valid.issueAfter.status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(valid.issueAfter.resolvedByRecordID, fixture.input.draft.id)

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
        var wrongIssue = fixture.input.issue
        wrongIssue = IssuePayloadV1(
            id: wrongIssue.id, schemaVersion: wrongIssue.schemaVersion,
            assetID: wrongIssue.assetID, openedByRecordID: wrongIssue.openedByRecordID,
            labelKey: wrongIssue.labelKey,
            labelDisplaySnapshot: wrongIssue.labelDisplaySnapshot,
            status: IssueStatus.open.rawValue, resolvedByRecordID: nil,
            createdAt: wrongIssue.createdAt, updatedAt: wrongIssue.updatedAt
        )
        XCTAssertThrowsError(try RecheckOutcomeRule.makePlan(RecheckOutcomeRuleInput(
            draft: fixture.input.draft, parent: fixture.input.parent,
            issue: wrongIssue, outcomeKey: "resolved", note: nil,
            completedAt: fixture.input.completedAt,
            mutationID: UUID(), packetID: UUID()
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
                selection: .resolved(note: nil),
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
            reportID: UUID(), issueID: harness.issueID
        )

        await XCTAssertThrowsErrorAsync {
            try await harness.runner.finalize(
                assetID: harness.assetID,
                selection: .resolved(note: nil),
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
        storeFailure: FinalizationIntentStoreFailureInjection? = nil
    ) async throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent(
            "S5_2RecheckOutcomeTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        let fixture = try await WorkCanonicalCurrentRouteFixtureV1.make(
            applicationSupportURL: support,
            pack: pack,
            workPhotoData: try makePNG(width: 88, height: 66, seed: 30)
        )
        do {
            let runner = try CheckRunnerCoordinator(
                modelContext: fixture.context,
                packageLifecycleDependencies: fixture.lifecycleDependencies,
                packageLifecycleProfile: fixture.lifecycleProfile,
                diagnosticsStore: diagnostics,
                finalizationStoreFailureInjection: storeFailure
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
            draft: draft, parent: parent,
            issue: IssuePayloadV1(
                id: issueID, schemaVersion: 1, assetID: assetID,
                openedByRecordID: openingID, labelKey: "dark_section",
                labelDisplaySnapshot: "Section appears dark",
                status: IssueStatus.recheckDue.rawValue, resolvedByRecordID: nil,
                createdAt: parentCompleted.addingTimeInterval(-120),
                updatedAt: parentCompleted
            ),
            outcomeKey: "resolved", note: nil,
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

extension S5_2RecheckOutcomeTests {
    func testV23P03C14FailedRecheckReopensOnlyThroughDeclaredTrigger() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_252)
        try fixture.actions[4].validateSuccessor(of: fixture.actions[3], policy: fixture.policy)
        XCTAssertEqual(fixture.actions[4].state, .reopened)
        XCTAssertEqual(fixture.actions[4].reopenTrigger, .failedVerifiedRecheck)
        XCTAssertTrue(fixture.policy.reopenTriggers.contains(.failedVerifiedRecheck))
    }
}

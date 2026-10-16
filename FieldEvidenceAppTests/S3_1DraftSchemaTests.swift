import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S3_1DraftSchemaTests: XCTestCase {
    private let fileManager = FileManager.default

    func testClosedRawDomainsAreExact() {
        XCTAssertEqual(WorkflowRevisionKind.allCases.map(\.rawValue), ["original", "clerical_correction"])
        XCTAssertEqual(WorkflowStage.allCases.map(\.rawValue), ["check", "work", "recheck"])
        XCTAssertEqual(WorkflowState.allCases.map(\.rawValue), ["draft", "completed"])
        XCTAssertEqual(WorkflowDraftStep.allCases.map(\.rawValue), ["wide", "close", "outcome", "review"])
        XCTAssertEqual(IssueStatus.allCases.map(\.rawValue), ["open", "recheck_due", "resolved"])
        XCTAssertEqual(ReportPDFState.allCases.map(\.rawValue), ["pending", "ready", "failed"])
    }

    func testTimeContextUsesTheNamedZoneAtTheSuppliedWinterAndSummerInstants() throws {
        let winter = try TimeContextRule.freeze(
            observedAtUTC: Date(timeIntervalSince1970: 1_768_438_923),
            confirmedTimeZoneID: "America/New_York"
        )
        XCTAssertEqual(winter.utcOffsetMinutes, -300)
        XCTAssertEqual(winter.localDate, "2026-01-14")
        XCTAssertEqual(winter.localTime, "20:02:03")

        let summerInstant = Date(timeIntervalSince1970: 1_783_230_123)
        let summer = try TimeContextRule.freeze(
            observedAtUTC: summerInstant,
            confirmedTimeZoneID: "America/New_York"
        )
        XCTAssertEqual(summer.observedAtUTC, summerInstant)
        XCTAssertEqual(summer.timeZoneID, "America/New_York")
        XCTAssertEqual(summer.utcOffsetMinutes, -240)
    }

    @MainActor
    func testExactlySevenModelShapesRoundTripEveryFieldThroughTheNamedGeneration() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let ids = FixtureIDs()
        let started = Date(timeIntervalSince1970: 1_768_438_923)
        let completed = Date(timeIntervalSince1970: 1_768_435_999)

        do {
            var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
            let context = try XCTUnwrap(session).modelContext
            context.insert(Site(id: ids.site, label: "North Campus", address: "10 Main", timeZoneID: "America/New_York", createdAt: started, updatedAt: completed))
            context.insert(Asset(id: ids.asset, siteID: ids.site, packID: pack.packID, packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion, label: "Monument Sign", createdAt: started, updatedAt: completed))
            context.insert(
                WorkflowRecord(
                    id: ids.record,
                    assetID: ids.asset,
                    packetID: ids.packet,
                    issueID: ids.issue,
                    parentRecordID: ids.parent,
                    recordRevisionRootID: ids.root,
                    revisesRecordID: ids.revises,
                    evidenceSourceRecordID: ids.evidenceSource,
                    revisionKind: .clericalCorrection,
                    stage: .recheck,
                    state: .completed,
                    draftStepKey: .review,
                    startedAt: started,
                    completedAt: completed,
                    observedAtUTC: started,
                    timeZoneID: "America/New_York",
                    utcOffsetMinutes: -300,
                    localDate: "2026-01-14",
                    localTime: "20:02:03",
                    afterDarkAcknowledgementKey: "after_dark",
                    afterDarkAcknowledgementCopy: pack.acknowledgements[0].copy,
                    afterDarkAcknowledgementVersion: pack.acknowledgements[0].version,
                    afterDarkAcknowledgementAccepted: true,
                    safePositionAcknowledgementKey: "safe_authorized_position",
                    safePositionAcknowledgementCopy: pack.acknowledgements[1].copy,
                    safePositionAcknowledgementVersion: pack.acknowledgements[1].version,
                    safePositionAcknowledgementAccepted: true,
                    packID: pack.packID,
                    packSchemaVersion: pack.schemaVersion,
                    packContentVersion: pack.contentVersion,
                    pdfTemplateID: "field.evidence.pdf.worklight.v1",
                    pdfTemplateVersion: 1,
                    outcomeKey: "resolved",
                    couldNotVerifyKey: "conditions_changed",
                    couldNotVerifyDisplaySnapshot: "Conditions changed",
                    couldNotVerifyRegistryVersion: "cnv.reason.en-US.v1",
                    workPerformedLocalDate: "2026-01-14",
                    workDescription: "Replaced power supply",
                    note: "Exact fixture note",
                    finalizationMutationID: ids.mutation
                )
            )
            context.insert(EvidenceFile(id: ids.evidence, recordID: ids.record, purposeKey: "wide_context", relativePath: "evidence/e/original.jpg", mimeType: "image/jpeg", byteCount: 123, sha256: String(repeating: "a", count: 64), createdAt: started, thumbnailRelativePath: "evidence/e/thumbnail.jpg", thumbnailByteCount: 45, thumbnailSHA256: String(repeating: "b", count: 64)))
            context.insert(Issue(id: ids.issue, assetID: ids.asset, openedByRecordID: ids.parent, labelKey: "dark_section", labelDisplaySnapshot: "Section appears dark", status: .resolved, resolvedByRecordID: ids.record, createdAt: started, updatedAt: completed))
            context.insert(Packet(id: ids.packet, stableRootID: ids.stableRoot, currentRecordID: ids.record, evaluationCounted: true, contentDeletedAt: completed, createdAt: started))
            context.insert(Report(id: ids.report, packetID: ids.packet, sourceRecordID: ids.record, snapshotSchemaVersion: 1, snapshotRelativePath: "snapshots/r.json", snapshotSHA256: String(repeating: "c", count: 64), pdfState: .ready, pdfRelativePath: "pdfs/r.pdf", pdfSHA256: String(repeating: "d", count: 64), createdAt: completed, replacesReportID: ids.replacesReport))
            try context.save()
            session = nil
        }

        let reopenedSession = try factory.openOrBootstrapCurrent()
        let reopened = reopenedSession.modelContext
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<EvidenceFile>()), 1)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<Issue>()), 1)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<Report>()), 1)

        let record = try XCTUnwrap(reopened.fetch(FetchDescriptor<WorkflowRecord>()).first)
        XCTAssertEqual(record.id, ids.record); XCTAssertEqual(record.schemaVersion, 1)
        XCTAssertEqual(record.assetID, ids.asset); XCTAssertEqual(record.packetID, ids.packet)
        XCTAssertEqual(record.issueID, ids.issue); XCTAssertEqual(record.parentRecordID, ids.parent)
        XCTAssertEqual(record.recordRevisionRootID, ids.root); XCTAssertEqual(record.revisesRecordID, ids.revises)
        XCTAssertEqual(record.evidenceSourceRecordID, ids.evidenceSource)
        XCTAssertEqual(record.revisionKind, WorkflowRevisionKind.clericalCorrection.rawValue)
        XCTAssertEqual(record.stage, WorkflowStage.recheck.rawValue); XCTAssertEqual(record.state, WorkflowState.completed.rawValue)
        XCTAssertEqual(record.draftStepKey, WorkflowDraftStep.review.rawValue)
        XCTAssertEqual(record.startedAt, started); XCTAssertEqual(record.completedAt, completed); XCTAssertEqual(record.observedAtUTC, started)
        XCTAssertEqual(record.timeZoneID, "America/New_York"); XCTAssertEqual(record.utcOffsetMinutes, -300)
        XCTAssertEqual(record.localDate, "2026-01-14"); XCTAssertEqual(record.localTime, "20:02:03")
        XCTAssertEqual(record.afterDarkAcknowledgementKey, "after_dark"); XCTAssertEqual(record.afterDarkAcknowledgementCopy, pack.acknowledgements[0].copy)
        XCTAssertEqual(record.afterDarkAcknowledgementVersion, pack.acknowledgements[0].version); XCTAssertEqual(record.afterDarkAcknowledgementAccepted, true)
        XCTAssertEqual(record.safePositionAcknowledgementKey, "safe_authorized_position"); XCTAssertEqual(record.safePositionAcknowledgementCopy, pack.acknowledgements[1].copy)
        XCTAssertEqual(record.safePositionAcknowledgementVersion, pack.acknowledgements[1].version); XCTAssertEqual(record.safePositionAcknowledgementAccepted, true)
        XCTAssertEqual(record.packID, pack.packID); XCTAssertEqual(record.packSchemaVersion, 1); XCTAssertEqual(record.packContentVersion, 1)
        XCTAssertEqual(record.pdfTemplateID, "field.evidence.pdf.worklight.v1"); XCTAssertEqual(record.pdfTemplateVersion, 1)
        XCTAssertEqual(record.outcomeKey, "resolved"); XCTAssertEqual(record.couldNotVerifyKey, "conditions_changed")
        XCTAssertEqual(record.couldNotVerifyDisplaySnapshot, "Conditions changed"); XCTAssertEqual(record.couldNotVerifyRegistryVersion, "cnv.reason.en-US.v1")
        XCTAssertEqual(record.workPerformedLocalDate, "2026-01-14"); XCTAssertEqual(record.workDescription, "Replaced power supply")
        XCTAssertEqual(record.note, "Exact fixture note"); XCTAssertEqual(record.finalizationMutationID, ids.mutation)

        let evidence = try XCTUnwrap(reopened.fetch(FetchDescriptor<EvidenceFile>()).first)
        XCTAssertEqual(evidence.id, ids.evidence); XCTAssertEqual(evidence.schemaVersion, 1); XCTAssertEqual(evidence.recordID, ids.record)
        XCTAssertEqual(evidence.purposeKey, "wide_context"); XCTAssertEqual(evidence.relativePath, "evidence/e/original.jpg")
        XCTAssertEqual(evidence.mimeType, "image/jpeg"); XCTAssertEqual(evidence.byteCount, 123); XCTAssertEqual(evidence.sha256, String(repeating: "a", count: 64))
        XCTAssertEqual(evidence.createdAt, started); XCTAssertEqual(evidence.thumbnailRelativePath, "evidence/e/thumbnail.jpg")
        XCTAssertEqual(evidence.thumbnailByteCount, 45); XCTAssertEqual(evidence.thumbnailSHA256, String(repeating: "b", count: 64))

        let issue = try XCTUnwrap(reopened.fetch(FetchDescriptor<Issue>()).first)
        XCTAssertEqual(issue.id, ids.issue); XCTAssertEqual(issue.schemaVersion, 1); XCTAssertEqual(issue.assetID, ids.asset)
        XCTAssertEqual(issue.openedByRecordID, ids.parent); XCTAssertEqual(issue.labelKey, "dark_section")
        XCTAssertEqual(issue.labelDisplaySnapshot, "Section appears dark"); XCTAssertEqual(issue.status, IssueStatus.resolved.rawValue)
        XCTAssertEqual(issue.resolvedByRecordID, ids.record); XCTAssertEqual(issue.createdAt, started); XCTAssertEqual(issue.updatedAt, completed)

        let packet = try XCTUnwrap(reopened.fetch(FetchDescriptor<Packet>()).first)
        XCTAssertEqual(packet.id, ids.packet); XCTAssertEqual(packet.schemaVersion, 1); XCTAssertEqual(packet.stableRootID, ids.stableRoot)
        XCTAssertEqual(packet.currentRecordID, ids.record); XCTAssertTrue(packet.evaluationCounted); XCTAssertEqual(packet.contentDeletedAt, completed); XCTAssertEqual(packet.createdAt, started)

        let report = try XCTUnwrap(reopened.fetch(FetchDescriptor<Report>()).first)
        XCTAssertEqual(report.id, ids.report); XCTAssertEqual(report.schemaVersion, 1); XCTAssertEqual(report.packetID, ids.packet)
        XCTAssertEqual(report.sourceRecordID, ids.record); XCTAssertEqual(report.snapshotSchemaVersion, 1); XCTAssertEqual(report.snapshotRelativePath, "snapshots/r.json")
        XCTAssertEqual(report.snapshotSHA256, String(repeating: "c", count: 64)); XCTAssertEqual(report.pdfState, ReportPDFState.ready.rawValue)
        XCTAssertEqual(report.pdfRelativePath, "pdfs/r.pdf"); XCTAssertEqual(report.pdfSHA256, String(repeating: "d", count: 64)); XCTAssertEqual(report.createdAt, completed); XCTAssertEqual(report.replacesReportID, ids.replacesReport)
    }

    @MainActor
    func testExistingS2TwoModelGenerationReopensUnchangedUnderSevenModelSchema() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let generationID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let siteID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let assetID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let dataRoot = root.appendingPathComponent("FieldEvidenceData", isDirectory: true)
        let generationRoot = dataRoot
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(generationID.uuidString.lowercased(), isDirectory: true)
        let storeURL = generationRoot.appendingPathComponent("model.sqlite", isDirectory: false)
        try fileManager.createDirectory(at: generationRoot, withIntermediateDirectories: true)

        do {
            let s2Schema = Schema(
                [Site.self, Asset.self],
                version: Schema.Version(1, 0, 0)
            )
            let configuration = ModelConfiguration(
                "FieldEvidenceV1",
                schema: s2Schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            var container: ModelContainer? = try ModelContainer(
                for: s2Schema,
                migrationPlan: nil,
                configurations: [configuration]
            )
            let context = try XCTUnwrap(container).mainContext
            context.insert(Site(id: siteID, label: "Legacy North Campus", address: "10 Legacy Way", timeZoneID: "America/New_York", createdAt: createdAt, updatedAt: updatedAt))
            context.insert(Asset(id: assetID, siteID: siteID, packID: pack.packID, packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion, label: "Legacy Monument Sign", createdAt: createdAt, updatedAt: updatedAt))
            try context.save()
            container = nil
        }

        try Data("{\"generationID\":\"\(generationID.uuidString.lowercased())\",\"schemaVersion\":1}".utf8)
            .write(to: dataRoot.appendingPathComponent("current.json"), options: .atomic)
        try Data("{\"generationIDs\":[],\"schemaVersion\":1}".utf8)
            .write(to: dataRoot.appendingPathComponent("retired.json"), options: .atomic)

        let reopened = try StoreGenerationFactory(applicationSupportURL: root)
            .openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, generationID)
        let sites = try reopened.modelContext.fetch(FetchDescriptor<Site>())
        let assets = try reopened.modelContext.fetch(FetchDescriptor<Asset>())
        let site = try XCTUnwrap(sites.first)
        let asset = try XCTUnwrap(assets.first)
        XCTAssertEqual(sites.count, 1); XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(site.id, siteID); XCTAssertEqual(site.schemaVersion, 1); XCTAssertEqual(site.label, "Legacy North Campus")
        XCTAssertEqual(site.address, "10 Legacy Way"); XCTAssertEqual(site.timeZoneID, "America/New_York")
        XCTAssertEqual(site.createdAt, createdAt); XCTAssertEqual(site.updatedAt, updatedAt)
        XCTAssertEqual(asset.id, assetID); XCTAssertEqual(asset.schemaVersion, 1); XCTAssertEqual(asset.siteID, siteID)
        XCTAssertEqual(asset.packID, pack.packID); XCTAssertEqual(asset.packSchemaVersion, 1); XCTAssertEqual(asset.packContentVersion, 1)
        XCTAssertEqual(asset.label, "Legacy Monument Sign"); XCTAssertEqual(asset.createdAt, createdAt); XCTAssertEqual(asset.updatedAt, updatedAt)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<EvidenceFile>()), 0)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Issue>()), 0)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Packet>()), 0)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Report>()), 0)
    }

    @MainActor
    func testFixedPreflightCreatesAndReopensOneExactCheckDraftOnly() throws {
        let root = try makeTemporaryApplicationSupportURL()
        // Retain this private root while the owner, session and context alias its store.
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let instant = Date(timeIntervalSince1970: 1_768_438_923)
        let fixture = try makeCurrentDraftFixture(in: factory, timeZoneID: nil,
            createdAt: instant.addingTimeInterval(-1))
        defer { closeCurrentDraftWriter(fixture.owner) }
        let ids = fixture.ids
        let context = ids.session.modelContext
        let coordinator = fixture.coordinator
        fixture.clock.set(instant)

        let draft = try coordinator.beginOrResumeDraft(
            BeginDraftSubmission(assetID: ids.asset, requestedStage: .check, issueID: nil, observedAtUTC: instant, confirmedTimeZoneID: "America/New_York", afterDarkAccepted: true, safePositionAccepted: true)
        )
        assertExactCheckDraft(draft, assetID: ids.asset, instant: instant)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EvidenceFile>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Issue>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Packet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Report>()), 0)

        let savedSite = try XCTUnwrap(context.fetch(FetchDescriptor<Site>()).first)
        XCTAssertEqual(savedSite.timeZoneID, "America/New_York")

        let reopenedSession = try factory.openOrBootstrapCurrent()
        let reopenedContext = reopenedSession.modelContext
        let reopened = try XCTUnwrap(reopenedContext.fetch(FetchDescriptor<WorkflowRecord>()).first)
        XCTAssertEqual(reopened.id, draft.id)
        assertExactCheckDraft(reopened, assetID: ids.asset, instant: instant)
    }

    @MainActor
    func testInvalidPreflightWritesNoZoneAndNoDraft() throws {
        struct InvalidCase {
            let name: String
            let zone: String?
            let afterDark: Bool
            let safe: Bool
            let expected: CheckRunnerCoordinatorError
        }
        let cases = [
            InvalidCase(name: "missing zone", zone: nil, afterDark: true, safe: true, expected: .timeZoneConfirmationRequired),
            InvalidCase(name: "unknown zone", zone: "Mars/Olympus", afterDark: true, safe: true, expected: .invalidTimeZoneID),
            InvalidCase(name: "after dark rejected", zone: "America/New_York", afterDark: false, safe: true, expected: .acknowledgementsRequired),
            InvalidCase(name: "safe position rejected", zone: "America/New_York", afterDark: true, safe: false, expected: .acknowledgementsRequired),
        ]

        for testCase in cases {
            let root = try makeTemporaryApplicationSupportURL()
            defer { try? fileManager.removeItem(at: root) }
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            let ids = try seedSiteAndAsset(in: factory, timeZoneID: nil)
            let context = ids.session.modelContext
            let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
            let submission = BeginDraftSubmission(assetID: ids.asset, requestedStage: .check, issueID: nil, observedAtUTC: Date(timeIntervalSince1970: 1_768_438_923), confirmedTimeZoneID: testCase.zone, afterDarkAccepted: testCase.afterDark, safePositionAccepted: testCase.safe)

            XCTAssertThrowsError(try coordinator.beginOrResumeDraft(submission), testCase.name) {
                XCTAssertEqual($0 as? CheckRunnerCoordinatorError, testCase.expected, testCase.name)
            }
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkflowRecord>()), 0, testCase.name)
            XCTAssertNil(try XCTUnwrap(context.fetch(FetchDescriptor<Site>()).first).timeZoneID, testCase.name)
        }
    }

    @MainActor
    func testExistingDraftWinsBeforeEveryNewRequestedRouteValidation() throws {
        let root = try makeTemporaryApplicationSupportURL()
        // Retain this private root while the owner, session and context alias its store.
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let instant = Date(timeIntervalSince1970: 1_768_438_923)
        var access = DraftAccessNormalizedStateV1.entitled
        let fixture = try makeCurrentDraftFixture(in: factory,
            timeZoneID: "America/New_York", createdAt: instant.addingTimeInterval(-1),
            draftAccessState: { access })
        defer { closeCurrentDraftWriter(fixture.owner) }
        let ids = fixture.ids
        let context = ids.session.modelContext
        let coordinator = fixture.coordinator
        fixture.clock.set(instant)
        let original = try coordinator.beginOrResumeDraft(BeginDraftSubmission(assetID: ids.asset, requestedStage: .check, issueID: nil, observedAtUTC: instant, confirmedTimeZoneID: nil, afterDarkAccepted: true, safePositionAccepted: true))
        fixture.clock.set(instant.addingTimeInterval(1))
        let persistedBefore = try lineageState(in: context)
        let revisionBefore = try fixture.dependencies.writer.currentRevision()
        access = .formerPaidInactive
        XCTAssertEqual(try coordinator.prepare(assetID: ids.asset).existingDraftID, original.id)

        let invalidIssue = UUID()
        let workResult = try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .work, issueID: nil)
        let recheckResult = try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .recheck, issueID: invalidIssue)
        let invalidPreflightResult = try coordinator.beginOrResumeDraft(BeginDraftSubmission(assetID: ids.asset, requestedStage: .check, issueID: invalidIssue, observedAtUTC: nil, confirmedTimeZoneID: "Invalid/Zone", afterDarkAccepted: false, safePositionAccepted: false))

        XCTAssertEqual(workResult.id, original.id)
        XCTAssertEqual(recheckResult.id, original.id)
        XCTAssertEqual(invalidPreflightResult.id, original.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        assertExactCheckDraft(original, assetID: ids.asset, instant: Date(timeIntervalSince1970: 1_768_438_923))
        // C472: a different requested issue also resumes this exact saved check.
        XCTAssertEqual(try coordinator.accessDecision(assetID: ids.asset,
            requestedStage: .work, issueID: invalidIssue), .continueExisting)
        XCTAssertEqual(try coordinator.beginOrResumeDraft(assetID: ids.asset,
            requestedStage: .work, issueID: invalidIssue).id, original.id)
        try coordinator.requestRecheck(assetID: ids.asset, issueID: invalidIssue)
        XCTAssertEqual(try coordinator.beginCheck(assetID: ids.asset, timeZoneID: "Invalid/Zone",
            isTimeZoneConfirmed: false, afterDarkAccepted: false, safePositionAccepted: false,
            observedAt: instant.addingTimeInterval(2)).id, original.id)
        XCTAssertEqual(try lineageState(in: context), persistedBefore)
        XCTAssertEqual(try fixture.dependencies.writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Issue>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EvidenceFile>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Packet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Report>()), 0)
        XCTAssertFalse(context.hasChanges)

        let reopenedSession = try factory.openOrBootstrapCurrent()
        let reopened = reopenedSession.modelContext
        let saved = try XCTUnwrap(reopened.fetch(FetchDescriptor<WorkflowRecord>()).first)
        XCTAssertEqual(saved.id, original.id)
        assertExactCheckDraft(saved, assetID: ids.asset, instant: instant)
        XCTAssertEqual(try lineageState(in: reopened), persistedBefore)
    }

    @MainActor
    func testExistingWorkAndRecheckResumeValidateTheirOwnIssueLineage() async throws {
        for existingStage in [WorkflowStage.work, .recheck] {
            let root = try makeTemporaryApplicationSupportURL()
            let fixture = try makeCurrentDraftFixture(
                in: StoreGenerationFactory(applicationSupportURL: root),
                timeZoneID: "America/New_York", createdAt: Date(timeIntervalSince1970: 99))
            defer { closeCurrentDraftWriter(fixture.owner) }
            let context = fixture.ids.session.modelContext
            let issueID = UUID()
            fixture.clock.set(Date(timeIntervalSince1970: 100))
            let opening = try fixture.coordinator.beginOrResumeDraft(BeginDraftSubmission(
                assetID: fixture.ids.asset, requestedStage: .check, issueID: nil,
                observedAtUTC: Date(timeIntervalSince1970: 100), confirmedTimeZoneID: nil,
                afterDarkAccepted: true, safePositionAccepted: true))
            try await finishCurrentCheck(fixture, draft: opening,
                selection: .visibleIssue(labelKey: "dark_section"), issueID: issueID,
                completedAt: Date(timeIntervalSince1970: 200))
            let work = try fixture.coordinator.beginOrResumeDraft(assetID: fixture.ids.asset,
                requestedStage: .work, issueID: issueID)
            let draft: WorkflowRecord
            if existingStage == .recheck {
                try await finishCurrentWork(fixture, draft: work,
                    completedAt: Date(timeIntervalSince1970: 300))
                fixture.clock.set(Date(timeIntervalSince1970: 400))
                draft = try fixture.coordinator.beginOrResumeDraft(BeginDraftSubmission(
                    assetID: fixture.ids.asset, requestedStage: .recheck, issueID: issueID,
                    observedAtUTC: Date(timeIntervalSince1970: 400), confirmedTimeZoneID: nil,
                    afterDarkAccepted: true, safePositionAccepted: true))
            } else {
                draft = work
            }
            fixture.clock.set(draft.startedAt.addingTimeInterval(1))
            let before = try lineageState(in: context)
            let revisionBefore = try fixture.dependencies.writer.currentRevision()
            let resumed = try fixture.coordinator.beginOrResumeDraft(assetID: fixture.ids.asset,
                requestedStage: .check, issueID: UUID())
            XCTAssertEqual(resumed.id, draft.id)
            XCTAssertEqual(resumed.stage, existingStage.rawValue)
            XCTAssertEqual(resumed.issueID, issueID)
            XCTAssertEqual(try lineageState(in: context), before)
            XCTAssertEqual(try fixture.dependencies.writer.currentRevision(), revisionBefore)

            // The saved draft's own current parent still governs continuation.
            draft.parentRecordID = UUID()
            try context.save()
            let corruptBefore = try lineageState(in: context)
            XCTAssertThrowsError(try fixture.coordinator.beginOrResumeDraft(assetID: fixture.ids.asset,
                requestedStage: .check, issueID: nil)) {
                XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .accessDenied(.blockInvalidRequest))
            }
            XCTAssertEqual(try lineageState(in: context), corruptBefore)
            XCTAssertEqual(try fixture.dependencies.writer.currentRevision(), revisionBefore)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testExistingDraftResumeRejectsDirtyCorruptAndAmbiguousDrafts() throws {
        let root = try makeTemporaryApplicationSupportURL()
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let instant = Date(timeIntervalSince1970: 1_768_438_923)
        let fixture = try makeCurrentDraftFixture(in: factory,
            timeZoneID: "America/New_York", createdAt: instant.addingTimeInterval(-1))
        defer { closeCurrentDraftWriter(fixture.owner) }
        let context = fixture.ids.session.modelContext
        fixture.clock.set(instant)
        let draft = try fixture.coordinator.beginOrResumeDraft(BeginDraftSubmission(
            assetID: fixture.ids.asset, requestedStage: .check, issueID: nil,
            observedAtUTC: instant, confirmedTimeZoneID: nil,
            afterDarkAccepted: true, safePositionAccepted: true))
        fixture.clock.set(instant.addingTimeInterval(1))
        let revisionBefore = try fixture.dependencies.writer.currentRevision()

        draft.note = "Unsaved owner edit"
        XCTAssertThrowsError(try fixture.coordinator.beginOrResumeDraft(
            assetID: fixture.ids.asset, requestedStage: .work, issueID: UUID())) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .invalidLineage)
        }
        XCTAssertEqual(draft.note, "Unsaved owner edit")
        XCTAssertTrue(context.hasChanges)
        context.rollback()
        XCTAssertNil(draft.note)

        // Construct the hostile root through the model's initializer; the
        // production root remains immutable after construction.
        let corrupt = WorkflowRecord(
            id: draft.id, assetID: draft.assetID, packetID: draft.packetID,
            issueID: draft.issueID, parentRecordID: draft.parentRecordID,
            recordRevisionRootID: UUID(), revisesRecordID: draft.revisesRecordID,
            evidenceSourceRecordID: draft.evidenceSourceRecordID,
            revisionKind: .original, stage: .check, state: .draft, draftStepKey: .wide,
            startedAt: draft.startedAt, completedAt: draft.completedAt,
            observedAtUTC: draft.observedAtUTC, timeZoneID: draft.timeZoneID,
            utcOffsetMinutes: draft.utcOffsetMinutes,
            localDate: draft.localDate, localTime: draft.localTime,
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
            pdfTemplateID: draft.pdfTemplateID, pdfTemplateVersion: draft.pdfTemplateVersion,
            outcomeKey: draft.outcomeKey, couldNotVerifyKey: draft.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: draft.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: draft.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: draft.workPerformedLocalDate,
            workDescription: draft.workDescription, note: draft.note,
            finalizationMutationID: draft.finalizationMutationID)
        // Persist deletion before reinserting the same unique logical ID, so
        // this fixture does not depend on upsert or read the deleted alias.
        context.delete(draft)
        try context.save()
        context.insert(corrupt)
        try context.save()
        let persistedCorrupt = try context.fetch(FetchDescriptor<WorkflowRecord>())
        XCTAssertEqual(persistedCorrupt.count, 1)
        XCTAssertEqual(persistedCorrupt.map(\.id), [corrupt.id])
        XCTAssertEqual(persistedCorrupt.map(\.recordRevisionRootID), [corrupt.recordRevisionRootID])
        XCTAssertEqual(persistedCorrupt.map(\.state), [WorkflowState.draft.rawValue])
        XCTAssertNotEqual(corrupt.recordRevisionRootID, corrupt.id)
        let corruptBefore = try lineageState(in: context)
        XCTAssertEqual(try fixture.coordinator.accessDecision(assetID: fixture.ids.asset,
            requestedStage: .recheck, issueID: UUID()), .blockInvalidRequest)
        XCTAssertThrowsError(try fixture.coordinator.beginOrResumeDraft(
            assetID: fixture.ids.asset, requestedStage: .work, issueID: nil)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .accessDenied(.blockInvalidRequest))
        }
        XCTAssertEqual(try lineageState(in: context), corruptBefore)
        XCTAssertFalse(context.hasChanges)

        let duplicate = completedRecord(id: UUID(), assetID: fixture.ids.asset,
            issueID: nil, parentID: nil, stage: .check)
        duplicate.state = WorkflowState.draft.rawValue
        context.insert(duplicate)
        try context.save()
        let ambiguousBefore = try lineageState(in: context)
        XCTAssertThrowsError(try fixture.coordinator.beginOrResumeDraft(
            assetID: fixture.ids.asset, requestedStage: .work, issueID: UUID())) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .multipleActiveDrafts)
        }
        XCTAssertEqual(try lineageState(in: context), ambiguousBefore)
        XCTAssertEqual(try fixture.dependencies.writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Issue>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testExistingDraftResumeRejectsForeignReadOnlyAndInvalidatedWriterContexts() throws {
        let root = try makeTemporaryApplicationSupportURL()
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let instant = Date(timeIntervalSince1970: 1_768_438_923)
        let fixture = try makeCurrentDraftFixture(in: factory,
            timeZoneID: "America/New_York", createdAt: instant.addingTimeInterval(-1))
        defer { closeCurrentDraftWriter(fixture.owner) }
        let context = fixture.ids.session.modelContext
        fixture.clock.set(instant)
        let draft = try fixture.coordinator.beginOrResumeDraft(BeginDraftSubmission(
            assetID: fixture.ids.asset, requestedStage: .check, issueID: nil,
            observedAtUTC: instant, confirmedTimeZoneID: nil,
            afterDarkAccepted: true, safePositionAccepted: true))
        fixture.clock.set(instant.addingTimeInterval(1))
        let before = try lineageState(in: context)
        let revisionBefore = try fixture.dependencies.writer.currentRevision()
        let profile = try fixture.dependencies.profileRegistry.resolve(
            PackageReleaseIdentityV1(package: pack))

        let readOnlyConfiguration = ModelConfiguration("FieldEvidenceV1",
            schema: context.container.schema,
            url: fixture.ids.session.generationRootURL.appendingPathComponent("model.sqlite"),
            allowsSave: false, cloudKitDatabase: .none)
        let readOnlyContainer = try ModelContainer(for: context.container.schema,
            migrationPlan: nil, configurations: [readOnlyConfiguration])
        readOnlyContainer.mainContext.autosaveEnabled = false
        let readOnlyRunner = try CheckRunnerCoordinator(modelContext: readOnlyContainer.mainContext,
            packageLifecycleDependencies: fixture.dependencies, packageLifecycleProfile: profile)
        XCTAssertEqual(try readOnlyContainer.mainContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertThrowsError(try readOnlyRunner.beginOrResumeDraft(assetID: fixture.ids.asset,
            requestedStage: .work, issueID: UUID())) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
        }
        XCTAssertFalse(readOnlyContainer.mainContext.hasChanges)

        let foreignRoot = try makeTemporaryApplicationSupportURL()
        let foreign = try makeCurrentDraftFixture(
            in: StoreGenerationFactory(applicationSupportURL: foreignRoot),
            timeZoneID: "America/New_York", createdAt: instant.addingTimeInterval(-1))
        defer { closeCurrentDraftWriter(foreign.owner) }
        foreign.clock.set(instant)
        _ = try foreign.coordinator.beginOrResumeDraft(BeginDraftSubmission(
            assetID: foreign.ids.asset, requestedStage: .check, issueID: nil,
            observedAtUTC: instant, confirmedTimeZoneID: nil,
            afterDarkAccepted: true, safePositionAccepted: true))
        let foreignBefore = try lineageState(in: foreign.ids.session.modelContext)
        let foreignRunner = try CheckRunnerCoordinator(modelContext: foreign.ids.session.modelContext,
            packageLifecycleDependencies: fixture.dependencies, packageLifecycleProfile: profile)
        XCTAssertThrowsError(try foreignRunner.beginOrResumeDraft(assetID: foreign.ids.asset,
            requestedStage: .work, issueID: UUID())) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
        }
        XCTAssertThrowsError(try fixture.coordinator.beginOrResumeDraft(assetID: foreign.ids.asset,
            requestedStage: .work, issueID: nil)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .assetNotFound)
        }
        XCTAssertEqual(try lineageState(in: foreign.ids.session.modelContext), foreignBefore)
        XCTAssertEqual(try lineageState(in: context), before)
        XCTAssertEqual(try fixture.dependencies.writer.currentRevision(), revisionBefore)

        // Invalidating the incumbent writer revokes even an otherwise valid saved draft.
        fixture.dependencies.writer.invalidate()
        XCTAssertThrowsError(try fixture.coordinator.beginOrResumeDraft(assetID: fixture.ids.asset,
            requestedStage: .recheck, issueID: UUID())) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        XCTAssertEqual(try lineageState(in: context), before)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkflowRecord>()).map(\.id), [draft.id])
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testMultipleActiveDraftsFailClosed() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let ids = try seedSiteAndAsset(in: factory, timeZoneID: "America/New_York")
        let context = ids.session.modelContext
        let first = completedRecord(id: UUID(), assetID: ids.asset, issueID: nil, parentID: nil, stage: .check)
        let second = completedRecord(id: UUID(), assetID: ids.asset, issueID: nil, parentID: nil, stage: .check)
        first.state = WorkflowState.draft.rawValue
        second.state = WorkflowState.draft.rawValue
        context.insert(first); context.insert(second); try context.save()
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)

        XCTAssertThrowsError(try coordinator.existingDraft(assetID: ids.asset)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .multipleActiveDrafts)
        }
    }

    @MainActor
    func testNoDraftStageIssueAndLatestParentValidationIsExact() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        // Retain this private root while the owner, session and context alias its store.
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let fixture = try makeCurrentDraftFixture(in: factory,
            timeZoneID: "America/New_York", createdAt: Date(timeIntervalSince1970: 100))
        defer { closeCurrentDraftWriter(fixture.owner) }
        let ids = fixture.ids
        let context = ids.session.modelContext
        let coordinator = fixture.coordinator

        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .check, issueID: UUID())) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .issueNotAllowed)
        }
        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .work, issueID: nil)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .issueRequired)
        }
        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .work, issueID: UUID())) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .issueNotFound)
        }

        let issueID = UUID()
        let opening = try coordinator.beginOrResumeDraft(BeginDraftSubmission(
            assetID: ids.asset, requestedStage: .check, issueID: nil,
            observedAtUTC: Date(timeIntervalSince1970: 100), confirmedTimeZoneID: nil,
            afterDarkAccepted: true, safePositionAccepted: true))
        try await finishCurrentCheck(fixture, draft: opening,
            selection: .visibleIssue(labelKey: "dark_section"), issueID: issueID,
            completedAt: Date(timeIntervalSince1970: 200))
        let issue = try XCTUnwrap(context.fetch(FetchDescriptor<Issue>()).first { $0.id == issueID })

        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .recheck, issueID: issue.id)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .issueStateMismatch)
        }
        let work = try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .work, issueID: issue.id)
        XCTAssertEqual(work.stage, WorkflowStage.work.rawValue)
        XCTAssertEqual(work.issueID, issue.id)
        XCTAssertEqual(work.parentRecordID, opening.id)
        XCTAssertNil(work.observedAtUTC); XCTAssertNil(work.afterDarkAcknowledgementKey)

        // Complete the actual returned work through the same sole writer;
        // its receipt-backed transition, rather than a raw row, makes Recheck due.
        try await finishCurrentWork(fixture, draft: work,
            completedAt: Date(timeIntervalSince1970: 200))
        let completedWork = work

        let recheck = try coordinator.beginOrResumeDraft(
            BeginDraftSubmission(assetID: ids.asset, requestedStage: .recheck, issueID: issue.id, observedAtUTC: Date(timeIntervalSince1970: 1_768_438_923), confirmedTimeZoneID: nil, afterDarkAccepted: true, safePositionAccepted: true)
        )
        XCTAssertEqual(recheck.stage, WorkflowStage.recheck.rawValue)
        XCTAssertEqual(recheck.issueID, issue.id)
        XCTAssertEqual(recheck.parentRecordID, completedWork.id)
        XCTAssertEqual(recheck.draftStepKey, WorkflowDraftStep.wide.rawValue)

        // Traverse both accepted child branches, not just the opening check.
        // This completion follows the unchanged 2026 observed instant above.
        try await finishCurrentCheck(fixture, draft: recheck,
            selection: .issueStillVisible(note: nil), issueID: issue.id,
            completedAt: Date(timeIntervalSince1970: 1_768_438_926))
        let completedRecheck = recheck
        let nextWork = try coordinator.beginOrResumeDraft(
            assetID: ids.asset, requestedStage: .work, issueID: issue.id)
        XCTAssertEqual(nextWork.parentRecordID, completedRecheck.id)
        XCTAssertEqual(nextWork.issueID, issue.id)
        XCTAssertEqual(nextWork.stage, WorkflowStage.work.rawValue)

        // Deliberate hostile source corruption after all successful mutations.
        // No writer effect is requested from this corrupted state.
        context.delete(nextWork)
        completedRecheck.outcomeKey = "work_recorded"
        try context.save()
        let invalidSource = try lineageState(in: context)
        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(
            assetID: ids.asset, requestedStage: .work, issueID: issue.id)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .invalidLineage)
        }
        XCTAssertEqual(try lineageState(in: context), invalidSource)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testForkedIssueLineageFailsClosedWithoutCreatingDraft() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let ids = try seedSiteAndAsset(in: factory, timeZoneID: "America/New_York")
        let context = ids.session.modelContext
        let opening = completedRecord(id: UUID(), assetID: ids.asset, issueID: nil, parentID: nil, stage: .check)
        let issue = Issue(id: UUID(), assetID: ids.asset, openedByRecordID: opening.id, labelKey: "dark_section", labelDisplaySnapshot: "Section appears dark", status: .recheckDue, resolvedByRecordID: nil, createdAt: opening.startedAt, updatedAt: opening.startedAt)
        opening.issueID = issue.id
        let firstChild = completedRecord(id: UUID(), assetID: ids.asset, issueID: issue.id, parentID: opening.id, stage: .work)
        let secondChild = completedRecord(id: UUID(), assetID: ids.asset, issueID: issue.id, parentID: opening.id, stage: .recheck)
        context.insert(opening); context.insert(issue); context.insert(firstChild); context.insert(secondChild)
        try context.save()
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        let source = try lineageState(in: context)

        XCTAssertThrowsError(
            try coordinator.beginOrResumeDraft(
                BeginDraftSubmission(assetID: ids.asset, requestedStage: .recheck, issueID: issue.id, observedAtUTC: Date(timeIntervalSince1970: 1_768_438_923), confirmedTimeZoneID: nil, afterDarkAccepted: true, safePositionAccepted: true)
            )
        ) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .invalidLineage)
        }
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
                $0.state == WorkflowState.draft.rawValue
            }.count,
            0
        )
        XCTAssertEqual(try lineageState(in: context), source)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testDifferentIssueOpeningRecheckBecomesTheNewIssuesFirstParent() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        // Retain this private root while the live owner/session/context aliases its store.
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let fixture = try makeCurrentDraftFixture(in: factory,
            timeZoneID: "America/New_York", createdAt: Date(timeIntervalSince1970: 100))
        defer { closeCurrentDraftWriter(fixture.owner) }
        let ids = fixture.ids
        let context = ids.session.modelContext
        let coordinator = fixture.coordinator
        let oldIssueID = UUID()
        let oldOpening = try coordinator.beginOrResumeDraft(BeginDraftSubmission(
            assetID: ids.asset, requestedStage: .check, issueID: nil,
            observedAtUTC: Date(timeIntervalSince1970: 100), confirmedTimeZoneID: nil,
            afterDarkAccepted: true, safePositionAccepted: true))
        try await finishCurrentCheck(fixture, draft: oldOpening,
            selection: .visibleIssue(labelKey: "dark_section"), issueID: oldIssueID,
            completedAt: Date(timeIntervalSince1970: 150))
        let oldIssue = try XCTUnwrap(context.fetch(FetchDescriptor<Issue>()).first { $0.id == oldIssueID })
        let oldWork = try coordinator.beginOrResumeDraft(
            assetID: ids.asset, requestedStage: .work, issueID: oldIssueID)
        try await finishCurrentWork(fixture, draft: oldWork,
            completedAt: Date(timeIntervalSince1970: 200))
        fixture.clock.set(Date(timeIntervalSince1970: 201))
        let openingRecheck = try coordinator.beginOrResumeDraft(BeginDraftSubmission(
            assetID: ids.asset, requestedStage: .recheck, issueID: oldIssueID,
            observedAtUTC: Date(timeIntervalSince1970: 201), confirmedTimeZoneID: nil,
            afterDarkAccepted: true, safePositionAccepted: true))
        // Produce the old resolution and external new-Issue opener in one real
        // receipt-backed finalization, using this fixture's existing writer.
        for source in [(offset: 1.0, seed: UInt8(31)), (offset: 2.0, seed: UInt8(79))] {
            let createdAt = openingRecheck.startedAt.addingTimeInterval(source.offset)
            fixture.clock.set(createdAt)
            let candidate = try await coordinator.importCandidate(assetID: ids.asset,
                sourceData: try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: source.seed),
                createdAt: createdAt)
            _ = try await coordinator.accept(candidate: candidate, assetID: ids.asset)
        }
        let newIssueID = UUID()
        let completedAt = Date(timeIntervalSince1970: 300)
        fixture.clock.set(completedAt)
        let result = try await coordinator.finalize(assetID: ids.asset,
            selection: .originalResolvedDifferentIssue(labelKey: "color_mismatch", note: nil),
            completedAt: completedAt, snapshotCreatedAt: completedAt,
            sourceApp: SourceAppSnapshotV1(build: "draft-schema", version: "1"),
            identifiers: FinalizationIdentifiers(mutationID: UUID(), packetID: UUID(),
                stableRootID: UUID(), reportID: UUID(), issueID: oldIssueID, newIssueID: newIssueID))
        XCTAssertEqual(result.recordID, openingRecheck.id)
        XCTAssertEqual(result.issueID, oldIssueID)
        XCTAssertEqual(result.newIssueID, newIssueID)
        let newIssue = try XCTUnwrap(context.fetch(FetchDescriptor<Issue>()).first { $0.id == newIssueID })
        XCTAssertEqual(newIssue.openedByRecordID, openingRecheck.id)
        XCTAssertEqual(newIssue.createdAt, completedAt)
        XCTAssertEqual(oldIssue.updatedAt, completedAt)

        let work = try coordinator.beginOrResumeDraft(
            assetID: ids.asset,
            requestedStage: .work,
            issueID: newIssue.id
        )

        XCTAssertEqual(work.stage, WorkflowStage.work.rawValue)
        XCTAssertEqual(work.state, WorkflowState.draft.rawValue)
        XCTAssertEqual(work.issueID, newIssue.id)
        XCTAssertNotEqual(work.issueID, oldIssueID)
        XCTAssertEqual(work.parentRecordID, openingRecheck.id)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
                $0.state == WorkflowState.draft.rawValue
            }.map(\.id),
            [work.id]
        )

        // The new issue's opening belongs to the resolved old issue. Its own
        // later work/recheck rows must still form one exact accepted chain.
        try await finishCurrentWork(fixture, draft: work,
            completedAt: Date(timeIntervalSince1970: 350))
        let completedWork = work
        let mutationID = try MutationIDV1(rawValue: XCTUnwrap(completedWork.finalizationMutationID))
        let envelope = try XCTUnwrap(fixture.dependencies.writer.workEnvelope(mutationID: mutationID))
        XCTAssertNotNil(try fixture.dependencies.writer.workCommitReceipt(envelope: envelope))
        fixture.clock.set(Date(timeIntervalSince1970: 351))
        let completedRecheck = try coordinator.beginOrResumeDraft(BeginDraftSubmission(
            assetID: ids.asset, requestedStage: .recheck, issueID: newIssue.id,
            observedAtUTC: Date(timeIntervalSince1970: 351), confirmedTimeZoneID: nil,
            afterDarkAccepted: true, safePositionAccepted: true))
        try await finishCurrentCheck(fixture, draft: completedRecheck,
            selection: .issueStillVisible(note: nil), issueID: newIssue.id,
            completedAt: Date(timeIntervalSince1970: 400))
        let continued = try coordinator.beginOrResumeDraft(
            assetID: ids.asset, requestedStage: .work, issueID: newIssue.id)
        XCTAssertEqual(continued.parentRecordID, completedRecheck.id)
        XCTAssertEqual(continued.issueID, newIssue.id)
        XCTAssertEqual(continued.stage, WorkflowStage.work.rawValue)
        XCTAssertEqual(oldIssue.resolvedByRecordID, openingRecheck.id)
        XCTAssertEqual(oldIssue.status, IssueStatus.resolved.rawValue)

        context.delete(continued)
        completedRecheck.outcomeKey = "work_recorded"
        try context.save()
        let invalidSource = try lineageState(in: context)
        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(
            assetID: ids.asset, requestedStage: .work, issueID: newIssue.id)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .invalidLineage)
        }
        XCTAssertEqual(try lineageState(in: context), invalidSource)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testDifferentIssueOpeningRejectsAForkedOldIssueChain() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let ids = try seedSiteAndAsset(in: factory, timeZoneID: "America/New_York")
        let context = ids.session.modelContext
        let oldIssueID = UUID()
        let oldOpening = completedRecord(id: UUID(), assetID: ids.asset, issueID: oldIssueID, parentID: nil, stage: .check)
        let oldWork = completedRecord(id: UUID(), assetID: ids.asset, issueID: oldIssueID, parentID: oldOpening.id, stage: .work)
        let forkedWork = completedRecord(id: UUID(), assetID: ids.asset, issueID: oldIssueID, parentID: oldOpening.id, stage: .work)
        let terminalRecheck = completedRecord(id: UUID(), assetID: ids.asset, issueID: oldIssueID, parentID: oldWork.id, stage: .recheck)
        terminalRecheck.outcomeKey = "original_resolved_different_issue"
        let oldIssue = Issue(id: oldIssueID, assetID: ids.asset, openedByRecordID: oldOpening.id, labelKey: "dark_section", labelDisplaySnapshot: "Section appears dark", status: .resolved, resolvedByRecordID: terminalRecheck.id, createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 300))
        let newIssue = Issue(id: UUID(), assetID: ids.asset, openedByRecordID: terminalRecheck.id, labelKey: "color_mismatch", labelDisplaySnapshot: "Visible color mismatch", status: .open, resolvedByRecordID: nil, createdAt: Date(timeIntervalSince1970: 300), updatedAt: Date(timeIntervalSince1970: 300))
        context.insert(oldOpening); context.insert(oldWork); context.insert(forkedWork)
        context.insert(terminalRecheck); context.insert(oldIssue); context.insert(newIssue)
        try context.save()
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        let source = try lineageState(in: context)

        XCTAssertThrowsError(
            try coordinator.beginOrResumeDraft(
                assetID: ids.asset,
                requestedStage: .work,
                issueID: newIssue.id
            )
        ) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .invalidLineage)
        }
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
                $0.state == WorkflowState.draft.rawValue
            }.count,
            0
        )
        XCTAssertEqual(try lineageState(in: context), source)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    private func lineageState(in context: ModelContext) throws -> [[String]] {
        let records = try context.fetch(FetchDescriptor<WorkflowRecord>()).map { row in
            ["record", row.id.uuidString, row.assetID.uuidString, row.issueID?.uuidString ?? "nil",
             row.parentRecordID?.uuidString ?? "nil", row.recordRevisionRootID.uuidString,
             row.revisesRecordID?.uuidString ?? "nil", row.evidenceSourceRecordID?.uuidString ?? "nil",
             row.revisionKind, row.stage, row.state, row.outcomeKey ?? "nil",
             row.draftStepKey ?? "nil", row.finalizationMutationID?.uuidString ?? "nil",
             String(row.startedAt.timeIntervalSince1970),
             row.completedAt.map { String($0.timeIntervalSince1970) } ?? "nil"]
        }
        let issues = try context.fetch(FetchDescriptor<Issue>()).map { row in
            ["issue", row.id.uuidString, row.assetID.uuidString, row.openedByRecordID.uuidString,
             row.status, row.resolvedByRecordID?.uuidString ?? "nil", row.labelKey,
             row.labelDisplaySnapshot, String(row.createdAt.timeIntervalSince1970),
             String(row.updatedAt.timeIntervalSince1970)]
        }
        return (records + issues).sorted { $0.lexicographicallyPrecedes($1) }
    }

    private var pack: SignPack { .illuminatedSignV1 }

    @MainActor
    private struct CurrentDraftFixture {
        let ids: (session: StoreGenerationSession, site: UUID, asset: UUID)
        let owner: StoreSessionCoordinator
        let dependencies: WorkspacePackageLifecycleDependenciesV1
        let coordinator: CheckRunnerCoordinator
        let clock: CurrentDraftClock
    }

    @MainActor
    private func makeCurrentDraftFixture(in factory: StoreGenerationFactory,
        timeZoneID: String?, createdAt: Date,
        draftAccessState: (@MainActor () -> DraftAccessNormalizedStateV1)? = nil) throws -> CurrentDraftFixture {
        let session = try factory.openOrBootstrapCurrent()
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let clock = CurrentDraftClock(createdAt)
        let owner = try StoreSessionCoordinator(validatingSession: session, clock: clock,
            lifecycleProfileRegistry: registry)
        do {
            let siteID = UUID()
            let assetID = UUID()
            let placementMutationID = try MutationIDV1(rawValue: UUID())
            _ = try owner.workspaceWriter.execute(.createFirstSign(.init(
                siteID: siteID,
                newSite: .init(id: siteID, label: "North Campus", address: nil, timeZoneID: timeZoneID),
                assetID: assetID, assetLabel: "Monument Sign", packID: pack.packID,
                packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
                createdAt: createdAt, initialPlacementMutationID: placementMutationID,
                initialPlacementEventID: UUID(),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
            )), mutationID: placementMutationID)
            let dependencies = try owner.packageLifecycleDependencies(profileRegistry: registry)
            let coordinator = try CheckRunnerCoordinator(modelContext: session.modelContext,
                packageLifecycleDependencies: dependencies, packageLifecycleProfile: profile,
                draftAccessState: draftAccessState)
            coordinator.configureCapture(generationRootURL: session.generationRootURL)
            return CurrentDraftFixture(ids: (session, siteID, assetID), owner: owner,
                dependencies: dependencies, coordinator: coordinator, clock: clock)
        } catch {
            closeCurrentDraftWriter(owner)
            throw error
        }
    }

    @MainActor
    private func finishCurrentCheck(_ fixture: CurrentDraftFixture, draft: WorkflowRecord,
        selection: CheckOutcomeSelection, issueID: UUID,
        completedAt: Date) async throws {
        let sources: [(offset: Double, seed: UInt8)] = [(1, 31), (2, 79)]
        for source in sources {
            let createdAt = draft.startedAt.addingTimeInterval(source.offset)
            fixture.clock.set(createdAt)
            let candidate = try await fixture.coordinator.importCandidate(
                assetID: fixture.ids.asset,
                sourceData: try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: source.seed),
                createdAt: createdAt)
            _ = try await fixture.coordinator.accept(candidate: candidate, assetID: fixture.ids.asset)
        }
        fixture.clock.set(completedAt)
        let result = try await fixture.coordinator.finalize(assetID: fixture.ids.asset,
            selection: selection, completedAt: completedAt, snapshotCreatedAt: completedAt,
            sourceApp: SourceAppSnapshotV1(build: "draft-schema", version: "1"),
            identifiers: FinalizationIdentifiers(mutationID: UUID(), packetID: UUID(),
                stableRootID: UUID(), reportID: UUID(), issueID: issueID))
        XCTAssertEqual(result.recordID, draft.id)
        XCTAssertEqual(result.issueID, issueID)
        XCTAssertNil(result.newIssueID)
    }

    @MainActor
    private func finishCurrentWork(_ fixture: CurrentDraftFixture, draft: WorkflowRecord,
        completedAt: Date) async throws {
        let work = try WorkCoordinator(modelContext: fixture.ids.session.modelContext,
            signPack: pack, generationRootURL: fixture.ids.session.generationRootURL,
            checkRunnerCoordinator: fixture.coordinator, lifecycleDependencies: fixture.dependencies)
        fixture.clock.set(completedAt)
        _ = try await work.saveWork(draftID: draft.id,
            submission: WorkSaveSubmission(performedLocalDate: "1970-01-01",
                description: "Completed fixture work", note: nil, photos: [], completedAt: completedAt),
            identifiers: WorkIdentifiers(mutationID: UUID(), evidenceID: nil))
        XCTAssertEqual(draft.state, WorkflowState.completed.rawValue)
        XCTAssertEqual(draft.outcomeKey, "work_recorded")
    }

    @MainActor
    private func closeCurrentDraftWriter(_ owner: StoreSessionCoordinator) {
        do { try owner.invalidateAndReleaseWriter() }
        catch { XCTFail("Current draft fixture writer close failed: \(error)") }
    }

    @MainActor
    private func seedSiteAndAsset(in factory: StoreGenerationFactory, timeZoneID: String?) throws -> (session: StoreGenerationSession, site: UUID, asset: UUID) {
        let session = try factory.openOrBootstrapCurrent()
        let context = session.modelContext
        let site = Site(label: "North Campus", timeZoneID: timeZoneID)
        let asset = Asset(siteID: site.id, packID: pack.packID, packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion, label: "Monument Sign")
        context.insert(site); context.insert(asset); try context.save()
        return (session, site.id, asset.id)
    }

    private func assertExactCheckDraft(_ draft: WorkflowRecord, assetID: UUID, instant: Date, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(draft.id, draft.recordRevisionRootID, file: file, line: line)
        XCTAssertEqual(draft.schemaVersion, 1, file: file, line: line); XCTAssertEqual(draft.assetID, assetID, file: file, line: line)
        XCTAssertNil(draft.packetID, file: file, line: line); XCTAssertNil(draft.issueID, file: file, line: line); XCTAssertNil(draft.parentRecordID, file: file, line: line)
        XCTAssertNil(draft.revisesRecordID, file: file, line: line); XCTAssertNil(draft.evidenceSourceRecordID, file: file, line: line)
        XCTAssertEqual(draft.revisionKind, WorkflowRevisionKind.original.rawValue, file: file, line: line)
        XCTAssertEqual(draft.stage, WorkflowStage.check.rawValue, file: file, line: line); XCTAssertEqual(draft.state, WorkflowState.draft.rawValue, file: file, line: line)
        XCTAssertEqual(draft.draftStepKey, WorkflowDraftStep.wide.rawValue, file: file, line: line)
        XCTAssertEqual(draft.startedAt, instant, file: file, line: line); XCTAssertEqual(draft.observedAtUTC, instant, file: file, line: line)
        XCTAssertEqual(draft.timeZoneID, "America/New_York", file: file, line: line); XCTAssertEqual(draft.utcOffsetMinutes, -300, file: file, line: line)
        XCTAssertEqual(draft.localDate, "2026-01-14", file: file, line: line); XCTAssertEqual(draft.localTime, "20:02:03", file: file, line: line)
        XCTAssertEqual(draft.afterDarkAcknowledgementKey, "after_dark", file: file, line: line); XCTAssertEqual(draft.afterDarkAcknowledgementCopy, pack.acknowledgements[0].copy, file: file, line: line)
        XCTAssertEqual(draft.afterDarkAcknowledgementVersion, pack.acknowledgements[0].version, file: file, line: line); XCTAssertEqual(draft.afterDarkAcknowledgementAccepted, true, file: file, line: line)
        XCTAssertEqual(draft.safePositionAcknowledgementKey, "safe_authorized_position", file: file, line: line); XCTAssertEqual(draft.safePositionAcknowledgementCopy, pack.acknowledgements[1].copy, file: file, line: line)
        XCTAssertEqual(draft.safePositionAcknowledgementVersion, pack.acknowledgements[1].version, file: file, line: line); XCTAssertEqual(draft.safePositionAcknowledgementAccepted, true, file: file, line: line)
        XCTAssertEqual(draft.packID, pack.packID, file: file, line: line); XCTAssertEqual(draft.packSchemaVersion, 1, file: file, line: line); XCTAssertEqual(draft.packContentVersion, 1, file: file, line: line)
        XCTAssertEqual(draft.pdfTemplateID, "field.evidence.pdf.worklight.v1", file: file, line: line); XCTAssertEqual(draft.pdfTemplateVersion, 1, file: file, line: line)
        XCTAssertNil(draft.completedAt, file: file, line: line); XCTAssertNil(draft.outcomeKey, file: file, line: line); XCTAssertNil(draft.couldNotVerifyKey, file: file, line: line)
        XCTAssertNil(draft.couldNotVerifyDisplaySnapshot, file: file, line: line); XCTAssertNil(draft.couldNotVerifyRegistryVersion, file: file, line: line)
        XCTAssertNil(draft.workPerformedLocalDate, file: file, line: line); XCTAssertNil(draft.workDescription, file: file, line: line); XCTAssertNil(draft.note, file: file, line: line); XCTAssertNil(draft.finalizationMutationID, file: file, line: line)
    }

    private func completedRecord(id: UUID, assetID: UUID, issueID: UUID?, parentID: UUID?, stage: WorkflowStage) -> WorkflowRecord {
        let outcomeKey: String
        let workDate: String?
        let workDescription: String?
        switch stage {
        case .check:
            outcomeKey = "visible_issue"
            workDate = nil
            workDescription = nil
        case .work:
            outcomeKey = "work_recorded"
            workDate = "1970-01-01"
            workDescription = "Completed fixture work"
        case .recheck:
            outcomeKey = "issue_still_visible"
            workDate = nil
            workDescription = nil
        }
        return WorkflowRecord(id: id, assetID: assetID, packetID: nil, issueID: issueID, parentRecordID: parentID, recordRevisionRootID: id, revisesRecordID: nil, evidenceSourceRecordID: nil, revisionKind: .original, stage: stage, state: .completed, draftStepKey: nil, startedAt: Date(timeIntervalSince1970: 100), completedAt: Date(timeIntervalSince1970: 200), observedAtUTC: nil, timeZoneID: nil, utcOffsetMinutes: nil, localDate: nil, localTime: nil, afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil, afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: nil, safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil, safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: nil, packID: pack.packID, packSchemaVersion: 1, packContentVersion: 1, pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1, outcomeKey: outcomeKey, couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil, workPerformedLocalDate: workDate, workDescription: workDescription, note: nil, finalizationMutationID: UUID())
    }

    private func makeTemporaryApplicationSupportURL() throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent("S3_1DraftSchemaTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class CurrentDraftClock: ApplicationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func set(_ value: Date) { lock.withLock { self.value = value } }
    func now() -> Date { lock.withLock { value } }
}

extension S3_1DraftSchemaTests {
    func testV23P03C18DraftPlanAndMigrationSchemaAreTyped() throws {
        XCTAssertEqual(DraftUpgradePlanV1.schemaVersion, 1)
        XCTAssertEqual(PackageEvolutionLifecycleV1.schema, "PACKAGE_EVOLUTION_V1")
        XCTAssertTrue(PackageEvolutionLifecycleV1.migrationRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.backupRestoreRequired)
    }
}

private struct FixtureIDs {
    let site = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let asset = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let record = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let parent = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    let root = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    let revises = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    let evidenceSource = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    let mutation = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
    let evidence = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
    let issue = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    let packet = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    let stableRoot = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
    let report = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
    let replacesReport = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
}

extension S3_1DraftSchemaTests {
    func testC36AttachmentStageIsDurableAndEvidenceFreeUntilCommit() throws {
        let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
        let stageID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let draftID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let scratchLeaseID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let mutationID = try MutationIDV1(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!)
        let digest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "a", count: 64)
        )
        let item = try AttachmentStagingItemV1(
            stageID: stageID,
            draftID: draftID,
            workspaceID: workspaceID,
            attachmentKind: .photo,
            scratchLeaseID: scratchLeaseID,
            expectedByteCount: 4,
            actualByteCount: 4,
            contentDigest: digest,
            retryClass: .none,
            state: .readyLocal,
            protectionState: .available,
            revision: 1,
            mutationID: mutationID
        )

        try item.validate()
        XCTAssertNil(item.contentReference)
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(
                for: item,
                durableReceiptReadBack: false
            ),
            .stagedLocal
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(
                for: item,
                durableReceiptReadBack: true
            ),
            .ready
        )
    }
}

extension S3_1DraftSchemaTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension S3_1DraftSchemaTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(FieldReferenceReleaseV1.schemaVersion, 1)
        XCTAssertEqual(FieldReferenceBindingV1.schemaVersion, 1)
        XCTAssertEqual(FieldReferencePackLifecycleV1.persistentFamilies.count, 2)
    }
}

extension S3_1DraftSchemaTests {
    func testV23P03C34DraftAnchorResolvesWithoutAutomaticRestart() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x01)))
        let anchor = try DraftResumeAnchorV1(sectionID: "draft", fieldID: "body", selectedStableID: "field-1", boundedPosition: 2)
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .draftReview, requestedMode: .resume, draftResumeAnchor: anchor)
        let result = try RouteRegistryV1().resolve(target, context: .init(currentWorkspaceID: workspace, currentRevision: 0))
        XCTAssertEqual(result.target.draftResumeAnchor, anchor)
        XCTAssertEqual(result.canonicalMutationCount, 0)
        XCTAssertFalse(result.startsAutomaticWork)
    }
}

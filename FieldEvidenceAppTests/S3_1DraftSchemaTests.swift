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
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let instant = Date(timeIntervalSince1970: 1_768_438_923)
        let ids = try seedSiteAndAsset(in: factory, timeZoneID: nil)
        let context = ids.session.modelContext
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)

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
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let ids = try seedSiteAndAsset(in: factory, timeZoneID: "America/New_York")
        let context = ids.session.modelContext
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        let original = try coordinator.beginOrResumeDraft(BeginDraftSubmission(assetID: ids.asset, requestedStage: .check, issueID: nil, observedAtUTC: Date(timeIntervalSince1970: 1_768_438_923), confirmedTimeZoneID: nil, afterDarkAccepted: true, safePositionAccepted: true))

        let invalidIssue = UUID()
        let workResult = try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .work, issueID: nil)
        let recheckResult = try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .recheck, issueID: invalidIssue)
        let invalidPreflightResult = try coordinator.beginOrResumeDraft(BeginDraftSubmission(assetID: ids.asset, requestedStage: .check, issueID: invalidIssue, observedAtUTC: nil, confirmedTimeZoneID: "Invalid/Zone", afterDarkAccepted: false, safePositionAccepted: false))

        XCTAssertEqual(workResult.id, original.id)
        XCTAssertEqual(recheckResult.id, original.id)
        XCTAssertEqual(invalidPreflightResult.id, original.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        assertExactCheckDraft(original, assetID: ids.asset, instant: Date(timeIntervalSince1970: 1_768_438_923))
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
    func testNoDraftStageIssueAndLatestParentValidationIsExact() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let ids = try seedSiteAndAsset(in: factory, timeZoneID: "America/New_York")
        let context = ids.session.modelContext
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)

        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .check, issueID: UUID())) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .issueNotAllowed)
        }
        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .work, issueID: nil)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .issueRequired)
        }
        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .work, issueID: UUID())) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .issueNotFound)
        }

        let opening = completedRecord(id: UUID(), assetID: ids.asset, issueID: nil, parentID: nil, stage: .check)
        let issue = Issue(id: UUID(), assetID: ids.asset, openedByRecordID: opening.id, labelKey: "dark_section", labelDisplaySnapshot: "Section appears dark", status: .open, resolvedByRecordID: nil, createdAt: opening.startedAt, updatedAt: opening.startedAt)
        opening.issueID = issue.id
        context.insert(opening); context.insert(issue); try context.save()

        XCTAssertThrowsError(try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .recheck, issueID: issue.id)) {
            XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .issueStateMismatch)
        }
        let work = try coordinator.beginOrResumeDraft(assetID: ids.asset, requestedStage: .work, issueID: issue.id)
        XCTAssertEqual(work.stage, WorkflowStage.work.rawValue)
        XCTAssertEqual(work.issueID, issue.id)
        XCTAssertEqual(work.parentRecordID, opening.id)
        XCTAssertNil(work.observedAtUTC); XCTAssertNil(work.afterDarkAcknowledgementKey)

        context.delete(work)
        let completedWork = completedRecord(id: UUID(), assetID: ids.asset, issueID: issue.id, parentID: opening.id, stage: .work)
        issue.status = IssueStatus.recheckDue.rawValue
        context.insert(completedWork)
        try context.save()

        let recheck = try coordinator.beginOrResumeDraft(
            BeginDraftSubmission(assetID: ids.asset, requestedStage: .recheck, issueID: issue.id, observedAtUTC: Date(timeIntervalSince1970: 1_768_438_923), confirmedTimeZoneID: nil, afterDarkAccepted: true, safePositionAccepted: true)
        )
        XCTAssertEqual(recheck.stage, WorkflowStage.recheck.rawValue)
        XCTAssertEqual(recheck.issueID, issue.id)
        XCTAssertEqual(recheck.parentRecordID, completedWork.id)
        XCTAssertEqual(recheck.draftStepKey, WorkflowDraftStep.wide.rawValue)
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
    }

    @MainActor
    func testDifferentIssueOpeningRecheckBecomesTheNewIssuesFirstParent() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let ids = try seedSiteAndAsset(in: factory, timeZoneID: "America/New_York")
        let context = ids.session.modelContext
        let oldIssueID = UUID()
        let oldOpening = completedRecord(
            id: UUID(),
            assetID: ids.asset,
            issueID: oldIssueID,
            parentID: nil,
            stage: .check
        )
        let oldWork = completedRecord(
            id: UUID(),
            assetID: ids.asset,
            issueID: oldIssueID,
            parentID: oldOpening.id,
            stage: .work
        )
        let openingRecheck = completedRecord(
            id: UUID(),
            assetID: ids.asset,
            issueID: oldIssueID,
            parentID: oldWork.id,
            stage: .recheck
        )
        openingRecheck.outcomeKey = "original_resolved_different_issue"
        let oldIssue = Issue(
            id: oldIssueID,
            assetID: ids.asset,
            openedByRecordID: oldOpening.id,
            labelKey: "dark_section",
            labelDisplaySnapshot: "Section appears dark",
            status: .resolved,
            resolvedByRecordID: openingRecheck.id,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let newIssue = Issue(
            id: UUID(),
            assetID: ids.asset,
            openedByRecordID: openingRecheck.id,
            labelKey: "color_mismatch",
            labelDisplaySnapshot: "Visible color mismatch",
            status: .open,
            resolvedByRecordID: nil,
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        context.insert(oldOpening)
        context.insert(oldWork)
        context.insert(openingRecheck)
        context.insert(oldIssue)
        context.insert(newIssue)
        try context.save()
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)

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
    }

    private var pack: SignPack { .illuminatedSignV1 }

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

import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S5_1RecordWorkTests: XCTestCase {
    private let fileManager = FileManager.default
    private let pack = SignPack.illuminatedSignV1

    @MainActor
    func testGoldenWorkPhotoPersistsReopensAndExactReplayCreatesNoReportRoot() async throws {
        let harness = try await makeHarness()
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }

        let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
        let source = try makePNG(width: 96, height: 72, seed: 41)
        let normalized = try MediaNormalizerV1().normalize(source)
        let completedAt = draft.startedAt.addingTimeInterval(30)
        let submission = WorkSaveSubmission(
            performedLocalDate: "2026-08-13",
            description: "Replaced failed power supply",
            note: "Observed steady illumination after the work.",
            photos: [
                WorkPhotoSubmission(
                    purposeKey: "work_context",
                    sourceData: source,
                    createdAt: draft.startedAt.addingTimeInterval(10)
                ),
            ],
            completedAt: completedAt
        )
        let identifiers = WorkIdentifiers(
            mutationID: UUID(),
            evidenceID: UUID()
        )
        let packetIDsBefore = try harness.context.fetch(FetchDescriptor<Packet>())
            .map(\.id)
        let reportIDsBefore = try harness.context.fetch(FetchDescriptor<Report>())
            .map(\.id)

        let saved = try await harness.coordinator.saveWork(
            draftID: draft.recordID,
            submission: submission,
            identifiers: identifiers
        )

        XCTAssertEqual(saved.id, harness.issueID)
        XCTAssertEqual(saved.status, .recheckDue)
        XCTAssertEqual(saved.label, "Section appears dark")
        XCTAssertEqual(saved.records.count, 1)
        XCTAssertEqual(saved.records[0].performedLocalDate, "2026-08-13")
        XCTAssertEqual(saved.records[0].description, "Replaced failed power supply")
        XCTAssertEqual(
            saved.records[0].note,
            "Observed steady illumination after the work."
        )
        XCTAssertEqual(saved.records[0].photoThumbnailJPEG, normalized.thumbnailJPEG)

        let records = try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
        let work = try XCTUnwrap(records.first { $0.id == draft.recordID })
        XCTAssertEqual(work.schemaVersion, 1)
        XCTAssertEqual(work.assetID, harness.assetID)
        XCTAssertNil(work.packetID)
        XCTAssertEqual(work.issueID, harness.issueID)
        XCTAssertEqual(work.parentRecordID, harness.openingRecordID)
        XCTAssertEqual(work.recordRevisionRootID, work.id)
        XCTAssertNil(work.revisesRecordID)
        XCTAssertNil(work.evidenceSourceRecordID)
        XCTAssertEqual(work.revisionKind, WorkflowRevisionKind.original.rawValue)
        XCTAssertEqual(work.stage, WorkflowStage.work.rawValue)
        XCTAssertEqual(work.state, WorkflowState.completed.rawValue)
        XCTAssertNil(work.draftStepKey)
        XCTAssertEqual(work.completedAt, completedAt)
        XCTAssertNil(work.observedAtUTC)
        XCTAssertNil(work.timeZoneID)
        XCTAssertNil(work.utcOffsetMinutes)
        XCTAssertNil(work.localDate)
        XCTAssertNil(work.localTime)
        XCTAssertNil(work.afterDarkAcknowledgementKey)
        XCTAssertNil(work.safePositionAcknowledgementKey)
        XCTAssertEqual(work.packID, pack.packID)
        XCTAssertEqual(work.packSchemaVersion, pack.schemaVersion)
        XCTAssertEqual(work.packContentVersion, pack.contentVersion)
        XCTAssertEqual(work.pdfTemplateID, "field.evidence.pdf.worklight.v1")
        XCTAssertEqual(work.pdfTemplateVersion, 1)
        XCTAssertEqual(work.outcomeKey, "work_recorded")
        XCTAssertEqual(work.workPerformedLocalDate, "2026-08-13")
        XCTAssertEqual(work.workDescription, "Replaced failed power supply")
        XCTAssertEqual(work.finalizationMutationID, identifiers.mutationID)

        let issue = try onlyIssue(in: harness.context)
        XCTAssertEqual(issue.status, IssueStatus.recheckDue.rawValue)
        XCTAssertNil(issue.resolvedByRecordID)
        XCTAssertEqual(issue.updatedAt, completedAt)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<Packet>()).map(\.id),
            packetIDsBefore
        )
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<Report>()).map(\.id),
            reportIDsBefore
        )
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<EvidenceFile>())
                .filter { $0.recordID == draft.recordID }.count,
            1
        )

        let replay = try await harness.coordinator.saveWork(
            draftID: draft.recordID,
            submission: submission,
            identifiers: identifiers
        )
        XCTAssertEqual(replay, saved)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 3)

        let reopened = try WorkCoordinator(
            modelContext: harness.context,
            signPack: pack,
            generationRootURL: harness.generationRootURL,
            checkRunnerCoordinator: harness.runner
        )
        let reopenedIssue = try await reopened.issue(id: harness.issueID)
        XCTAssertEqual(reopenedIssue, saved)

        let differentSource = try makePNG(width: 96, height: 72, seed: 42)
        let mismatchedReplay = WorkSaveSubmission(
            performedLocalDate: submission.performedLocalDate,
            description: submission.description,
            note: submission.note,
            photos: [
                WorkPhotoSubmission(
                    purposeKey: "work_context",
                    sourceData: differentSource,
                    createdAt: submission.photos[0].createdAt
                ),
            ],
            completedAt: completedAt
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await reopened.saveWork(
                draftID: draft.recordID,
                submission: mismatchedReplay,
                identifiers: identifiers
            )
        }
    }

    @MainActor
    func testALTValidationFamilyWritesNothingAndKeepsOpenDraftRetryable() async throws {
        let harness = try await makeHarness()
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
        let source = try makePNG(width: 80, height: 60, seed: 52)
        let baselineFiles = try mediaFiles(in: harness.generationRootURL)
        let completedAt = draft.startedAt.addingTimeInterval(30)
        let validPhoto = WorkPhotoSubmission(
            purposeKey: "work_context",
            sourceData: source,
            createdAt: draft.startedAt.addingTimeInterval(10)
        )
        let invalid: [(WorkSaveSubmission, WorkIdentifiers)] = [
            (
                WorkSaveSubmission(
                    performedLocalDate: "",
                    description: "Replaced power supply",
                    note: nil,
                    photos: [],
                    completedAt: completedAt
                ),
                WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
            ),
            (
                WorkSaveSubmission(
                    performedLocalDate: "2026-08-13",
                    description: "   ",
                    note: nil,
                    photos: [],
                    completedAt: completedAt
                ),
                WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
            ),
            (
                WorkSaveSubmission(
                    performedLocalDate: "2026-08-13",
                    description: String(repeating: "x", count: 161),
                    note: nil,
                    photos: [],
                    completedAt: completedAt
                ),
                WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
            ),
            (
                WorkSaveSubmission(
                    performedLocalDate: "2026-08-13",
                    description: "Replaced power supply",
                    note: String(repeating: "n", count: 1_001),
                    photos: [],
                    completedAt: completedAt
                ),
                WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
            ),
            (
                WorkSaveSubmission(
                    performedLocalDate: "2026-08-13",
                    description: "Replaced power supply",
                    note: nil,
                    photos: [
                        WorkPhotoSubmission(
                            purposeKey: "wide_context",
                            sourceData: source,
                            createdAt: validPhoto.createdAt
                        ),
                    ],
                    completedAt: completedAt
                ),
                WorkIdentifiers(mutationID: UUID(), evidenceID: UUID())
            ),
            (
                WorkSaveSubmission(
                    performedLocalDate: "2026-08-13",
                    description: "Replaced power supply",
                    note: nil,
                    photos: [validPhoto, validPhoto],
                    completedAt: completedAt
                ),
                WorkIdentifiers(mutationID: UUID(), evidenceID: UUID())
            ),
        ]

        for (submission, identifiers) in invalid {
            await XCTAssertThrowsErrorAsync {
                _ = try await harness.coordinator.saveWork(
                    draftID: draft.recordID,
                    submission: submission,
                    identifiers: identifiers
                )
            }
            let issue = try onlyIssue(in: harness.context)
            XCTAssertEqual(issue.status, IssueStatus.open.rawValue)
            XCTAssertNil(issue.resolvedByRecordID)
            let persistedDraft = try onlyRecord(
                id: draft.recordID,
                in: harness.context
            )
            XCTAssertEqual(persistedDraft.state, WorkflowState.draft.rawValue)
            XCTAssertNil(persistedDraft.finalizationMutationID)
            XCTAssertEqual(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>())
                    .filter { $0.recordID == draft.recordID }.count,
                0
            )
            XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), baselineFiles)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        }
    }

    @MainActor
    func testMalformedLineageEvidenceAndRootIdentityFailClosed() async throws {
        do {
            let harness = try await makeHarness()
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let packet = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<Packet>()).first
            )
            packet.currentRecordID = UUID()
            try harness.context.save()
            XCTAssertThrowsError(
                try harness.coordinator.beginWork(issueID: harness.issueID)
            )
            XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.open.rawValue)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        }

        do {
            let harness = try await makeHarness()
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let row = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>()).first
            )
            row.sha256 = String(repeating: "f", count: 64)
            try harness.context.save()
            let retainedFiles = try mediaFiles(in: harness.generationRootURL)
            XCTAssertThrowsError(
                try harness.coordinator.beginWork(issueID: harness.issueID)
            )
            XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), retainedFiles)
            XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.open.rawValue)
        }

        do {
            let harness = try await makeHarness()
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let retainedRoot = harness.applicationSupportURL.appendingPathComponent(
                "retained-generation",
                isDirectory: true
            )
            try fileManager.moveItem(at: harness.generationRootURL, to: retainedRoot)
            try fileManager.createDirectory(
                at: harness.generationRootURL,
                withIntermediateDirectories: false
            )
            XCTAssertThrowsError(
                try harness.coordinator.beginWork(issueID: harness.issueID)
            )
            try fileManager.removeItem(at: harness.generationRootURL)
            try fileManager.moveItem(at: retainedRoot, to: harness.generationRootURL)
            XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.open.rawValue)
        }
    }

    @MainActor
    func testPromotionAndModelSaveFailuresCleanOwnedMediaThenRetryExactlyOnce() async throws {
        for failurePoint in [
            WorkCoordinatorFailurePoint.afterEvidencePromotion,
            WorkCoordinatorFailurePoint.modelSave,
        ] {
            let injection = WorkCoordinatorFailureInjection(failOnceAt: failurePoint)
            let harness = try await makeHarness(workFailureInjection: injection)
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
            let baselineFiles = try mediaFiles(in: harness.generationRootURL)
            let source = try makePNG(width: 88, height: 66, seed: 70)
            let submission = WorkSaveSubmission(
                performedLocalDate: "2026-08-13",
                description: "Replaced failed power supply",
                note: nil,
                photos: [
                    WorkPhotoSubmission(
                        purposeKey: "work_context",
                        sourceData: source,
                        createdAt: draft.startedAt.addingTimeInterval(5)
                    ),
                ],
                completedAt: draft.startedAt.addingTimeInterval(20)
            )
            let identifiers = WorkIdentifiers(
                mutationID: UUID(),
                evidenceID: UUID()
            )

            await XCTAssertThrowsErrorAsync {
                _ = try await harness.coordinator.saveWork(
                    draftID: draft.recordID,
                    submission: submission,
                    identifiers: identifiers
                )
            }
            XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), baselineFiles)
            XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.open.rawValue)
            XCTAssertEqual(
                try onlyRecord(id: draft.recordID, in: harness.context).state,
                WorkflowState.draft.rawValue
            )
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)

            let saved = try await harness.coordinator.saveWork(
                draftID: draft.recordID,
                submission: submission,
                identifiers: identifiers
            )
            XCTAssertEqual(saved.status, .recheckDue)
            XCTAssertEqual(saved.records.count, 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 2)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 3)
        }
    }

    @MainActor
    func testDirtyContextAndStorageFailurePreserveUnrelatedWorkAndOwnedFiles() async throws {
        do {
            let harness = try await makeHarness()
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
            let site = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<Site>()).first
            )
            site.label = "Unsaved operator edit"
            let baselineFiles = try mediaFiles(in: harness.generationRootURL)
            await XCTAssertThrowsErrorAsync {
                _ = try await harness.coordinator.saveWork(
                    draftID: draft.recordID,
                    submission: validSubmission(for: draft, photo: nil),
                    identifiers: WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
                )
            }
            XCTAssertTrue(harness.context.hasChanges)
            XCTAssertEqual(site.label, "Unsaved operator edit")
            XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), baselineFiles)
            XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.open.rawValue)
            harness.context.rollback()
        }

        do {
            let unavailable = StoragePreflightService { _ in 0 }
            let harness = try await makeHarness(storagePreflight: unavailable)
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
            let baselineFiles = try mediaFiles(in: harness.generationRootURL)
            let source = try makePNG(width: 64, height: 48, seed: 91)
            await XCTAssertThrowsErrorAsync {
                _ = try await harness.coordinator.saveWork(
                    draftID: draft.recordID,
                    submission: validSubmission(for: draft, photo: source),
                    identifiers: WorkIdentifiers(
                        mutationID: UUID(),
                        evidenceID: UUID()
                    )
                )
            }
            XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), baselineFiles)
            XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.open.rawValue)
            XCTAssertEqual(
                try onlyRecord(id: draft.recordID, in: harness.context).state,
                WorkflowState.draft.rawValue
            )
        }
    }

    private struct Harness {
        let applicationSupportURL: URL
        let session: StoreGenerationSession
        let generationRootURL: URL
        let context: ModelContext
        let runner: CheckRunnerCoordinator
        let coordinator: WorkCoordinator
        let assetID: UUID
        let issueID: UUID
        let openingRecordID: UUID
    }

    @MainActor
    private func makeHarness(
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        workFailureInjection: WorkCoordinatorFailureInjection? = nil
    ) async throws -> Harness {
        let applicationSupportURL = fileManager.temporaryDirectory.appendingPathComponent(
            "S5_1RecordWorkTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: false
        )
        do {
            let session = try StoreGenerationFactory(
                applicationSupportURL: applicationSupportURL
            ).openOrBootstrapCurrent()
            let context = session.modelContext
            let siteID = UUID()
            let assetID = UUID()
            let issueID = UUID()
            let openingRecordID = UUID()
            let packetID = UUID()
            let startedAt = Date(timeIntervalSince1970: 1_780_000_000)
            let completedAt = startedAt.addingTimeInterval(60)
            let frozen = try TimeContextRule.freeze(
                observedAtUTC: startedAt,
                confirmedTimeZoneID: "America/New_York"
            )
            let site = Site(
                id: siteID,
                label: "North Campus",
                address: "10 Main Street",
                timeZoneID: "America/New_York",
                createdAt: startedAt.addingTimeInterval(-120)
            )
            let asset = Asset(
                id: assetID,
                siteID: siteID,
                packID: pack.packID,
                packSchemaVersion: pack.schemaVersion,
                packContentVersion: pack.contentVersion,
                label: "Monument Sign",
                createdAt: startedAt.addingTimeInterval(-100)
            )
            let opening = WorkflowRecord(
                id: openingRecordID,
                assetID: assetID,
                packetID: packetID,
                issueID: issueID,
                parentRecordID: nil,
                recordRevisionRootID: openingRecordID,
                revisesRecordID: nil,
                evidenceSourceRecordID: nil,
                revisionKind: .original,
                stage: .check,
                state: .completed,
                draftStepKey: nil,
                startedAt: startedAt,
                completedAt: completedAt,
                observedAtUTC: frozen.observedAtUTC,
                timeZoneID: frozen.timeZoneID,
                utcOffsetMinutes: frozen.utcOffsetMinutes,
                localDate: frozen.localDate,
                localTime: frozen.localTime,
                afterDarkAcknowledgementKey: pack.acknowledgements[0].key,
                afterDarkAcknowledgementCopy: pack.acknowledgements[0].copy,
                afterDarkAcknowledgementVersion: pack.acknowledgements[0].version,
                afterDarkAcknowledgementAccepted: true,
                safePositionAcknowledgementKey: pack.acknowledgements[1].key,
                safePositionAcknowledgementCopy: pack.acknowledgements[1].copy,
                safePositionAcknowledgementVersion: pack.acknowledgements[1].version,
                safePositionAcknowledgementAccepted: true,
                packID: pack.packID,
                packSchemaVersion: pack.schemaVersion,
                packContentVersion: pack.contentVersion,
                pdfTemplateID: "field.evidence.pdf.worklight.v1",
                pdfTemplateVersion: 1,
                outcomeKey: "visible_issue",
                couldNotVerifyKey: nil,
                couldNotVerifyDisplaySnapshot: nil,
                couldNotVerifyRegistryVersion: nil,
                workPerformedLocalDate: nil,
                workDescription: nil,
                note: nil,
                finalizationMutationID: UUID()
            )
            let issue = Issue(
                id: issueID,
                assetID: assetID,
                openedByRecordID: openingRecordID,
                labelKey: "dark_section",
                labelDisplaySnapshot: "Section appears dark",
                status: .open,
                resolvedByRecordID: nil,
                createdAt: completedAt,
                updatedAt: completedAt
            )
            let packet = Packet(
                id: packetID,
                stableRootID: UUID(),
                currentRecordID: openingRecordID,
                evaluationCounted: true,
                contentDeletedAt: nil,
                createdAt: completedAt
            )
            let report = Report(
                id: UUID(),
                packetID: packetID,
                sourceRecordID: openingRecordID,
                snapshotSchemaVersion: 1,
                snapshotRelativePath: "snapshots/fixture.json",
                snapshotSHA256: String(repeating: "a", count: 64),
                pdfState: .pending,
                pdfRelativePath: nil,
                pdfSHA256: nil,
                createdAt: completedAt,
                replacesReportID: nil
            )
            context.insert(site)
            context.insert(asset)
            context.insert(opening)
            context.insert(issue)
            context.insert(packet)
            context.insert(report)

            let store = EvidenceBundleStore(
                generationRootURL: session.generationRootURL
            )
            let wide = try makePNG(width: 80, height: 60, seed: 11)
            let close = try makePNG(width: 72, height: 72, seed: 22)
            let wideRow = try await makeEvidence(
                id: UUID(),
                recordID: openingRecordID,
                purposeKey: "wide_context",
                source: wide,
                createdAt: startedAt.addingTimeInterval(15),
                store: store
            )
            let closeRow = try await makeEvidence(
                id: UUID(),
                recordID: openingRecordID,
                purposeKey: "close_detail",
                source: close,
                createdAt: startedAt.addingTimeInterval(30),
                store: store
            )
            context.insert(wideRow)
            context.insert(closeRow)
            try context.save()

            let runner = CheckRunnerCoordinator(
                modelContext: context,
                signPack: pack
            )
            let coordinator = try WorkCoordinator(
                modelContext: context,
                signPack: pack,
                generationRootURL: session.generationRootURL,
                checkRunnerCoordinator: runner,
                storagePreflight: storagePreflight,
                failureInjection: workFailureInjection
            )
            return Harness(
                applicationSupportURL: applicationSupportURL,
                session: session,
                generationRootURL: session.generationRootURL,
                context: context,
                runner: runner,
                coordinator: coordinator,
                assetID: assetID,
                issueID: issueID,
                openingRecordID: openingRecordID
            )
        } catch {
            try? fileManager.removeItem(at: applicationSupportURL)
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
            id: id,
            recordID: recordID,
            purposeKey: purposeKey,
            relativePath: promoted.originalRelativePath,
            mimeType: "image/jpeg",
            byteCount: promoted.originalByteCount,
            sha256: promoted.originalSHA256,
            createdAt: createdAt,
            thumbnailRelativePath: promoted.thumbnailRelativePath,
            thumbnailByteCount: promoted.thumbnailByteCount,
            thumbnailSHA256: promoted.thumbnailSHA256
        )
    }

    private func validSubmission(
        for draft: WorkDraftValue,
        photo: Data?
    ) -> WorkSaveSubmission {
        let completedAt = draft.startedAt.addingTimeInterval(20)
        return WorkSaveSubmission(
            performedLocalDate: "2026-08-13",
            description: "Replaced failed power supply",
            note: nil,
            photos: photo.map {
                [
                    WorkPhotoSubmission(
                        purposeKey: "work_context",
                        sourceData: $0,
                        createdAt: draft.startedAt.addingTimeInterval(5)
                    ),
                ]
            } ?? [],
            completedAt: completedAt
        )
    }

    @MainActor
    private func onlyIssue(in context: ModelContext) throws -> Issue {
        let values = try context.fetch(FetchDescriptor<Issue>())
        XCTAssertEqual(values.count, 1)
        return try XCTUnwrap(values.first)
    }

    @MainActor
    private func onlyRecord(id: UUID, in context: ModelContext) throws -> WorkflowRecord {
        let matches = try context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.id == id
        }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    private func mediaFiles(in root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for directory in ["evidence", ".staging/evidence"] {
            let parent = root.appendingPathComponent(directory, isDirectory: true)
            guard fileManager.fileExists(atPath: parent.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: parent,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let relative = url.path.replacingOccurrences(
                    of: root.path + "/",
                    with: ""
                )
                result[relative] = try Data(contentsOf: url)
            }
        }
        return result
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
        let pixelData = Data(pixels)
        guard let provider = CGDataProvider(data: pixelData as CFData),
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
            throw FixtureError.couldNotCreateImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw FixtureError.couldNotCreateImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.couldNotCreateImage
        }
        return output as Data
    }

    private enum FixtureError: Error {
        case couldNotCreateImage
    }
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

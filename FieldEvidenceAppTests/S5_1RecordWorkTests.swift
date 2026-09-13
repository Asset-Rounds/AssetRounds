import CoreGraphics
import CryptoKit
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
        var activeOwner: StoreSessionCoordinator? = harness.storeCoordinator
        defer {
            try? activeOwner?.invalidateAndReleaseWriter()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }

        let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
        let source = try makePNG(width: 96, height: 72, seed: 41)
        let normalized = try MediaNormalizerV1().normalize(source)
        let startedSecond = floor(draft.startedAt.timeIntervalSince1970)
        let photoCreatedAt = Date(timeIntervalSince1970: startedSecond + 10.000_789)
        let completedAt = Date(timeIntervalSince1970: startedSecond + 30.000_456)
        let submission = WorkSaveSubmission(
            performedLocalDate: "2026-08-13",
            description: "Replaced failed power supply",
            note: "Observed steady illumination after the work.",
            photos: [
                WorkPhotoSubmission(
                    purposeKey: "work_context",
                    sourceData: source,
                    createdAt: photoCreatedAt
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

        let mutationID = try MutationIDV1(rawValue: identifiers.mutationID)
        let envelope = try XCTUnwrap(
            harness.lifecycleDependencies.writer.workEnvelope(mutationID: mutationID)
        )
        let journalReceipt = try XCTUnwrap(
            harness.lifecycleDependencies.writer.workCommitReceipt(envelope: envelope)
        )
        guard case let .recordWork(workMutation) = envelope.command,
              let writerAuthority = workMutation.writerAuthority else {
            XCTFail("Expected authority-bearing Work envelope")
            throw WorkCanonicalIntegrationFixtureFailureV1.invalidEnvelope
        }
        try writerAuthority.validate(envelope: envelope)
        try journalReceipt.validate()
        let durableJournal = try MutationJournalStoreV1(
            modelContext: harness.context,
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            allowStateBootstrap: false
        )
        XCTAssertEqual(try durableJournal.receipt(mutationID: mutationID), journalReceipt)
        XCTAssertEqual(journalReceipt.mutationID, mutationID)
        XCTAssertEqual(journalReceipt.identity.workspaceID, harness.session.workspaceID)
        XCTAssertEqual(Set(try journalReceipt.postImages.map { try $0.identity }), Set([
            try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: draft.recordID),
            try WorkspaceEntityIdentityV1(kind: .issue, id: harness.issueID),
            try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: try XCTUnwrap(identifiers.evidenceID)),
        ]))
        XCTAssertEqual(
            try writerAuthority.affectedIdentities,
            try journalReceipt.postImages.map { try $0.identity }
                .sorted { $0.stableKey < $1.stableKey }
        )
        for postImage in journalReceipt.postImages {
            let identity = try postImage.identity
            XCTAssertEqual(
                journalReceipt.resultingRevision.entityRevisions.first {
                    $0.identity == identity
                }?.revision,
                postImage.revision
            )
        }
        try durableJournal.validateAll()

        try harness.runner.requestRecheck(assetID: harness.assetID, issueID: harness.issueID)
        let recheckObservedAt = completedAt.addingTimeInterval(60)
        _ = try harness.runner.beginCheck(
            assetID: harness.assetID,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: recheckObservedAt
        )
        let wide = try await harness.runner.importCandidate(
            assetID: harness.assetID,
            sourceData: try makePNG(width: 80, height: 60, seed: 61),
            createdAt: recheckObservedAt.addingTimeInterval(10)
        )
        _ = try await harness.runner.accept(candidate: wide, assetID: harness.assetID)
        let close = try await harness.runner.importCandidate(
            assetID: harness.assetID,
            sourceData: try makePNG(width: 72, height: 72, seed: 62),
            createdAt: recheckObservedAt.addingTimeInterval(20)
        )
        _ = try await harness.runner.accept(candidate: close, assetID: harness.assetID)
        _ = try await harness.runner.finalize(
            assetID: harness.assetID,
            selection: .resolved(note: "Work remained effective."),
            completedAt: recheckObservedAt.addingTimeInterval(30),
            snapshotCreatedAt: recheckObservedAt.addingTimeInterval(30),
            sourceApp: SourceAppSnapshotV1(build: "work-replay", version: "1")
        )
        let afterRecheckReplay = try await harness.coordinator.saveWork(
            draftID: draft.recordID,
            submission: submission,
            identifiers: identifiers
        )
        XCTAssertEqual(afterRecheckReplay.status, .resolved)
        XCTAssertEqual(afterRecheckReplay.records.map(\.id), [draft.recordID])
        XCTAssertEqual(try durableJournal.receipt(mutationID: mutationID), journalReceipt)

        try harness.storeCoordinator.invalidateAndReleaseWriter()
        activeOwner = nil
        let reopenedSession = try StoreGenerationFactory(
            applicationSupportURL: harness.applicationSupportURL
        ).openOrBootstrapCurrent()
        let reopenedRegistry = try WorkspacePackageLifecycleProfileRegistryV1(
            profiles: [harness.lifecycleProfile]
        )
        let reopenedOwner = try StoreSessionCoordinator(
            validatingSession: reopenedSession,
            lifecycleProfileRegistry: reopenedRegistry
        )
        activeOwner = reopenedOwner
        let reopenedLifecycle = try reopenedOwner.packageLifecycleDependencies(
            profileRegistry: reopenedRegistry
        )
        let reopenedRunner = try CheckRunnerCoordinator(
            modelContext: reopenedSession.modelContext,
            packageLifecycleDependencies: reopenedLifecycle,
            packageLifecycleProfile: harness.lifecycleProfile
        )
        reopenedRunner.configureCapture(generationRootURL: reopenedSession.generationRootURL)
        let reopened = try WorkCoordinator(
            modelContext: reopenedSession.modelContext,
            signPack: pack,
            generationRootURL: reopenedSession.generationRootURL,
            checkRunnerCoordinator: reopenedRunner,
            lifecycleDependencies: reopenedLifecycle
        )
        let reopenedIssue = try await reopened.issue(id: harness.issueID)
        XCTAssertEqual(reopenedIssue, afterRecheckReplay)
        let reopenedReplay = try await reopened.saveWork(
            draftID: draft.recordID,
            submission: submission,
            identifiers: identifiers
        )
        XCTAssertEqual(reopenedReplay, afterRecheckReplay)
        XCTAssertEqual(
            try MutationJournalStoreV1(
                modelContext: reopenedSession.modelContext,
                identity: reopenedSession.workspaceIdentity,
                generationID: reopenedSession.generationID,
                allowStateBootstrap: false
            ).receipt(mutationID: mutationID),
            journalReceipt
        )

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
        let differentCanonicalTimestamp = WorkSaveSubmission(
            performedLocalDate: submission.performedLocalDate,
            description: submission.description,
            note: submission.note,
            photos: submission.photos,
            completedAt: submission.completedAt.addingTimeInterval(0.001)
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await reopened.saveWork(
                draftID: draft.recordID,
                submission: differentCanonicalTimestamp,
                identifiers: identifiers
            )
        }
    }

    @MainActor
    func testALTValidationFamilyWritesNothingAndKeepsOpenDraftRetryable() async throws {
        let harness = try await makeHarness()
        defer {
            try? harness.storeCoordinator.invalidateAndReleaseWriter()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
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
            defer {
                try? harness.storeCoordinator.invalidateAndReleaseWriter()
                try? fileManager.removeItem(at: harness.applicationSupportURL)
            }
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
            defer {
                try? harness.storeCoordinator.invalidateAndReleaseWriter()
                try? fileManager.removeItem(at: harness.applicationSupportURL)
            }
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
            defer {
                try? harness.storeCoordinator.invalidateAndReleaseWriter()
                try? fileManager.removeItem(at: harness.applicationSupportURL)
            }
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
            defer {
                try? harness.storeCoordinator.invalidateAndReleaseWriter()
                try? fileManager.removeItem(at: harness.applicationSupportURL)
            }
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
            let mutationID = try MutationIDV1(rawValue: identifiers.mutationID)
            let journal = try MutationJournalStoreV1(
                modelContext: harness.context,
                identity: harness.session.workspaceIdentity,
                generationID: harness.session.generationID,
                allowStateBootstrap: false
            )
            XCTAssertNil(try journal.receipt(mutationID: mutationID))
            try journal.validateAll()
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
            XCTAssertNotNil(try journal.receipt(mutationID: mutationID))
        }
    }

    @MainActor
    func testStagedCleanupRejectsForgedReceiptAndExactReceiptDeletesOnlyOwnedBytes() async throws {
        let harness = try await makeHarness()
        defer {
            try? harness.storeCoordinator.invalidateAndReleaseWriter()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
        let baselineFiles = try mediaFiles(in: harness.generationRootURL)
        let normalized = try MediaNormalizerV1().normalize(
            try makePNG(width: 82, height: 62, seed: 84)
        )
        let store = EvidenceBundleStore(generationRootURL: harness.generationRootURL)
        let staged = try await store.stage(evidenceID: UUID(), normalized: normalized)
        let stagedFiles = try mediaFiles(in: harness.generationRootURL)
        XCTAssertNotEqual(stagedFiles, baselineFiles)

        let forgedReceipts = [
            StagedEvidenceBundle(
                evidenceID: staged.evidenceID,
                stagingDirectoryRelativePath: staged.stagingDirectoryRelativePath + "-forged",
                originalRelativePath: staged.originalRelativePath,
                thumbnailRelativePath: staged.thumbnailRelativePath,
                originalByteCount: staged.originalByteCount,
                thumbnailByteCount: staged.thumbnailByteCount,
                originalSHA256: staged.originalSHA256,
                thumbnailSHA256: staged.thumbnailSHA256
            ),
            StagedEvidenceBundle(
                evidenceID: staged.evidenceID,
                stagingDirectoryRelativePath: staged.stagingDirectoryRelativePath,
                originalRelativePath: staged.originalRelativePath,
                thumbnailRelativePath: staged.thumbnailRelativePath,
                originalByteCount: staged.originalByteCount,
                thumbnailByteCount: staged.thumbnailByteCount,
                originalSHA256: String(repeating: "f", count: 64),
                thumbnailSHA256: staged.thumbnailSHA256
            ),
        ]
        for forged in forgedReceipts {
            XCTAssertThrowsError(
                try store.discardStagedBundleIfOwnedSynchronously(forged)
            ) { error in
                XCTAssertEqual(error as? EvidenceBundleStoreError, .bundleFactsMismatch)
            }
            XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), stagedFiles)
        }

        try store.discardStagedBundleIfOwnedSynchronously(staged)
        XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), baselineFiles)
    }

    @MainActor
    func testPromotedMediaAdoptedByAnotherCanonicalMutationIsPreserved() async throws {
        let harness = try await makeHarness()
        defer {
            try? harness.storeCoordinator.invalidateAndReleaseWriter()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
        let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
        let source = try makePNG(width: 90, height: 68, seed: 86)
        let normalized = try MediaNormalizerV1().normalize(source)
        let identifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: UUID())
        let evidenceID = try XCTUnwrap(identifiers.evidenceID)
        let competingMutationID = try MutationIDV1(rawValue: UUID())
        let key = evidenceID.uuidString.lowercased()
        let originalRelativePath = "evidence/\(key)/original.jpg"
        let thumbnailRelativePath = "evidence/\(key)/thumbnail.jpg"
        let createdAt = draft.startedAt.addingTimeInterval(5)
        let submission = WorkSaveSubmission(
            performedLocalDate: "2026-08-13",
            description: "Replaced failed power supply",
            note: "Competing canonical adoption",
            photos: [WorkPhotoSubmission(
                purposeKey: "work_context",
                sourceData: source,
                createdAt: createdAt
            )],
            completedAt: draft.startedAt.addingTimeInterval(20)
        )
        let injection = WorkCoordinatorFailureInjection(afterEvidencePromotion: {
            _ = try harness.lifecycleDependencies.writer.execute(
                .acceptCheckEvidence(CheckEvidenceMutationV1(
                    evidenceID: evidenceID,
                    draftID: draft.recordID,
                    purposeKey: "work_context",
                    relativePath: originalRelativePath,
                    mimeType: "image/jpeg",
                    byteCount: normalized.originalJPEG.count,
                    sha256: Self.sha256(normalized.originalJPEG),
                    thumbnailRelativePath: thumbnailRelativePath,
                    thumbnailByteCount: normalized.thumbnailJPEG.count,
                    thumbnailSHA256: Self.sha256(normalized.thumbnailJPEG),
                    nextDraftStepKey: WorkflowDraftStep.review.rawValue,
                    createdAt: createdAt
                )),
                mutationID: competingMutationID
            )
        })
        let work = try WorkCoordinator(
            modelContext: harness.context,
            signPack: pack,
            generationRootURL: harness.generationRootURL,
            checkRunnerCoordinator: harness.runner,
            lifecycleDependencies: harness.lifecycleDependencies,
            failureInjection: injection
        )

        do {
            _ = try await work.saveWork(
                draftID: draft.recordID,
                submission: submission,
                identifiers: identifiers
            )
            XCTFail("Expected competing canonical ownership to block Work")
        } catch {
            XCTAssertEqual(error as? WorkCoordinatorError, .cleanupFailed)
        }

        let files = try mediaFiles(in: harness.generationRootURL)
        XCTAssertEqual(files[originalRelativePath], normalized.originalJPEG)
        XCTAssertEqual(files[thumbnailRelativePath], normalized.thumbnailJPEG)
        let adopted = try harness.context.fetch(FetchDescriptor<EvidenceFile>()).filter {
            $0.id == evidenceID
        }
        XCTAssertEqual(adopted.count, 1)
        XCTAssertEqual(adopted.first?.recordID, draft.recordID)
        XCTAssertEqual(adopted.first?.sha256, Self.sha256(normalized.originalJPEG))
        let journal = try MutationJournalStoreV1(
            modelContext: harness.context,
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            allowStateBootstrap: false
        )
        XCTAssertNotNil(try journal.receipt(mutationID: competingMutationID))
        XCTAssertNil(try journal.receipt(
            mutationID: MutationIDV1(rawValue: identifiers.mutationID)
        ))
        try journal.validateAll()
        XCTAssertEqual(
            try onlyRecord(id: draft.recordID, in: harness.context).state,
            WorkflowState.draft.rawValue
        )
        XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.open.rawValue)
    }

    @MainActor
    func testWriterInvalidationAfterPromotionPreservesMediaAndJournalOnReopen() async throws {
        let harness = try await makeHarness()
        var activeOwner: StoreSessionCoordinator? = harness.storeCoordinator
        defer {
            try? activeOwner?.invalidateAndReleaseWriter()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
        let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
        let historyBefore = try harness.lifecycleDependencies.writer
            .sourceMutationHistorySnapshot()
        let source = try makePNG(width: 94, height: 70, seed: 87)
        let normalized = try MediaNormalizerV1().normalize(source)
        let identifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: UUID())
        let evidenceID = try XCTUnwrap(identifiers.evidenceID)
        let key = evidenceID.uuidString.lowercased()
        let originalRelativePath = "evidence/\(key)/original.jpg"
        let thumbnailRelativePath = "evidence/\(key)/thumbnail.jpg"
        let submission = validSubmission(for: draft, photo: source)
        let injection = WorkCoordinatorFailureInjection(afterEvidencePromotion: {
            harness.lifecycleDependencies.writer.invalidate()
        })
        let work = try WorkCoordinator(
            modelContext: harness.context,
            signPack: pack,
            generationRootURL: harness.generationRootURL,
            checkRunnerCoordinator: harness.runner,
            lifecycleDependencies: harness.lifecycleDependencies,
            failureInjection: injection
        )

        do {
            _ = try await work.saveWork(
                draftID: draft.recordID,
                submission: submission,
                identifiers: identifiers
            )
            XCTFail("Expected invalidated writer cleanup truth to fail closed")
        } catch {
            XCTAssertEqual(error as? WorkCoordinatorError, .cleanupFailed)
        }
        let filesBeforeReopen = try mediaFiles(in: harness.generationRootURL)
        XCTAssertEqual(filesBeforeReopen[originalRelativePath], normalized.originalJPEG)
        XCTAssertEqual(filesBeforeReopen[thumbnailRelativePath], normalized.thumbnailJPEG)

        try harness.storeCoordinator.invalidateAndReleaseWriter()
        activeOwner = nil
        let reopenedSession = try StoreGenerationFactory(
            applicationSupportURL: harness.applicationSupportURL
        ).openOrBootstrapCurrent()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(
            profiles: [harness.lifecycleProfile]
        )
        let reopenedOwner = try StoreSessionCoordinator(
            validatingSession: reopenedSession,
            lifecycleProfileRegistry: registry
        )
        activeOwner = reopenedOwner
        let reopenedDependencies = try reopenedOwner.packageLifecycleDependencies(
            profileRegistry: registry
        )
        XCTAssertEqual(
            try reopenedDependencies.writer.sourceMutationHistorySnapshot(),
            historyBefore
        )
        let journal = try MutationJournalStoreV1(
            modelContext: reopenedSession.modelContext,
            identity: reopenedSession.workspaceIdentity,
            generationID: reopenedSession.generationID,
            allowStateBootstrap: false
        )
        XCTAssertNil(try journal.receipt(
            mutationID: MutationIDV1(rawValue: identifiers.mutationID)
        ))
        try journal.validateAll()
        XCTAssertEqual(
            try onlyRecord(id: draft.recordID, in: reopenedSession.modelContext).state,
            WorkflowState.draft.rawValue
        )
        XCTAssertEqual(
            try onlyIssue(in: reopenedSession.modelContext).status,
            IssueStatus.open.rawValue
        )
        XCTAssertTrue(
            try reopenedSession.modelContext.fetch(FetchDescriptor<EvidenceFile>()).allSatisfy {
                $0.id != evidenceID
            }
        )
        XCTAssertEqual(try mediaFiles(in: reopenedSession.generationRootURL), filesBeforeReopen)
    }

    @MainActor
    func testSavedBeforeReturnKeepsCanonicalRowsReceiptAndMediaThenExactRetryReplays() async throws {
        let harness = try await makeHarness()
        let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
        try harness.storeCoordinator.invalidateAndReleaseWriter()

        let factory = StoreGenerationFactory(
            applicationSupportURL: harness.applicationSupportURL
        )
        let leaseRegistry = try factory.makeGenerationLeaseRegistry()
        let epoch = try XCTUnwrap(harness.session.generationEpoch)
        let lease = try leaseRegistry.acquireHandle(epoch: epoch, role: .writer)
        var writer: WorkspaceWriterV1?
        defer {
            writer?.invalidate()
            try? lease.close()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
        let fence = try factory.makeWriterFence(
            expectedGenerationEpoch: epoch,
            writerLeaseToken: lease.token,
            registry: leaseRegistry
        )
        let journal = try MutationJournalStoreV1(
            modelContext: harness.context,
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            failureInjection: MutationJournalFailureInjectionV1(
                failOnceAt: .afterSaveBeforeReturn
            ),
            allowStateBootstrap: false,
            staleWriterFence: fence
        )
        try MutationReceiptRecoveryServiceV1(store: journal).recoverBeforeWriterActivation()
        let writerInstanceID = UUID()
        let replacement = try WorkspaceWriterV1(
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerInstanceID),
            clock: SystemApplicationClock(),
            idSource: SystemApplicationIDSource(),
            fileAuthority: SystemApplicationFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(
                modelContext: harness.context,
                generationRootURL: harness.generationRootURL,
                expectedRootIdentity: try ReportPDFAnchoredFile.rootIdentity(
                    at: harness.generationRootURL
                ),
                lifecycleProfileRegistry: harness.lifecycleDependencies.profileRegistry
            ),
            journalStore: journal
        )
        writer = replacement
        let lifecycle = try WorkspacePackageLifecycleDependenciesV1(
            workspaceID: harness.session.workspaceID,
            generationID: harness.session.generationID,
            generationRootURL: harness.generationRootURL,
            writer: replacement,
            clock: SystemApplicationClock(),
            idSource: SystemApplicationIDSource(),
            fileAuthority: SystemApplicationFileAuthorityV1(),
            profileRegistry: harness.lifecycleDependencies.profileRegistry
        )
        let runner = try CheckRunnerCoordinator(
            modelContext: harness.context,
            packageLifecycleDependencies: lifecycle,
            packageLifecycleProfile: harness.lifecycleProfile
        )
        let work = try WorkCoordinator(
            modelContext: harness.context,
            signPack: pack,
            generationRootURL: harness.generationRootURL,
            checkRunnerCoordinator: runner,
            lifecycleDependencies: lifecycle
        )
        let photo = try makePNG(width: 92, height: 68, seed: 97)
        let submission = validSubmission(for: draft, photo: photo)
        let identifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: UUID())
        let baselineFiles = try mediaFiles(in: harness.generationRootURL)

        do {
            _ = try await work.saveWork(
                draftID: draft.recordID,
                submission: submission,
                identifiers: identifiers
            )
            XCTFail("Expected the journal acknowledgement fault")
        } catch {
            XCTAssertEqual(
                error as? MutationJournalFailureV1,
                .injected(.afterSaveBeforeReturn)
            )
        }

        let mutationID = try MutationIDV1(rawValue: identifiers.mutationID)
        let durableReceipt = try XCTUnwrap(journal.receipt(mutationID: mutationID))
        XCTAssertEqual(
            try onlyRecord(id: draft.recordID, in: harness.context).state,
            WorkflowState.completed.rawValue
        )
        XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.recheckDue.rawValue)
        let committedFiles = try mediaFiles(in: harness.generationRootURL)
        XCTAssertNotEqual(committedFiles, baselineFiles)
        XCTAssertTrue(Set(baselineFiles.keys).isSubset(of: Set(committedFiles.keys)))
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<EvidenceFile>()).filter {
                $0.recordID == draft.recordID
            }.map(\.id),
            [try XCTUnwrap(identifiers.evidenceID)]
        )
        let replay = try await work.saveWork(
            draftID: draft.recordID,
            submission: submission,
            identifiers: identifiers
        )
        XCTAssertEqual(replay.status, .recheckDue)
        XCTAssertEqual(replay.records.map(\.id), [draft.recordID])
        XCTAssertEqual(try journal.receipt(mutationID: mutationID), durableReceipt)
        XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), committedFiles)
        try journal.validateAll()
    }

    @MainActor
    func testDirtyContextAndStorageFailurePreserveUnrelatedWorkAndOwnedFiles() async throws {
        do {
            let harness = try await makeHarness()
            defer {
                try? harness.storeCoordinator.invalidateAndReleaseWriter()
                try? fileManager.removeItem(at: harness.applicationSupportURL)
            }
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
            defer {
                try? harness.storeCoordinator.invalidateAndReleaseWriter()
                try? fileManager.removeItem(at: harness.applicationSupportURL)
            }
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

    @MainActor
    func testForeignGenerationAndInvalidatedLiveWriterFailBeforeWorkOrMediaCommit() async throws {
        let harness = try await makeHarness()
        defer {
            try? harness.storeCoordinator.invalidateAndReleaseWriter()
            try? fileManager.removeItem(at: harness.applicationSupportURL)
        }
        XCTAssertThrowsError(try WorkspacePackageLifecycleDependenciesV1(
            workspaceID: harness.session.workspaceID,
            generationID: UUID(),
            generationRootURL: harness.generationRootURL,
            writer: harness.lifecycleDependencies.writer,
            clock: SystemApplicationClock(),
            idSource: SystemApplicationIDSource(),
            fileAuthority: SystemApplicationFileAuthorityV1(),
            profileRegistry: harness.lifecycleDependencies.profileRegistry
        ))

        let draft = try harness.coordinator.beginWork(issueID: harness.issueID)
        let source = try makePNG(width: 80, height: 60, seed: 121)
        let submission = validSubmission(for: draft, photo: source)
        let identifiers = WorkIdentifiers(mutationID: UUID(), evidenceID: UUID())
        let baselineFiles = try mediaFiles(in: harness.generationRootURL)
        harness.lifecycleDependencies.writer.invalidate()
        await XCTAssertThrowsErrorAsync {
            _ = try await harness.coordinator.saveWork(
                draftID: draft.recordID,
                submission: submission,
                identifiers: identifiers
            )
        }
        XCTAssertEqual(try mediaFiles(in: harness.generationRootURL), baselineFiles)
        XCTAssertEqual(
            try onlyRecord(id: draft.recordID, in: harness.context).state,
            WorkflowState.draft.rawValue
        )
        XCTAssertEqual(try onlyIssue(in: harness.context).status, IssueStatus.open.rawValue)
        XCTAssertNil(try MutationJournalStoreV1(
            modelContext: harness.context,
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            allowStateBootstrap: false
        ).receipt(mutationID: MutationIDV1(rawValue: identifiers.mutationID)))
    }

    private struct Harness {
        let applicationSupportURL: URL
        let session: StoreGenerationSession
        let storeCoordinator: StoreSessionCoordinator
        let lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1
        let lifecycleProfile: WorkspacePackageLifecycleProfileV1
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
            let fixture = try await WorkCanonicalOpenIssueFixtureV1.make(
                applicationSupportURL: applicationSupportURL,
                pack: pack
            )
            let coordinator = try WorkCoordinator(
                modelContext: fixture.context,
                signPack: pack,
                generationRootURL: fixture.session.generationRootURL,
                checkRunnerCoordinator: fixture.runner,
                lifecycleDependencies: fixture.lifecycleDependencies,
                storagePreflight: storagePreflight,
                failureInjection: workFailureInjection
            )
            return Harness(
                applicationSupportURL: applicationSupportURL,
                session: fixture.session,
                storeCoordinator: fixture.storeCoordinator,
                lifecycleDependencies: fixture.lifecycleDependencies,
                lifecycleProfile: fixture.lifecycleProfile,
                generationRootURL: fixture.session.generationRootURL,
                context: fixture.context,
                runner: fixture.runner,
                coordinator: coordinator,
                assetID: fixture.assetID,
                issueID: fixture.issueID,
                openingRecordID: fixture.openingRecordID
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

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

/// Shared current-store fixture for the paired Work integration regressions.
/// It deliberately enters through the leased production writer and returns
/// only durable journal values to cross-file codec tests.
@MainActor
final class WorkCanonicalOpenIssueFixtureV1 {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let storeCoordinator: StoreSessionCoordinator
    let lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1
    let lifecycleProfile: WorkspacePackageLifecycleProfileV1
    let context: ModelContext
    let runner: CheckRunnerCoordinator
    let assetID: UUID
    let issueID: UUID
    let openingRecordID: UUID

    private init(
        applicationSupportURL: URL,
        session: StoreGenerationSession,
        storeCoordinator: StoreSessionCoordinator,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1,
        lifecycleProfile: WorkspacePackageLifecycleProfileV1,
        runner: CheckRunnerCoordinator,
        assetID: UUID,
        issueID: UUID,
        openingRecordID: UUID
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.session = session
        self.storeCoordinator = storeCoordinator
        self.lifecycleDependencies = lifecycleDependencies
        self.lifecycleProfile = lifecycleProfile
        context = session.modelContext
        self.runner = runner
        self.assetID = assetID
        self.issueID = issueID
        self.openingRecordID = openingRecordID
    }

    static func make(
        applicationSupportURL: URL,
        pack: SignPack,
        siteLabel: String = "North Campus",
        siteAddress: String = "10 Main Street",
        assetLabel: String = "Monument Sign",
        diagnosticsStore: DiagnosticsStore? = nil
    ) async throws -> WorkCanonicalOpenIssueFixtureV1 {
        let session = try StoreGenerationFactory(applicationSupportURL: applicationSupportURL)
            .openOrBootstrapCurrent()
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: pack
        )
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let owner = try StoreSessionCoordinator(
            validatingSession: session,
            lifecycleProfileRegistry: registry
        )
        do {
            let lifecycle = try owner.packageLifecycleDependencies(profileRegistry: registry)
            let observedAt = Date(timeIntervalSince1970: 1_780_000_000)
            let siteID = UUID()
            let assetID = UUID()
            let placementMutationID = try MutationIDV1(rawValue: UUID())
            _ = try owner.workspaceWriter.execute(
                .createFirstSign(.init(
                    siteID: siteID,
                    newSite: .init(
                        id: siteID,
                        label: siteLabel,
                        address: siteAddress,
                        timeZoneID: "America/New_York"
                    ),
                    assetID: assetID,
                    assetLabel: assetLabel,
                    packID: pack.packID,
                    packSchemaVersion: pack.schemaVersion,
                    packContentVersion: pack.contentVersion,
                    createdAt: observedAt.addingTimeInterval(-100),
                    initialPlacementMutationID: placementMutationID,
                    initialPlacementEventID: UUID(),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
                )),
                mutationID: placementMutationID
            )
            let runner = try CheckRunnerCoordinator(
                modelContext: session.modelContext,
                packageLifecycleDependencies: lifecycle,
                packageLifecycleProfile: profile,
                diagnosticsStore: diagnosticsStore
            )
            runner.configureCapture(generationRootURL: session.generationRootURL)
            _ = try runner.beginCheck(
                assetID: assetID,
                timeZoneID: "America/New_York",
                isTimeZoneConfirmed: true,
                afterDarkAccepted: true,
                safePositionAccepted: true,
                observedAt: observedAt
            )
            let wide = try await runner.importCandidate(
                assetID: assetID,
                sourceData: try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 11),
                createdAt: observedAt.addingTimeInterval(15)
            )
            _ = try await runner.accept(candidate: wide, assetID: assetID)
            let close = try await runner.importCandidate(
                assetID: assetID,
                sourceData: try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 22),
                createdAt: observedAt.addingTimeInterval(30)
            )
            _ = try await runner.accept(candidate: close, assetID: assetID)
            let opening = try await runner.finalize(
                assetID: assetID,
                selection: .visibleIssue(labelKey: "dark_section"),
                completedAt: observedAt.addingTimeInterval(60),
                snapshotCreatedAt: observedAt.addingTimeInterval(60),
                sourceApp: SourceAppSnapshotV1(build: "work-opening", version: "1")
            )
            return WorkCanonicalOpenIssueFixtureV1(
                applicationSupportURL: applicationSupportURL,
                session: session,
                storeCoordinator: owner,
                lifecycleDependencies: lifecycle,
                lifecycleProfile: profile,
                runner: runner,
                assetID: assetID,
                issueID: try XCTUnwrap(opening.issueID),
                openingRecordID: opening.recordID
            )
        } catch {
            try? owner.invalidateAndReleaseWriter()
            throw error
        }
    }
}

@MainActor
final class WorkCanonicalCurrentRouteFixtureV1 {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let storeCoordinator: StoreSessionCoordinator
    let lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1
    let lifecycleProfile: WorkspacePackageLifecycleProfileV1
    let context: ModelContext
    let openingRunner: CheckRunnerCoordinator
    let workCoordinator: WorkCoordinator
    let assetID: UUID
    let issueID: UUID
    let openingRecordID: UUID
    let workRecordID: UUID
    let workSubmission: WorkSaveSubmission
    let workIdentifiers: WorkIdentifiers
    let savedWork: WorkIssuePresentationValue

    private init(
        applicationSupportURL: URL,
        session: StoreGenerationSession,
        storeCoordinator: StoreSessionCoordinator,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1,
        lifecycleProfile: WorkspacePackageLifecycleProfileV1,
        openingRunner: CheckRunnerCoordinator,
        workCoordinator: WorkCoordinator,
        assetID: UUID,
        issueID: UUID,
        openingRecordID: UUID,
        workRecordID: UUID,
        workSubmission: WorkSaveSubmission,
        workIdentifiers: WorkIdentifiers,
        savedWork: WorkIssuePresentationValue
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.session = session
        self.storeCoordinator = storeCoordinator
        self.lifecycleDependencies = lifecycleDependencies
        self.lifecycleProfile = lifecycleProfile
        context = session.modelContext
        self.openingRunner = openingRunner
        self.workCoordinator = workCoordinator
        self.assetID = assetID
        self.issueID = issueID
        self.openingRecordID = openingRecordID
        self.workRecordID = workRecordID
        self.workSubmission = workSubmission
        self.workIdentifiers = workIdentifiers
        self.savedWork = savedWork
    }

    static func make(
        applicationSupportURL: URL,
        pack: SignPack,
        workPhotoData: Data?,
        siteLabel: String = "North Campus",
        siteAddress: String = "10 Main Street",
        assetLabel: String = "Monument Sign",
        workPerformedLocalDate: String = "2026-08-13",
        workDescription: String = "Replaced failed power supply",
        workNote: String? = "Work saved.",
        diagnosticsStore: DiagnosticsStore? = nil
    ) async throws -> WorkCanonicalCurrentRouteFixtureV1 {
        let opening = try await WorkCanonicalOpenIssueFixtureV1.make(
            applicationSupportURL: applicationSupportURL,
            pack: pack,
            siteLabel: siteLabel,
            siteAddress: siteAddress,
            assetLabel: assetLabel,
            diagnosticsStore: diagnosticsStore
        )
        do {
            let workCoordinator = try WorkCoordinator(
                modelContext: opening.context,
                signPack: pack,
                generationRootURL: opening.session.generationRootURL,
                checkRunnerCoordinator: opening.runner,
                lifecycleDependencies: opening.lifecycleDependencies
            )
            let draft = try workCoordinator.beginWork(issueID: opening.issueID)
            let workSubmission = WorkSaveSubmission(
                performedLocalDate: workPerformedLocalDate,
                description: workDescription,
                note: workNote,
                photos: workPhotoData.map { [WorkPhotoSubmission(
                    purposeKey: "work_context",
                    sourceData: $0,
                    createdAt: draft.startedAt.addingTimeInterval(10)
                )] } ?? [],
                completedAt: draft.startedAt.addingTimeInterval(30)
            )
            let workIdentifiers = WorkIdentifiers(
                mutationID: UUID(),
                evidenceID: workPhotoData == nil ? nil : UUID()
            )
            let savedWork = try await workCoordinator.saveWork(
                draftID: draft.recordID,
                submission: workSubmission,
                identifiers: workIdentifiers
            )
            return WorkCanonicalCurrentRouteFixtureV1(
                applicationSupportURL: applicationSupportURL,
                session: opening.session,
                storeCoordinator: opening.storeCoordinator,
                lifecycleDependencies: opening.lifecycleDependencies,
                lifecycleProfile: opening.lifecycleProfile,
                openingRunner: opening.runner,
                workCoordinator: workCoordinator,
                assetID: opening.assetID,
                issueID: opening.issueID,
                openingRecordID: opening.openingRecordID,
                workRecordID: draft.recordID,
                workSubmission: workSubmission,
                workIdentifiers: workIdentifiers,
                savedWork: savedWork
            )
        } catch {
            try? opening.storeCoordinator.invalidateAndReleaseWriter()
            throw error
        }
    }

    func close() throws {
        try storeCoordinator.invalidateAndReleaseWriter()
    }
}

@MainActor
enum WorkCanonicalIntegrationTestSupportV1 {
    static func withCommittedWork(
        _ body: (MutationEnvelopeV1, MutationReceiptV1, MutationHistorySnapshotV1) throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let support = fileManager.temporaryDirectory.appendingPathComponent(
            "WorkCanonicalIntegrationTestSupportV1-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let fixture = try await WorkCanonicalCurrentRouteFixtureV1.make(
            applicationSupportURL: support,
            pack: .illuminatedSignV1,
            workPhotoData: try makePNG(seed: 113)
        )
        defer {
            try? fixture.close()
            try? fileManager.removeItem(at: support)
        }
        let mutationID = try MutationIDV1(rawValue: fixture.workIdentifiers.mutationID)
        let envelope = try XCTUnwrap(
            fixture.lifecycleDependencies.writer.workEnvelope(mutationID: mutationID)
        )
        let receipt = try XCTUnwrap(
            fixture.lifecycleDependencies.writer.workCommitReceipt(envelope: envelope)
        )
        try body(
            envelope,
            receipt,
            try fixture.lifecycleDependencies.writer.sourceMutationHistorySnapshot()
        )
    }
    static func makePNG(seed: UInt8) throws -> Data {
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
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw WorkCanonicalIntegrationFixtureFailureV1.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw WorkCanonicalIntegrationFixtureFailureV1.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WorkCanonicalIntegrationFixtureFailureV1.invalidImage
        }
        return output as Data
    }
}

private enum WorkCanonicalIntegrationFixtureFailureV1: Error {
    case invalidImage
    case invalidEnvelope
}

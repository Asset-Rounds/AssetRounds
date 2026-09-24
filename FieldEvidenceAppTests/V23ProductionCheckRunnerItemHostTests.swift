import Combine
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23ProductionCheckRunnerItemHostTests: XCTestCase {
    func testPhotoDiscardPreparationReopensOriginalPendingReceipt() async throws {
        for phase in ["awaiting", "raw", "pair"] {
            try await withAsyncFrozenBeginFixture("photo-discard-\(phase)", entry: .check,
                storedTimeZoneID: "America/New_York", appDirectoryLayout: true) { h in
                let photo = try await FrozenProductionPhotoV1.make(h, publishRaw: phase != "awaiting")
                let writer = h.coordinator.workspaceWriter
                let checkpoint: FieldDraftCheckpointV1
                if phase == "pair" {
                    checkpoint = try await photo.service.preparePhotoPair(parentDraftID: photo.parentID,
                        childDraftID: photo.childID)
                } else {
                    checkpoint = try XCTUnwrap(writer.checkRunnerPhotoRawStageEvidence(workspaceID: h.workspaceID,
                        parentDraftID: photo.parentID, childDraftID: photo.childID)).currentCheckpoint
                }
                let parent = try photo.service.read(draftID: photo.parentID)
                let priorStage = try await photo.adapter.item(stageID: photo.intent.stageID)
                let history = try writer.sourceMutationHistorySnapshot()
                XCTAssertThrowsError(try photo.service.preparePhotoDiscard(parentDraftID: photo.parentID,
                    childDraftID: photo.childID, expectedCheckpointSHA256: String(repeating: "0", count: 64)))
                XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
                h.clock.value = checkpoint.updatedAt.addingTimeInterval(1)
                let saved = try photo.service.preparePhotoDiscard(parentDraftID: photo.parentID,
                    childDraftID: photo.childID, expectedCheckpointSHA256: checkpoint.checkpointSHA256)
                XCTAssertEqual(saved.pending.state, .discardPending)
                XCTAssertEqual(saved.pending.payloadData, checkpoint.payloadData)
                XCTAssertNotNil(try writer.fieldDraftEvidence(mutationID: saved.pending.mutationID))
                XCTAssertEqual(try photo.service.read(draftID: photo.parentID), parent)
                let observedStage = try await photo.adapter.item(stageID: photo.intent.stageID)
                XCTAssertEqual(observedStage, priorStage)
                let pendingHistory = try writer.sourceMutationHistorySnapshot()
                XCTAssertNotEqual(pendingHistory, history)
                h.clock.value = h.clock.value.addingTimeInterval(86_400)
                let fresh = try FrozenProductionPhotoV1.reopen(owner: h.coordinator, root: h.root,
                    profile: h.profile, release: h.publishedRelease, clock: h.clock, ids: h.ids)
                let allocations = h.ids.callCount
                for digest in [checkpoint.checkpointSHA256, saved.pending.checkpointSHA256] {
                    XCTAssertEqual(try fresh.service.preparePhotoDiscard(parentDraftID: photo.parentID,
                        childDraftID: photo.childID, expectedCheckpointSHA256: digest), saved)
                }
                XCTAssertEqual(h.ids.callCount, allocations)
                XCTAssertThrowsError(try fresh.service.preparePhotoDiscard(parentDraftID: photo.parentID,
                    childDraftID: photo.childID, expectedCheckpointSHA256: String(repeating: "0", count: 64)))
                XCTAssertThrowsError(try fresh.service.preparePhotoDiscard(parentDraftID: UUID(),
                    childDraftID: photo.childID, expectedCheckpointSHA256: saved.pending.checkpointSHA256))
                XCTAssertThrowsError(try fresh.service.preparePhotoCommit(parentDraftID: photo.parentID,
                    childDraftID: photo.childID, expectedCheckpointSHA256: saved.pending.checkpointSHA256))
                XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), pendingHistory)

                // Exercise canonical history with the real writer. This deliberately
                // leaves media intact: terminal journal proof alone must never be
                // interpreted as a successful physical cleanup or backup admission.
                let activeOriginal = try XCTUnwrap(writer.fieldDraftEvidence(mutationID: checkpoint.mutationID))
                let pendingOriginal = try XCTUnwrap(writer.fieldDraftEvidence(mutationID: saved.pending.mutationID))
                let pendingEvidence = try CheckRunnerPhotoPendingDiscardEvidenceV1(
                    activeCheckpoint: checkpoint, activeOriginal: activeOriginal, pendingOriginal: pendingOriginal)
                let pendingChildHistory = try self.photoChildHistory(pendingHistory, childID: photo.childID)
                let pendingPartition = try CheckRunnerPhotoDiscardHistoryV1(history: pendingChildHistory,
                    checkpoint: saved.pending, receipts: [])
                XCTAssertEqual(pendingPartition.pending, pendingEvidence)
                XCTAssertNil(pendingPartition.terminal)
                XCTAssertEqual(pendingPartition.activeHistory.last, activeOriginal)
                let bundle = try saved.terminalBundle(disposedStageIDs: checkpoint.stageIDs)
                let lifecycle = try writer.makeFieldDraftLifecycleAdapter(modelContext: h.coordinator.modelContext)
                _ = try lifecycle.apply(discardTerminalBundle: bundle,
                    expectedDraftRevision: saved.pending.draftRevision)
                let terminalOriginal = try XCTUnwrap(writer.fieldDraftEvidence(mutationID: saved.terminalMutationID))
                let terminalCheckpoint = try XCTUnwrap(lifecycle.currentCheckpoint(
                    workspaceID: h.workspaceID, draftID: photo.childID))
                let storedReceipts = try h.coordinator.modelContext.fetch(FetchDescriptor<DraftDiscardReceiptRow>())
                    .filter { $0.workspaceID == h.workspaceID.rawValue && $0.draftID == photo.childID }
                    .map { try $0.value() }
                XCTAssertEqual(storedReceipts, [bundle.receipt])
                let terminalEvidence = try CheckRunnerPhotoTerminalDiscardEvidenceV1(pending: pendingEvidence,
                    checkpoint: terminalCheckpoint, receipts: storedReceipts, terminalOriginal: terminalOriginal)
                XCTAssertEqual(terminalEvidence.checkpoint, bundle.discardedCheckpoint)
                XCTAssertEqual(terminalEvidence.receipt.disposedStageIDs, checkpoint.stageIDs)
                XCTAssertEqual(terminalEvidence.pending.request, saved)
                XCTAssertEqual(terminalEvidence.original, terminalOriginal)
                let stageAfterTerminal = try await photo.adapter.item(stageID: photo.intent.stageID)
                XCTAssertEqual(stageAfterTerminal, priorStage)
                XCTAssertEqual(try photo.service.read(draftID: photo.parentID), parent)
                let terminalHistory = try writer.sourceMutationHistorySnapshot()
                let terminalChildHistory = try self.photoChildHistory(terminalHistory, childID: photo.childID)
                let partition = try CheckRunnerPhotoDiscardHistoryV1(history: terminalChildHistory,
                    checkpoint: terminalCheckpoint, receipts: storedReceipts)
                XCTAssertEqual(partition.activeHistory, pendingPartition.activeHistory)
                XCTAssertEqual(partition.terminal, terminalEvidence)
                XCTAssertEqual(try CheckRunnerPhotoDiscardHistoryV1(history: Array(terminalChildHistory.reversed()),
                    checkpoint: terminalCheckpoint, receipts: storedReceipts), partition)
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardHistoryV1(
                    history: terminalChildHistory + [pendingOriginal], checkpoint: terminalCheckpoint,
                    receipts: storedReceipts))
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardHistoryV1(history: [pendingOriginal, terminalOriginal],
                    checkpoint: terminalCheckpoint, receipts: storedReceipts))
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardHistoryV1(history: terminalChildHistory,
                    checkpoint: terminalCheckpoint, receipts: []))
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardHistoryV1(history: pendingChildHistory,
                    checkpoint: saved.pending, receipts: storedReceipts))
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardHistoryV1(history: terminalChildHistory,
                    checkpoint: checkpoint, receipts: storedReceipts))
                XCTAssertThrowsError(try CheckRunnerPhotoTerminalDiscardEvidenceV1(pending: pendingEvidence,
                    checkpoint: saved.pending, receipts: [bundle.receipt], terminalOriginal: terminalOriginal))
                XCTAssertThrowsError(try CheckRunnerPhotoTerminalDiscardEvidenceV1(pending: pendingEvidence,
                    checkpoint: terminalCheckpoint, receipts: [], terminalOriginal: terminalOriginal))
                XCTAssertThrowsError(try CheckRunnerPhotoTerminalDiscardEvidenceV1(pending: pendingEvidence,
                    checkpoint: terminalCheckpoint, receipts: [bundle.receipt, bundle.receipt],
                    terminalOriginal: terminalOriginal))
                let foreignReceipt = try DraftDiscardReceiptV1(receiptID: UUID(), workspaceID: h.workspaceID,
                    draftID: photo.childID, planSHA256: saved.plan.planSHA256,
                    disposedStageIDs: checkpoint.stageIDs, quarantinedReservationIDs: [],
                    discardedAt: saved.pending.updatedAt, mutationID: saved.terminalMutationID)
                XCTAssertThrowsError(try CheckRunnerPhotoTerminalDiscardEvidenceV1(pending: pendingEvidence,
                    checkpoint: terminalCheckpoint, receipts: [foreignReceipt], terminalOriginal: terminalOriginal))
                XCTAssertThrowsError(try CheckRunnerPhotoTerminalDiscardEvidenceV1(pending: pendingEvidence,
                    checkpoint: terminalCheckpoint, receipts: [bundle.receipt], terminalOriginal: pendingOriginal))
                XCTAssertEqual(try CheckRunnerPhotoTerminalDiscardEvidenceV1(pending: pendingEvidence,
                    checkpoint: terminalCheckpoint, receipts: [bundle.receipt], terminalOriginal: terminalOriginal),
                    terminalEvidence)
                XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), terminalHistory)
            }
        }
    }

    private func photoChildHistory(_ snapshot: MutationHistorySnapshotV1, childID: UUID) throws
        -> [FieldDraftCommittedEvidenceV1] {
        try snapshot.receipts.compactMap { record in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyFieldDraft(mutation) = envelope.command,
                  RepetitiveCaptureSourceGraphReviewV2.draftID(mutation.postImage) == childID else { return nil }
            return try FieldDraftCommittedEvidenceV1(envelope: envelope,
                receipt: MutationReceiptV1.decodeCanonical(from: record.receiptData))
        }
    }

    func testPhotoDiscardValuesRetainOriginalStagesAndRejectCommit() async throws {
        try await withAsyncFrozenBeginFixture("photo-discard-values", entry: .check,
            storedTimeZoneID: "America/New_York", appDirectoryLayout: true) { h in
            let photo = try await FrozenProductionPhotoV1.make(h, publishRaw: false)
            let writer = h.coordinator.workspaceWriter
            let original = try XCTUnwrap(writer.checkRunnerPhotoRawStageEvidence(workspaceID: h.workspaceID,
                parentDraftID: photo.parentID, childDraftID: photo.childID))
            let source = h.root.appendingPathComponent("discard-picker.png")
            try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 183).write(to: source)
            _ = try await photo.service.publishRawPhoto(parentDraftID: photo.parentID,
                childDraftID: photo.childID, sourceURL: source)
            let raw = try XCTUnwrap(writer.checkRunnerPhotoRawStageEvidence(workspaceID: h.workspaceID,
                parentDraftID: photo.parentID, childDraftID: photo.childID))
            let pair = try await photo.service.preparePhotoPair(parentDraftID: photo.parentID,
                childDraftID: photo.childID)
            let history = try writer.sourceMutationHistorySnapshot()
            for checkpoint in [original.currentCheckpoint, raw.currentCheckpoint, pair] {
                let request = try CheckRunnerPhotoDiscardV1.prepare(from: checkpoint,
                    mutationID: .init(rawValue: UUID()), at: checkpoint.updatedAt.addingTimeInterval(1))
                XCTAssertEqual(request.pending.state, .discardPending)
                XCTAssertEqual(request.pending.payloadData, checkpoint.payloadData)
                XCTAssertEqual(request.pending.stageIDs, checkpoint.stageIDs)
                XCTAssertEqual(request.cleanupStageID, photo.intent.stageID)
                XCTAssertEqual(request.plan.stageIDs, checkpoint.stageIDs)
                XCTAssertTrue(request.plan.reservationIDs.isEmpty)
                XCTAssertEqual(try CheckRunnerPhotoDiscardV1(pending: request.pending), request)
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardV1(pending: checkpoint))
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardV1.prepare(from: request.pending,
                    mutationID: .init(rawValue: UUID()), at: request.pending.updatedAt))
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardV1.prepare(from: checkpoint,
                    mutationID: checkpoint.mutationID, at: checkpoint.updatedAt))
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardV1.prepare(from: checkpoint,
                    mutationID: .init(rawValue: UUID()), at: checkpoint.updatedAt.addingTimeInterval(-1)))
                if !checkpoint.stageIDs.isEmpty {
                    XCTAssertThrowsError(try request.terminalBundle(disposedStageIDs: []))
                } else {
                    XCTAssertThrowsError(try request.terminalBundle(disposedStageIDs: [photo.intent.stageID]))
                }
                XCTAssertThrowsError(try request.terminalBundle(disposedStageIDs: [UUID()]))
                XCTAssertThrowsError(try request.terminalBundle(disposedStageIDs: [photo.intent.stageID, photo.intent.stageID]))
                let terminal = try request.terminalBundle(disposedStageIDs: checkpoint.stageIDs)
                XCTAssertEqual(terminal.discardedCheckpoint.state, .discarded)
                XCTAssertEqual(terminal.discardedCheckpoint.payloadData, checkpoint.payloadData)
                XCTAssertEqual(terminal.receipt.planSHA256, request.plan.planSHA256)
                XCTAssertEqual(terminal.receipt.disposedStageIDs, checkpoint.stageIDs)
                XCTAssertEqual(try CheckRunnerPhotoDiscardV1(pending: request.pending)
                    .terminalBundle(disposedStageIDs: checkpoint.stageIDs), terminal)
                XCTAssertThrowsError(try CheckRunnerPhotoDiscardV1(pending: terminal.discardedCheckpoint))
            }
            // Value construction never deletes bytes or persists a discard.
            XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            let committing = try photo.service.preparePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, expectedCheckpointSHA256: pair.checkpointSHA256)
            XCTAssertThrowsError(try CheckRunnerPhotoDiscardV1.prepare(from: committing,
                mutationID: .init(rawValue: UUID()), at: committing.updatedAt))
            let activeWithCommitPayload = try FieldDraftCheckpointV1(draftID: committing.draftID,
                workspaceID: committing.workspaceID, scope: committing.scope, purpose: committing.purpose,
                codec: committing.codec, baseCanonicalRevision: committing.baseCanonicalRevision,
                draftRevision: committing.draftRevision, payloadData: committing.payloadData,
                stageIDs: committing.stageIDs, resumeAnchor: committing.resumeAnchor,
                state: .active, updatedAt: committing.updatedAt, mutationID: committing.mutationID)
            XCTAssertThrowsError(try CheckRunnerPhotoDiscardV1.prepare(from: activeWithCommitPayload,
                mutationID: .init(rawValue: UUID()), at: committing.updatedAt))
        }
    }

    func testDurablePreflightSubmitsConfirmedEnteredTimeZoneWithoutRewritingSavedInput() async throws {
        for mode in ["confirmed", "unconfirmed", "invalid"] {
            try await withAsyncFrozenBeginFixture("durable-preflight-\(mode)", entry: .check,
                storedTimeZoneID: nil) { h in
                let source = try h.captureSource()
                let service = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator,
                    progress: h.progress, coordinator: h.runner, publishedRelease: h.publishedRelease,
                    clock: h.clock, ids: h.ids)
                let fields = CheckRunnerEditablePreflightV1(
                    timeZoneID: mode == "invalid" ? "  invalid/timezone  " : "  America/New_York  ",
                    isTimeZoneConfirmed: mode != "unconfirmed", confirmedTimeZoneID: nil,
                    afterDarkAccepted: true, safePositionAccepted: true)
                let parent = try service.create(source: source, preflight: fields)
                let revision = try h.coordinator.workspaceWriter.currentRevision()
                if mode != "confirmed" {
                    XCTAssertThrowsError(try service.prepareBegin(draftID: parent.draftID,
                        expectedCheckpointSHA256: parent.checkpointSHA256, observedAtUTC: h.clock.millisecondValue))
                    XCTAssertEqual(try service.read(draftID: parent.draftID), parent)
                    XCTAssertEqual(try h.coordinator.workspaceWriter.currentRevision(), revision)
                    return
                }
                let prepared = try service.prepareBegin(draftID: parent.draftID,
                    expectedCheckpointSHA256: parent.checkpointSHA256, observedAtUTC: h.clock.millisecondValue)
                let attempt = try XCTUnwrap(CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared).field.begin.attempt)
                XCTAssertEqual(try XCTUnwrap(attempt.timeZone).command.timeZoneID, "America/New_York")
                let bound = try service.resumeInitialBegin(draftID: parent.draftID)
                let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(bound)
                guard case .bound = payload.field.begin else { return XCTFail("Expected authentic Begin readback") }
                XCTAssertEqual(payload.field.preflight, fields)
                let sites = try h.coordinator.modelContext.fetch(FetchDescriptor<Site>())
                XCTAssertEqual(try XCTUnwrap(sites.first { $0.id == h.siteID }).timeZoneID, "America/New_York")
                let committedRevision = try h.coordinator.workspaceWriter.currentRevision()
                XCTAssertEqual(try service.resumeInitialBegin(draftID: parent.draftID), bound)
                XCTAssertEqual(try h.coordinator.workspaceWriter.currentRevision(), committedRevision)
            }
        }
    }

    func testStartupPrivateRetirementPreservesCanonicalNamesAndRejectsStaleOrReplacedPlans() async throws {
        for mode in ["success", "replacement", "retired", "access-expired"] {
            try await withAsyncFrozenBeginFixture("private-startup-\(mode)", entry: .check,
                storedTimeZoneID: "America/Chicago", appDirectoryLayout: true) { h in
                let generationRoot = h.coordinator.generationRootURL
                // Create the same protected directories as the real finalizer.
                _ = FinalizationIntentStore(generationRootURL: generationRoot)
                let staging = generationRoot.appendingPathComponent(".staging/snapshots")
                let partialJournal = staging.appendingPathComponent(".live-finalization-\(UUID().uuidString.lowercased()).tmp")
                let displacedSnapshot = staging.appendingPathComponent(".live-finalization-\(UUID().uuidString.lowercased()).tmp")
                let privatePhoto = generationRoot.appendingPathComponent(".immutable-\(UUID().uuidString.lowercased()).tmp")
                let canonicalName = staging.appendingPathComponent("\(UUID().uuidString.lowercased()).json")
                let canary = Data("canonical-name-must-survive".utf8)
                for (url, data, policy) in [
                    (partialJournal, Data(), OwnedFileKindV1.journal),
                    (displacedSnapshot, Data("uncommitted-private-snapshot".utf8), .reportSnapshot),
                    (privatePhoto, Data("private-photo-preparation".utf8), .temporaryFile),
                    (canonicalName, canary, .stagingFile)
                ] {
                    try data.write(to: url)
                    try ProtectedFilePolicyV1.applyAndVerify(policy, at: url)
                }
                var resourceLeftovers: [URL] = []
                if mode == "success" {
                    // A sparse private payload must be retired without reading it
                    // into memory; accumulated leaves must not retain one FD each.
                    let sparse = generationRoot.appendingPathComponent(
                        ".immutable-\(UUID().uuidString.lowercased()).tmp")
                    try Data().write(to: sparse)
                    let handle = try FileHandle(forWritingTo: sparse)
                    do {
                        try handle.truncate(atOffset: 8 * 1_024 * 1_024 * 1_024)
                        try handle.close()
                    } catch {
                        try? handle.close()
                        throw error
                    }
                    try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: sparse)
                    XCTAssertEqual(try sparse.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                        8 * 1_024 * 1_024 * 1_024)
                    resourceLeftovers.append(sparse)
                    for _ in 0..<384 {
                        let leftover = staging.appendingPathComponent(
                            ".live-finalization-\(UUID().uuidString.lowercased()).tmp")
                        try Data([0x41]).write(to: leftover)
                        try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: leftover)
                        resourceLeftovers.append(leftover)
                    }
                }
                let history = try h.coordinator.workspaceWriter.sourceMutationHistorySnapshot()
                try h.closeCoordinator()
                let router = StartupRouter(applicationSupportURL: h.root)
                var startupDiagnostics: [String] = []
                router.startupFailureDiagnosticForTesting = { startupDiagnostics.append($0) }
                let gate = AppAccessGateV1(setting: .absentDisabled,
                    authentication: FrozenBeginAuthentication(), clock: h.clock, identifiers: h.ids)
                var boundaryCount = 0
                let replacedBytes = Data("replacement-is-not-the-prepared-inode".utf8)
                if mode == "replacement" {
                    router.beforePrivatePreparationCleanupForTesting = { _ in
                        boundaryCount += 1
                        try FileManager.default.removeItem(at: privatePhoto)
                        try replacedBytes.write(to: privatePhoto)
                        try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: privatePhoto)
                    }
                } else if mode == "retired" {
                    router.beforePrivatePreparationCleanupForTesting = { _ in
                        boundaryCount += 1
                        router.pauseForAppAccess()
                    }
                } else if mode == "access-expired" {
                    router.beforePrivatePreparationCleanupForTesting = { _ in
                        boundaryCount += 1
                        // Disabled -> disabled still retires the original read epoch.
                        // Do not pause the router: the actual gate must deny cleanup.
                        await gate.lock(reason: .interrupted)
                    }
                }
                defer { router.beforePrivatePreparationCleanupForTesting = nil }
                if mode == "access-expired" {
                    do {
                        try await router.startIfNeeded(accessGate: gate)
                        XCTFail("Startup must reject its expired original access token" + " " + startupDiagnosis(router, diagnostics: startupDiagnostics, boundary: boundaryCount))
                    } catch {
                        XCTAssertNotNil(error as? AppAccessContractFailureV1)
                    }
                } else {
                    await router.startIfNeeded()
                }
                XCTAssertEqual(try Data(contentsOf: canonicalName), canary)
                if mode == "replacement" {
                    guard case .maintenance(.finalizationInconsistent) = router.route else {
                        return XCTFail("Startup must reject substitution before deleting any prepared leaf" + " " + startupDiagnosis(router, diagnostics: startupDiagnostics, boundary: boundaryCount))
                    }
                    XCTAssertEqual(boundaryCount, 1)
                    XCTAssertEqual(try Data(contentsOf: privatePhoto), replacedBytes)
                    XCTAssertTrue(FileManager.default.fileExists(atPath: partialJournal.path))
                    XCTAssertTrue(FileManager.default.fileExists(atPath: displacedSnapshot.path))
                } else if mode == "retired" || mode == "access-expired" {
                    guard case .checking = router.route else {
                        return XCTFail("A retired startup must not publish its former writer" + " " + startupDiagnosis(router, diagnostics: startupDiagnostics, boundary: boundaryCount))
                    }
                    XCTAssertEqual(boundaryCount, 1)
                    XCTAssertEqual(try Data(contentsOf: privatePhoto), Data("private-photo-preparation".utf8))
                    XCTAssertTrue(FileManager.default.fileExists(atPath: partialJournal.path))
                    XCTAssertTrue(FileManager.default.fileExists(atPath: displacedSnapshot.path))
                    if mode == "access-expired" {
                        XCTAssertNotNil(router.lastStartupAccessFailure)
                        router.beforePrivatePreparationCleanupForTesting = nil
                        try await router.retryChecks(accessGate: gate)
                        guard case let .ready(store, _, _) = router.route else {
                            return XCTFail("Fresh access must recover without reusing the expired cleanup ticket" + " " + startupDiagnosis(router, diagnostics: startupDiagnostics, boundary: boundaryCount))
                        }
                        defer { XCTAssertNoThrow(try store.invalidateAndReleaseWriter()) }
                        for url in [partialJournal, displacedSnapshot, privatePhoto] {
                            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                        }
                        XCTAssertEqual(try Data(contentsOf: canonicalName), canary)
                        XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), history)
                    }
                } else {
                    guard case let .ready(store, _, _) = router.route else {
                        return XCTFail("Actual startup must dispose of reserved crash leftovers before publication" + " " + startupDiagnosis(router, diagnostics: startupDiagnostics, boundary: boundaryCount))
                    }
                    defer { XCTAssertNoThrow(try store.invalidateAndReleaseWriter()) }
                    for url in [partialJournal, displacedSnapshot, privatePhoto] + resourceLeftovers {
                        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                    }
                    XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), history)
                }
            }
        }
    }

    func testStartupPrivateRetirementRejectsMalformedNamesAndUnsafeFileKinds() async throws {
        for mode in ["malformed", "directory", "symlink", "hardlink"] {
            try await withAsyncFrozenBeginFixture("private-hostile-\(mode)", entry: .check,
                storedTimeZoneID: "America/Chicago", appDirectoryLayout: true) { h in
                let generationRoot = h.coordinator.generationRootURL
                _ = FinalizationIntentStore(generationRootURL: generationRoot)
                let staging = generationRoot.appendingPathComponent(".staging/snapshots")
                let legitimate = staging.appendingPathComponent(".live-finalization-00000000-0000-0000-0000-000000000001.tmp")
                let privateBytes = Data("owned-private-preparation".utf8)
                try privateBytes.write(to: legitimate)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: legitimate)
                let name = mode == "malformed" ? ".live-finalization-not-a-uuid.tmp"
                    : ".live-finalization-\(UUID().uuidString.lowercased()).tmp"
                let hostile = staging.appendingPathComponent(name)
                let outside = h.root.appendingPathComponent("unowned-private-cleanup-canary")
                let canary = Data("must-not-follow-or-delete".utf8)
                try canary.write(to: outside)
                try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: outside)
                switch mode {
                case "malformed":
                    try canary.write(to: hostile)
                    try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: hostile)
                case "directory":
                    try FileManager.default.createDirectory(at: hostile, withIntermediateDirectories: false)
                    try canary.write(to: hostile.appendingPathComponent("child"))
                case "symlink":
                    try FileManager.default.createSymbolicLink(at: hostile, withDestinationURL: outside)
                case "hardlink":
                    try FileManager.default.linkItem(at: outside, to: hostile)
                default: return XCTFail("Unexpected hostile case")
                }
                try h.closeCoordinator()
                let router = StartupRouter(applicationSupportURL: h.root)
                var publicationBoundaryCount = 0
                var startupDiagnostics: [String] = []
                router.startupFailureDiagnosticForTesting = { startupDiagnostics.append($0) }
                router.beforePrivatePreparationCleanupForTesting = { _ in publicationBoundaryCount += 1 }
                defer { router.beforePrivatePreparationCleanupForTesting = nil }
                await router.startIfNeeded()
                guard case .maintenance(.finalizationInconsistent) = router.route else {
                    return XCTFail("Unsafe private preparation must fail the actual startup route: \(mode) " + startupDiagnosis(router, diagnostics: startupDiagnostics, boundary: publicationBoundaryCount))
                }
                XCTAssertEqual(publicationBoundaryCount, 0)
                XCTAssertEqual(try Data(contentsOf: legitimate), privateBytes)
                XCTAssertEqual(try Data(contentsOf: outside), canary)
                XCTAssertTrue(FileManager.default.fileExists(atPath: hostile.path))
                if mode == "directory" {
                    XCTAssertEqual(try Data(contentsOf: hostile.appendingPathComponent("child")), canary)
                }
            }
        }
    }

    func testStartupPrivateRetirementPreservesInterruptedFinalizationAndReachesEraseAdmission() async throws {
        for committed in [false, true] {
            try await withAsyncFrozenBeginFixture("private-recovery-\(committed)", entry: .check,
                storedTimeZoneID: "America/Chicago", appDirectoryLayout: true) { h in
                let draft = try await makeFrozenParentFinalizationDraft(h,
                    selection: .couldNotVerify(reasonKey: "conditions_changed", note: nil), photoCount: 0)
                let runner = try CheckRunnerCoordinator(modelContext: h.coordinator.modelContext,
                    packageLifecycleDependencies: h.coordinator.packageLifecycleDependencies(
                        profileRegistry: h.coordinator.lifecycleProfileRegistry),
                    packageLifecycleProfile: h.profile,
                    finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection(
                        failOnceAt: .intentPhaseWrite(committed ? .databaseCommitted : .snapshotPromoted)))
                runner.configureCapture(generationRootURL: h.coordinator.generationRootURL)
                let service = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator,
                    progress: h.progress, coordinator: runner, publishedRelease: h.publishedRelease,
                    clock: h.clock, ids: h.ids)
                let prepared = try await service.prepareFinalization(draftID: draft.checkpoint.draftID,
                    expectedCheckpointSHA256: draft.checkpoint.checkpointSHA256,
                    sourceApp: SourceAppSnapshotV1(build: "private-recovery", version: "1.0")) { }
                let attempt = try XCTUnwrap(CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared).finalizationAttempt)
                do {
                    let terminal = try await service.resumeFinalization(draftID: prepared.draftID) { }
                    // A committed target may recover its receipt despite a lost
                    // cleanup acknowledgement; the uncommitted case cannot.
                    XCTAssertTrue(committed)
                    XCTAssertEqual(terminal.state, .committed)
                } catch {
                    // The durable journal and receipt assertions below identify
                    // the exact interruption; unrelated earlier failures cannot pass.
                }
                let generationRoot = h.coordinator.generationRootURL
                let journal = h.root.appendingPathComponent(
                    "FieldEvidenceOperations/finalization/\(attempt.identifiers.mutationID.uuidString.lowercased()).json")
                let journalBytes = try Data(contentsOf: journal)
                let intent = try FinalizationContractDecoderV1().decodeIntent(journalBytes)
                XCTAssertEqual(intent.phase, committed ? .snapshotPromoted : .prepared)
                let binding = try XCTUnwrap(intent.writerCommitBinding)
                XCTAssertEqual(try h.coordinator.workspaceWriter.finalizationCommitReceipt(binding) != nil, committed)
                let snapshot = generationRoot.appendingPathComponent(intent.snapshotFinalRelativePath)
                let snapshotBytes = try Data(contentsOf: snapshot)
                let privateJournal = generationRoot.appendingPathComponent(
                    ".staging/snapshots/.live-finalization-\(UUID().uuidString.lowercased()).tmp")
                let privatePhoto = generationRoot.appendingPathComponent(".immutable-\(UUID().uuidString.lowercased()).tmp")
                try Data("interrupted-private-journal".utf8).write(to: privateJournal)
                try ProtectedFilePolicyV1.applyAndVerify(.journal, at: privateJournal)
                try Data("interrupted-private-photo".utf8).write(to: privatePhoto)
                try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: privatePhoto)
                try h.closeCoordinator()

                let router = StartupRouter(applicationSupportURL: h.root)
                var preparationCount = 0
                var startupDiagnostics: [String] = []
                router.startupFailureDiagnosticForTesting = { startupDiagnostics.append($0) }
                router.beforePrivatePreparationCleanupForTesting = { _ in
                    preparationCount += 1
                    XCTAssertEqual(try Data(contentsOf: journal), journalBytes)
                    XCTAssertEqual(try Data(contentsOf: snapshot), snapshotBytes)
                }
                defer { router.beforePrivatePreparationCleanupForTesting = nil }
                await router.startIfNeeded()
                guard case let .ready(store, diagnostics, _) = router.route else {
                    return XCTFail("Private retirement must leave canonical interrupted finalization recoverable " + startupDiagnosis(router, diagnostics: startupDiagnostics, boundary: preparationCount))
                }
                defer { XCTAssertNoThrow(try store.invalidateAndReleaseWriter()) }
                XCTAssertEqual(preparationCount, 1)
                for url in [privateJournal, privatePhoto, journal] {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                }
                XCTAssertEqual(try Data(contentsOf: snapshot), snapshotBytes)
                XCTAssertNotNil(try store.workspaceWriter.finalizationCommitReceipt(binding))
                let recoveredEnvelope = try XCTUnwrap(store.workspaceWriter.finalizationEnvelope(
                    mutationID: .init(rawValue: attempt.identifiers.mutationID)))
                XCTAssertEqual(try recoveredEnvelope.canonicalData(), binding.envelopeData)
                XCTAssertEqual(try store.modelContext.fetch(FetchDescriptor<Report>())
                    .filter { $0.id == attempt.identifiers.reportID }.count, 1)

                // Exercise the real Erase entry and strict inventory before its
                // first destructive effect. This proves admission, not full Erase.
                let suite = "V23.PrivateRecoveryErase.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let fixtureRoot = h.root.deletingLastPathComponent()
                let temporary = fixtureRoot.appendingPathComponent("tmp", isDirectory: true)
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                var admissionCount = 0
                let history = try store.workspaceWriter.sourceMutationHistorySnapshot()
                let revision = try store.workspaceWriter.currentRevision()
                let eraser = EraseAllService(applicationSupportURL: h.root,
                    cachesDirectoryURL: fixtureRoot.appendingPathComponent("Caches", isDirectory: true),
                    temporaryDirectoryURL: temporary, userDefaults: defaults, defaultsDomainName: suite,
                    privateSystemDiscoveryIndex: nil, notificationSystem: ItemHostNotificationSystem(),
                    admitErase: { _ in
                        admissionCount += 1
                        throw ItemHostInjectedFailure.stopAtEraseAdmission
                    })
                do {
                    _ = try await eraser.erase(confirmation: "ERASE", coordinator: store,
                        diagnosticsStore: diagnostics,
                        activate: { _ in XCTFail("Admission stop must prevent activation") },
                        lifecycleDependencies: store.packageLifecycleDependencies())
                    XCTFail("The admission probe must not perform Erase")
                } catch {
                    XCTAssertEqual(error as? ItemHostInjectedFailure, .stopAtEraseAdmission)
                }
                XCTAssertEqual(admissionCount, 1)
                XCTAssertEqual(try store.workspaceWriter.currentRevision(), revision)
                XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), history)
                XCTAssertEqual(try Data(contentsOf: snapshot), snapshotBytes)
                XCTAssertNil(try EraseIntentStore(applicationSupportURL: h.root).load())
            }
        }
    }

    /// Diagnostic only: the actual startup route and the router's DEBUG failure phase.
    @MainActor
    private func startupDiagnosis(_ router: StartupRouter, diagnostics: [String], boundary: Int) -> String {
        let route: String
        switch router.route {
        case .checking: route = "checking"
        case let .maintenance(reason): route = "maintenance(\(reason))"
        case .ready: route = "ready"
        case .awaitingIndependentValidation: route = "awaitingIndependentValidation"
        case .eraseCleanupPending: route = "eraseCleanupPending"
        }
        let summary = "route=\(route) boundary=\(boundary) diagnostics=\(diagnostics)"
        print("V23_STARTUP_DIAGNOSIS " + summary)
        return summary
    }

    func testLiveFinalizationUsesOriginalReceiptAndRejectsRetiredOperation() async throws {
        try await withAsyncFrozenBeginFixture("live-parent-finalization", entry: .check,
            storedTimeZoneID: "America/Chicago", appDirectoryLayout: true) { h in
            let draft = try await makeFrozenParentFinalizationDraft(h,
                selection: .couldNotVerify(reasonKey: "conditions_changed", note: nil), photoCount: 0)
            let source = try CheckRunnerItemDraftCodecV1.validateCheckpoint(draft.checkpoint).source
            try h.closeCoordinator()
            let suite = "V23.LiveFinalization.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let router = StartupRouter(applicationSupportURL: h.root)
            let session = try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: h.root, startupRouter: router, defaults: defaults,
                authenticationClient: FrozenBeginAuthentication(), notificationSystem: ItemHostNotificationSystem())
            let presentation = AppAccessPresentationV1(startupRouter: router, sessionFactory: { session })
            let ready = self.expectation(description: "Real live finalization publication")
            let subscription = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
                .sink { _ in ready.fulfill() }
            defer { subscription.cancel() }
            await presentation.bootstrapIfNeeded()
            await self.fulfillment(of: [ready], timeout: 30)
            guard case let .ready(store, _, _) = router.route else {
                return XCTFail("Expected the production finalization writer")
            }
            defer { XCTAssertNoThrow(try store.invalidateAndReleaseWriter()) }
            let access = try XCTUnwrap(presentation.roundAccess)
            let scene = AppShellSceneStateV1(workspaceID: store.workspaceID,
                access: try XCTUnwrap(presentation.sceneNavigationAccess), registry: try RouteRegistryV1())
            try scene.restore()
            let target = try NavigationTargetV1(workspaceID: store.workspaceID, destination: .work,
                stableSessionID: source.roundAtEntry.sessionID, requestedMode: .resume,
                fallback: NavigationFallbackV1(root: .work, destination: .work))
            try scene.open(target)
            let service = try access.makeCheckRunnerItemService(source: source)
            let operation = try access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target)
            let prepared = try await service.prepareFinalization(draftID: draft.checkpoint.draftID,
                expectedCheckpointSHA256: draft.checkpoint.checkpointSHA256,
                sourceApp: SourceAppSnapshotV1(build: "live-finalization", version: "1.0"),
                authorizing: operation) { }
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared)
            let attempt = try XCTUnwrap(payload.finalizationAttempt)
            let mutationID = try MutationIDV1(rawValue: attempt.identifiers.mutationID)
            let reportName = "\(attempt.identifiers.reportID.uuidString.lowercased()).json"
            let snapshot = store.generationRootURL.appendingPathComponent("snapshots/\(reportName)")
            let staged = store.generationRootURL.appendingPathComponent(".staging/snapshots/\(reportName)")
            let journal = h.root.appendingPathComponent(
                "FieldEvidenceOperations/finalization/\(attempt.identifiers.mutationID.uuidString.lowercased()).json")
            let before = try store.workspaceWriter.sourceMutationHistorySnapshot()
            let revision = try store.workspaceWriter.currentRevision()
            // Returning to the same route must not revive the old operation.
            try scene.select(.reports)
            try scene.select(.work)
            do {
                _ = try await service.resumeFinalization(draftID: prepared.draftID, authorizing: operation) { }
                XCTFail("Retired scene authority must not enter the real finalizer")
            } catch { }
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), before)
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), revision)
            XCTAssertNil(try store.workspaceWriter.durableReceipt(mutationID: mutationID))
            for path in [snapshot, staged, journal] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
            }
            let retiring = try access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target)
            var preparedBoundaryCount = 0
            var boundaryHistory: MutationHistorySnapshotV1?
            var boundaryRevision: WorkspaceRevisionV1?
            retiring.beforeFinalizationPreparationPublicationForTesting = {
                preparedBoundaryCount += 1
                try scene.select(.reports)
                try scene.select(.work)
                boundaryHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
                boundaryRevision = try store.workspaceWriter.currentRevision()
            }
            do {
                _ = try await service.resumeFinalization(draftID: prepared.draftID, authorizing: retiring) { }
                XCTFail("Retirement after real private preparation must deny canonical publication")
            } catch { }
            retiring.beforeFinalizationPreparationPublicationForTesting = nil
            XCTAssertEqual(preparedBoundaryCount, 1)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), try XCTUnwrap(boundaryHistory))
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), try XCTUnwrap(boundaryRevision))
            XCTAssertNil(try store.workspaceWriter.durableReceipt(mutationID: mutationID))
            for path in [snapshot, staged, journal] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
            }
            let stagingDirectory = store.generationRootURL.appendingPathComponent(".staging/snapshots")
            let privateAfterDenial = try FileManager.default.contentsOfDirectory(atPath: stagingDirectory.path)
                .filter { $0.hasPrefix(".live-finalization-") }
            XCTAssertTrue(privateAfterDenial.isEmpty)
            let current = try access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target)
            service.beforeParentTargetAcknowledgementForTesting = { throw ItemHostInjectedFailure.lostAcknowledgement }
            defer { service.beforeParentTargetAcknowledgementForTesting = nil }
            do {
                _ = try await service.resumeFinalization(draftID: prepared.draftID, authorizing: current) { }
                XCTFail("The actual finalizer must reach the lost acknowledgement boundary")
            } catch { XCTAssertEqual(error as? ItemHostInjectedFailure, .lostAcknowledgement) }
            let receipt = try XCTUnwrap(store.workspaceWriter.durableReceipt(mutationID: mutationID))
            let snapshotBytes = try Data(contentsOf: snapshot)
            XCTAssertFalse(snapshotBytes.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: stagingDirectory.path)
                .filter { $0.hasPrefix(".live-finalization-") }.isEmpty)
            service.beforeParentTargetAcknowledgementForTesting = nil
            let terminal = try await service.resumeFinalization(draftID: prepared.draftID, authorizing: current) { }
            XCTAssertEqual(terminal.state, .committed)
            XCTAssertEqual(try store.workspaceWriter.durableReceipt(mutationID: mutationID), receipt)
            let completedHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
            let completedRevision = try store.workspaceWriter.currentRevision()
            let replay = try await service.resumeFinalization(draftID: prepared.draftID, authorizing: current) { }
            XCTAssertEqual(replay, terminal)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), completedHistory)
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), completedRevision)
            XCTAssertEqual(try Data(contentsOf: snapshot), snapshotBytes)
        }
    }

    func testLivePhotoRejectsRetiredPublicationAndRecoversOriginalCommitReceipt() async throws {
        try await withAsyncFrozenBeginFixture("live-photo-publication", entry: .check,
            storedTimeZoneID: "America/New_York", appDirectoryLayout: true) { h in
            // Seed only the genuine durable Begin. Selection, byte publication
            // and commit below exercise the live production entry points.
            let source = try h.captureSource()
            let seed = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator,
                progress: h.progress, coordinator: h.runner, publishedRelease: h.publishedRelease,
                clock: h.clock, ids: h.ids)
            let initial = try seed.create(source: source, preflight: .init(
                timeZoneID: "America/Chicago", isTimeZoneConfirmed: true,
                confirmedTimeZoneID: "America/Chicago", afterDarkAccepted: true, safePositionAccepted: true))
            let preparedBegin = try seed.prepareBegin(draftID: initial.draftID,
                expectedCheckpointSHA256: initial.checkpointSHA256, observedAtUTC: h.clock.millisecondValue)
            let bound = try seed.resumeInitialBegin(draftID: preparedBegin.draftID)
            let bytes = try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 183)
            let picker = h.root.appendingPathComponent("live-picker-original.png")
            try bytes.write(to: picker)
            try h.closeCoordinator()

            let suite = "V23.LivePhoto.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let router = StartupRouter(applicationSupportURL: h.root)
            let session = try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: h.root, startupRouter: router, defaults: defaults,
                authenticationClient: FrozenBeginAuthentication(), notificationSystem: ItemHostNotificationSystem())
            let presentation = AppAccessPresentationV1(startupRouter: router, sessionFactory: { session })
            let ready = self.expectation(description: "Real live photo publication")
            let subscription = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
                .sink { _ in ready.fulfill() }
            defer { subscription.cancel() }
            await presentation.bootstrapIfNeeded()
            await self.fulfillment(of: [ready], timeout: 30)
            guard case let .ready(store, _, _) = router.route else {
                return XCTFail("Expected the production writer for live photo capture")
            }
            defer { XCTAssertNoThrow(try store.invalidateAndReleaseWriter()) }
            let access = try XCTUnwrap(presentation.roundAccess)
            let scene = AppShellSceneStateV1(workspaceID: store.workspaceID,
                access: try XCTUnwrap(presentation.sceneNavigationAccess), registry: try RouteRegistryV1())
            try scene.restore()
            let target = try NavigationTargetV1(workspaceID: store.workspaceID, destination: .work,
                stableSessionID: source.roundAtEntry.sessionID, requestedMode: .resume,
                fallback: NavigationFallbackV1(root: .work, destination: .work))
            try scene.open(target)
            let service = try access.makeCheckRunnerItemService(source: source)
            let operation = try access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target)
            let beforeSelection = try store.workspaceWriter.sourceMutationHistorySnapshot()
            XCTAssertThrowsError(try service.makeRawPhotoProposal(parentDraftID: bound.draftID,
                expectedCheckpointSHA256: bound.checkpointSHA256, captureStep: .wide,
                expectedSourceByteCount: Int64(bytes.count), origin: .localImport))
            XCTAssertThrowsError(try service.makeRawPhotoProposal(parentDraftID: bound.draftID,
                expectedCheckpointSHA256: String(repeating: "0", count: 64), captureStep: .wide,
                expectedSourceByteCount: Int64(bytes.count), origin: .localImport, authorizing: operation))
            XCTAssertThrowsError(try service.makeRawPhotoProposal(parentDraftID: bound.draftID,
                expectedCheckpointSHA256: bound.checkpointSHA256, captureStep: .close,
                expectedSourceByteCount: Int64(bytes.count), origin: .localImport, authorizing: operation))
            XCTAssertThrowsError(try service.makeRawPhotoProposal(parentDraftID: bound.draftID,
                expectedCheckpointSHA256: bound.checkpointSHA256, captureStep: .wide,
                expectedSourceByteCount: 0, origin: .localImport, authorizing: operation))
            let proposal = try service.makeRawPhotoProposal(parentDraftID: bound.draftID,
                expectedCheckpointSHA256: bound.checkpointSHA256, captureStep: .wide,
                expectedSourceByteCount: Int64(bytes.count), origin: .localImport, authorizing: operation)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), beforeSelection)
            XCTAssertEqual(try service.read(draftID: bound.draftID), bound)
            XCTAssertEqual(proposal.sourceBinding, source)
            XCTAssertEqual(proposal.purposeKey, "wide_context")
            XCTAssertEqual(proposal.phase.intent.expectedSourceByteCount, Int64(bytes.count))
            let photo = (parentID: bound.draftID, childID: proposal.childDraftID)
            let awaiting = try operation.withAuthorization {
                try service.prepareRawPhoto(parentDraftID: bound.draftID,
                    expectedCheckpointSHA256: bound.checkpointSHA256, proposal: proposal)
            }
            let pendingParent = try service.read(draftID: bound.draftID)
            let selectedHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
            XCTAssertEqual(try operation.withAuthorization {
                try service.prepareRawPhoto(parentDraftID: bound.draftID,
                    expectedCheckpointSHA256: pendingParent.checkpointSHA256, proposal: proposal)
            }, awaiting)
            XCTAssertThrowsError(try service.makeRawPhotoProposal(parentDraftID: bound.draftID,
                expectedCheckpointSHA256: pendingParent.checkpointSHA256, captureStep: .wide,
                expectedSourceByteCount: Int64(bytes.count), origin: .localImport, authorizing: operation))
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), selectedHistory)
            try service.prepareLivePhotoStaging(authorizing: operation)
            _ = try await service.publishRawPhoto(parentDraftID: photo.parentID, childDraftID: photo.childID,
                sourceURL: picker, authorizing: operation)
            let pairCheckpoint = try await service.preparePhotoPair(parentDraftID: photo.parentID,
                childDraftID: photo.childID, authorizing: operation)
            let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(pairCheckpoint)
            guard case let .pairReady(pair) = payload.phase else { return XCTFail("Expected actual normalized pair") }
            XCTAssertEqual(pair.raw.originalProvenance.origin, .localImport)
            let continuation = try XCTUnwrap(store.workspaceWriter.checkRunnerPhotoContinuationEvidence(
                workspaceID: store.workspaceID, parentDraftID: photo.parentID, childDraftID: photo.childID))
            let beforePreparation = try store.workspaceWriter.sourceMutationHistorySnapshot()
            XCTAssertThrowsError(try service.preparePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, expectedCheckpointSHA256: pairCheckpoint.checkpointSHA256))
            XCTAssertThrowsError(try service.preparePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, expectedCheckpointSHA256: String(repeating: "0", count: 64),
                authorizing: operation))
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), beforePreparation)
            let committing = try service.preparePhotoCommit(parentDraftID: photo.parentID, childDraftID: photo.childID,
                expectedCheckpointSHA256: pairCheckpoint.checkpointSHA256, authorizing: operation)
            let attempt = try XCTUnwrap(CheckRunnerPhotoDraftCodecV1.validateCheckpoint(committing).phase.attempt)
            XCTAssertEqual(attempt.expectedWorkflowRecordRevision, continuation.currentWorkflowPostImage.revision)
            XCTAssertEqual(attempt.targetMutationID.rawValue, pair.raw.intent.evidenceID)
            XCTAssertEqual(attempt.reservationReviewAfter.timeIntervalSince(attempt.promotionAt), 3_600)
            let preparedHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
            for originalOrCurrent in [pairCheckpoint.checkpointSHA256, committing.checkpointSHA256] {
                XCTAssertEqual(try service.preparePhotoCommit(parentDraftID: photo.parentID, childDraftID: photo.childID,
                    expectedCheckpointSHA256: originalOrCurrent, authorizing: operation), committing)
            }
            XCTAssertThrowsError(try service.preparePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, expectedCheckpointSHA256: String(repeating: "0", count: 64),
                authorizing: operation))
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), preparedHistory)
            let content = store.generationRootURL.appendingPathComponent(
                "content/\(store.workspaceID.rawValue.uuidString.lowercased())/\(pair.raw.inspection.rawContentID)/original.bin")
            let manifest = h.root.appendingPathComponent("FieldEvidenceData")
                .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName)
                .appendingPathComponent(DraftAttachmentStagingAdapterV1.manifestName)
            let originalManifest = try Data(contentsOf: manifest)
            var boundaryHistory: MutationHistorySnapshotV1?
            var boundaryRevision: WorkspaceRevisionV1?
            var boundaries = 0
            service.beforeRawPhotoImmutablePublicationForTesting = {
                boundaries += 1
                XCTAssertFalse(FileManager.default.fileExists(atPath: content.path))
                boundaryHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
                boundaryRevision = try store.workspaceWriter.currentRevision()
                try scene.select(.reports)
                try scene.select(.work)
            }
            defer { service.beforeRawPhotoImmutablePublicationForTesting = nil }
            do {
                _ = try await service.resumePhotoCommit(parentDraftID: photo.parentID,
                    childDraftID: photo.childID, authorizing: operation)
                XCTFail("The original scene operation must not publish prepared immutable bytes")
            } catch { }
            XCTAssertEqual(boundaries, 1)
            XCTAssertThrowsError(try service.preparePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, expectedCheckpointSHA256: committing.checkpointSHA256,
                authorizing: operation))
            XCTAssertFalse(FileManager.default.fileExists(atPath: content.path))
            XCTAssertEqual(try Data(contentsOf: manifest), originalManifest)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), try XCTUnwrap(boundaryHistory))
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), try XCTUnwrap(boundaryRevision))
            XCTAssertNil(try store.workspaceWriter.durableReceipt(mutationID: attempt.targetMutationID))

            let nextOperation = try access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target)
            service.beforeRawPhotoImmutablePublicationForTesting = {
                boundaries += 1
                boundaryHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
                boundaryRevision = try store.workspaceWriter.currentRevision()
                presentation.receive(.sceneInactive)
            }
            do {
                _ = try await service.resumePhotoCommit(parentDraftID: photo.parentID,
                    childDraftID: photo.childID, authorizing: nextOperation)
                XCTFail("Retired app publication must not publish prepared immutable bytes")
            } catch { }
            XCTAssertEqual(boundaries, 2)
            XCTAssertNil(presentation.roundAccess)
            XCTAssertFalse(FileManager.default.fileExists(atPath: content.path))
            XCTAssertEqual(try Data(contentsOf: manifest), originalManifest)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), try XCTUnwrap(boundaryHistory))
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), try XCTUnwrap(boundaryRevision))
            XCTAssertNil(try store.workspaceWriter.durableReceipt(mutationID: attempt.targetMutationID))
            let childID = photo.childID
            let retained = try XCTUnwrap(store.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
                predicate: #Predicate { $0.draftID == childID })).first).value()
            XCTAssertEqual(retained, committing)
            service.beforeRawPhotoImmutablePublicationForTesting = nil

            let republished = self.expectation(description: "Fresh live photo operation after retirement")
            let republication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
                .sink { _ in republished.fulfill() }
            defer { republication.cancel() }
            presentation.receive(.sceneActive)
            await self.fulfillment(of: [republished], timeout: 30)
            let freshAccess = try XCTUnwrap(presentation.roundAccess)
            let freshScene = AppShellSceneStateV1(workspaceID: store.workspaceID,
                access: try XCTUnwrap(presentation.sceneNavigationAccess), registry: try RouteRegistryV1())
            try freshScene.restore()
            let freshService = try freshAccess.makeCheckRunnerItemService(source: source)
            let freshOperation = try freshAccess.captureCheckRunnerItemOperation(service: freshService,
                scene: freshScene, target: target)
            try freshService.prepareLivePhotoStaging(authorizing: freshOperation)
            XCTAssertThrowsError(try nextOperation.withAuthorization { })
            let beforeRecovery = try store.workspaceWriter.sourceMutationHistorySnapshot()
            XCTAssertEqual(try freshService.preparePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, expectedCheckpointSHA256: pairCheckpoint.checkpointSHA256,
                authorizing: freshOperation), committing)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), beforeRecovery)
            freshService.beforePhotoTargetAcknowledgementForTesting = { throw ItemHostInjectedFailure.lostAcknowledgement }
            defer { freshService.beforePhotoTargetAcknowledgementForTesting = nil }
            do {
                _ = try await freshService.resumePhotoCommit(parentDraftID: photo.parentID,
                    childDraftID: photo.childID, authorizing: freshOperation)
                XCTFail("The real target acknowledgement hook must be reached")
            } catch { XCTAssertEqual(error as? ItemHostInjectedFailure, .lostAcknowledgement) }
            let originalReceipt = try XCTUnwrap(store.workspaceWriter.durableReceipt(mutationID: attempt.targetMutationID))
            XCTAssertEqual(try Data(contentsOf: content), bytes)
            freshService.beforePhotoTargetAcknowledgementForTesting = nil
            let terminal = try await freshService.resumePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, authorizing: freshOperation)
            XCTAssertEqual(terminal.state, .committed)
            XCTAssertEqual(try store.workspaceWriter.durableReceipt(mutationID: attempt.targetMutationID), originalReceipt)
            let observed = try XCTUnwrap(freshService.readCurrentPhotoTarget(parentDraftID: photo.parentID,
                childDraftID: photo.childID))
            XCTAssertEqual(observed.parent.slot.childDraftID, photo.childID)
            XCTAssertEqual(try Data(contentsOf: content), bytes)
            let completedHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
            let completedRevision = try store.workspaceWriter.currentRevision()
            let replay = try await freshService.resumePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, authorizing: freshOperation)
            XCTAssertEqual(replay, terminal)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), completedHistory)
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), completedRevision)
            try await self.assertLivePendingPhotoDiscardUsesOriginalOperation(presentation: presentation,
                access: freshAccess, store: store, scene: freshScene, target: target, source: source,
                service: freshService, operation: freshOperation, parentID: photo.parentID,
                sourceByteCount: Int64(bytes.count))
        }
    }

    private func assertLivePendingPhotoDiscardUsesOriginalOperation(
        presentation: AppAccessPresentationV1, access: AppAccessPresentationV1.RoundAccess,
        store: StoreSessionCoordinator, scene: AppShellSceneStateV1, target: NavigationTargetV1,
        source: CheckRunnerRoundItemSourceV1, service: ProductionCheckRunnerItemDraftServiceV1,
        operation: AppAccessPresentationV1.CheckRunnerItemOperationAccess, parentID: UUID,
        sourceByteCount: Int64) async throws {
        let parent = try service.read(draftID: parentID)
        let wide = try XCTUnwrap(CheckRunnerItemDraftCodecV1.validateCheckpoint(parent).field.wideContext)
        let proposal = try service.makeRawPhotoProposal(parentDraftID: parentID,
            expectedCheckpointSHA256: parent.checkpointSHA256, captureStep: .close,
            expectedSourceByteCount: sourceByteCount, origin: .humanCapture, authorizing: operation)
        let awaiting = try operation.withAuthorization {
            try service.prepareRawPhoto(parentDraftID: parentID,
                expectedCheckpointSHA256: parent.checkpointSHA256, proposal: proposal)
        }
        let beforeRequest = try store.workspaceWriter.sourceMutationHistorySnapshot()
        XCTAssertThrowsError(try service.preparePhotoDiscard(parentDraftID: parentID,
            childDraftID: proposal.childDraftID, expectedCheckpointSHA256: awaiting.checkpointSHA256))
        XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), beforeRequest)
        let saved = try service.preparePhotoDiscard(parentDraftID: parentID,
            childDraftID: proposal.childDraftID, expectedCheckpointSHA256: awaiting.checkpointSHA256,
            authorizing: operation)
        let pendingHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
        XCTAssertEqual(try CheckRunnerItemDraftCodecV1.validateCheckpoint(service.read(draftID: parentID))
            .field.wideContext, wide)

        // Returning to the same route cannot revive the previous scene permit.
        try scene.select(.reports)
        try scene.open(target)
        XCTAssertThrowsError(try service.preparePhotoDiscard(parentDraftID: parentID,
            childDraftID: proposal.childDraftID, expectedCheckpointSHA256: saved.pending.checkpointSHA256,
            authorizing: operation))
        XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), pendingHistory)
        let nextOperation = try access.captureCheckRunnerItemOperation(service: service, scene: scene, target: target)
        XCTAssertEqual(try service.preparePhotoDiscard(parentDraftID: parentID,
            childDraftID: proposal.childDraftID, expectedCheckpointSHA256: awaiting.checkpointSHA256,
            authorizing: nextOperation), saved)

        presentation.receive(.sceneInactive)
        XCTAssertThrowsError(try service.preparePhotoDiscard(parentDraftID: parentID,
            childDraftID: proposal.childDraftID, expectedCheckpointSHA256: saved.pending.checkpointSHA256,
            authorizing: nextOperation))
        XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), pendingHistory)
        let ready = expectation(description: "Fresh publication resumes original pending photo discard")
        let subscription = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in ready.fulfill() }
        defer { subscription.cancel() }
        presentation.receive(.sceneActive)
        await fulfillment(of: [ready], timeout: 30)
        let freshAccess = try XCTUnwrap(presentation.roundAccess)
        let freshScene = AppShellSceneStateV1(workspaceID: store.workspaceID,
            access: try XCTUnwrap(presentation.sceneNavigationAccess), registry: try RouteRegistryV1())
        try freshScene.restore()
        try freshScene.open(target)
        let freshService = try freshAccess.makeCheckRunnerItemService(source: source)
        let freshOperation = try freshAccess.captureCheckRunnerItemOperation(service: freshService,
            scene: freshScene, target: target)
        XCTAssertThrowsError(try service.preparePhotoDiscard(parentDraftID: parentID,
            childDraftID: proposal.childDraftID, expectedCheckpointSHA256: saved.pending.checkpointSHA256,
            authorizing: freshOperation))
        XCTAssertEqual(try freshService.preparePhotoDiscard(parentDraftID: parentID,
            childDraftID: proposal.childDraftID, expectedCheckpointSHA256: awaiting.checkpointSHA256,
            authorizing: freshOperation), saved)
        XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), pendingHistory)
        XCTAssertEqual(try CheckRunnerItemDraftCodecV1.validateCheckpoint(freshService.read(draftID: parentID))
            .field.wideContext, wide)
    }

    func testLiveItemFactoryAndEditorKeepOriginalPublicationWithoutCreatingStaging() async throws {
        try await withAsyncFrozenBeginFixture("live-item-publication", entry: .check,
            storedTimeZoneID: "America/New_York", appDirectoryLayout: true) { h in
            let source = try h.captureSource()
            let seed = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator,
                progress: h.progress, coordinator: h.runner, publishedRelease: h.publishedRelease,
                clock: h.clock, ids: h.ids)
            let parent = try seed.create(source: source, preflight: .init())
            let stagingRoot = h.root.appendingPathComponent(OwnedStorageRootKindV1.data.rawValue)
                .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName)
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingRoot.path))
            try h.closeCoordinator()

            let suite = "V23.LiveItem.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let router = StartupRouter(applicationSupportURL: h.root)
            let session = try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: h.root, startupRouter: router, defaults: defaults,
                authenticationClient: FrozenBeginAuthentication(),
                notificationSystem: ItemHostNotificationSystem())
            let presentation = AppAccessPresentationV1(startupRouter: router, sessionFactory: { session })
            let ready = self.expectation(description: "Real production item publication")
            let subscription = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
                .sink { _ in ready.fulfill() }
            defer { subscription.cancel() }
            await presentation.bootstrapIfNeeded()
            await self.fulfillment(of: [ready], timeout: 30)
            guard case let .ready(store, _, _) = router.route else {
                return XCTFail("Expected the actual reopened production writer")
            }
            defer { XCTAssertNoThrow(try store.invalidateAndReleaseWriter()) }
            let access = try XCTUnwrap(presentation.roundAccess)
            let sceneAccess = try XCTUnwrap(presentation.sceneNavigationAccess)
            let scene = AppShellSceneStateV1(workspaceID: store.workspaceID,
                access: sceneAccess, registry: try RouteRegistryV1())
            try scene.restore()
            let target = try NavigationTargetV1(workspaceID: store.workspaceID, destination: .work,
                stableSessionID: source.roundAtEntry.sessionID, requestedMode: .resume,
                fallback: NavigationFallbackV1(root: .work, destination: .work))
            try scene.open(target)
            XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [target])
            let beforeOpen = try store.workspaceWriter.currentRevision()
            let beforeHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
            let host = try ProductionCheckRunnerItemCapturePresentationV1(
                source: source, target: target, scene: scene, access: access)
            let service = host.service
            XCTAssertEqual(host.checkpoint, parent)
            let preflight = try XCTUnwrap(host.preflight)
            XCTAssertEqual(preflight.snapshot.assetID, source.assetID)
            XCTAssertEqual(preflight.snapshot.siteID, h.siteID)
            XCTAssertEqual(preflight.snapshot.timeZoneID, "America/New_York")
            XCTAssertEqual(preflight.pack.packID, h.signPack.packID)
            let initial = try service.readEditableFields(draftID: parent.draftID)
            XCTAssertEqual(initial.checkpoint, parent)
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), beforeOpen)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), beforeHistory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingRoot.path))

            let wrongRound = try NavigationTargetV1(workspaceID: store.workspaceID, destination: .work,
                stableSessionID: UUID(), requestedMode: .resume,
                fallback: NavigationFallbackV1(root: .work, destination: .work))
            XCTAssertThrowsError(try service.validateLiveTarget(wrongRound))
            let sameProgress = try access.repetitiveCaptureOwnerForTesting()
            let standaloneRunner = try CheckRunnerCoordinator(modelContext: store.modelContext,
                packageLifecycleDependencies: store.packageLifecycleDependencies(), packageLifecycleProfile: h.profile)
            let standalone = try ProductionCheckRunnerItemDraftServiceV1(session: store,
                progress: sameProgress, coordinator: standaloneRunner, publishedRelease: h.publishedRelease,
                clock: h.clock, ids: h.ids)
            XCTAssertThrowsError(try access.captureCheckRunnerItemOperation(service: standalone,
                scene: scene, target: target))

            // A service from the retired fixture's progress/writer cannot be
            // adopted by the new production publication.
            XCTAssertThrowsError(try access.captureCheckRunnerItemOperation(service: seed,
                scene: scene, target: target))
            let originalOperation = try access.captureCheckRunnerItemOperation(service: service,
                scene: scene, target: target)
            var finalizerEffects = 0
            XCTAssertThrowsError(try originalOperation.withFinalizationAuthorization(generationID: UUID(),
                generationRootURL: store.generationRootURL) { finalizerEffects += 1 })
            XCTAssertThrowsError(try originalOperation.withFinalizationAuthorization(generationID: store.generationID,
                generationRootURL: h.root.appendingPathComponent("foreign-generation")) { finalizerEffects += 1 })
            XCTAssertEqual(finalizerEffects, 0)
            try originalOperation.withFinalizationAuthorization(generationID: store.generationID,
                generationRootURL: store.generationRootURL) { finalizerEffects += 1 }
            XCTAssertEqual(finalizerEffects, 1)
            let editor = try XCTUnwrap(host.editor)
            var outcome = initial.values.outcome
            outcome.recheckNote = "  durable live editor value\n"
            let desired = CheckRunnerEditableItemValuesV1(preflight: initial.values.preflight,
                outcome: outcome, semanticAnchor: initial.values.semanticAnchor)
            try host.replaceEditableValues(desired)
            var navigationCount = 0
            try await host.flushAndPerform(reason: .back) { navigationCount += 1 }
            XCTAssertEqual(navigationCount, 1)
            let saved = try await editor.forceFlushAndReadBack(reason: .back)
            try editor.validateForPublication(saved)
            XCTAssertEqual(saved.parent.values, desired)
            XCTAssertFalse(editor.hasUnacknowledgedEdits)
            let savedRevision = try store.workspaceWriter.currentRevision()
            let savedHistory = try store.workspaceWriter.sourceMutationHistorySnapshot()
            let nonexistentChild = UUID()
            do {
                _ = try await service.publishRawPhoto(parentDraftID: parent.draftID,
                    childDraftID: nonexistentChild, sourceURL: h.root.appendingPathComponent("absent-source"))
                XCTFail("Live raw publication must not fall back to standalone authority")
            } catch { XCTAssertEqual(error as? ScanToWorkFailureV1, .authorityMismatch) }
            do {
                _ = try await service.preparePhotoPair(parentDraftID: parent.draftID, childDraftID: nonexistentChild)
                XCTFail("Live pair preparation requires its operation")
            } catch { XCTAssertEqual(error as? ScanToWorkFailureV1, .authorityMismatch) }
            do {
                _ = try await service.resumePhotoCommit(parentDraftID: parent.draftID, childDraftID: nonexistentChild)
                XCTFail("Live commit recovery requires its original operation")
            } catch { XCTAssertEqual(error as? ScanToWorkFailureV1, .authorityMismatch) }
            var parentIntentChecks = 0
            do {
                _ = try await service.resumeFinalization(draftID: parent.draftID) { parentIntentChecks += 1 }
                XCTFail("Live finalization cannot substitute a validator for its operation")
            } catch { XCTAssertEqual(error as? ScanToWorkFailureV1, .authorityMismatch) }
            XCTAssertEqual(parentIntentChecks, 0)
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), savedRevision)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), savedHistory)

            try scene.select(.reports)
            try scene.select(.work)
            var staleEffects = 0
            XCTAssertThrowsError(try originalOperation.withAuthorization { staleEffects += 1 })
            XCTAssertThrowsError(try originalOperation.withFinalizationAuthorization(generationID: store.generationID,
                generationRootURL: store.generationRootURL) { finalizerEffects += 1 })
            XCTAssertEqual(finalizerEffects, 1)
            XCTAssertEqual(staleEffects, 0)
            XCTAssertThrowsError(try editor.validateForPublication(saved))
            do {
                _ = try await service.resumeFinalization(draftID: parent.draftID,
                    authorizing: originalOperation) { parentIntentChecks += 1 }
                XCTFail("A stale scene operation cannot start parent finalization")
            } catch { }
            XCTAssertEqual(parentIntentChecks, 0)
            let fresh = try await editor.forceFlushAndReadBack(reason: .share)
            try editor.validateForPublication(fresh)
            XCTAssertEqual(fresh.parent.receipt, saved.parent.receipt)
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), savedRevision)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), savedHistory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingRoot.path))

            outcome.recheckNote = "must remain unsaved after publication retirement"
            try host.replaceEditableValues(.init(preflight: desired.preflight,
                outcome: outcome, semanticAnchor: desired.semanticAnchor))
            let retiringOperation = try access.captureCheckRunnerItemOperation(service: service,
                scene: scene, target: target)
            try retiringOperation.withAuthorization {
                presentation.receive(.sceneInactive)
                XCTAssertThrowsError(try retiringOperation.withAuthorization { staleEffects += 1 })
            }
            XCTAssertEqual(staleEffects, 0)
            XCTAssertNil(presentation.roundAccess)
            XCTAssertThrowsError(try access.makeCheckRunnerItemService(source: source))
            do {
                try await host.flushAndPerform(reason: .sceneInactive) { navigationCount += 1 }
                XCTFail("Retired publication must reject the real field effect")
            } catch {
                XCTAssertTrue(editor.hasUnacknowledgedEdits)
            }
            XCTAssertEqual(navigationCount, 1)
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), savedRevision)
            XCTAssertEqual(try store.workspaceWriter.sourceMutationHistorySnapshot(), savedHistory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingRoot.path))
            await host.retire()
            XCTAssertThrowsError(try host.replaceEditableValues(desired))

            let republished = self.expectation(description: "Fresh publication after item retirement")
            let republication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
                .sink { _ in republished.fulfill() }
            defer { republication.cancel() }
            presentation.receive(.sceneActive)
            await self.fulfillment(of: [republished], timeout: 30)
            let freshAccess = try XCTUnwrap(presentation.roundAccess)
            XCTAssertThrowsError(try access.makeCheckRunnerItemService(source: source))
            XCTAssertThrowsError(try retiringOperation.withAuthorization { staleEffects += 1 })
            XCTAssertEqual(staleEffects, 0)
            let reopened = try freshAccess.makeCheckRunnerItemService(source: source)
            XCTAssertEqual(try reopened.readEditableFields(draftID: parent.draftID).receipt, saved.parent.receipt)
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingRoot.path))
            XCTAssertThrowsError(try service.prepareLivePhotoStaging(authorizing: retiringOperation))
            XCTAssertThrowsError(try reopened.prepareLivePhotoStaging(authorizing: originalOperation))
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingRoot.path))
            let freshScene = AppShellSceneStateV1(workspaceID: store.workspaceID,
                access: try XCTUnwrap(presentation.sceneNavigationAccess), registry: try RouteRegistryV1())
            try freshScene.restore()
            let mediaOperation = try freshAccess.captureCheckRunnerItemOperation(service: reopened,
                scene: freshScene, target: target)
            XCTAssertNil(reopened.livePhotoStagingIdentityForTesting)
            try reopened.prepareLivePhotoStaging(authorizing: mediaOperation)
            let adapterIdentity = try XCTUnwrap(reopened.livePhotoStagingIdentityForTesting)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stagingRoot.path))
            let manifest = stagingRoot.appendingPathComponent(DraftAttachmentStagingAdapterV1.manifestName)
            let originalManifest = try Data(contentsOf: manifest)
            try reopened.prepareLivePhotoStaging(authorizing: mediaOperation)
            XCTAssertEqual(reopened.livePhotoStagingIdentityForTesting, adapterIdentity)
            XCTAssertEqual(try Data(contentsOf: manifest), originalManifest)

            let resumedHost = try ProductionCheckRunnerItemCapturePresentationV1(
                source: source, target: target, scene: freshScene, access: freshAccess)
            let resumedEditor = try XCTUnwrap(resumedHost.editor)
            XCTAssertEqual(resumedEditor.values, desired)
            let acknowledged = resumedEditor.acknowledgement
            try resumedHost.replaceEditableValues(.init(preflight: .init(timeZoneID: "America/New_York",
                isTimeZoneConfirmed: true, confirmedTimeZoneID: "America/New_York",
                afterDarkAccepted: true, safePositionAccepted: true),
                outcome: desired.outcome, semanticAnchor: desired.semanticAnchor))
            do {
                try await resumedHost.reload()
                XCTFail("Reopen must not discard unacknowledged field input")
            } catch {
                XCTAssertEqual(error as? CheckRunnerItemEditingSessionFailureV1, .changedCheckpoint)
            }
            XCTAssertEqual(resumedEditor.acknowledgement.checkpoint, acknowledged.checkpoint)
            let observedAt = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1_000).rounded(.down) / 1_000)
            try await resumedHost.begin(observedAtUTC: observedAt)
            let bound = try XCTUnwrap(resumedHost.checkpoint)
            guard case .bound = try CheckRunnerItemDraftCodecV1.validateCheckpoint(bound).field.begin else {
                return XCTFail("The host must publish the authenticated durable Begin result")
            }
            let beganRevision = try store.workspaceWriter.currentRevision()
            try await resumedHost.begin(observedAtUTC: observedAt.addingTimeInterval(1))
            XCTAssertEqual(resumedHost.checkpoint, bound)
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), beganRevision)
            await resumedHost.retire()
        }
    }
}

private enum ItemHostInjectedFailure: Error, Equatable { case lostAcknowledgement, stopAtEraseAdmission }

@MainActor
private final class ItemHostNotificationSystem: NotificationSystemPortV1 {
    private var requests: [NotificationSystemRequestV1] = []
    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }
    func observations() async throws -> [NotificationSystemObservationV1] {
        requests.map { .init(requestID: $0.notification.requestID, request: $0, delivered: false) }
    }
    func add(_ request: NotificationSystemRequestV1) async throws { requests.append(request) }
    func remove(_ requestIDs: [String]) async throws {
        requests.removeAll { requestIDs.contains($0.notification.requestID) }
    }
}

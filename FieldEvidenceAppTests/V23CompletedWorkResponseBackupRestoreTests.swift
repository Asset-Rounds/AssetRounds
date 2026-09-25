import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
private struct SIG1RecordedSourceV1 {
    let fixture: V23ProductionMyDayPresentationHarness
    let proof: CompletedWorkSubjectProofV1
    let receipt: SignoffEnrollmentReceiptV1
    let signoff: SignoffSnapshotV1
    let signoffBytes: Data
    let actorBytes: Data
    let history: CompletedWorkResponseHistoryV1
    let package: URL
}

final class V23CompletedWorkResponseBackupRestoreTests: V23ProductionFourRootShellTestSupport {
    /// Real finalize, real response through the production service, then the
    /// incumbent backup export of the whole store.
    @MainActor
    private func makeRecordedSource(_ name: String) async throws -> SIG1RecordedSourceV1 {
        let fixture = try await makeFixture(name)
        let report = try await makeReadyReport(in: fixture, label: name)
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let service = workflow.completedWorkResponses
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        let proof = try XCTUnwrap(try service.subjectDetail(key).proof)
        let prepared = try service.prepare(
            submission: completedWorkSubmission(for: proof),
            expectedProof: proof
        )
        let outcome = service.record(prepared)
        guard case let .saved(receipt) = outcome else {
            XCTFail("Expected a saved response, got \(outcome)")
            throw CompletedWorkResponseFailureV1.unavailable
        }
        let context = fixture.coordinator.modelContext
        let signoffRow = try XCTUnwrap(context.fetch(FetchDescriptor<SignoffSnapshotRow>()).first)
        let signoff = try signoffRow.value()
        let actorRow = try XCTUnwrap(context.fetch(FetchDescriptor<ActorSnapshotRow>()).first {
            $0.snapshotID == prepared.actorSnapshotID
        })
        let history = try service.history(focusedSignoffID: receipt.snapshotID)

        let exportRoot = fixture.root.appendingPathComponent("sig1-export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: context,
            generationRootURL: fixture.coordinator.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_800_600_000) }
        )
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: exportRoot)
        return SIG1RecordedSourceV1(
            fixture: fixture, proof: proof, receipt: receipt, signoff: signoff,
            signoffBytes: signoffRow.canonicalData, actorBytes: actorRow.canonicalData,
            history: history, package: package
        )
    }

    @MainActor
    private func restore(
        _ source: SIG1RecordedSourceV1,
        name: String,
        mode: BackupRestoreMode
    ) async throws -> (support: URL, session: StoreGenerationSession) {
        let support = source.fixture.root
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let current = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()
        let validated = try BackupImportService(
            generationRootURL: current.generationRootURL,
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: source.package)
        let restoreService = try BackupRestoreService(
            applicationSupportURL: support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        )
        let restored = try await restoreService.restore(
            validatedPackage: validated,
            currentModelContext: current.modelContext,
            currentGenerationID: current.generationID,
            currentGenerationRootURL: current.generationRootURL,
            mode: mode
        )
        return (support, restored)
    }

    @MainActor
    private func makeResolver(for session: StoreGenerationSession) -> CompletedWorkSubjectResolverV1 {
        CompletedWorkSubjectResolverV1(
            modelContext: session.modelContext,
            workspaceID: session.workspaceID,
            generationID: session.generationID,
            generationRootURL: session.generationRootURL,
            signPack: .illuminatedSignV1
        )
    }

    @MainActor
    func testReplaceRestorePreservesResponseBytesAndResolvesSameSubject() async throws {
        let source = try await makeRecordedSource("sig1-restore-replace")
        defer { source.fixture.cleanUp() }
        let restored = try await restore(source, name: "replace-target", mode: .replaceExisting).session
        XCTAssertEqual(restored.workspaceID, source.fixture.coordinator.workspaceID)

        let signoffRows = try restored.modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>())
        XCTAssertEqual(signoffRows.count, 1)
        let restoredRow = try XCTUnwrap(signoffRows.first)
        XCTAssertEqual(restoredRow.canonicalData, source.signoffBytes)
        XCTAssertEqual(try restoredRow.value(), source.signoff)
        let actorID = try XCTUnwrap(source.signoff.roleAssertion?.actor.snapshotID)
        let actorRow = try XCTUnwrap(restored.modelContext.fetch(FetchDescriptor<ActorSnapshotRow>()).first {
            $0.snapshotID == actorID
        })
        XCTAssertEqual(actorRow.canonicalData, source.actorBytes)

        let resolver = makeResolver(for: restored)
        let key = try CompletedWorkSubjectKeyV1(signoff: try restoredRow.value())
        XCTAssertEqual(key, try source.proof.key)
        let proof = try XCTUnwrap(resolver.resolve(key).proof)
        XCTAssertEqual(proof.reportID, source.proof.reportID)
        XCTAssertEqual(proof.packetID, source.proof.packetID)
        XCTAssertEqual(proof.sourceRecordID, source.proof.sourceRecordID)
        XCTAssertEqual(proof.chainPosition, source.proof.chainPosition)
        XCTAssertEqual(proof.snapshotSHA256, source.proof.snapshotSHA256)
        XCTAssertEqual(proof.display, source.proof.display)
        XCTAssertTrue(proof.isTip)
        let history = try CompletedWorkResponseHistoryReaderV1(resolver: resolver)
            .history(focusedSignoffID: source.receipt.snapshotID)
        XCTAssertEqual(history, source.history)

        let journal = try MutationJournalStoreV1(
            modelContext: restored.modelContext,
            identity: restored.workspaceIdentity,
            generationID: restored.generationID,
            allowStateBootstrap: false
        )
        try journal.validateAll()
    }

    @MainActor
    func testForkRebindsResponseWorkspaceAndResolvesSameReportIdentityWithoutByteClaim() async throws {
        let source = try await makeRecordedSource("sig1-restore-fork")
        defer { source.fixture.cleanUp() }
        let restored = try await restore(source, name: "fork-target", mode: .fork).session
        XCTAssertNotEqual(restored.workspaceID, source.fixture.coordinator.workspaceID)

        let signoffRows = try restored.modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>())
        XCTAssertEqual(signoffRows.count, 1)
        let restoredRow = try XCTUnwrap(signoffRows.first)
        let rebound = try restoredRow.value()
        XCTAssertEqual(rebound.snapshotID, source.signoff.snapshotID)
        XCTAssertEqual(rebound.workspaceID, restored.workspaceID)
        XCTAssertEqual(rebound.purpose, source.signoff.purpose)
        XCTAssertEqual(rebound.subjectID, source.signoff.subjectID)
        XCTAssertEqual(rebound.subjectRevision, source.signoff.subjectRevision)
        XCTAssertEqual(rebound.method, source.signoff.method)
        XCTAssertEqual(rebound.recordedAt, source.signoff.recordedAt)
        XCTAssertEqual(rebound.roleAssertion?.actor.workspaceID, restored.workspaceID)
        XCTAssertEqual(rebound.roleAssertion?.claimedRole, source.signoff.roleAssertion?.claimedRole)
        XCTAssertEqual(
            rebound.roleAssertion?.actor.displayNameAtTime,
            source.signoff.roleAssertion?.actor.displayNameAtTime
        )
        try C43SignoffEnrollmentBoundaryV1.validate(rebound)
        // The binding is identity plus position; bytes are not claimed equal.
        XCTAssertNotEqual(restoredRow.canonicalData, source.signoffBytes)
        XCTAssertNotEqual(rebound.snapshotSHA256, source.signoff.snapshotSHA256)

        let resolver = makeResolver(for: restored)
        let key = try CompletedWorkSubjectKeyV1(signoff: rebound)
        XCTAssertEqual(key.workspaceID, restored.workspaceID)
        XCTAssertEqual(key.subjectID, source.proof.reportID)
        XCTAssertEqual(key.subjectRevision, source.proof.chainPosition)
        let proof = try XCTUnwrap(resolver.resolve(key).proof)
        XCTAssertEqual(proof.reportID, source.proof.reportID)
        XCTAssertEqual(proof.chainPosition, source.proof.chainPosition)
        XCTAssertEqual(proof.display, source.proof.display)
        XCTAssertTrue(proof.isTip)
        let history = try CompletedWorkResponseHistoryReaderV1(resolver: resolver)
            .history(focusedSignoffID: rebound.snapshotID)
        XCTAssertEqual(history.subject, source.history.subject)
        XCTAssertEqual(history.current.map(\.facts), source.history.current.map(\.facts))
        XCTAssertEqual(history.current.map(\.version), source.history.current.map(\.version))
        XCTAssertTrue(history.earlier.isEmpty)
    }

    @MainActor
    func testEraseRemovesResponsesAndActorSnapshots() async throws {
        let source = try await makeRecordedSource("sig1-restore-erase")
        defer { source.fixture.cleanUp() }
        let restored = try await restore(source, name: "erase-target", mode: .replaceExisting)
        XCTAssertEqual(try restored.session.modelContext.fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 1)
        XCTAssertGreaterThanOrEqual(
            try restored.session.modelContext.fetchCount(FetchDescriptor<ActorSnapshotRow>()), 1
        )

        let root = source.fixture.root.appendingPathComponent("erase-target", isDirectory: true)
        let caches = root.appendingPathComponent("caches", isDirectory: true)
        let temporary = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let coordinator = StoreSessionCoordinator(session: restored.session)
        let diagnostics = DiagnosticsStore(applicationSupportURL: restored.support)
        await diagnostics.prepare()
        let suiteName = "SIG1-erase-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let erase = EraseAllService(
            applicationSupportURL: restored.support,
            cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary,
            userDefaults: defaults,
            bundleIdentifier: suiteName
        )
        let erased = try await erase.erase(
            confirmation: EraseAllService.requiredConfirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnostics
        ) { replacement in
            coordinator.activate(session: replacement)
        }
        let context = erased.session.modelContext
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActorSnapshotRow>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Report>()), 0)
        let resolver = makeResolver(for: erased.session)
        XCTAssertTrue(try resolver.currentTips().isEmpty)
        XCTAssertTrue(try CompletedWorkResponseHistoryReaderV1(resolver: resolver).boundResponseCounts().isEmpty)
        let erasedKey = try CompletedWorkSubjectKeyV1(
            workspaceID: erased.session.workspaceID,
            subjectID: source.proof.reportID,
            subjectRevision: source.proof.chainPosition
        )
        XCTAssertEqual(resolver.resolve(erasedKey), .unavailable(.missing))
    }
}

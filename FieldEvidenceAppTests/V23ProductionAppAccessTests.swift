import Combine
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest

@testable import FieldEvidenceApp

final class V23ProductionAppAccessTests: XCTestCase {
    @MainActor private static var retainedDeferredEraseOwners:
        [(URL, StartupRouter, ProductionAppAccessSessionV1, AppAccessPresentationV1)] = []
    @MainActor private static var retainedRestoreTransitionOwners:
        [(URL, StartupRouter, ProductionAppAccessSessionV1, AppAccessPresentationV1)] = []
    @MainActor private static var retainedMaintenanceJournalOwners:
        [(URL, ModelContainer, ModelContext, WholeSignDeletionService,
          RestoreMaintenanceOperationsDescriptorOwnerV1)] = []
    @MainActor private static var retainedMaintenanceJournalDescriptorAttempts:
        [RestoreMaintenanceOperationsDescriptorOwnerV1] = []

    @MainActor
    private static func observedRestoreService(at url: URL) throws -> BackupRestoreService {
        let service = try BackupRestoreService(applicationSupportURL: url)
        service.restorePhaseDiagnosticForTesting = { phase in
            // Only closed, source-defined phase names reach the diagnostic.
            // No package, path, owner ID, row, or error payload is emitted.
            let label: String
            switch phase {
            case "access-and-admission": label = "access"
            case "generation-authority": label = "authority"
            case "lifecycle-scope": label = "lifecycle"
            case "current-generation-admission": label = "current"
            case "current-and-source-identity": label = "identity"
            case "current-records": label = "records"
            case "package-revalidation": label = "package"
            case "review-source-validation": label = "review-source"
            case "portable-exchange-snapshot": label = "exchange"
            case "storage-preflight": label = "storage"
            case "exclusive-import-staging": label = "staging"
            case "photo-canonical-plan": label = "photo"
            case "deletion-winning-plan": label = "deletion"
            case "destination-identity": label = "destination"
            case "reliability-and-metadata": label = "metadata"
            case "destination-review-plan": label = "review-plan"
            case "records-for-materialization": label = "materialization-input"
            case "parts-stock-lifecycle": label = "parts-stock"
            case "accessible-documents": label = "documents"
            case "photo-and-clone-plan": label = "photo-clone"
            case "materialize": label = "materialize"
            case "validate-staging": label = "validate-staging"
            case "staging-manifest": label = "manifest"
            case "prepare-intent": label = "prepare-intent"
            case "intent.create": label = "intent-created"
            case "intent.install-generation": label = "install"
            case "intent.pointer-switch.begin": label = "switch-before"
            case "intent.pointer-switch.done": label = "switch-after"
            case "intent.current-reopen.begin": label = "reopen-before"
            case "intent.current-reopen.done": label = "reopen-after"
            case "intent.current-validation.done": label = "validated"
            case "post-validation.exchange.begin": label = "exchange-before"
            case "post-validation.exchange.end": label = "exchange-after"
            case "post-validation.intent.end": label = "intent-after"
            case "post-validation.retired-protection.end": label = "retired-protection-after"
            case "post-validation.retire.end": label = "retire-after"
            case "post-validation.search.end": label = "search-after"
            case "post-validation.access.end": label = "access-after"
            case "post-validation.discovery.end": label = "discovery-after"
            case "post-validation.final-access.end": label = "final-access-after"
            case "restore-error.access": label = "restore-error-access"
            case "restore-error.recovery.begin": label = "recovery-before"
            case "recovery.return-session": label = "recovery-return"
            case "recovery.rethrow-original": label = "recovery-rethrow"
            case "materialize.journal.replace.guard.line-6139": label = "history-target-identity"
            case "materialize.journal.replace.guard.line-6149": label = "history-target-stock"
            case "materialize.journal.error.wrongGeneration": label = "history-wrong-generation"
            default: return
            }
            FileHandle.standardError.write(Data(
                "V23_RESTORE_APPACCESS_STAGE_V1 stage=\(label)\n".utf8))
        }
        return service
    }

    func testScenePreferencesPersistBoundedSnapshotsAndDiscardCorruptionAcrossReopen() throws {
        let suiteName = "V23.ProductionAppAccess.scene-state.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesAdapterV1(defaults: defaults)
        let adapter = SceneNavigationStateAdapterV1(port: preferences)
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: WorkspaceID(rawValue: UUID()),
            selectedRoot: .work, paths: AppRootV1.frozenOrder.map { .init(root: $0, targets: []) },
            snapshotID: UUID())
        defaults.set("retained", forKey: "unrelated-device-preference")
        try adapter.save(snapshot)
        let reopened = PreferencesAdapterV1(defaults: defaults)
        let reopenedAdapter = SceneNavigationStateAdapterV1(port: reopened)
        XCTAssertEqual(try reopenedAdapter.loadAndReconcile(), .restored(snapshot))
        let stored = try reopened.loadSceneNavigationData()
        XCTAssertThrowsError(try preferences.saveSceneNavigationData(
            Data(repeating: 0x61, count: SceneNavigationSnapshotV1.maximumEncodedByteCount + 1)))
        XCTAssertEqual(try reopened.loadSceneNavigationData(), stored)
        for corrupt in [Data("not-json".utf8), Data(repeating: 0x61,
                           count: SceneNavigationSnapshotV1.maximumEncodedByteCount + 1)] {
            defaults.set(corrupt, forKey: "scene-navigation.v1")
            XCTAssertEqual(try reopenedAdapter.loadAndReconcile(), .discarded(.corruptSnapshot))
            XCTAssertNil(try preferences.loadSceneNavigationData())
        }
        defaults.set("not-data", forKey: "scene-navigation.v1")
        XCTAssertEqual(try reopenedAdapter.loadAndReconcile(), .discarded(.corruptSnapshot))
        XCTAssertNil(try preferences.loadSceneNavigationData())
        try preferences.saveSceneNavigationData(Data(#"{"schemaVersion":99}"#.utf8))
        XCTAssertEqual(try reopenedAdapter.loadAndReconcile(), .discarded(.unsupportedSnapshotVersion))
        XCTAssertNil(try preferences.loadSceneNavigationData())
        XCTAssertEqual(defaults.string(forKey: "unrelated-device-preference"), "retained")
    }

    @MainActor
    func testRestorePreviewRetainsOriginalAccessAcrossLifecycleAndRejectsStaleCallbacks() async throws {
        let suiteName = "V23.ProductionAppAccess.preview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-preview-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: ProductionAccessNotificationSystem())
        let presentation = AppAccessPresentationV1(startupRouter: router, sessionFactory: { session })
        XCTAssertNil(presentation.backupPreviewAccess)
        XCTAssertNil(presentation.sceneNavigationAccess)
        let published = expectation(description: "Initial authorized production presentation")
        let publication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { publication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        let original = try XCTUnwrap(presentation.backupPreviewAccess)
        let originalRender = try XCTUnwrap(presentation.renderAccess)
        let originalScene = try XCTUnwrap(presentation.sceneNavigationAccess)
        guard case .ready(let coordinator, _, _) = router.route else {
            return XCTFail("Expected the actual production coordinator")
        }
        var reads = 0
        let summary = try original.withRead {
            reads += 1
            return try BackupRestoreService.currentSummary(modelContext: coordinator.modelContext,
                generationRootURL: coordinator.generationRootURL)
        }
        XCTAssertEqual(summary.signCount, 0)
        XCTAssertEqual(reads, 1)
        var renderReads = 0
        try originalRender.withRead { renderReads += 1 }
        XCTAssertEqual(renderReads, 1)
        let revision = try originalRender.withRead { try coordinator.workspaceWriter.currentRevision() }
        let sceneSnapshot = try SceneNavigationSnapshotV1(workspaceID: revision.workspaceID,
            selectedRoot: .work, paths: AppRootV1.frozenOrder.map { .init(root: $0, targets: []) },
            snapshotID: UUID())
        XCTAssertEqual(try originalScene.load(), .absent)
        try originalScene.save(sceneSnapshot)
        let sceneRequest = RouteRestorationRequestV1(
            context: .init(currentWorkspaceID: revision.workspaceID, currentRevision: revision.revision),
            startupMaintenanceTarget: nil, incompleteMutationRecoveryTarget: nil,
            explicitIngressTarget: nil, sceneSnapshot: sceneSnapshot, discardedSnapshotReason: nil,
            evidenceKind: .golden, receiptID: UUID())
        let routeCoordinator = RouteCoordinatorV1(registry: try RouteRegistryV1())
        let sceneResult = try originalScene.restore(sceneRequest, using: routeCoordinator)
        XCTAssertEqual(sceneResult.selectedRoot, .work)
        XCTAssertEqual(sceneResult.paths.map(\.root), AppRootV1.frozenOrder)
        XCTAssertFalse(sceneResult.receipt.startsAutomaticWork)
        XCTAssertEqual(try PreferencesAdapterV1(defaults: defaults).loadSceneNavigationData(),
            try RouteCanonicalCodecV1.encode(sceneSnapshot))

        presentation.receive(.sceneInactive)
        // No await: the presentation boundary must deny even before its
        // queued actor transition has revoked the underlying gate token.
        XCTAssertNil(presentation.backupPreviewAccess)
        XCTAssertThrowsError(try original.withRead { reads += 1 }) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertNil(presentation.renderAccess)
        XCTAssertThrowsError(try originalRender.withRead { renderReads += 1 }) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(renderReads, 1)
        XCTAssertNil(presentation.sceneNavigationAccess)
        XCTAssertThrowsError(try originalScene.load())
        XCTAssertThrowsError(try originalScene.save(sceneSnapshot))
        XCTAssertThrowsError(try originalScene.restore(sceneRequest, using: routeCoordinator))
        let republished = expectation(description: "Fresh foreground production presentation")
        let republication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in republished.fulfill() }
        defer { republication.cancel() }
        presentation.receive(.sceneActive)
        await fulfillment(of: [republished], timeout: 30)
        let fresh = try XCTUnwrap(presentation.backupPreviewAccess)
        let freshRender = try XCTUnwrap(presentation.renderAccess)
        let freshScene = try XCTUnwrap(presentation.sceneNavigationAccess)
        XCTAssertThrowsError(try original.withRead { reads += 1 })
        XCTAssertThrowsError(try originalRender.withRead { renderReads += 1 })
        XCTAssertThrowsError(try originalScene.load())
        XCTAssertThrowsError(try originalScene.save(sceneSnapshot))
        XCTAssertThrowsError(try originalScene.restore(sceneRequest, using: routeCoordinator))
        XCTAssertEqual(try freshScene.load(), .restored(sceneSnapshot))
        try freshScene.save(sceneSnapshot)
        XCTAssertEqual(try freshScene.restore(sceneRequest, using: routeCoordinator).selectedRoot, .work)
        guard case .ready(let freshCoordinator, _, _) = router.route else {
            return XCTFail("Fresh startup must publish its current coordinator")
        }
        let freshSummary = try fresh.withRead {
            reads += 1
            return try BackupRestoreService.currentSummary(modelContext: freshCoordinator.modelContext,
                generationRootURL: freshCoordinator.generationRootURL)
        }
        XCTAssertEqual(freshSummary.signCount, 0)
        XCTAssertEqual(reads, 2)
        try freshRender.withRead { renderReads += 1 }
        XCTAssertEqual(renderReads, 2)

        // An authorized retry also replaces the presentation capability even
        // when it does not require a lock/unlock transition of the gate.
        await presentation.retryStartup()
        XCTAssertTrue(presentation.permitsContentPresentation)
        XCTAssertThrowsError(try fresh.withRead { reads += 1 })
        XCTAssertThrowsError(try freshRender.withRead { renderReads += 1 })
        XCTAssertThrowsError(try freshScene.load())
        XCTAssertThrowsError(try freshScene.save(sceneSnapshot))
        XCTAssertThrowsError(try freshScene.restore(sceneRequest, using: routeCoordinator))
        let retried = try XCTUnwrap(presentation.backupPreviewAccess)
        let retriedRender = try XCTUnwrap(presentation.renderAccess)
        let retriedScene = try XCTUnwrap(presentation.sceneNavigationAccess)
        XCTAssertEqual(try retriedScene.load(), .restored(sceneSnapshot))
        try retried.withRead { reads += 1 }
        try retriedRender.withRead { renderReads += 1 }
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(renderReads, 3)

        presentation.receive(.protectedDataUnavailable)
        XCTAssertNil(presentation.backupPreviewAccess)
        XCTAssertThrowsError(try retried.withRead { reads += 1 })
        XCTAssertNil(presentation.renderAccess)
        XCTAssertThrowsError(try retriedRender.withRead { renderReads += 1 })
        XCTAssertNil(presentation.sceneNavigationAccess)
        XCTAssertThrowsError(try retriedScene.load())
        XCTAssertThrowsError(try retriedScene.save(sceneSnapshot))
        XCTAssertThrowsError(try retriedScene.restore(sceneRequest, using: routeCoordinator))
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(renderReads, 3)
    }

    @MainActor
    func testPresentationRestoreRejectsItsOriginalTicketAfterAdmissionRevocation() async throws {
        let suiteName = "V23.ProductionAppAccess.restore-revocation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-restore-revocation-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let exportRoot = root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: ProductionAccessNotificationSystem())
        var presentation: AppAccessPresentationV1!
        var serviceCount = 0
        var identifierCount = 0
        presentation = AppAccessPresentationV1(startupRouter: router,
            restoreServiceFactory: { applicationSupportURL in
                serviceCount += 1
                return try BackupRestoreService(applicationSupportURL: applicationSupportURL,
                    makeUUID: {
                        MainActor.assumeIsolated {
                            identifierCount += 1
                            if identifierCount == 1 {
                                // The service has passed its first ticket validation. Pause the
                                // router before the next validation and before any durable intent.
                                presentation.receive(.sceneInactive)
                            }
                            return UUID()
                        }
                    })
            }, sessionFactory: { session })
        // A revoked original ticket retains its real source reader/root and
        // failed effect owner. This host owns that graph through test exit;
        // deleting the physical root here would bypass checked retirement.
        Self.retainedRestoreTransitionOwners.append((root, router, session, presentation))
        let published = expectation(description: "Actual production startup publishes the Restore owner")
        let publication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { publication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        guard case .ready(let coordinator, _, _) = router.route else {
            return XCTFail("Production startup did not publish its Restore owner")
        }

        let exporter = BackupExportService(modelContext: coordinator.modelContext,
            generationRootURL: coordinator.generationRootURL)
        let preview = try exporter.prepare()
        let archive = try exporter.export(previewID: preview.id, to: exportRoot)
        let importer = try BackupImportService(generationRootURL: coordinator.generationRootURL,
            scopedAccess: .alreadyAuthorized)
        let package = try importer.stageAndValidate(selectedPackageURL: archive)
        let originalGeneration = coordinator.generationID
        let originalSummary = try BackupRestoreService.currentSummary(
            modelContext: coordinator.modelContext,
            generationRootURL: coordinator.generationRootURL)
        let generationsRoot = support.appendingPathComponent("FieldEvidenceData/generations")
        let originalGenerationEntries = try Set(FileManager.default.contentsOfDirectory(
            at: generationsRoot, includingPropertiesForKeys: nil).map(\.lastPathComponent))

        do {
            try await presentation.performRestore(applicationSupportURL: support, package: package,
                sourceModelContext: coordinator.modelContext,
                sourceGenerationID: coordinator.generationID,
                sourceGenerationRootURL: coordinator.generationRootURL,
                mode: .emptyInstall, coordinator: coordinator)
            XCTFail("The paused router must reject the original Restore ticket")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .staleAttempt)
        }

        XCTAssertEqual(serviceCount, 1)
        XCTAssertEqual(identifierCount, 2)
        XCTAssertFalse(presentation.isBusy)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertEqual(try StoreGenerationFactory(applicationSupportURL: support).currentGenerationID(),
            originalGeneration)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: support).load())
        XCTAssertEqual(try BackupRestoreService.currentSummary(modelContext: coordinator.modelContext,
            generationRootURL: coordinator.generationRootURL), originalSummary)
        XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(
            at: generationsRoot, includingPropertiesForKeys: nil).map(\.lastPathComponent)),
            originalGenerationEntries)
    }

    @MainActor
    func testAuthenticatedReadyRestoreRefusesHeldOriginalReader() async throws {
        let suiteName = "V23.ProductionAppAccess.restore-transition.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-restore-transition-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let exportRoot = root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let router = StartupRouter(applicationSupportURL: support)
        let accessSession = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: ProductionAccessNotificationSystem())
        let presentation = AppAccessPresentationV1(
            startupRouter: router,
            restoreServiceFactory: { try Self.observedRestoreService(at: $0) },
            sessionFactory: { accessSession })
        // The host retains every uncertain FD/owner and the root. This test
        // cannot claim that deleting a live store is checked teardown.
        Self.retainedRestoreTransitionOwners.append(
            (root, router, accessSession, presentation))
        let initialReady = expectation(description: "Actual authenticated source presentation")
        let initialPublication = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in initialReady.fulfill() }
        defer { initialPublication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [initialReady], timeout: 30)
        guard case let .ready(original, _, _) = router.route else {
            return XCTFail("Authenticated startup must publish its actual owner")
        }
        let heldOriginalContext = original.modelContext
        do {
            let exporter = BackupExportService(
                modelContext: original.modelContext,
                generationRootURL: original.generationRootURL)
            let preview = try exporter.prepare()
            let archive = try exporter.export(previewID: preview.id, to: exportRoot)
            let importer = try BackupImportService(
                generationRootURL: original.generationRootURL,
                scopedAccess: .alreadyAuthorized)
            let package = try importer.stageAndValidate(selectedPackageURL: archive)
            try await presentation.performRestore(applicationSupportURL: support,
                package: package, sourceModelContext: original.modelContext,
                sourceGenerationID: original.generationID,
                sourceGenerationRootURL: original.generationRootURL,
                mode: .emptyInstall, coordinator: original)
        }
        let pendingID = try XCTUnwrap(presentation.pendingRestoreTransitionID)
        XCTAssertFalse(presentation.permitsContentPresentation)
        guard case .checking = router.route else {
            return XCTFail("B must stay unpublished until A's old reader drains")
        }
        // This strong test alias is still live. A dismissed sheet alone is
        // never proof that A's reader and SwiftData container have drained.
        await presentation.retryPendingRestoreTransition()
        XCTAssertEqual(presentation.pendingRestoreTransitionID, pendingID)
        XCTAssertFalse(presentation.permitsContentPresentation)
        // This final use forces the actual A context alias across the awaited
        // refusal; lexical scope alone is not an ARC lifetime proof.
        XCTAssertTrue(heldOriginalContext === original.modelContext)
    }

    @MainActor
    func testAuthenticatedReadyRestorePublishesExactTargetAfterOriginalAliasDrain() async throws {
        let suiteName = "V23.ProductionAppAccess.restore-ready.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-restore-ready-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let exportRoot = root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let router = StartupRouter(applicationSupportURL: support)
        let accessSession = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: ProductionAccessNotificationSystem())
        let presentation = AppAccessPresentationV1(
            startupRouter: router,
            restoreServiceFactory: { try Self.observedRestoreService(at: $0) },
            sessionFactory: { accessSession })
        Self.retainedRestoreTransitionOwners.append(
            (root, router, accessSession, presentation))
        let initialReady = expectation(description: "Actual authenticated source presentation")
        let initialPublication = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in initialReady.fulfill() }
        defer { initialPublication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [initialReady], timeout: 30)

        func performFromLexicalOriginalOwner() async throws -> (UUID, UUID) {
            guard case let .ready(original, _, _) = router.route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            let sourceID = original.generationID
            let exporter = BackupExportService(
                modelContext: original.modelContext,
                generationRootURL: original.generationRootURL)
            let preview = try exporter.prepare()
            let archive = try exporter.export(previewID: preview.id, to: exportRoot)
            let importer = try BackupImportService(
                generationRootURL: original.generationRootURL,
                scopedAccess: .alreadyAuthorized)
            let package = try importer.stageAndValidate(selectedPackageURL: archive)
            try await presentation.performRestore(applicationSupportURL: support,
                package: package, sourceModelContext: original.modelContext,
                sourceGenerationID: sourceID,
                sourceGenerationRootURL: original.generationRootURL,
                mode: .emptyInstall, coordinator: original)
            return (sourceID, try XCTUnwrap(presentation.pendingRestoreTransitionID))
        }

        let (sourceID, pendingID) = try await performFromLexicalOriginalOwner()
        XCTAssertFalse(presentation.permitsContentPresentation)
        do {
            _ = try await router.resumeOriginalRestoreReaderTransition(UUID())
            XCTFail("A foreign pending ID must not close A or publish B")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .staleAttempt)
        }
        XCTAssertEqual(presentation.pendingRestoreTransitionID, pendingID)
        guard case .checking = router.route else {
            return XCTFail("A foreign pending ID must leave the original transition covered")
        }
        await presentation.retryPendingRestoreTransition()
        XCTAssertNil(presentation.pendingRestoreTransitionID)
        guard case let .ready(target, _, _) = router.route else {
            return XCTFail("The checked A exit must publish its actual B owner")
        }
        XCTAssertNotEqual(target.generationID, sourceID)
        XCTAssertTrue(presentation.permitsContentPresentation)
        let targetSession = try target.sourceSessionForV949EraseFixture(router: router)
        let targetFactory = try targetSession.validatedOpeningFactoryForWriter()
        XCTAssertTrue(try target.requireOriginalEraseOpeningAuthority(
            factory: targetFactory) === targetSession)
        // Admission to an original Erase repeats Router/Coordinator/session B
        // provider and durable reader/writer checks after its auth await.
        _ = try await router.beginEraseOperation(
            coordinator: target, accessGate: accessSession.gate)
    }

    @MainActor
    func testAuthenticatedReadyRestoreRefusesPostDrainSourceSHMByteMutation() async throws {
        let suiteName = "V23.ProductionAppAccess.restore-shm-hostile.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-restore-shm-hostile-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let exportRoot = root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let router = StartupRouter(applicationSupportURL: support)
        let accessSession = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: ProductionAccessNotificationSystem())
        let presentation = AppAccessPresentationV1(
            startupRouter: router,
            restoreServiceFactory: { try Self.observedRestoreService(at: $0) },
            sessionFactory: { accessSession })
        Self.retainedRestoreTransitionOwners.append(
            (root, router, accessSession, presentation))
        let initialReady = expectation(description: "Actual authenticated source presentation")
        let initialPublication = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in initialReady.fulfill() }
        defer { initialPublication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [initialReady], timeout: 30)

        // The lexical frame owns the real source Coordinator, context and
        // container through the Restore effect, then releases those aliases.
        func performFromLexicalOriginalOwner() async throws -> (UUID, UUID) {
            guard case let .ready(original, _, _) = router.route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            let sourceID = original.generationID
            let exporter = BackupExportService(
                modelContext: original.modelContext,
                generationRootURL: original.generationRootURL)
            let preview = try exporter.prepare()
            let archive = try exporter.export(previewID: preview.id, to: exportRoot)
            let importer = try BackupImportService(
                generationRootURL: original.generationRootURL,
                scopedAccess: .alreadyAuthorized)
            let package = try importer.stageAndValidate(selectedPackageURL: archive)
            try await presentation.performRestore(applicationSupportURL: support,
                package: package, sourceModelContext: original.modelContext,
                sourceGenerationID: sourceID,
                sourceGenerationRootURL: original.generationRootURL,
                mode: .emptyInstall, coordinator: original)
            return (sourceID, try XCTUnwrap(presentation.pendingRestoreTransitionID))
        }
        let (sourceID, pendingID) = try await performFromLexicalOriginalOwner()
        guard case .checking = router.route else {
            return XCTFail("B must remain unpublished during the old-source drain")
        }
        let shm = support.appendingPathComponent("FieldEvidenceData/generations")
            .appendingPathComponent(sourceID.uuidString.lowercased())
            .appendingPathComponent("model.sqlite-shm")
        var originalFact = stat()
        XCTAssertEqual(Darwin.lstat(shm.path, &originalFact), 0)
        var changed = try Data(contentsOf: shm)
        guard !changed.isEmpty else {
            return XCTFail("The authenticated source SHM file must be present and nonempty")
        }
        changed[changed.startIndex] ^= 0x01
        try changed.write(to: shm, options: [])
        var changedFact = stat()
        XCTAssertEqual(Darwin.lstat(shm.path, &changedFact), 0)
        XCTAssertEqual(changedFact.st_dev, originalFact.st_dev)
        XCTAssertEqual(changedFact.st_ino, originalFact.st_ino)
        XCTAssertEqual(changedFact.st_size, originalFact.st_size)
        XCTAssertEqual(try Data(contentsOf: shm), changed)

        // A byte change under the same SHM inode is never the permitted
        // ctime-only SwiftData alias-drain transition.
        do {
            _ = try await router.resumeOriginalRestoreReaderTransition(pendingID)
            XCTFail("A hostile source byte change must refuse checked A exit")
        } catch let error as StoreGenerationFailure {
            XCTAssertEqual(error, .dataPointerInvalid)
        }
        XCTAssertEqual(presentation.pendingRestoreTransitionID, pendingID)
        XCTAssertFalse(presentation.permitsContentPresentation)
        guard case .maintenance(.restoreInconsistent) = router.route else {
            return XCTFail("The hostile source must remain covered with Restore inconsistent and B unpublished")
        }
    }

    @MainActor
    func testAuthenticatedMaintenanceRestorePublishesBAndAdmitsOriginalEraseAfterHostDrain() async throws {
        let suiteName = "V23.ProductionAppAccess.restore-maintenance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-restore-maintenance-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let exportRoot = root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let router = StartupRouter(applicationSupportURL: support)
        var failBeforeFirstMediaPublish = true
        router.beforeCurrentMediaCleanupForTesting = { _ in
            if failBeforeFirstMediaPublish {
                failBeforeFirstMediaPublish = false
                throw StartupMaintenanceReason.mediaInconsistent
            }
        }
        let accessSession = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: ProductionAccessNotificationSystem())
        let presentation = AppAccessPresentationV1(
            startupRouter: router, sessionFactory: { accessSession })
        // The test host retains the actual old and new control owners and root.
        Self.retainedRestoreTransitionOwners.append(
            (root, router, accessSession, presentation))
        let initialMaintenance = expectation(description: "Actual prepublication media maintenance")
        let initialFailure = expectation(description: "Startup action completed under maintenance cover")
        let initialRoute = router.$route.filter { route in
            if case .maintenance(.mediaInconsistent) = route { return true }
            return false
        }.prefix(1).sink { _ in initialMaintenance.fulfill() }
        let failureObservation = presentation.$failure.filter { value in
            guard let value else { return false }
            return value == .startup
        }.prefix(1).sink { _ in initialFailure.fulfill() }
        defer { initialRoute.cancel(); failureObservation.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [initialMaintenance, initialFailure], timeout: 30)
        guard case .maintenance(.mediaInconsistent) = router.route else {
            return XCTFail("The one-time prepublication media fault must expose real maintenance Restore")
        }

        func restoreFromLexicalMaintenanceHost() async throws -> UUID {
            let source = try XCTUnwrap(router.maintenanceRestoreSession)
            XCTAssertTrue(router.maintenanceEraseSession === source,
                "The same installed writer and reader must support the maintenance Erase option")
            let exporter = BackupExportService(
                modelContext: source.modelContext,
                generationRootURL: source.generationRootURL)
            let preview = try exporter.prepare()
            let archive = try exporter.export(previewID: preview.id, to: exportRoot)
            let importer = try BackupImportService(
                generationRootURL: source.generationRootURL,
                scopedAccess: .alreadyAuthorized)
            let package = try importer.stageAndValidate(selectedPackageURL: archive)
            try await presentation.performRestore(applicationSupportURL: support,
                package: package, sourceModelContext: source.modelContext,
                sourceGenerationID: source.generationID,
                sourceGenerationRootURL: source.generationRootURL,
                mode: .emptyInstall, coordinator: nil)
            return source.generationID
        }

        let sourceID = try await restoreFromLexicalMaintenanceHost()
        XCTAssertNotNil(presentation.pendingRestoreTransitionID)
        XCTAssertFalse(presentation.permitsContentPresentation)
        await presentation.retryPendingRestoreTransition()
        XCTAssertNil(presentation.pendingRestoreTransitionID)
        guard case let .ready(target, _, _) = router.route else {
            return XCTFail("The real maintenance source must release A before B publication")
        }
        XCTAssertNotEqual(target.generationID, sourceID)
        let targetSession = try target.sourceSessionForV949EraseFixture(router: router)
        let targetFactory = try targetSession.validatedOpeningFactoryForWriter()
        XCTAssertTrue(try target.requireOriginalEraseOpeningAuthority(
            factory: targetFactory) === targetSession)
        _ = try await router.beginEraseOperation(
            coordinator: target, accessGate: accessSession.gate)
    }

    @MainActor
    func testMaintenanceRestoreAdmissionRefusesForeignOrReplacedValidatedStage() async throws {
        for replaceValidatedStage in [false, true] {
            let suiteName = "V23.ProductionAppAccess.restore-stage.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "V23-MaintenanceRestoreStage-\(UUID().uuidString)", isDirectory: true)
            let support = root.appendingPathComponent("Library/Application Support")
            let exportRoot = root.appendingPathComponent("export", isDirectory: true)
            try FileManager.default.createDirectory(at: support,
                withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent(
                "Library/Caches", isDirectory: true), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: exportRoot,
                withIntermediateDirectories: true)
            let router = StartupRouter(applicationSupportURL: support)
            var failOnce = true
            router.beforeCurrentMediaCleanupForTesting = { _ in
                if failOnce {
                    failOnce = false
                    throw StartupMaintenanceReason.mediaInconsistent
                }
            }
            let accessSession = try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: support, startupRouter: router,
                defaults: defaults,
                authenticationClient: ProductionAccessAuthentication(),
                notificationSystem: ProductionAccessNotificationSystem())
            let presentation = AppAccessPresentationV1(
                startupRouter: router, sessionFactory: { accessSession })
            Self.retainedRestoreTransitionOwners.append(
                (root, router, accessSession, presentation))
            let maintenanceReached = expectation(
                description: "Original startup reaches real media maintenance")
            let routeObservation = router.$route.filter { route in
                if case .maintenance(.mediaInconsistent) = route { return true }
                return false
            }.prefix(1).sink { _ in maintenanceReached.fulfill() }
            defer { routeObservation.cancel() }
            await presentation.bootstrapIfNeeded()
            await fulfillment(of: [maintenanceReached], timeout: 30)
            guard case .maintenance(.mediaInconsistent) = router.route else {
                return XCTFail("The genuine startup fault must admit the maintenance host")
            }
            let source = try XCTUnwrap(router.maintenanceRestoreSession)
            let exporter = BackupExportService(modelContext: source.modelContext,
                generationRootURL: source.generationRootURL)
            let preview = try exporter.prepare()
            let archive = try exporter.export(previewID: preview.id, to: exportRoot)
            let importer = try BackupImportService(
                generationRootURL: source.generationRootURL,
                scopedAccess: .alreadyAuthorized)
            let package = try importer.stageAndValidate(selectedPackageURL: archive)
            let current = support.appendingPathComponent("FieldEvidenceData/current.json")
            let currentBefore = try Data(contentsOf: current)
            let staged = package.stagedPackageURL
            let staging = staged.deletingLastPathComponent()
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(
                atPath: staging.path), [staged.lastPathComponent])
            if replaceValidatedStage {
                let displaced = root.appendingPathComponent("displaced-package",
                    isDirectory: true)
                try FileManager.default.moveItem(at: staged, to: displaced)
                try FileManager.default.createDirectory(at: staged,
                    withIntermediateDirectories: false)
                XCTAssertNotEqual(
                    try BackupPackageAnchoredFile.rootIdentity(at: staged),
                    package.members.rootIdentity)
            } else {
                let foreign = staging.appendingPathComponent(
                    "\(UUID().uuidString.lowercased()).fieldrecordbackup",
                    isDirectory: true)
                try FileManager.default.createDirectory(at: foreign,
                    withIntermediateDirectories: false)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(
                    atPath: staging.path).count, 2)
            }
            let generationNamesBeforeRefusal = try Set(FileManager.default.contentsOfDirectory(
                atPath: support.appendingPathComponent("FieldEvidenceData/generations").path))
            let stageNamesBeforeRefusal = try Set(FileManager.default.contentsOfDirectory(
                atPath: staging.path))
            let stageIdentitiesBeforeRefusal = try stageNamesBeforeRefusal.sorted().map { name in
                try BackupPackageAnchoredFile.rootIdentity(
                    at: staging.appendingPathComponent(name, isDirectory: true))
            }
            let displacedIdentityBeforeRefusal = replaceValidatedStage
                ? try BackupPackageAnchoredFile.rootIdentity(
                    at: root.appendingPathComponent("displaced-package", isDirectory: true))
                : nil
            do {
                try await presentation.performRestore(applicationSupportURL: support,
                    package: package, sourceModelContext: source.modelContext,
                    sourceGenerationID: source.generationID,
                    sourceGenerationRootURL: source.generationRootURL,
                    mode: .emptyInstall, coordinator: nil)
                XCTFail("A foreign or replaced validated stage must refuse original admission")
            } catch let error as StoreGenerationFailure {
                XCTAssertEqual(error, .dataPointerInvalid)
            }
            XCTAssertEqual(try Data(contentsOf: current), currentBefore)
            XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(
                atPath: support.appendingPathComponent("FieldEvidenceData/generations").path)),
                generationNamesBeforeRefusal)
            let stageNamesAfterRefusal = try Set(FileManager.default.contentsOfDirectory(
                atPath: staging.path))
            XCTAssertEqual(stageNamesAfterRefusal, stageNamesBeforeRefusal)
            let stageIdentitiesAfterRefusal = try stageNamesBeforeRefusal.sorted().map { name in
                try BackupPackageAnchoredFile.rootIdentity(
                    at: staging.appendingPathComponent(name, isDirectory: true))
            }
            XCTAssertEqual(stageIdentitiesAfterRefusal, stageIdentitiesBeforeRefusal)
            if let displacedIdentityBeforeRefusal {
                XCTAssertEqual(try BackupPackageAnchoredFile.rootIdentity(
                    at: root.appendingPathComponent("displaced-package", isDirectory: true)),
                    displacedIdentityBeforeRefusal)
            }
            XCTAssertNil(presentation.pendingRestoreTransitionID)
            guard case .maintenance(.mediaInconsistent) = router.route else {
                return XCTFail("The original maintenance owner must remain covered")
            }
        }
    }

    @MainActor
    func testTrackedMaintenanceDeletionRecoversActualPreparedJournalAndClosesOwner() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-MaintenanceDeletion-\(UUID().uuidString)", isDirectory: true)
        let generationID = UUID()
        let generation = support.appendingPathComponent(
            "FieldEvidenceData/generations/\(generationID.uuidString.lowercased())",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: generation, withIntermediateDirectories: true)
        let schema = Schema(PersistentSchemaV53.models,
            version: PersistentSchemaV53.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil,
            configurations: [ModelConfiguration("MaintenanceDeletion", schema: schema,
                url: generation.appendingPathComponent("model.sqlite"),
                allowsSave: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        context.autosaveEnabled = false
        let completed = Date(timeIntervalSince1970: 1_760_000_000)
        let placementDate = completed.addingTimeInterval(-120)
        let site = Site(label: "Site", createdAt: placementDate)
        let asset = Asset(siteID: site.id,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: 1, packContentVersion: 1, label: "Sign",
            createdAt: placementDate)
        context.insert(site)
        context.insert(asset)
        let workspaceID = WorkspaceID()
        let placement = try AssetPlacementEventV1(
            id: UUID(), workspaceID: workspaceID,
            assetID: asset.id, siteID: site.id,
            locationNodeID: nil, predecessorEventID: nil,
            source: .migratedBaseline,
            physicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID()),
            continuity: .samePhysicalInstallation,
            pathSnapshot: try LocationPathSnapshotV1(
                siteID: site.id, siteDisplay: site.label, nodes: []),
            mutationID: try MutationIDV1(rawValue: UUID()),
            occurredAt: placementDate)
        try AssetPlacementHistoryV1.validate([placement])
        try WholeSignDeletionRule.validateLocationDeletionNoCascade(
            deletingAssetID: asset.id, deletingSiteID: nil,
            liveAssetSiteByID: [asset.id: site.id],
            locationNodes: [], placementEvents: [placement], compositionEdges: [])
        context.insert(try AssetPlacementEventRow(placement))
        let recordID = UUID()
        let packetID = UUID()
        let record = WorkflowRecord(
            id: recordID, assetID: asset.id, packetID: packetID, issueID: nil,
            parentRecordID: nil, recordRevisionRootID: recordID,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: .original, stage: .check, state: .completed,
            draftStepKey: nil, startedAt: completed.addingTimeInterval(-60),
            completedAt: completed, observedAtUTC: completed,
            timeZoneID: "America/New_York", utcOffsetMinutes: -240,
            localDate: "2025-10-09", localTime: "04:53:20",
            afterDarkAcknowledgementKey: "after_dark",
            afterDarkAcknowledgementCopy: "After dark",
            afterDarkAcknowledgementVersion: "1",
            afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: "safe_position",
            safePositionAcknowledgementCopy: "Safe position",
            safePositionAcknowledgementVersion: "1",
            safePositionAcknowledgementAccepted: true,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: 1, packContentVersion: 1,
            pdfTemplateID: "field.evidence.pdf.worklight.v1",
            pdfTemplateVersion: 1, outcomeKey: "no_issue_found",
            couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil, note: nil,
            finalizationMutationID: UUID())
        context.insert(record)
        let observationBasis = try XCTUnwrap(
            ObservationAndTimeLegacyMigrationV1.observationBasis(
                couldNotVerifyKey: record.couldNotVerifyKey,
                displaySnapshot: record.couldNotVerifyDisplaySnapshot,
                registryVersion: record.couldNotVerifyRegistryVersion))
        let temporalContext = try XCTUnwrap(
            ObservationAndTimeLegacyMigrationV1.temporalContext(
                observedAtUTC: record.observedAtUTC,
                recordedAtUTC: record.startedAt,
                timeZoneID: record.timeZoneID,
                utcOffsetMinutes: record.utcOffsetMinutes,
                localDate: record.localDate,
                localTime: record.localTime))
        context.insert(try ObservationAndTimeRow(
            recordID: recordID, observationBasis: observationBasis,
            temporalContext: temporalContext))
        context.insert(Packet(id: packetID, stableRootID: UUID(),
            currentRecordID: recordID, evaluationCounted: true,
            contentDeletedAt: nil, createdAt: completed))
        let evidenceID = UUID()
        let evidenceName = evidenceID.uuidString.lowercased()
        let pixels = Data(repeating: 128, count: 40 * 40 * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(width: 40, height: 40,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 40 * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        let pngOutput = NSMutableData()
        let pngWriter = try XCTUnwrap(CGImageDestinationCreateWithData(
            pngOutput, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(pngWriter, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(pngWriter))
        let normalized = try MediaNormalizerV1().normalize(pngOutput as Data)
        let evidenceBytes = normalized.originalJPEG
        let thumbnailBytes = normalized.thumbnailJPEG
        let evidenceHash = SHA256.hash(data: evidenceBytes)
            .map { String(format: "%02x", $0) }.joined()
        let thumbnailHash = SHA256.hash(data: thumbnailBytes)
            .map { String(format: "%02x", $0) }.joined()
        let evidenceDirectory = generation.appendingPathComponent(
            "evidence/\(evidenceName)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: evidenceDirectory, withIntermediateDirectories: true)
        try evidenceBytes.write(to: evidenceDirectory.appendingPathComponent("original.jpg"))
        try thumbnailBytes.write(to: evidenceDirectory.appendingPathComponent("thumbnail.jpg"))
        context.insert(EvidenceFile(id: evidenceID, recordID: recordID,
            purposeKey: "wide_context",
            relativePath: "evidence/\(evidenceName)/original.jpg",
            mimeType: "image/jpeg", byteCount: evidenceBytes.count,
            sha256: evidenceHash, createdAt: completed,
            thumbnailRelativePath: "evidence/\(evidenceName)/thumbnail.jpg",
            thumbnailByteCount: thumbnailBytes.count,
            thumbnailSHA256: thumbnailHash))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AssetPlacementEventRow>()), 1)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID, replicaID: ReplicaID())
        let mutationJournal = try MutationJournalStoreV1(
            modelContext: context, identity: identity,
            generationID: generationID)
        try mutationJournal.validateAll()
        let historyBefore = try mutationJournal.exportSnapshot()
        let interrupted = WholeSignDeletionService(modelContext: context,
            generationRootURL: generation,
            failureInjection: WholeSignDeletionFailureInjection(
                failOnceAt: .preparedJournal))
        do {
            _ = try await interrupted.delete(assetID: asset.id)
            XCTFail("The genuine deletion producer must stop after its prepared journal")
        } catch {
            XCTAssertEqual(error as? WholeSignDeletionServiceError, .injectedFailure)
        }
        let journal = support.appendingPathComponent(
            "FieldEvidenceOperations/deletion", isDirectory: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: journal.path).count, 1)

        let descriptorOwner = RestoreMaintenanceOperationsDescriptorOwnerV1()
        Self.retainedMaintenanceJournalDescriptorAttempts.append(descriptorOwner)
        let recovery = WholeSignDeletionService(modelContext: context,
            generationRootURL: generation,
            trackStartupOperationsCreation: true,
            startupDescriptorOwner: descriptorOwner)
        Self.retainedMaintenanceJournalOwners.append(
            (support, container, context, recovery, descriptorOwner))
        let openingReceipt = try recovery.startupOperationsReceipt()
        XCTAssertEqual(openingReceipt.name, "deletion")
        XCTAssertFalse(openingReceipt.created)
        let result = try await recovery.reconcile()
        XCTAssertEqual(result.cancelledPreparedCount, 0)
        XCTAssertEqual(result.completedCommittedCount, 1)
        let recoveredJournal = try MutationJournalStoreV1(
            modelContext: context, identity: identity,
            generationID: generationID, allowStateBootstrap: false)
        try recoveredJournal.validateAll()
        XCTAssertEqual(try recoveredJournal.exportSnapshot(), historyBefore)
        let recoveryReceipt = try recovery.startupRecoveryJournalReceipt()
        XCTAssertEqual(recoveryReceipt.name, "deletion")
        XCTAssertGreaterThan(recoveryReceipt.mutationCount, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: journal.path), [])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            evidenceDirectory.appendingPathComponent("original.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            evidenceDirectory.appendingPathComponent("thumbnail.jpg").path))
        try descriptorOwner.closeAllChecked()
        XCTAssertThrowsError(try descriptorOwner.requireOpen())
    }

    @MainActor
    func testMaintenanceRestoreClearProbeRefusesMissingOrLinkedChildWithoutRepair() async throws {
        for linkedChild in [false, true] {
            let suiteName = "V23.ProductionAppAccess.restore-no-repair.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("V23-ProductionAppAccess-restore-no-repair-\(UUID().uuidString)")
            let support = root.appendingPathComponent("Library/Application Support")
            let caches = root.appendingPathComponent("Library/Caches")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let router = StartupRouter(applicationSupportURL: support)
            let target = support.appendingPathComponent(
                linkedChild ? "FieldEvidenceRestore/staging" : "FieldEvidenceRestore/generations")
            let foreign = root.appendingPathComponent("foreign-staging")
            let marker = foreign.appendingPathComponent("foreign-marker")
            let pointer = support.appendingPathComponent("FieldEvidenceData/current.json")
            var pointerBeforeFault: Data?
            var injected = false
            router.beforeCurrentMediaCleanupForTesting = { _ in
                throw StartupMaintenanceReason.mediaInconsistent
            }
            router.beforeMaintenanceClearObservationForTesting = {
                guard !injected else { return }
                injected = true
                pointerBeforeFault = try Data(contentsOf: pointer)
                let entries = try FileManager.default.contentsOfDirectory(atPath: target.path)
                guard entries.isEmpty else {
                    XCTFail("The original startup child must be empty before this hostile transition")
                    throw StartupMaintenanceReason.mediaInconsistent
                }
                try FileManager.default.removeItem(at: target)
                if linkedChild {
                    try FileManager.default.createDirectory(
                        at: foreign, withIntermediateDirectories: false)
                    try Data("foreign-marker".utf8).write(to: marker)
                    try FileManager.default.createSymbolicLink(
                        at: target, withDestinationURL: foreign)
                }
            }
            let accessSession = try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: support, startupRouter: router, defaults: defaults,
                authenticationClient: ProductionAccessAuthentication(),
                notificationSystem: ProductionAccessNotificationSystem())
            let presentation = AppAccessPresentationV1(
                startupRouter: router, sessionFactory: { accessSession })
            // The startup session, failed probe and root remain owned by the
            // test host. Removing the root under their FDs is not cleanup.
            Self.retainedRestoreTransitionOwners.append(
                (root, router, accessSession, presentation))
            let maintenance = expectation(description: "Authentic prepublication maintenance")
            let routeObservation = router.$route.filter { route in
                if case .maintenance(.mediaInconsistent) = route { return true }
                return false
            }.prefix(1).sink { _ in maintenance.fulfill() }
            defer { routeObservation.cancel() }
            await presentation.bootstrapIfNeeded()
            await fulfillment(of: [maintenance], timeout: 30)
            XCTAssertTrue(injected)
            guard case .maintenance(.mediaInconsistent) = router.route else {
                return XCTFail("The hostile child must leave the actual Router in maintenance")
            }
            XCTAssertNil(router.maintenanceRestoreSession)
            XCTAssertNil(router.maintenanceEraseSession)
            XCTAssertFalse(presentation.permitsContentPresentation)
            XCTAssertNil(presentation.pendingRestoreTransitionID)
            XCTAssertEqual(try Data(contentsOf: pointer), try XCTUnwrap(pointerBeforeFault))
            if linkedChild {
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(
                    atPath: target.path), foreign.path)
                XCTAssertEqual(try Data(contentsOf: marker), Data("foreign-marker".utf8))
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
            }
        }
    }

    @MainActor
    func testMaintenanceEligibilityRefusesForeignOperationsChildWithoutRepair() async throws {
        let suiteName = "V23.ProductionAppAccess.maintenance-operations-extra.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-maintenance-operations-extra-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let router = StartupRouter(applicationSupportURL: support)
        let pointerURL = support.appendingPathComponent("FieldEvidenceData/current.json")
        let foreign = support.appendingPathComponent("FieldEvidenceOperations/foreign-startup-child")
        let marker = foreign.appendingPathComponent("foreign-marker")
        var pointerBeforeFault: Data?
        var injected = false
        router.beforeCurrentMediaCleanupForTesting = { _ in
            throw StartupMaintenanceReason.mediaInconsistent
        }
        router.beforeMaintenanceClearObservationForTesting = {
            guard !injected else { return }
            injected = true
            pointerBeforeFault = try Data(contentsOf: pointerURL)
            try FileManager.default.createDirectory(at: foreign,
                withIntermediateDirectories: false)
            try Data("foreign-marker".utf8).write(to: marker)
        }
        let accessSession = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: ProductionAccessNotificationSystem())
        let presentation = AppAccessPresentationV1(
            startupRouter: router, sessionFactory: { accessSession })
        Self.retainedRestoreTransitionOwners.append(
            (root, router, accessSession, presentation))
        let maintenance = expectation(description: "Actual maintenance after foreign Operations child")
        let routeObservation = router.$route.filter { route in
            if case .maintenance(.mediaInconsistent) = route { return true }
            return false
        }.prefix(1).sink { _ in maintenance.fulfill() }
        defer { routeObservation.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [maintenance], timeout: 30)
        XCTAssertTrue(injected)
        guard case .maintenance(.mediaInconsistent) = router.route else {
            return XCTFail("The foreign Operations child must keep the actual Router covered")
        }
        XCTAssertNil(router.maintenanceRestoreSession)
        XCTAssertNil(router.maintenanceEraseSession)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.pendingRestoreTransitionID)
        XCTAssertEqual(try Data(contentsOf: pointerURL), try XCTUnwrap(pointerBeforeFault))
        XCTAssertEqual(try Data(contentsOf: marker), Data("foreign-marker".utf8))
    }

    @MainActor
    func testMaintenanceEligibilityRefusesPostOpenV3HistoryDriftWithoutRepair() async throws {
        let suiteName = "V23.ProductionAppAccess.maintenance-history-drift.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-maintenance-history-drift-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let router = StartupRouter(applicationSupportURL: support)
        let pointerURL = support.appendingPathComponent("FieldEvidenceData/current.json")
        var hostilePointer: Data?
        var originalPointer: Data?
        router.beforeCurrentMediaCleanupForTesting = { _ in
            throw StartupMaintenanceReason.mediaInconsistent
        }
        router.beforeMaintenanceClearObservationForTesting = {
            guard hostilePointer == nil else { return }
            let original = try Data(contentsOf: pointerURL)
            guard case .v3(let pointer, _) = try CurrentPointerCodecV1.decode(original) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            let changed = try CurrentGenerationPointerV3(
                generationID: XCTUnwrap(UUID(uuidString: pointer.generationID)),
                generationManifestSHA256: pointer.generationManifestSHA256,
                workspaceID: WorkspaceID(rawValue:
                    XCTUnwrap(UUID(uuidString: pointer.workspaceID))),
                replicaID: ReplicaID(rawValue:
                    XCTUnwrap(UUID(uuidString: pointer.replicaID))),
                knownReplicaIDs: try pointer.knownReplicaIdentitySet()
                    .union([ReplicaID(rawValue: UUID())]),
                storeSchemaVersion: pointer.storeSchemaVersion).canonicalData()
            originalPointer = original
            hostilePointer = changed
            try changed.write(to: pointerURL, options: [])
        }
        let accessSession = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: ProductionAccessNotificationSystem())
        let presentation = AppAccessPresentationV1(
            startupRouter: router, sessionFactory: { accessSession })
        Self.retainedRestoreTransitionOwners.append(
            (root, router, accessSession, presentation))
        let maintenance = expectation(description: "Actual maintenance after writer install")
        let routeObservation = router.$route.filter { route in
            if case .maintenance(.mediaInconsistent) = route { return true }
            return false
        }.prefix(1).sink { _ in maintenance.fulfill() }
        defer { routeObservation.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [maintenance], timeout: 30)
        guard case .maintenance(.mediaInconsistent) = router.route else {
            return XCTFail("The hostile current pointer must keep the Router covered")
        }
        XCTAssertNotEqual(try XCTUnwrap(originalPointer), try XCTUnwrap(hostilePointer))
        XCTAssertEqual(try Data(contentsOf: pointerURL),
            try XCTUnwrap(hostilePointer))
        XCTAssertNil(router.maintenanceRestoreSession)
        XCTAssertNil(router.maintenanceEraseSession)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.pendingRestoreTransitionID)
    }


    @MainActor
    func testPresentationRetriesOriginalEraseAfterPointerSwitchToReady() async throws {
        let suiteName = "V23.ProductionAppAccess.original-retry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-original-retry-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        let temporary = root.appendingPathComponent("tmp")
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let system = ProductionAccessNotificationSystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        var serviceCount = 0
        var reservations = [AppAccessGateV1.EraseAdoptionToken]()
        var completions = [CompletedEraseReceiptV1]()
#if DEBUG
        var fixedStages = [String]()
        var retryStages = [String]()
#endif
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                serviceCount += 1
                let service = EraseAllService(applicationSupportURL: support,
                    cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                    userDefaults: defaults, defaultsDomainName: suiteName,
                    failureInjection: serviceCount == 1
                        ? EraseAllFailureInjection(failOnceAt: .afterPointerSwitch) : nil,
                    sceneNavigationStatePort: sceneState,
                    privateSystemDiscoveryIndex: nil, notificationSystem: system,
                    admitErase: { subject in
                        let actualAdmission = try XCTUnwrap(admission)
                        let reservation = try await actualAdmission(subject)
                        reservations.append(reservation)
                        return reservation
                    }, didCompleteErase: { receipt in
                        completions.append(receipt)
                        completion?(receipt)
                    }, didAbortEraseAdmission: aborted)
#if DEBUG
                if serviceCount == 1 {
                    service.schema2ColdFixedStageForTesting = { stage in
                        if !stage.hasPrefix("empty.policy.") {
                            fixedStages.append(stage)
                            if fixedStages.count > 32 {
                                fixedStages.removeFirst()
                            }
                        }
                    }
                } else if serviceCount == 2 {
                    service.schema2ColdFixedStageForTesting = { stage in
                        retryStages.append(stage)
                        if retryStages.count > 32 {
                            retryStages.removeFirst()
                        }
                    }
                }
#endif
                return service
            }, sessionFactory: { session })
        // Retain the authentic owners and their root if any failure leaves
        // descriptors alive. Never delete a live recovery tree in teardown.
        Self.retainedDeferredEraseOwners.append((root, router, session, presentation))
        let published = expectation(description: "Original production owner publishes")
        let startupPublication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { startupPublication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        var coordinator: StoreSessionCoordinator?
        let diagnostics: DiagnosticsStore
        switch router.route {
        case let .ready(value, store, _): coordinator = value; diagnostics = store
        default: return XCTFail("Original startup did not become ready")
        }
        let oldID = try XCTUnwrap(coordinator).generationID
        do {
            try await presentation.performErase(applicationSupportURL: support,
                confirmation: "ERASE", coordinator: try XCTUnwrap(coordinator),
                diagnosticsStore: diagnostics)
            return XCTFail("The original pointer-switch interruption was not reached")
        } catch {
            guard error as? EraseAllServiceError == .injectedFailure else {
#if DEBUG
                let category: String
                if error is GenerationLeaseRegistryFailureV1 {
                    category = "registry"
                } else if error is EraseAllServiceError {
                    category = "erase"
                } else if error is AppAccessContractFailureV1 {
                    category = "app-access"
                } else {
                    category = "other"
                }
                let fixed = fixedStages.last ?? "none"
                let history = fixedStages.joined(separator: ",")
                FileHandle.standardError.write(Data(
                    ("ORIGINAL_APPACCESS_ERASE_FIXED_V1 stage=" + fixed
                    + " category=" + category + " history=" + history
                    + "\n").utf8))
#endif
                throw error
            }
        }
        XCTAssertEqual(serviceCount, 1)
        XCTAssertFalse(presentation.isBusy)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(reservations.count, 1, "The interrupted original admits exactly once")
        let originalReservation = try XCTUnwrap(reservations.first)
        // Decode existing bytes directly: no reparative EraseIntentStore
        // construction may precede the production retry under test.
        let intent = try EraseIntentCodecV1.decode(Data(contentsOf: support
            .appendingPathComponent("FieldEvidenceErase/erase.json")))
        XCTAssertEqual(intent.phase, .emptyGenerationPrepared)
        XCTAssertEqual(intent.oldGenerationID, oldID)
        XCTAssertEqual(intent.newGenerationID, originalReservation.subject.newGenerationID)
        XCTAssertEqual(intent.eraseID, originalReservation.subject.eraseID)
        guard case .v3(let pointer, _) = try CurrentPointerCodecV1.decode(
            Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/current.json"))) else {
            return XCTFail("The real pointer switch must publish the current pointer schema")
        }
        XCTAssertEqual(UUID(uuidString: pointer.generationID), intent.newGenerationID,
            "Retry must enter the target-current recovery branch")
        weak var originalCoordinator = coordinator
        coordinator = nil
        XCTAssertNotNil(originalCoordinator, "The actual pending operation must retain its source owner")
        let ready = expectation(description: "Same presentation retry completes and publishes target")
        let retryPublication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in ready.fulfill() }
        defer { retryPublication.cancel() }
#if DEBUG
        var retryDiagnosticCount = 0
        presentation.eraseRecoveryDiagnosticForTesting = { fixedMessage in
            guard retryDiagnosticCount < 32 else { return }
            retryDiagnosticCount += 1
            FileHandle.standardError.write(Data(
                ("ORIGINAL_APPACCESS_RETRY_V1 " + fixedMessage + "\n").utf8))
        }
        defer { presentation.eraseRecoveryDiagnosticForTesting = nil }
#endif
        await presentation.retryStartup()
#if DEBUG
        if !presentation.permitsContentPresentation {
            FileHandle.standardError.write(Data(
                ("ORIGINAL_APPACCESS_RETRY_SERVICE_V1 stage="
                + (retryStages.last ?? "none")
                + " history=" + retryStages.joined(separator: ",")
                + "\n").utf8))
        }
#endif
        await fulfillment(of: [ready], timeout: 30)
        XCTAssertEqual(serviceCount, 2, "Retry must use the retained original operation's service factory")
        XCTAssertEqual(reservations.count, 2, "One original admission and one checked recovery admission")
        XCTAssertTrue(reservations.allSatisfy { $0 == originalReservation })
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.subject, originalReservation.subject)
        XCTAssertTrue(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.failure)
        XCTAssertNil(originalCoordinator)
        guard case let .ready(recovered, _, _) = router.route else {
            return XCTFail("Original retry did not publish its target")
        }
        XCTAssertEqual(recovered.generationID, intent.newGenerationID)
        XCTAssertEqual(try recovered.workspaceWriter.currentRevision().generationID,
            intent.newGenerationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support
            .appendingPathComponent("FieldEvidenceErase").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            StoreGenerationFactory(applicationSupportURL: support)
                .installedGenerationURL(id: oldID).path))
    }

    @MainActor
    func testPresentationRetriesOriginalEraseWithTwoPriorRetiredGenerationsToReady() async throws {
        let suiteName = "V23.ProductionAppAccess.original-multiretired-retry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-original-multiretired-retry-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        let temporary = root.appendingPathComponent("tmp")
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let priorIDs = try makeOriginalRetryRetiredSources(support: support)
        let priorManifestBytes = try Dictionary(uniqueKeysWithValues: priorIDs.map { id in
            (id, try Data(contentsOf: support.appendingPathComponent(
                "FieldEvidenceOperations/schema-migration/manifest-\(id.uuidString.lowercased()).json")))
        })
        let priorInodes = try Dictionary(uniqueKeysWithValues: priorIDs.map { id in
            (id, try XCTUnwrap(FileManager.default.attributesOfItem(atPath:
                StoreGenerationFactory(applicationSupportURL: support)
                    .installedGenerationURL(id: id).path)[.systemFileNumber] as? NSNumber))
        })
        let system = ProductionAccessNotificationSystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        var serviceCount = 0
        var reservations = [AppAccessGateV1.EraseAdoptionToken]()
        var completions = [CompletedEraseReceiptV1]()
#if DEBUG
        var fixedStages = [String]()
        var retryStages = [String]()
        var transferredSourceChecks = 0
#endif
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                serviceCount += 1
                let service = EraseAllService(applicationSupportURL: support,
                    cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                    userDefaults: defaults, defaultsDomainName: suiteName,
                    failureInjection: serviceCount == 1
                        ? EraseAllFailureInjection(failOnceAt: .afterPointerSwitch) : nil,
                    sceneNavigationStatePort: sceneState,
                    privateSystemDiscoveryIndex: nil, notificationSystem: system,
                    admitErase: { subject in
                        let actualAdmission = try XCTUnwrap(admission)
                        let reservation = try await actualAdmission(subject)
                        reservations.append(reservation)
                        return reservation
                    }, didCompleteErase: { receipt in
                        completions.append(receipt)
                        completion?(receipt)
                    }, didAbortEraseAdmission: aborted)
#if DEBUG
                if serviceCount == 1 {
                    service.schema2ColdFixedStageForTesting = { stage in
                        if !stage.hasPrefix("empty.policy.") {
                            fixedStages.append(stage)
                            if fixedStages.count > 32 {
                                fixedStages.removeFirst()
                            }
                        }
                    }
                } else if serviceCount == 2 {
                    service.schema2ColdFixedStageForTesting = { stage in
                        if stage == "recovery.presence.transferred-prior-enter" {
                            transferredSourceChecks += 1
                        }
                        retryStages.append(stage)
                        if retryStages.count > 32 {
                            retryStages.removeFirst()
                        }
                    }
                }
#endif
                return service
            }, sessionFactory: { session })
        // Retain the authentic owners and their root if any failure leaves
        // descriptors alive. Never delete a live recovery tree in teardown.
        Self.retainedDeferredEraseOwners.append((root, router, session, presentation))
        let published = expectation(description: "Original production owner publishes")
        let startupPublication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { startupPublication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        var coordinator: StoreSessionCoordinator?
        let diagnostics: DiagnosticsStore
        switch router.route {
        case let .ready(value, store, _): coordinator = value; diagnostics = store
        default: return XCTFail("Original startup did not become ready")
        }
        let oldID = try XCTUnwrap(coordinator).generationID
        do {
            try await presentation.performErase(applicationSupportURL: support,
                confirmation: "ERASE", coordinator: try XCTUnwrap(coordinator),
                diagnosticsStore: diagnostics)
            return XCTFail("The original pointer-switch interruption was not reached")
        } catch {
            guard error as? EraseAllServiceError == .injectedFailure else {
#if DEBUG
                let category: String
                if error is GenerationLeaseRegistryFailureV1 {
                    category = "registry"
                } else if error is EraseAllServiceError {
                    category = "erase"
                } else if error is AppAccessContractFailureV1 {
                    category = "app-access"
                } else {
                    category = "other"
                }
                let fixed = fixedStages.last ?? "none"
                let history = fixedStages.joined(separator: ",")
                FileHandle.standardError.write(Data(
                    ("ORIGINAL_APPACCESS_ERASE_FIXED_V1 stage=" + fixed
                    + " category=" + category + " history=" + history
                    + "\n").utf8))
#endif
                throw error
            }
        }
        XCTAssertEqual(serviceCount, 1)
        XCTAssertFalse(presentation.isBusy)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(reservations.count, 1, "The interrupted original admits exactly once")
        let originalReservation = try XCTUnwrap(reservations.first)
        // Decode existing bytes directly: no reparative EraseIntentStore
        // construction may precede the production retry under test.
        let intent = try EraseIntentCodecV1.decode(Data(contentsOf: support
            .appendingPathComponent("FieldEvidenceErase/erase.json")))
        XCTAssertEqual(intent.phase, .emptyGenerationPrepared)
        XCTAssertEqual(intent.oldGenerationID, oldID)
        XCTAssertEqual(Set(intent.generationIDsToDelete), Set(priorIDs + [oldID]))
        let priorFactory = StoreGenerationFactory(applicationSupportURL: support)
        let retiredAtCut = try JSONDecoder().decode(RetiredPointerV1.self,
            from: Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/retired.json")))
        XCTAssertEqual(Set(retiredAtCut.generationIDs),
            Set((priorIDs + [oldID]).map { $0.uuidString.lowercased() }))
        for id in priorIDs {
            XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent(
                "FieldEvidenceOperations/schema-migration/manifest-\(id.uuidString.lowercased()).json")),
                try XCTUnwrap(priorManifestBytes[id]))
            XCTAssertEqual(try XCTUnwrap(FileManager.default.attributesOfItem(atPath:
                priorFactory.installedGenerationURL(id: id).path)[.systemFileNumber] as? NSNumber),
                try XCTUnwrap(priorInodes[id]))
        }
        XCTAssertEqual(intent.newGenerationID, originalReservation.subject.newGenerationID)
        XCTAssertEqual(intent.eraseID, originalReservation.subject.eraseID)
        guard case .v3(let pointer, _) = try CurrentPointerCodecV1.decode(
            Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/current.json"))) else {
            return XCTFail("The real pointer switch must publish the current pointer schema")
        }
        XCTAssertEqual(UUID(uuidString: pointer.generationID), intent.newGenerationID,
            "Retry must enter the target-current recovery branch")
        weak var originalCoordinator = coordinator
        coordinator = nil
        XCTAssertNotNil(originalCoordinator, "The actual pending operation must retain its source owner")
        let ready = expectation(description: "Same presentation retry completes and publishes target")
        let retryPublication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in ready.fulfill() }
        defer { retryPublication.cancel() }
#if DEBUG
        var retryDiagnosticCount = 0
        presentation.eraseRecoveryDiagnosticForTesting = { fixedMessage in
            guard retryDiagnosticCount < 32 else { return }
            retryDiagnosticCount += 1
            FileHandle.standardError.write(Data(
                ("ORIGINAL_APPACCESS_RETRY_V1 " + fixedMessage + "\n").utf8))
        }
        defer { presentation.eraseRecoveryDiagnosticForTesting = nil }
#endif
        await presentation.retryStartup()
#if DEBUG
        if !presentation.permitsContentPresentation {
            FileHandle.standardError.write(Data(
                ("ORIGINAL_APPACCESS_RETRY_SERVICE_V1 stage="
                + (retryStages.last ?? "none")
                + " history=" + retryStages.joined(separator: ",")
                + "\n").utf8))
        }
#endif
        await fulfillment(of: [ready], timeout: 30)
        XCTAssertEqual(serviceCount, 2, "Retry must use the retained original operation's service factory")
        XCTAssertEqual(reservations.count, 2, "One original admission and one checked recovery admission")
        XCTAssertTrue(reservations.allSatisfy { $0 == originalReservation })
#if DEBUG
        XCTAssertEqual(transferredSourceChecks, 2 * (priorIDs.count + 1),
            "The retained retry must reach both presence-validation passes for old plus both prior sources")
#endif
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.subject, originalReservation.subject)
        XCTAssertTrue(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.failure)
        XCTAssertNil(originalCoordinator)
        guard case let .ready(recovered, _, _) = router.route else {
            return XCTFail("Original retry did not publish its target")
        }
        XCTAssertEqual(recovered.generationID, intent.newGenerationID)
        for id in priorIDs {
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                StoreGenerationFactory(applicationSupportURL: support)
                    .installedGenerationURL(id: id).path),
                "A successful same-owner retry must remove every prior retired generation")
        }
        XCTAssertEqual(try recovered.workspaceWriter.currentRevision().generationID,
            intent.newGenerationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support
            .appendingPathComponent("FieldEvidenceErase").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            StoreGenerationFactory(applicationSupportURL: support)
                .installedGenerationURL(id: oldID).path))
    }

    @MainActor
    func testOriginalRetryRefusesNestedOperationsSubstitutionBeforePriorRead() async throws {
#if DEBUG
        let suiteName = "V23.ProductionAppAccess.original-operations-hostile.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-operations-hostile-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        let temporary = root.appendingPathComponent("tmp")
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory,
                withIntermediateDirectories: true)
        }
        let priorIDs = try makeOriginalRetryRetiredSources(support: support)
        let system = ProductionAccessNotificationSystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router,
            defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(),
            notificationSystem: system)
        var serviceCount = 0
        var reservations = [AppAccessGateV1.EraseAdoptionToken]()
        var completions = [CompletedEraseReceiptV1]()
        var transferredChecks = 0
        var injectionOrdinal: Int?
        var oldLiveReadbacks = 0
        var injectionFailed = false
        var controlCut: [String: Data]?
        let controlNames = ["FieldEvidenceErase/erase.json",
            "FieldEvidenceData/current.json",
            "FieldEvidenceData/retired.json"]
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                serviceCount += 1
                let service = EraseAllService(applicationSupportURL: support,
                    cachesDirectoryURL: caches,
                    temporaryDirectoryURL: temporary,
                    userDefaults: defaults, defaultsDomainName: suiteName,
                    failureInjection: serviceCount == 1
                        ? EraseAllFailureInjection(failOnceAt: .afterPointerSwitch)
                        : nil,
                    sceneNavigationStatePort: sceneState,
                    privateSystemDiscoveryIndex: nil,
                    notificationSystem: system,
                    admitErase: { subject in
                        let actualAdmission = try XCTUnwrap(admission)
                        let token = try await actualAdmission(subject)
                        reservations.append(token)
                        return token
                    }, didCompleteErase: { receipt in
                        completions.append(receipt)
                        completion?(receipt)
                    }, didAbortEraseAdmission: aborted)
                if serviceCount == 2 {
                    service.v949RetainedSourceReadbackForTesting = { _, _ in
                        oldLiveReadbacks += 1
                    }
                    service.schema2ColdFixedStageForTesting = { stage in
                        guard stage == "recovery.presence.transferred-prior-enter" else {
                            return
                        }
                        transferredChecks += 1
                        guard let injectionOrdinal,
                              transferredChecks == injectionOrdinal else {
                            return
                        }
                        let scratch = support.appendingPathComponent(
                            "FieldEvidenceOperations/ScratchDataV1",
                            isDirectory: true)
                        var isDirectory: ObjCBool = false
                        guard FileManager.default.fileExists(atPath: scratch.path,
                                isDirectory: &isDirectory), isDirectory.boolValue else {
                            injectionFailed = true
                            return
                        }
                        do {
                            controlCut = try Dictionary(uniqueKeysWithValues:
                                controlNames.map { name in
                                    (name, try Data(contentsOf:
                                        support.appendingPathComponent(name)))
                                })
                            let hostile = scratch.appendingPathComponent(
                                "foreign-child-\(UUID().uuidString)")
                            try Data("foreign".utf8).write(to: hostile,
                                options: .atomic)
                        } catch {
                            injectionFailed = true
                        }
                    }
                }
                return service
            }, sessionFactory: { session })
        // A failed retry may retain checked descriptors; preserve its owners.
        Self.retainedDeferredEraseOwners.append((root, router, session,
            presentation))
        let published = expectation(description: "Hostile fixture original ready")
        let startup = presentation.$permitsContentPresentation.filter { $0 }
            .prefix(1).sink { _ in published.fulfill() }
        defer { startup.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        let coordinator: StoreSessionCoordinator
        let diagnostics: DiagnosticsStore
        switch router.route {
        case let .ready(value, store, _):
            coordinator = value; diagnostics = store
        default: return XCTFail("Original fixture did not become ready")
        }
        let oldID = coordinator.generationID
        do {
            try await presentation.performErase(applicationSupportURL: support,
                confirmation: "ERASE", coordinator: coordinator,
                diagnosticsStore: diagnostics)
            return XCTFail("The after-pointer interruption was not reached")
        } catch {
            XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
        }
        let intent = try EraseIntentCodecV1.decode(Data(contentsOf:
            support.appendingPathComponent("FieldEvidenceErase/erase.json")))
        XCTAssertEqual(intent.phase, .emptyGenerationPrepared)
        XCTAssertEqual(Set(intent.generationIDsToDelete),
            Set(priorIDs + [oldID]))
        let firstPriorIndex = try XCTUnwrap(intent.generationIDsToDelete
            .firstIndex(where: { priorIDs.contains($0) }))
        injectionOrdinal = firstPriorIndex + 1
        guard case .v3(let pointer, _) = try CurrentPointerCodecV1.decode(
            Data(contentsOf: support.appendingPathComponent(
                "FieldEvidenceData/current.json"))) else {
            return XCTFail("The real target pointer was not published")
        }
        XCTAssertEqual(UUID(uuidString: pointer.generationID),
            intent.newGenerationID)
        await presentation.retryStartup()
        XCTAssertEqual(serviceCount, 2)
        XCTAssertEqual(transferredChecks, try XCTUnwrap(injectionOrdinal),
            "The nested substitution must occur at a real prior read")
        XCTAssertFalse(injectionFailed)
        let expected = try XCTUnwrap(controlCut)
        for name in controlNames {
            XCTAssertEqual(try Data(contentsOf:
                support.appendingPathComponent(name)),
                try XCTUnwrap(expected[name]),
                "A hostile prior read must not advance durable controls")
        }
        let afterIntent = try EraseIntentCodecV1.decode(
            try XCTUnwrap(expected["FieldEvidenceErase/erase.json"]))
        XCTAssertEqual(afterIntent.phase, .pointerSwitched)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertNotNil(presentation.failure)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(reservations.count, 2)
        let originalReservation = try XCTUnwrap(reservations.first)
        XCTAssertTrue(reservations.allSatisfy { $0 == originalReservation })
        XCTAssertEqual(oldLiveReadbacks, 0,
            "The original retry must not open old source live")
        for id in priorIDs + [oldID] {
            XCTAssertTrue(FileManager.default.fileExists(atPath:
                StoreGenerationFactory(applicationSupportURL: support)
                    .installedGenerationURL(id: id).path))
        }
#else
        throw XCTSkip("Requires the DEBUG original-recovery substitution seam")
#endif
    }

    @MainActor
    private func makeOriginalRetryRetiredSources(support: URL) throws -> [UUID] {
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        var retired: [UUID] = []
        for _ in 0..<2 {
            let observed = try autoreleasepool { () throws ->
                (CurrentGenerationPointerV3, WorkspaceReplicaIdentityV1) in
                let session = try factory.openOrBootstrapCurrent()
                return (try factory.currentGenerationPointerV3(
                    expectedGenerationID: session.generationID),
                    session.workspaceIdentity)
            }
            let pointer = observed.0
            let oldID = try XCTUnwrap(UUID(uuidString: pointer.generationID))
            let identity = RestorePointerIdentityV1(generationID: oldID,
                generationManifestSHA256: pointer.generationManifestSHA256,
                knownReplicaIDs: Set(try pointer.knownReplicaIdentitySet().map(\.rawValue)),
                workspaceID: observed.1.workspaceID.rawValue,
                replicaID: observed.1.replicaID.rawValue)
            let authority = try factory.makeRestoreGenerationAuthority()
            let nextID = UUID()
            let created = try factory.createEmptyEraseGeneration(id: nextID,
                expectedOldPointer: identity, identity: observed.1, authority: authority)
            try factory.publishEmptyEraseGeneration(expectedOldPointer: identity,
                targetPointer: created.pointer, expectedEmptyLedger: created.ledgerProof,
                authority: authority)
            try factory.retireGeneration(oldID: oldID, currentID: nextID,
                authority: authority)
            retired.append(oldID)
            XCTAssertEqual(try factory.currentGenerationID(), nextID)
            XCTAssertEqual(Set(try factory.retiredGenerationIDs()), Set(retired))
        }
        XCTAssertEqual(try factory.makeGenerationLeaseRegistry().activeEpochs(), [])
        return retired
    }

    @MainActor
    func testPresentationConsumesAuthenticAbortAndASecondEraseUsesNewAuthority() async throws {
        let suiteName = "V23.ProductionAppAccess.abort.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-abort-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        let temporary = root.appendingPathComponent("tmp")
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let system = ProductionAccessNotificationSystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        var serviceCount = 0
        let originalScenePort = session.sceneNavigationStatePort()
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                XCTAssertTrue(sceneState === originalScenePort)
                serviceCount += 1
                return EraseAllService(applicationSupportURL: support, cachesDirectoryURL: caches,
                    temporaryDirectoryURL: temporary, userDefaults: defaults, defaultsDomainName: suiteName,
                    failureInjection: serviceCount == 1
                        ? EraseAllFailureInjection(failOnceAt: .afterEmptyGenerationDirectoryCreate) : nil,
                    sceneNavigationStatePort: sceneState, privateSystemDiscoveryIndex: nil, notificationSystem: system,
                    admitErase: admission, didCompleteErase: completion,
                    didAbortEraseAdmission: aborted)
            }, sessionFactory: { session })
        let published = expectation(description: "Actual production startup publishes the abort owner")
        let publication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { publication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        guard case .ready(let originalCoordinator, let originalDiagnostics, _) = router.route else {
            return XCTFail("Production startup did not publish its original Erase owner")
        }
        let originalGeneration = originalCoordinator.generationID
        let originalScene = try XCTUnwrap(presentation.sceneNavigationAccess)
        let sceneSnapshot = try SceneNavigationSnapshotV1(workspaceID: originalCoordinator.workspaceID,
            selectedRoot: .work, paths: AppRootV1.frozenOrder.map { .init(root: $0, targets: []) },
            snapshotID: UUID())
        try originalScene.save(sceneSnapshot)
        let originalSceneBytes = try XCTUnwrap(originalScenePort.loadSceneNavigationData())

        do {
            try await presentation.performErase(applicationSupportURL: support,
                confirmation: "ERASE", coordinator: originalCoordinator,
                diagnosticsStore: originalDiagnostics)
            XCTFail("The first service must return its injected pre-intent failure")
        } catch {
            XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
        }
        XCTAssertEqual(serviceCount, 1)
        XCTAssertEqual(try originalScenePort.loadSceneNavigationData(), originalSceneBytes)
        XCTAssertThrowsError(try originalScene.load())
        XCTAssertFalse(presentation.isBusy)
        XCTAssertFalse(presentation.permitsContentPresentation)
        let retainedAbort = await session.lifecycle.pendingAbortedEraseAdmissionReceipt()
        let retainedCompletion = await session.lifecycle.pendingCompletedEraseReceipt()
        XCTAssertNil(retainedAbort)
        XCTAssertNil(retainedCompletion)
        XCTAssertNil(try EraseIntentStore(applicationSupportURL: support).load())
        XCTAssertNil(try EraseIntentStore(applicationSupportURL: support).loadPreparation())
        XCTAssertEqual(try StoreGenerationFactory(applicationSupportURL: support).currentGenerationID(),
            originalGeneration)

        await presentation.retryStartup()
        guard case .ready(let retryCoordinator, let retryDiagnostics, _) = router.route else {
            return XCTFail("The consumed abort must permit a fresh ticketed startup")
        }
        XCTAssertTrue(presentation.permitsContentPresentation)
        try await presentation.performErase(applicationSupportURL: support,
            confirmation: "ERASE", coordinator: retryCoordinator,
            diagnosticsStore: retryDiagnostics)
        XCTAssertEqual(serviceCount, 2)
        XCTAssertNotEqual(retryCoordinator.generationID, originalGeneration)
        XCTAssertTrue(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.failure)
        XCTAssertNil(try originalScenePort.loadSceneNavigationData())
        let freshScenePort = session.sceneNavigationStatePort()
        XCTAssertFalse(freshScenePort === originalScenePort)
        XCTAssertNil(try freshScenePort.loadSceneNavigationData())
        XCTAssertEqual(try SceneNavigationStateAdapterV1(
            port: PreferencesAdapterV1(defaults: defaults)).loadAndReconcile(), .absent)
        XCTAssertThrowsError(try originalScene.load())
        XCTAssertEqual(try XCTUnwrap(presentation.sceneNavigationAccess).load(), .absent)
        let gateAfterRetry = await session.lifecycle.accessGate()
        XCTAssertTrue(gateAfterRetry === session.gate)
    }

    @MainActor
    func testPresentationDeferredEraseRetainsDrainAcrossPauseAndResumesWithFreshService() async throws {
        let suiteName = "V23.ProductionAppAccess.deferred.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-deferred-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        let temporary = root.appendingPathComponent("tmp")
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // The retired operation and fresh published owner can still hold
        // descriptors at test return. Retain their exact root and shells.
        let system = ProductionAccessNotificationSystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        var serviceCount = 0
        var completedReceipts = [CompletedEraseReceiptV1]()
        let originalScenePort = session.sceneNavigationStatePort()
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                XCTAssertTrue(sceneState === originalScenePort)
                serviceCount += 1
                return EraseAllService(applicationSupportURL: support, cachesDirectoryURL: caches,
                    temporaryDirectoryURL: temporary, userDefaults: defaults, defaultsDomainName: suiteName,
                    sleeper: ProductionAccessImmediateSleeper(), sceneNavigationStatePort: sceneState, privateSystemDiscoveryIndex: nil,
                    notificationSystem: system, admitErase: admission,
                    didCompleteErase: { receipt in
                        completedReceipts.append(receipt)
                        XCTAssertNotNil(completion)
                        completion?(receipt)
                    }, didAbortEraseAdmission: aborted)
            }, sessionFactory: { session })
        Self.retainedDeferredEraseOwners.append((root, router, session, presentation))
        let published = expectation(description: "Actual production startup publishes the deferred Erase owner")
        let publication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { publication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        var coordinator: StoreSessionCoordinator?
        let diagnostics: DiagnosticsStore
        switch router.route {
        case let .ready(published, value, _):
            coordinator = published
            diagnostics = value
        default:
            return XCTFail("Production startup did not publish its original Erase owner")
        }
        let originalGeneration = try XCTUnwrap(coordinator).generationID
        let originalGenerationRoot = try XCTUnwrap(coordinator).generationRootURL
        let originalRootIdentity = try BackupPackageAnchoredFile.rootIdentity(
            at: originalGenerationRoot)
        let originalScene = try XCTUnwrap(presentation.sceneNavigationAccess)
        let sceneSnapshot = try SceneNavigationSnapshotV1(workspaceID: XCTUnwrap(coordinator).workspaceID,
            selectedRoot: .work, paths: AppRootV1.frozenOrder.map { .init(root: $0, targets: []) },
            snapshotID: UUID())
        try originalScene.save(sceneSnapshot)
        let originalSceneBytes = try XCTUnwrap(originalScenePort.loadSceneNavigationData())
        var retainedOldContext: ModelContext? = try XCTUnwrap(coordinator).modelContext
        var retainedOldContainer: ModelContainer? = retainedOldContext?.container
        weak var weakOldContext = retainedOldContext
        weak var weakOldContainer = retainedOldContainer

        try await presentation.performErase(applicationSupportURL: support,
            confirmation: "ERASE", coordinator: try XCTUnwrap(coordinator), diagnosticsStore: diagnostics)
        XCTAssertEqual(serviceCount, 1)
        XCTAssertTrue(completedReceipts.isEmpty)
        // Preparation clears device-local scene state before the covered
        // retirement returns, while the source generation remains physically
        // retained until the actual reader drain permits cleanup.
        XCTAssertNil(try originalScenePort.loadSceneNavigationData())
        XCTAssertFalse(originalSceneBytes.isEmpty)
        XCTAssertEqual(try BackupPackageAnchoredFile.rootIdentity(
            at: originalGenerationRoot), originalRootIdentity)
        XCTAssertThrowsError(try originalScene.load())
        XCTAssertFalse(presentation.permitsContentPresentation)
        guard case let .eraseCleanupPending(.retiring(originalOperation)) = router.route else {
            return XCTFail("A live original context must retain the actual retirement operation")
        }
        XCTAssertTrue(originalOperation.detached)
        XCTAssertTrue(originalOperation.hasPreparedCleanup)
        let pendingIntent = try XCTUnwrap(EraseIntentStore(applicationSupportURL: support).load())
        let preparedGeneration = pendingIntent.newGenerationID
        XCTAssertEqual(try XCTUnwrap(coordinator).generationID, preparedGeneration)
        XCTAssertNotEqual(preparedGeneration, originalGeneration)
        XCTAssertEqual(try BackupPackageAnchoredFile.rootIdentity(
            at: originalGenerationRoot), originalRootIdentity)
        XCTAssertNotNil(weakOldContext)
        XCTAssertNotNil(weakOldContainer)
        XCTAssertEqual(try EraseIntentStore(applicationSupportURL: support).load()?.newGenerationID,
            preparedGeneration)

        let inactiveHandled = expectation(description: "Lifecycle handles scene inactive")
        let inactiveReceipt = presentation.$accessState.dropFirst().prefix(1)
            .sink { _ in inactiveHandled.fulfill() }
        presentation.receive(.sceneInactive)
        await fulfillment(of: [inactiveHandled], timeout: 30)
        inactiveReceipt.cancel()
        let inactiveCover = await session.gate.privacyCoverRequired()
        XCTAssertTrue(inactiveCover)
        guard case let .eraseCleanupPending(.retiring(pausedOperation)) = router.route else {
            return XCTFail("Scene pause must retain the same deferred retirement operation")
        }
        XCTAssertTrue(pausedOperation === originalOperation)
        XCTAssertTrue(completedReceipts.isEmpty)

        let backgroundHandled = expectation(description: "Lifecycle handles scene background")
        let backgroundReceipt = presentation.$accessState.dropFirst().prefix(1)
            .sink { _ in backgroundHandled.fulfill() }
        presentation.receive(.sceneBackground)
        await fulfillment(of: [backgroundHandled], timeout: 30)
        backgroundReceipt.cancel()
        let backgroundCover = await session.gate.privacyCoverRequired()
        XCTAssertTrue(backgroundCover)
        guard case let .eraseCleanupPending(.retiring(backgroundOperation)) = router.route else {
            return XCTFail("Background must retain the same deferred retirement operation")
        }
        XCTAssertTrue(backgroundOperation === originalOperation)
        XCTAssertTrue(completedReceipts.isEmpty)

        let activeHandled = expectation(description: "Lifecycle handles scene active")
        let activeReceipt = presentation.$accessState.dropFirst().prefix(1)
            .sink { _ in activeHandled.fulfill() }
        presentation.receive(.sceneActive)
        await fulfillment(of: [activeHandled], timeout: 30)
        activeReceipt.cancel()
        let activeCover = await session.gate.privacyCoverRequired()
        XCTAssertTrue(activeCover)
        guard case let .eraseCleanupPending(.retiring(activeOperation)) = router.route else {
            return XCTFail("Active transition must retain the same deferred retirement operation")
        }
        XCTAssertTrue(activeOperation === originalOperation)
        XCTAssertTrue(completedReceipts.isEmpty)

        // Transfer invalidates this writer before returning to presentation.
        // Observe its exact object without retaining its adapter/context.
        weak var weakPreCleanupWriter = coordinator?.workspaceWriter
        weak var weakPreparedCoordinator = coordinator
        coordinator = nil
        let oldContextReleased = expectation(for: NSPredicate { _, _ in
            weakOldContext == nil && weakOldContainer == nil
                && weakPreparedCoordinator == nil && weakPreCleanupWriter == nil
        },
            evaluatedWith: NSObject())
        retainedOldContext = nil
        retainedOldContainer = nil
        await fulfillment(of: [oldContextReleased], timeout: 30)
        XCTAssertNil(weakOldContext)
        XCTAssertNil(weakOldContainer)
        XCTAssertNil(weakPreparedCoordinator)
        XCTAssertNil(weakPreCleanupWriter)
        presentation.eraseRecoveryDiagnosticForTesting = { print("EraseProduction.retry " + $0) }
        await presentation.retryStartup()
        XCTAssertEqual(serviceCount, 1)
        XCTAssertEqual(completedReceipts.count, 1)
        XCTAssertEqual(completedReceipts.first?.subject.newGenerationID, preparedGeneration)
        XCTAssertTrue(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.failure)
        // Fresh activation must preserve the completed physical cleanup.
        XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: support))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: support.appendingPathComponent("FieldEvidenceErase", isDirectory: true).path))
        guard case let .ready(recoveredCoordinator, _, _) = router.route else {
            return XCTFail("Fresh-service recovery must publish the retained ticket's Erase session")
        }
        XCTAssertEqual(recoveredCoordinator.generationID, preparedGeneration)
        XCTAssertNil(weakPreparedCoordinator)
        XCTAssertNil(weakPreCleanupWriter)
        let freshWriterRevision = try recoveredCoordinator.workspaceWriter.currentRevision()
        XCTAssertEqual(freshWriterRevision.generationID, preparedGeneration)
        XCTAssertNil(try originalScenePort.loadSceneNavigationData())
        let freshScenePort = session.sceneNavigationStatePort()
        XCTAssertFalse(freshScenePort === originalScenePort)
        XCTAssertNil(try freshScenePort.loadSceneNavigationData())
        XCTAssertEqual(try SceneNavigationStateAdapterV1(
            port: PreferencesAdapterV1(defaults: defaults)).loadAndReconcile(), .absent)
        XCTAssertThrowsError(try originalScene.load())
        XCTAssertEqual(try XCTUnwrap(presentation.sceneNavigationAccess).load(), .absent)
        let gateAfterRecovery = await session.lifecycle.accessGate()
        XCTAssertTrue(gateAfterRecovery === session.gate)
    }

    @MainActor
    func testProductionEraseAdoptsFreshSettingOwnerAndNextToggleCommits() async throws {
        var diagnosticPhase = "setup"
        defer { print("ProductionEraseOwner.exit phase=" + diagnosticPhase) }
        let suiteName = "V23.ProductionAppAccess.erase.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-erase-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        let temporary = root.appendingPathComponent("tmp")
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let system = ProductionAccessNotificationSystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        let originalScenePort = session.sceneNavigationStatePort()
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                XCTAssertTrue(sceneState === originalScenePort)
                return EraseAllService(applicationSupportURL: support, cachesDirectoryURL: caches,
                    temporaryDirectoryURL: temporary, userDefaults: defaults, defaultsDomainName: suiteName,
                    sceneNavigationStatePort: sceneState, privateSystemDiscoveryIndex: nil, notificationSystem: system,
                    admitErase: admission, didCompleteErase: completion, didAbortEraseAdmission: aborted)
            }, sessionFactory: { session })
        presentation.eraseRecoveryDiagnosticForTesting = {
            print("ProductionEraseOwner.trace " + $0)
        }
        let published = expectation(description: "Actual production startup publishes authorized content")
        let publication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { publication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        XCTAssertTrue(presentation.permitsContentPresentation)
        var coordinator: StoreSessionCoordinator?
        let diagnostics: DiagnosticsStore
        switch router.route {
        case let .ready(published, value, _):
            coordinator = published
            diagnostics = value
        default:
            return XCTFail("Production startup did not publish its sole coordinator")
        }
        let originalGeneration = try XCTUnwrap(coordinator).generationID
        let originalScene = try XCTUnwrap(presentation.sceneNavigationAccess)
        let sceneSnapshot = try SceneNavigationSnapshotV1(workspaceID: XCTUnwrap(coordinator).workspaceID,
            selectedRoot: .work, paths: AppRootV1.frozenOrder.map { .init(root: $0, targets: []) },
            snapshotID: UUID())
        try originalScene.save(sceneSnapshot)
        XCTAssertNotNil(try originalScenePort.loadSceneNavigationData())
        let originalGate = session.gate
        let preferences = PreferencesAdapterV1(defaults: defaults)
        let originalControl = try AppLockNotificationControlStoreV1(
            applicationSupportURL: support, preferences: preferences)
        diagnosticPhase = "perform-erase"
        try await presentation.performErase(applicationSupportURL: support,
            confirmation: "ERASE", coordinator: try XCTUnwrap(coordinator), diagnosticsStore: diagnostics)
        let cleanupWasPending: Bool
        if case .eraseCleanupPending = router.route {
            cleanupWasPending = true
            XCTAssertFalse(presentation.permitsContentPresentation)
            XCTAssertNil(presentation.sceneNavigationAccess)
            XCTAssertNotNil(try EraseIntentStore(applicationSupportURL: support).load())
            XCTAssertTrue(session.sceneNavigationStatePort() === originalScenePort)
        } else {
            cleanupWasPending = false
        }
        // The original coordinator owns its session, context, writer and
        // leases. Keep only value identities before attempting cold recovery.
        weak var weakOriginalCoordinator = coordinator
        coordinator = nil
        if cleanupWasPending {
            let originalReleased = expectation(for: NSPredicate { _, _ in
                weakOriginalCoordinator == nil
            }, evaluatedWith: NSObject())
            await fulfillment(of: [originalReleased], timeout: 30)
            XCTAssertNil(weakOriginalCoordinator)
            diagnosticPhase = "retry-startup"
            await presentation.retryStartup()
            // The automatic continuation may already own recovery, in which
            // case retryStartup correctly returns without starting another.
            // Observe that genuine action finishing before reading its result.
            let recoveryFinished = expectation(description: "Production Erase recovery action finishes")
            let recoveryCompletion = presentation.$isBusy.filter { !$0 }.prefix(1)
                .sink { _ in recoveryFinished.fulfill() }
            defer { recoveryCompletion.cancel() }
            await fulfillment(of: [recoveryFinished], timeout: 30)
            XCTAssertFalse(presentation.isBusy)
        }
        diagnosticPhase = "completed-owner-readback"
        guard case let .ready(recoveredCoordinator, _, _) = router.route else {
            let routeCategory: String
            switch router.route {
            case .checking: routeCategory = "checking"
            case .awaitingIndependentValidation: routeCategory = "awaiting-validation"
            case .eraseCleanupPending: routeCategory = "erase-pending"
            case .maintenance: routeCategory = "maintenance"
            case .ready: routeCategory = "ready"
            }
            let failureCategory: String
            switch presentation.failure {
            case nil: failureCategory = "none"
            case .bootstrap: failureCategory = "bootstrap"
            case .authentication: failureCategory = "authentication"
            case .configuration: failureCategory = "configuration"
            case .startup: failureCategory = "startup"
            case .lifecycle: failureCategory = "lifecycle"
            }
            print("ProductionEraseOwner.route route=" + routeCategory
                + " failure=" + failureCategory
                + " cleanupWasPending=" + String(cleanupWasPending)
                + " busy=" + String(presentation.isBusy))
            return XCTFail("Completed Erase did not publish a fresh coordinator")
        }
        XCTAssertNotEqual(recoveredCoordinator.generationID, originalGeneration)
        XCTAssertEqual(router.recoveryBootstrapState, .ready)
        XCTAssertTrue(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.failure)
        XCTAssertNil(try originalScenePort.loadSceneNavigationData())
        let freshScenePort = session.sceneNavigationStatePort()
        XCTAssertFalse(freshScenePort === originalScenePort)
        XCTAssertNil(try freshScenePort.loadSceneNavigationData())
        XCTAssertEqual(try SceneNavigationStateAdapterV1(
            port: PreferencesAdapterV1(defaults: defaults)).loadAndReconcile(), .absent)
        XCTAssertThrowsError(try originalScene.load())
        diagnosticPhase = "fresh-scene-access"
        XCTAssertEqual(try XCTUnwrap(presentation.sceneNavigationAccess).load(), .absent)
        let retainedGate = await session.lifecycle.accessGate()
        XCTAssertTrue(retainedGate === originalGate)
        diagnosticPhase = "original-control-denial"
        XCTAssertThrowsError(try originalControl.verifyNotificationStorage())
        diagnosticPhase = "fresh-control-open"
        let freshControl = try AppLockNotificationControlStoreV1(
            applicationSupportURL: support, preferences: preferences)
        diagnosticPhase = "fresh-control-read"
        XCTAssertNil(try freshControl.loadControl())

        diagnosticPhase = "enable"
        let enabled = try await session.lifecycle.enable(operationID: UUID())
        XCTAssertTrue(enabled.enabled)
        diagnosticPhase = "enabled-control-read"
        let enabledControl = try XCTUnwrap(freshControl.loadControl())
        XCTAssertEqual(enabledControl.phase, .settingCommitted)
        XCTAssertEqual(try preferences.readAppLockSettingSnapshot(), enabledControl.settingWrite.successor)
        let lockedState = await session.gate.currentState()
        XCTAssertEqual(lockedState, .locked(reason: .coldLaunch))
        diagnosticPhase = "locked-disable-denial"
        do {
            _ = try await session.lifecycle.disable(operationID: UUID())
            XCTFail("Disabling AppLock must require an unlocked app")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertEqual(try freshControl.loadControl(), enabledControl)
        XCTAssertEqual(try preferences.readAppLockSettingSnapshot(), enabledControl.settingWrite.successor)
        diagnosticPhase = "unlock-before-disable"
        let unlockOutcome = await session.gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlockOutcome, .authenticated)
#if DEBUG
        await session.lifecycle.setConfigurationPhaseDiagnosticForTesting { phase in
            print("ProductionEraseOwner.lifecycle." + phase)
        }
#endif
        diagnosticPhase = "disable"
        let disabled: AppLockConfigurationReceiptV1
        do {
            disabled = try await session.lifecycle.disable(operationID: UUID())
        } catch {
            let originalError = error
            let failureType = String(reflecting: type(of: originalError))
            let failureDomain = (originalError as NSError).domain
            let failureCode = (originalError as NSError).code
#if DEBUG
            let retainedPhases = await session.lifecycle.configurationPhasesForTesting()
#else
            let retainedPhases: [String] = ["diagnostics-unavailable"]
#endif
            let failureRecord = "ProductionEraseOwner.caught phase=\(retainedPhases.joined(separator: ">")) type=\(failureType) domain=\(failureDomain) code=\(failureCode)"
            XCTContext.runActivity(named: "Retained original failure before cleanup") { activity in
                let attachment = XCTAttachment(string: failureRecord)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            XCTFail(failureRecord)
            throw originalError
        }
        XCTAssertFalse(disabled.enabled)
        diagnosticPhase = "disabled-control-read"
        let disabledControl = try XCTUnwrap(freshControl.loadControl())
        XCTAssertEqual(disabledControl.phase, .settingCommitted)
        XCTAssertEqual(try preferences.readAppLockSettingSnapshot(), disabledControl.settingWrite.successor)
    }

    @MainActor
    func testFactorySettingTransactionsCompleteAndReopenWithoutRepair() async throws {
        let suiteName = "V23.ProductionAppAccess.transactions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-transactions-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let system = ProductionAccessNotificationSystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        try await router.startIfNeeded(accessGate: session.gate)
        XCTAssertEqual(router.recoveryBootstrapState, .ready)
        let preferences = PreferencesAdapterV1(defaults: defaults)
        let control = try AppLockNotificationControlStoreV1(
            applicationSupportURL: support, preferences: preferences)

        XCTAssertNil(try preferences.readStoredReminderPolicy())

        let enabled = try await session.lifecycle.enable(operationID: UUID())
        XCTAssertTrue(enabled.enabled)
        let initialPolicy = try XCTUnwrap(preferences.readStoredReminderPolicy())
        XCTAssertFalse(initialPolicy.isEnabled)
        XCTAssertEqual(initialPolicy.detail, .generic)
        XCTAssertEqual(initialPolicy.revision, 1)
        let enabledControl = try XCTUnwrap(control.loadControl())
        XCTAssertEqual(enabledControl.phase, .settingCommitted)
        XCTAssertEqual(try preferences.readAppLockSettingSnapshot(), enabledControl.settingWrite.successor)
        let reopenedEnabled = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: StartupRouter(applicationSupportURL: support),
            defaults: defaults, authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        let enabledState = await reopenedEnabled.gate.currentState()
        XCTAssertEqual(enabledState, .locked(reason: .coldLaunch))
        XCTAssertEqual(try control.loadControl(), enabledControl)

        let unlocked = await session.gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlocked, .authenticated)
        let disabled = try await session.lifecycle.disable(operationID: UUID())
        XCTAssertFalse(disabled.enabled)
        let disabledControl = try XCTUnwrap(control.loadControl())
        XCTAssertEqual(disabledControl.phase, .settingCommitted)
        XCTAssertEqual(try preferences.readAppLockSettingSnapshot(), disabledControl.settingWrite.successor)
        let reopenedDisabled = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: StartupRouter(applicationSupportURL: support),
            defaults: defaults, authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        let disabledState = await reopenedDisabled.gate.currentState()
        XCTAssertEqual(disabledState, .disabled)
        XCTAssertEqual(try control.loadControl(), disabledControl)
        XCTAssertEqual(try preferences.readStoredReminderPolicy(), initialPolicy)

        // A missing policy after a real completed configuration is not a
        // fresh-install default, and must not be silently recreated.
        defaults.removeObject(forKey: PreferencesAdapterV1.storagePrefix + DeviceLocalReminderPolicyV1.key)
        do {
            _ = try await session.lifecycle.enable(operationID: UUID())
            XCTFail("Expected missing established reminder policy to deny enable")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .notificationReconciliationRequired)
        }
        XCTAssertNil(try preferences.readStoredReminderPolicy())
        XCTAssertEqual(try control.loadControl(), disabledControl)
        let remainingRequests = try await system.observations()
        XCTAssertTrue(remainingRequests.isEmpty)
    }

    @MainActor
    func testFactoryKeepsStartupUnopenedAndBindsItsExactGateOnce() async throws {
        let suiteName = "V23.ProductionAppAccess.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionAppAccess-\(UUID().uuidString)")
        var begunSteps: [StartupStep] = []
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: support)
        }

        let router = StartupRouter(
            applicationSupportURL: support,
            didBeginStep: { begunSteps.append($0) }
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support,
            startupRouter: router,
            defaults: defaults
        )

        XCTAssertTrue(session.authentication is SystemLocalAuthenticationClient)
        let lifecycleGate = await session.lifecycle.accessGate()
        XCTAssertTrue(lifecycleGate === session.gate)
        XCTAssertEqual(begunSteps.count, 0)
        XCTAssertEqual(router.recoveryBootstrapState, .checking)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support
            .appendingPathComponent("FieldEvidenceData").path))

        let foreignGate = AppAccessGateV1(
            setting: .absentDisabled,
            authentication: SystemLocalAuthenticationClient(),
            clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource()
        )
        XCTAssertThrowsError(try router.bindStartupAccessGate(foreignGate)) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
    }
}

private actor ProductionAccessAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}

private struct ProductionAccessImmediateSleeper: ApplicationSleeper {
    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

@MainActor private final class ProductionAccessNotificationSystem: NotificationSystemPortV1 {
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

// These tests exercise the real production count model and disposable filesystem
// facts. They do not create an erase owner, permit, policy receipt, or authority.
final class V23EraseDirectoryEntryLinkModelTests: XCTestCase {
    private typealias Model = EraseDirectoryEntryLinkModelV1

    func testExpectedLinkCountsRequireExactNonnegativeCheckedDomain() {
        XCTAssertEqual(Int.bitWidth, 64)
        XCTAssertEqual(Model.expectedLinkCount(directEntryCount: 0), 2)
        XCTAssertEqual(Model.expectedLinkCount(directEntryCount: 1), 3)
        XCTAssertEqual(Model.expectedLinkCount(directEntryCount: 7), 9)
        XCTAssertEqual(Model.expectedLinkCount(directEntryCount: Int.max - 2), Int64.max)
        for invalid in [Int.min, -1, Int.max - 1, Int.max] {
            XCTAssertNil(Model.expectedLinkCount(directEntryCount: invalid))
        }
    }

    func testMatchesRefuseWrongBeforeAfterOffByOneAndDirectoryOnlyCounts() {
        for count in [0, 1, 2, 7] {
            let expected = Int64(count) + 2
            XCTAssertTrue(Model.matches(linkCount: expected, directEntryCount: count))
            XCTAssertFalse(Model.matches(linkCount: expected - 1, directEntryCount: count))
            XCTAssertFalse(Model.matches(linkCount: expected + 1, directEntryCount: count))
        }
        for invalidLinkCount in [Int64.min, -1, 0, 1] {
            XCTAssertFalse(Model.matches(linkCount: invalidLinkCount, directEntryCount: 0))
        }
        XCTAssertFalse(Model.matches(linkCount: 2, directEntryCount: -1))
        XCTAssertFalse(Model.matches(linkCount: 2, directEntryCount: Int.min))
        XCTAssertFalse(Model.matches(linkCount: Int64.max, directEntryCount: Int.max))
        XCTAssertTrue(Model.matches(linkCount: Int64.max, directEntryCount: Int.max - 2))

        // A file, its hard-link alias, and a directory are three names. A
        // directory-only or distinct-inode count must not substitute for them.
        XCTAssertTrue(Model.matches(linkCount: 5, directEntryCount: 3))
        XCTAssertFalse(Model.matches(linkCount: 3, directEntryCount: 3))
        XCTAssertFalse(Model.matches(linkCount: 4, directEntryCount: 3))
        // Retained-before and declared-after facts each have their own law.
        XCTAssertTrue(Model.matches(linkCount: 6, directEntryCount: 4))
        XCTAssertFalse(Model.matches(linkCount: 6, directEntryCount: 3))
        XCTAssertFalse(Model.matches(linkCount: 5, directEntryCount: 4))
        // An unaccounted extra or missing direct name cannot explain the
        // declared after count merely by changing the observed count input.
        XCTAssertFalse(Model.matches(linkCount: 7, directEntryCount: 4))
    }

    func testLinkDeltasValidateBothEndpointsIncludingZeroDeltaOverflow() {
        let cases: [(Int, Int, Int64?)] = [
            (0, 0, 0), (0, 1, 1), (1, 0, -1), (7, 7, 0),
            (0, Int.max - 2, Int64.max - 2),
            (Int.max - 2, 0, -(Int64.max - 2)),
            (-1, 0, nil), (0, -1, nil), (Int.min, Int.min, nil),
            (Int.max, Int.max, nil), (Int.max - 1, Int.max - 1, nil),
            (0, Int.max, nil), (Int.max, 0, nil)
        ]
        for (before, after, expected) in cases {
            XCTAssertEqual(Model.linkDelta(beforeDirectEntryCount: before,
                                           afterDirectEntryCount: after), expected)
        }
        // An absent same-parent rename keeps two names; replacing an existing
        // final removes one declared name. Neither delta uses observed nlink.
        XCTAssertEqual(Model.linkDelta(beforeDirectEntryCount: 2, afterDirectEntryCount: 2), 0)
        XCTAssertEqual(Model.linkDelta(beforeDirectEntryCount: 2, afterDirectEntryCount: 1), -1)
    }

    func testDirectEntryCountRequiresExactParentAndOneNonemptyComponent() {
        let paths: Set<String> = [
            "", "ScratchDataV1", "ScratchDataV1/", "ScratchDataV1/source",
            "ScratchDataV1/alias", "ScratchDataV1/directory",
            "ScratchDataV1/directory/descendant", "ScratchDataV1//malformed",
            "ScratchDataV10/prefix-neighbor", "ScratchDataV1-other/source",
            "ProtectedIngressReceiptsV1/receipt", "/ScratchDataV1/absolute"
        ]
        XCTAssertEqual(Model.directEntryCount(paths: paths, parentPath: "ScratchDataV1"), 3)
        XCTAssertEqual(Model.directEntryCount(paths: paths, parentPath: "ScratchDataV1/directory"), 1)
        XCTAssertEqual(Model.directEntryCount(paths: paths, parentPath: "ProtectedIngressReceiptsV1"), 1)
        XCTAssertEqual(Model.directEntryCount(paths: paths, parentPath: "absent"), 0)
        XCTAssertEqual(Model.directEntryCount(paths: ["source", "alias"], parentPath: ""), 2)
        XCTAssertEqual(Model.directEntryCount(paths: [], parentPath: ""), 0)
    }

    func testCompleteRootNamesIncludeUnwalkedAnchorsAndExcludeDescendants() {
        let paths: Set<String> = [
            "ScratchDataV1", "ProtectedIngressReceiptsV1", "unwalked-file-anchor",
            "unwalked-directory-anchor", "ScratchDataV1/partial",
            "ProtectedIngressReceiptsV1/receipt", "unwalked-directory-anchor/child",
            "", "trailing/", "/absolute"
        ]
        let roots: Set<String> = ["ScratchDataV1", "ProtectedIngressReceiptsV1",
                                  "unwalked-file-anchor", "unwalked-directory-anchor"]
        XCTAssertEqual(Model.directEntryCount(paths: paths, parentPath: ""), roots.count)
        XCTAssertTrue(Model.matches(linkCount: 6, directEntryCount: roots.count))
        XCTAssertFalse(Model.matches(linkCount: 6, directEntryCount: 2))

        // Equal counts do not establish exact namespace closure. That remains
        // a production observer obligation, covered by the unchanged tests.
        let substituted: Set<String> = ["ScratchDataV1", "ProtectedIngressReceiptsV1",
                                        "unwalked-file-anchor", "undeclared-root"]
        XCTAssertEqual(Model.directEntryCount(paths: substituted, parentPath: ""), roots.count)
        XCTAssertNotEqual(substituted, roots)
    }

    func testDisposablePrimitivesKeepHeldNamedFactsAndDeclaredParentEntryDeltas() throws {
        let operations = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-DirectoryEntryLinkModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: operations, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        var descriptors: [Int32] = []
        defer {
            for descriptor in descriptors.reversed() {
                XCTAssertEqual(Darwin.close(descriptor), 0)
            }
            try? FileManager.default.removeItem(at: operations)
        }
        let operationsFD = try openDirectory(operations)
        descriptors.append(operationsFD)
        let scratch = operations.appendingPathComponent("ScratchDataV1", isDirectory: true)
        let ingress = operations.appendingPathComponent("ProtectedIngressReceiptsV1", isDirectory: true)

        try assertDeclaredTransition(in: operationsFD, at: operations, before: [],
                                     after: ["ScratchDataV1"], delta: 1) {
            try requireZero(Darwin.mkdir(scratch.path, mode_t(0o700)))
        }
        try assertDeclaredTransition(in: operationsFD, at: operations, before: ["ScratchDataV1"],
                                     after: ["ScratchDataV1", "ProtectedIngressReceiptsV1"], delta: 1) {
            try requireZero(Darwin.mkdir(ingress.path, mode_t(0o700)))
        }
        var anchorFD: Int32 = -1
        try assertDeclaredTransition(in: operationsFD, at: operations,
                                     before: ["ScratchDataV1", "ProtectedIngressReceiptsV1"],
                                     after: ["ScratchDataV1", "ProtectedIngressReceiptsV1", "unwalked-anchor"], delta: 1) {
            anchorFD = try createEmptyFile(parent: operationsFD, name: "unwalked-anchor")
            descriptors.append(anchorFD)
        }
        let operationsBaseline = try snapshot(operationsFD, at: operations)
        XCTAssertEqual(operationsBaseline.names.count, 3)
        XCTAssertEqual(operationsBaseline.links, 5)
        let untouchedOperations = (operationsFD, operations)
        let ingressFD = try openDirectory(ingress)
        descriptors.append(ingressFD)

        var temporaryFD: Int32 = -1
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: [],
                                     after: ["temporary"], delta: 1, untouchedRoot: untouchedOperations) {
            temporaryFD = try createEmptyFile(parent: ingressFD, name: "temporary")
            descriptors.append(temporaryFD)
        }
        let originalFile = try assertFileHeldNamed(temporaryFD, at: ingress.appendingPathComponent("temporary"), links: 1)
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: ["temporary"],
                                     after: ["temporary", "published"], delta: 1, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.linkat(ingressFD, "temporary", ingressFD, "published", 0))
        }
        let linkedFile = try assertFileHeldNamed(temporaryFD, at: ingress.appendingPathComponent("temporary"), links: 2)
        assertStableMetadata(originalFile, linkedFile)
        assertFullFacts(linkedFile, try namedStat(ingress.appendingPathComponent("published")))
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: ["temporary", "published"],
                                     after: ["published"], delta: -1, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.unlinkat(ingressFD, "temporary", 0))
        }
        _ = try assertFileHeldNamed(temporaryFD, at: ingress.appendingPathComponent("published"), links: 1)
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: ["published"],
                                     after: ["renamed"], delta: 0, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.renameat(ingressFD, "published", ingressFD, "renamed"))
        }
        let renamedFile = try assertFileHeldNamed(temporaryFD, at: ingress.appendingPathComponent("renamed"), links: 1)
        assertStableMetadata(originalFile, renamedFile)

        var replacementFD: Int32 = -1
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: ["renamed"],
                                     after: ["renamed", "replacement"], delta: 1, untouchedRoot: untouchedOperations) {
            replacementFD = try createEmptyFile(parent: ingressFD, name: "replacement")
            descriptors.append(replacementFD)
        }
        let replacement = try assertFileHeldNamed(replacementFD, at: ingress.appendingPathComponent("replacement"), links: 1)
        XCTAssertNotEqual(replacement.st_ino, renamedFile.st_ino)
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: ["renamed", "replacement"],
                                     after: ["renamed"], delta: -1, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.renameat(ingressFD, "replacement", ingressFD, "renamed"))
        }
        let installed = try assertFileHeldNamed(replacementFD, at: ingress.appendingPathComponent("renamed"), links: 1)
        assertStableMetadata(replacement, installed)
        XCTAssertEqual(try heldStat(temporaryFD).st_nlink, 0)
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: ["renamed"],
                                     after: [], delta: -1, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.unlinkat(ingressFD, "renamed", 0))
        }
        XCTAssertEqual(try heldStat(replacementFD).st_nlink, 0)

        let lease = ingress.appendingPathComponent("lease", isDirectory: true)
        let tombstone = ingress.appendingPathComponent("tombstone", isDirectory: true)
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: [],
                                     after: ["lease"], delta: 1, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.mkdir(lease.path, mode_t(0o700)))
        }
        let leaseFD = try openDirectory(lease)
        descriptors.append(leaseFD)
        let ingressBeforeNestedCreate = try snapshot(ingressFD, at: ingress)
        var innerFD: Int32 = -1
        try assertDeclaredTransition(in: leaseFD, at: lease, before: [],
                                     after: ["inner"], delta: 1, untouchedRoot: untouchedOperations) {
            innerFD = try createEmptyFile(parent: leaseFD, name: "inner")
            descriptors.append(innerFD)
        }
        let innerBeforeRename = try assertFileHeldNamed(innerFD, at: lease.appendingPathComponent("inner"), links: 1)
        let leaseBeforeRename = try snapshot(leaseFD, at: lease)
        assertFullFacts(ingressBeforeNestedCreate.held, try snapshot(ingressFD, at: ingress).held)
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: ["lease"],
                                     after: ["tombstone"], delta: 0, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.renameat(ingressFD, "lease", ingressFD, "tombstone"))
        }
        let leaseAfterRename = try snapshot(leaseFD, at: tombstone)
        assertStableMetadata(leaseBeforeRename.held, leaseAfterRename.held)
        XCTAssertEqual(leaseAfterRename.names, ["inner"])
        XCTAssertEqual(leaseAfterRename.links, leaseBeforeRename.links)
        assertFullFacts(innerBeforeRename, try namedStat(tombstone.appendingPathComponent("inner")))
        let ingressBeforeNestedRemoval = try snapshot(ingressFD, at: ingress)
        try assertDeclaredTransition(in: leaseFD, at: tombstone, before: ["inner"],
                                     after: [], delta: -1, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.unlinkat(leaseFD, "inner", 0))
        }
        assertFullFacts(ingressBeforeNestedRemoval.held, try snapshot(ingressFD, at: ingress).held)
        try assertDeclaredTransition(in: ingressFD, at: ingress, before: ["tombstone"],
                                     after: [], delta: -1, untouchedRoot: untouchedOperations) {
            try requireZero(Darwin.rmdir(tombstone.path))
        }
        let operationsAfterNestedEffects = try snapshot(operationsFD, at: operations)
        XCTAssertEqual(operationsAfterNestedEffects.names, operationsBaseline.names)
        assertFullFacts(operationsBaseline.held, operationsAfterNestedEffects.held)
        _ = try assertFileHeldNamed(anchorFD, at: operations.appendingPathComponent("unwalked-anchor"), links: 1)

        try assertDeclaredTransition(in: operationsFD, at: operations,
                                     before: ["ScratchDataV1", "ProtectedIngressReceiptsV1", "unwalked-anchor"],
                                     after: ["ProtectedIngressReceiptsV1", "unwalked-anchor"], delta: -1) {
            try requireZero(Darwin.rmdir(scratch.path))
        }
        try assertDeclaredTransition(in: operationsFD, at: operations,
                                     before: ["ProtectedIngressReceiptsV1", "unwalked-anchor"],
                                     after: ["unwalked-anchor"], delta: -1) {
            try requireZero(Darwin.rmdir(ingress.path))
        }
        try assertDeclaredTransition(in: operationsFD, at: operations,
                                     before: ["unwalked-anchor"], after: [], delta: -1) {
            try requireZero(Darwin.unlinkat(operationsFD, "unwalked-anchor", 0))
        }
        let final = try snapshot(operationsFD, at: operations)
        XCTAssertEqual(final.names, [])
        XCTAssertEqual(final.links, 2)
    }

    private struct DirectorySnapshot {
        let held: stat
        let names: Set<String>
        let links: Int64
    }

    private enum FixtureFailure: Error {
        case syscall(Int32)
        case nonconformingDirectory
    }

    private func requireZero(_ result: Int32) throws {
        guard result == 0 else { throw FixtureFailure.syscall(errno) }
    }

    private func openDirectory(_ url: URL) throws -> Int32 {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw FixtureFailure.syscall(errno) }
        return descriptor
    }

    private func createEmptyFile(parent: Int32, name: String) throws -> Int32 {
        let descriptor = Darwin.openat(parent, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw FixtureFailure.syscall(errno) }
        return descriptor
    }

    private func heldStat(_ descriptor: Int32) throws -> stat {
        var value = stat()
        try requireZero(Darwin.fstat(descriptor, &value))
        return value
    }

    private func namedStat(_ url: URL) throws -> stat {
        var value = stat()
        try requireZero(Darwin.lstat(url.path, &value))
        return value
    }

    private func snapshot(_ descriptor: Int32, at url: URL) throws -> DirectorySnapshot {
        let before = try heldStat(descriptor)
        assertFullFacts(before, try namedStat(url))
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: url.path))
        let after = try heldStat(descriptor)
        assertFullFacts(before, after)
        assertFullFacts(after, try namedStat(url))
        return DirectorySnapshot(held: after, names: names,
                                 links: try XCTUnwrap(Int64(exactly: after.st_nlink)))
    }

    private func assertDeclaredTransition(in parent: Int32, at url: URL,
                                          before declaredBefore: Set<String>, after declaredAfter: Set<String>,
                                          delta declaredDelta: Int64, untouchedRoot: (Int32, URL)? = nil,
                                          effect: () throws -> Void) throws {
        let before = try snapshot(parent, at: url)
        let rootBefore = try untouchedRoot.map { try snapshot($0.0, at: $0.1) }
        // Build the relative model keys only from the declared parent URL and
        // declared names. Captured after names/nlink never choose a prediction.
        let parentPath: String
        if let untouchedRoot {
            let rootPrefix = untouchedRoot.1.path + "/"
            XCTAssertTrue(url.path.hasPrefix(rootPrefix))
            parentPath = String(url.path.dropFirst(rootPrefix.count))
        } else {
            parentPath = ""
        }
        let prefix = parentPath.isEmpty ? "" : parentPath + "/"
        let beforeKeys = Set(declaredBefore.map { prefix + $0 })
        let expectedKeys = Set(declaredAfter.map { prefix + $0 })
        let beforeCount = Model.directEntryCount(paths: beforeKeys, parentPath: parentPath)
        let afterCount = Model.directEntryCount(paths: expectedKeys, parentPath: parentPath)
        let predicted = try XCTUnwrap(Model.linkDelta(beforeDirectEntryCount: beforeCount,
                                                     afterDirectEntryCount: afterCount))
        XCTAssertEqual(predicted, declaredDelta)
        XCTAssertEqual(before.names, declaredBefore)
        // A nonconforming filesystem fails this fixture before any primitive;
        // there is no alternate law, skip, or learned post-effect allowance.
        guard Model.matches(linkCount: before.links, directEntryCount: beforeCount) else {
            XCTFail("Disposable directory does not satisfy the strict complete-name law")
            throw FixtureFailure.nonconformingDirectory
        }
        try effect()
        let after = try snapshot(parent, at: url)
        XCTAssertEqual(after.names, declaredAfter)
        XCTAssertTrue(Model.matches(linkCount: after.links, directEntryCount: afterCount))
        let actual = after.links.subtractingReportingOverflow(before.links)
        XCTAssertFalse(actual.overflow)
        XCTAssertEqual(actual.partialValue, predicted)
        assertStableMetadata(before.held, after.held)
        if let untouchedRoot, let rootBefore {
            let rootAfter = try snapshot(untouchedRoot.0, at: untouchedRoot.1)
            XCTAssertEqual(rootAfter.names, rootBefore.names)
            assertFullFacts(rootBefore.held, rootAfter.held)
        }
    }

    @discardableResult
    private func assertFileHeldNamed(_ descriptor: Int32, at url: URL, links: Int64) throws -> stat {
        let value = try heldStat(descriptor)
        assertFullFacts(value, try namedStat(url))
        XCTAssertEqual(value.st_mode & S_IFMT, S_IFREG)
        XCTAssertEqual(value.st_mode & 0o777, 0o600)
        XCTAssertEqual(value.st_size, 0)
        XCTAssertEqual(try XCTUnwrap(Int64(exactly: value.st_nlink)), links)
        XCTAssertEqual(try Data(contentsOf: url), Data())
        assertFullFacts(value, try heldStat(descriptor))
        assertFullFacts(value, try namedStat(url))
        return value
    }

    private func assertStableMetadata(_ before: stat, _ after: stat) {
        XCTAssertEqual(after.st_dev, before.st_dev)
        XCTAssertEqual(after.st_ino, before.st_ino)
        XCTAssertEqual(after.st_mode, before.st_mode)
        XCTAssertEqual(after.st_uid, before.st_uid)
        XCTAssertEqual(after.st_gid, before.st_gid)
    }

    private func assertFullFacts(_ before: stat, _ after: stat) {
        assertStableMetadata(before, after)
        XCTAssertEqual(after.st_nlink, before.st_nlink)
        XCTAssertEqual(after.st_size, before.st_size)
        XCTAssertEqual(after.st_mtimespec.tv_sec, before.st_mtimespec.tv_sec)
        XCTAssertEqual(after.st_mtimespec.tv_nsec, before.st_mtimespec.tv_nsec)
        XCTAssertEqual(after.st_ctimespec.tv_sec, before.st_ctimespec.tv_sec)
        XCTAssertEqual(after.st_ctimespec.tv_nsec, before.st_ctimespec.tv_nsec)
    }
}

#if DEBUG
@MainActor
private enum OriginalScratchIssuerDataFixtureRetentionV1 {
    // Existing harness retains Router/root. A Service may still own genuine
    // intent/control resources, so no test removes or implicitly closes it.
    static var services: [(URL, EraseAllService)] = []
}

@MainActor
private final class OriginalPostCloseSourceControlsStateV1 {
    var receipts: [CompletedEraseReceiptV1] = []
    var readbacks: [ErasePostCloseSourceControlsReadbackV1] = []
    var mutationApplied = false
    var originalPointerBytes: Data?
}

private enum OriginalPostCloseSourceFaultV1 {
    case none, pointerBytes, dataMembership
}

@MainActor
private struct OriginalPostCloseSourceFixtureV1 {
    let root: URL
    let support: URL
    let owner: V23EraseOperationHarnessV1
    let operation: EraseRouterOperationV1
    let state: OriginalPostCloseSourceControlsStateV1
    let originalGeneration: UUID
}

extension V23ProductionAppAccessTests {
    @MainActor
    func testGenuineOriginalPostCloseSourceOwnerCompletesAndRefusesForeignReceiptAndBinding() async throws {
        let foreign = try await prepareOriginalPostCloseSourceFixture(fault: .none)
        try await foreign.owner.completeCleanup()
        XCTAssertEqual(foreign.state.receipts.count, 1)
        assertOriginalPostCloseSourceReadback(foreign.state, expectsForeignOwner: false)
        let (_, foreignProof, foreignReceipt) = try foreign.operation.completedRetirement()
        XCTAssertNotNil(foreignReceipt)

        let fixture = try await prepareOriginalPostCloseSourceFixture(
            fault: .none, foreignOwner: foreignProof)
        try await fixture.owner.completeCleanup()
        XCTAssertEqual(fixture.state.receipts.count, 1)
        assertOriginalPostCloseSourceReadback(fixture.state, expectsForeignOwner: true)
        let completed = try XCTUnwrap(fixture.state.receipts.first)
        XCTAssertNotEqual(completed.subject, try XCTUnwrap(foreignReceipt).subject)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            fixture.support.appendingPathComponent("FieldEvidenceOperations").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            fixture.support.appendingPathComponent("FieldEvidenceErase").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            StoreGenerationFactory(applicationSupportURL: fixture.support)
                .installedGenerationURL(id: fixture.originalGeneration).path))
        try await fixture.owner.adoptCompletedReceipt()
        try await fixture.owner.activateFreshOrdinarySession()
        guard case let .ready(fresh, _, _) = fixture.owner.router.route else {
            return XCTFail("The actual post-close source owner must finish and activate its new ordinary owner")
        }
        XCTAssertEqual(fresh.generationID, completed.subject.newGenerationID)
        XCTAssertNotEqual(fresh.generationID, fixture.originalGeneration)
        XCTAssertEqual(try fresh.workspaceWriter.currentRevision().generationID, fresh.generationID)
    }

    @MainActor
    func testGenuineOriginalPostCloseSourceOwnerRefusesChangedCurrentPointerWithoutCompletion() async throws {
        try await assertOriginalPostCloseSourceFaultRefusesCompletion(.pointerBytes)
    }

    @MainActor
    func testGenuineOriginalPostCloseSourceOwnerRefusesUnexpectedDataMemberWithoutCompletion() async throws {
        try await assertOriginalPostCloseSourceFaultRefusesCompletion(.dataMembership)
    }

    @MainActor
    private func prepareOriginalPostCloseSourceFixture(
        fault: OriginalPostCloseSourceFaultV1,
        foreignOwner: ErasedRegistryRetirementProofV1? = nil
    ) async throws -> OriginalPostCloseSourceFixtureV1 {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            "V23-OriginalPostCloseSource-" + UUID().uuidString, isDirectory: true)
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        for directory in [support, caches, temporary] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let suite = "V23.OriginalPostCloseSource." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let shipping = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [shipping])
        let owner = V23EraseOperationHarnessV1(retainingRoot: root,
            applicationSupportURL: support,
            runtime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            profileRegistry: profiles)
        let state = OriginalPostCloseSourceControlsStateV1()
        // No coordinator, session, context or container escapes this genuine
        // preparation frame. The retained operation still decides real drain.
        let originalGeneration = try await { @MainActor () async throws -> UUID in
            let (coordinator, diagnostics) = try await owner.startOriginalOwner()
            let originalGeneration = coordinator.generationID
            try await owner.admit(coordinator: coordinator)
            let service = try owner.configure(EraseAllService(applicationSupportURL: support,
                cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                userDefaults: defaults, defaultsDomainName: suite,
                admitErase: { try await owner.admitSubject($0) },
                didCompleteErase: { state.receipts.append($0) }))
            service.postCloseSourceForeignOwnerForTesting = foreignOwner
            service.afterTerminalSourceValidationForTesting = { observed in
                state.readbacks.append(observed)
                // This is a hostile mutation after real owner/close validation,
                // never a callback returning a favorable authorization result.
                switch fault {
                case .none: break
                case .pointerBytes:
                    let pointer = support.appendingPathComponent("FieldEvidenceData/current.json")
                    var bytes = try Data(contentsOf: pointer)
                    guard !bytes.isEmpty else { throw EraseAllServiceError.invalidAuthority }
                    state.originalPointerBytes = bytes
                    bytes[bytes.startIndex] = bytes[bytes.startIndex] ^ 1
                    try bytes.write(to: pointer)
                    state.mutationApplied = true
                case .dataMembership:
                    try Data("hostile post-close member".utf8).write(to:
                        support.appendingPathComponent("FieldEvidenceData/post-close-unexpected.json"))
                    state.mutationApplied = true
                }
            }
            // Retain the genuine admitted service before preparation may throw.
            OriginalScratchIssuerDataFixtureRetentionV1.services.append((root, service))
            try await owner.prepareCompatibility(service: service, confirmation: "ERASE",
                coordinator: coordinator, diagnostics: diagnostics)
            return originalGeneration
        }()
        XCTAssertTrue(state.receipts.isEmpty)
        XCTAssertTrue(state.readbacks.isEmpty, "The close probe cannot run during original preparation")
        return OriginalPostCloseSourceFixtureV1(root: root, support: support, owner: owner,
            operation: try owner.originalOperationForInterruption(), state: state,
            originalGeneration: originalGeneration)
    }

    @MainActor
    private func assertOriginalPostCloseSourceReadback(
        _ state: OriginalPostCloseSourceControlsStateV1, expectsForeignOwner: Bool
    ) {
        XCTAssertEqual(state.readbacks.count, 1, "One genuine close, no repeated probe or reset")
        guard let observed = state.readbacks.first else { return XCTFail("Genuine post-close DATA is required") }
        XCTAssertTrue(observed.sameOwnerSourceValidated)
        XCTAssertTrue(observed.closedAuthorityReaderRefused,
            "Retained manifest ownership never reopens the closed generation authority")
        if expectsForeignOwner {
            XCTAssertEqual(observed.foreignReceiptRefused, true)
            XCTAssertEqual(observed.foreignBindingRefused, true)
        } else {
            XCTAssertNil(observed.foreignReceiptRefused)
            XCTAssertNil(observed.foreignBindingRefused)
        }
    }

    @MainActor
    private func assertOriginalPostCloseSourceFaultRefusesCompletion(
        _ fault: OriginalPostCloseSourceFaultV1
    ) async throws {
        let fixture = try await prepareOriginalPostCloseSourceFixture(fault: fault)
        var refusal: Error?
        do {
            try await fixture.owner.completeCleanup()
            XCTFail("Fresh post-close source checks must refuse the actual changed namespace")
        } catch { refusal = error }
        XCTAssertEqual(refusal as? StoreMigrationFailure, .invalidIdentity)
        assertOriginalPostCloseSourceReadback(fixture.state, expectsForeignOwner: false)
        XCTAssertTrue(fixture.state.mutationApplied, "Refusal must follow the completed hostile mutation")
        XCTAssertTrue(fixture.state.receipts.isEmpty)
        XCTAssertThrowsError(try fixture.operation.completedRetirement())
        guard case let .eraseCleanupPending(.retiring(retained)) = fixture.owner.router.route else {
            return XCTFail("The actual failed owner and recovery controls must remain retained")
        }
        XCTAssertTrue(retained === fixture.operation)
        for name in ["FieldEvidenceOperations", "FieldEvidenceErase"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath:
                fixture.support.appendingPathComponent(name).path))
        }
        switch fault {
        case .pointerBytes:
            let before = try XCTUnwrap(fixture.state.originalPointerBytes)
            XCTAssertNotEqual(try Data(contentsOf:
                fixture.support.appendingPathComponent("FieldEvidenceData/current.json")), before)
        case .dataMembership:
            XCTAssertEqual(try Data(contentsOf: fixture.support.appendingPathComponent(
                "FieldEvidenceData/post-close-unexpected.json")), Data("hostile post-close member".utf8))
        case .none: XCTFail("A genuine hostile source change is required")
        }
        // No second advance, repair, forced holder release or root teardown.
        // All original resources and the refused namespace remain retained.
    }

    @MainActor
    func testGenuineOriginalScratchNodeDataRequiresExactSelectionAndNaturalRevocation() async throws {
        try await runGenuineOriginalScratchIssuerDataProfile(.node)
    }

    @MainActor
    func testGenuineOriginalScratchDeclaredPairDataRequiresExactMembershipAndOrderAfterNaturalRevocation() async throws {
        try await runGenuineOriginalScratchIssuerDataProfile(.declaredPair)
    }

    @MainActor
    func testGenuineOriginalScratchEarlierImmutablePairProjectionCannotSelectLaterDeclaredPairData() async throws {
        try await runGenuineOriginalScratchIssuerDataProfile(.earlierPairProjectionMembership)
    }

    @MainActor
    private func runGenuineOriginalScratchIssuerDataProfile(
        _ profile: OriginalEraseScratchIssuerDataProfileV1
    ) async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            "V23-GenuineScratchIssuerData-" + UUID().uuidString, isDirectory: true)
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        for directory in [support, caches, temporary] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let suite = "V23.GenuineScratchIssuerData." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let shipping = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [shipping])
        let owner = V23EraseOperationHarnessV1(retainingRoot: root,
            applicationSupportURL: support,
            runtime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            profileRegistry: profiles)
        var completions = [CompletedEraseReceiptV1]()
        // Coordinator/context aliases exist only in this lexical original
        // preparation frame. The next genuine advance sees their actual drain.
        let (operation, ticket, slot, originalGeneration) = try await {
            @MainActor () async throws ->
                (EraseRouterOperationV1, StartupRouter.OriginalOperationTicket, UUID, UUID) in
            let (coordinator, diagnostics) = try await owner.startOriginalOwner()
            let originalGeneration = coordinator.generationID
            let payloadBytes = Data("genuine issuer DATA payload".utf8)
            let created = Date(timeIntervalSince1970: 1_786_800_012)
            weak var endedProducer: ScratchDataLeaseStoreV1?
            let payloadURL = try await { @MainActor () async throws -> URL in
                let scratch = try ScratchDataLeaseStoreV1(applicationSupportURL: support,
                    clock: { created }, capacityProvider: { _ in Int64.max })
                let requestedByteCount = try XCTUnwrap(UInt64(exactly: payloadBytes.count))
                let request = try ScratchDataLeaseRequestV1(leaseID: UUID(),
                    purpose: .supportExport, owner: .supportExport, ownerOperationID: UUID(),
                    requestedByteCount: requestedByteCount, createdAt: created,
                    expiresAt: created.addingTimeInterval(900))
                let lease = try await scratch.acquireScratchLease(request)
                let actualURL = try await scratch.writeScratchData(payloadBytes,
                    named: "support.json", lease: lease)
                endedProducer = scratch
                return actualURL
            }()
            XCTAssertNil(endedProducer, "The real producer must end before original cleanup admission")
            XCTAssertEqual(try Data(contentsOf: payloadURL), payloadBytes)
            try await owner.admit(coordinator: coordinator)
            let operation = try owner.originalOperationForInterruption()
            let ticket = try owner.originalTicketForInterruption()
            let slot = try OriginalEraseScratchIssuerDataTestsV1.arm(profile,
                support: support, operation: operation)
            // Occupancy is refused without replacing the current profile or
            // slot, even when a caller asks for another declared fixed case.
            XCTAssertThrowsError(try OriginalEraseScratchIssuerDataTestsV1.arm(
                profile == .node ? .declaredPair : .node, support: support, operation: operation)) {
                XCTAssertEqual($0 as? OriginalEraseScratchIssuerDataTestErrorV1, .occupied,
                    "An occupied fixed case must refuse replacement")
            }
            XCTAssertEqual(try OriginalEraseScratchIssuerDataTestsV1.report(slot: slot).profile, profile)
            let service = try owner.configure(EraseAllService(applicationSupportURL: support,
                cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                userDefaults: defaults, defaultsDomainName: suite,
                admitErase: { try await owner.admitSubject($0) },
                didCompleteErase: { completions.append($0) }))
            OriginalScratchIssuerDataFixtureRetentionV1.services.append((root, service))
            try await owner.prepareCompatibility(service: service, confirmation: "ERASE",
                coordinator: coordinator, diagnostics: diagnostics)
            return (operation, ticket, slot, originalGeneration)
        }()
        XCTAssertTrue(completions.isEmpty)
        // One actual advancement, no polling, callback success, repeated
        // primitive, timeout extension or fallback owner.
        try await owner.completeCleanup()
        XCTAssertEqual(completions.count, 1)
        let reservation = try owner.originalReservationForInterruption()
        let completed = try XCTUnwrap(completions.first)
        XCTAssertEqual(completed.reservation, reservation)
        XCTAssertEqual(completed.subject, reservation.subject)
        XCTAssertEqual(completed.subject.applicationSupportURL, support.standardizedFileURL)
        let report = try OriginalEraseScratchIssuerDataTestsV1.report(slot: slot)
        XCTAssertEqual(report.supportDevice, completed.subject.applicationSupportDevice)
        XCTAssertEqual(report.supportInode, completed.subject.applicationSupportInode)
        assertGenuineOriginalScratchIssuerDataReport(report, profile: profile,
            operationID: operation.operationID)
        // This window precedes normal activation removing the original Router
        // association. The helper obtains actual retirement/proof internally.
        try OriginalEraseScratchIssuerDataTestsV1.restoreAfterCompletedRetirement(
            slot: slot, support: support, router: owner.router, ticket: ticket,
            operation: operation, reservation: reservation)
        XCTAssertThrowsError(try OriginalEraseScratchIssuerDataTestsV1.report(slot: slot))
        try await owner.adoptCompletedReceipt()
        try await owner.activateFreshOrdinarySession()
        guard case let .ready(fresh, _, _) = owner.router.route else {
            return XCTFail("Genuine DATA probes must leave actual Erase able to activate its fresh ordinary owner")
        }
        XCTAssertEqual(fresh.generationID, completed.subject.newGenerationID)
        XCTAssertNotEqual(fresh.generationID, originalGeneration)
        XCTAssertEqual(try fresh.workspaceWriter.currentRevision().generationID, fresh.generationID)
        for name in ["FieldEvidenceErase", "FieldEvidenceOperations/ScratchDataV1",
            "FieldEvidenceOperations/ProtectedIngressReceiptsV1"] {
            XCTAssertFalse(manager.fileExists(atPath: support.appendingPathComponent(name).path))
        }
        XCTAssertFalse(manager.fileExists(atPath: StoreGenerationFactory(applicationSupportURL: support)
            .installedGenerationURL(id: originalGeneration).path))
        // Root/Harness/Service/new ordinary owner remain host-retained. Their
        // actual checked root teardown and uncertain recovery are not claimed.
    }

    @MainActor
    private func assertGenuineOriginalScratchIssuerDataReport(
        _ report: OriginalEraseScratchIssuerDataReportV1,
        profile: OriginalEraseScratchIssuerDataProfileV1, operationID: UUID
    ) {
        let nodeProbes: Set<OriginalEraseScratchIssuerDataProbeV1> = [
            .nodeExact, .nodeMissingURL, .nodeWrongKind, .nodeWrongFact,
            .nodeAfterRevoke, .nodeCurrentBindingRevoked, .nodeAuthorizedRevoked, .nodePairProjectionAfterRevoke]
        let pairProbes: Set<OriginalEraseScratchIssuerDataProbeV1> = [
            .pairNodeExact, .pairExact, .pairZeroCount, .pairOneCount, .pairThreeCount,
            .pairReordered, .pairDuplicateMember, .pairMissingMember,
            .pairNodeAfterRevoke, .pairAfterRevoke, .pairCurrentBindingRevoked,
            .pairNodeAuthorizedRevoked, .pairAuthorizedRevoked, .pairProjectionAfterRevoke]
        let expectedProbes: Set<OriginalEraseScratchIssuerDataProbeV1>
        switch profile {
        case .node: expectedProbes = nodeProbes
        case .declaredPair: expectedProbes = pairProbes
        case .earlierPairProjectionMembership: expectedProbes = nodeProbes.union(pairProbes).union([.earlierPairProjectionMissing])
        }
        let equalDataProbes: Set<OriginalEraseScratchIssuerDataProbeV1> = [
            .nodeExact, .nodeAfterRevoke, .nodePairProjectionAfterRevoke, .pairNodeExact, .pairExact,
            .pairNodeAfterRevoke, .pairAfterRevoke, .pairProjectionAfterRevoke]
        let selectedCount: UInt64 = profile == .earlierPairProjectionMembership ? 2 : 1
        XCTAssertEqual(report.profile, profile)
        XCTAssertEqual(report.operationID, operationID)
        XCTAssertTrue(report.completedSelectedProfile)
        XCTAssertNil(report.firstFailure)
        XCTAssertEqual(report.driverScopeHolderCount, 0)
        XCTAssertEqual(report.selectedIssuances, selectedCount)
        XCTAssertEqual(report.selectedRevokes, selectedCount)
        XCTAssertEqual(report.selectedObservationIDs.count, Int(selectedCount))
        XCTAssertEqual(Set(report.selectedObservationIDs).count, Int(selectedCount))
        XCTAssertEqual(report.revokedObservationIDs, report.selectedObservationIDs)
        XCTAssertEqual(report.revokedDriverScopeHolderCounts, Array(repeating: 0, count: Int(selectedCount)))
        XCTAssertEqual(report.issuedPairProjections.count, Int(selectedCount))
        XCTAssertEqual(report.revokedPairProjections.count, Int(selectedCount))
        XCTAssertEqual(report.ordinaryIssuances, report.ordinaryRevokes)
        XCTAssertEqual(Set(report.probes.keys), expectedProbes, "No missing, repeated or conditional probe can pass")
        for name in expectedProbes {
            XCTAssertEqual(report.probes[name], equalDataProbes.contains(name) ? .equalData : .invalidAuthority,
                "Actual API/outcome for " + name.rawValue)
        }
        if profile == .earlierPairProjectionMembership {
            // The complete earliest immutable pair list is genuinely empty.
            // The later real arguments exercise the same DEBUG selector on
            // this projection; no later call on an earlier Scope is claimed.
            XCTAssertTrue(report.issuedPairProjections.first?.isEmpty == true)
            XCTAssertTrue(report.revokedPairProjections.first?.isEmpty == true)
        }
        if profile != .declaredPair {
            guard let expected = report.expectedNode, let observed = report.observedNode else {
                return XCTFail("Selected genuine earliest node DATA is required")
            }
            assertGenuineIssuerNodeData(observed, equals: expected)
        }
        if profile != .node {
            guard let expectedNode = report.expectedPairNode, let observedNode = report.observedPairNode,
                  let expected = report.expectedPair, let observed = report.observedPair else {
                return XCTFail("Selected actual declared-publication pair/node DATA is required")
            }
            assertGenuineIssuerNodeData(observedNode, equals: expectedNode)
            XCTAssertEqual(observed.kind, expected.kind)
            XCTAssertEqual(observed.sha256, expected.sha256)
            XCTAssertEqual(observed.byteCount, expected.byteCount)
            XCTAssertGreaterThan(observed.byteCount, 0)
            XCTAssertEqual(observed.device, expected.device)
            XCTAssertEqual(observed.inode, expected.inode)
            XCTAssertEqual(observed.user, expected.user)
            XCTAssertEqual(observed.group, expected.group)
            XCTAssertEqual(observed.parentURL, expected.parentURL)
            XCTAssertEqual(observed.parentFullFact, expected.parentFullFact)
            XCTAssertEqual(observed.members.map(\.relativePath), expected.members.map(\.relativePath))
            XCTAssertEqual(observed.members.map(\.url), expected.members.map(\.url))
            XCTAssertEqual(observed.members.map(\.fullFact), expected.members.map(\.fullFact))
            XCTAssertEqual(observed.ancestors.map(\.url), expected.ancestors.map(\.url))
            XCTAssertEqual(observed.ancestors.map(\.fullFact), expected.ancestors.map(\.fullFact))
            XCTAssertEqual(observed.ancestors.map(\.directoryRole), expected.ancestors.map(\.directoryRole))
            XCTAssertEqual(observed.members.count, 2)
            if observed.members.count == 2 {
                XCTAssertNotEqual(observed.members[0].url, observed.members[1].url)
                XCTAssertTrue(observed.members[0].relativePath.utf8.lexicographicallyPrecedes(
                    observed.members[1].relativePath.utf8))
            }
            switch (observed.role, expected.role) {
            case let (.declaredLinkPublication(ac, al, at, af), .declaredLinkPublication(bc, bl, bt, bf)):
                XCTAssertEqual(ac, bc); XCTAssertEqual(al, bl)
                XCTAssertEqual(at, bt); XCTAssertEqual(af, bf)
            default: XCTFail("Only the actual declared create/link publication role qualifies")
            }
        }
    }

    @MainActor
    private func assertGenuineIssuerNodeData(_ observed: OriginalEraseScratchTemporalPolicyNodeV1,
        equals expected: OriginalEraseScratchTemporalPolicyNodeV1) {
        XCTAssertEqual(observed.kind, expected.kind)
        XCTAssertEqual(observed.url, expected.url)
        XCTAssertEqual(observed.fullFact, expected.fullFact)
        XCTAssertEqual(observed.parentURL, expected.parentURL)
        XCTAssertEqual(observed.parentFullFact, expected.parentFullFact)
        XCTAssertEqual(observed.directoryRole, expected.directoryRole)
        XCTAssertEqual(observed.ancestors.map(\.url), expected.ancestors.map(\.url))
        XCTAssertEqual(observed.ancestors.map(\.fullFact), expected.ancestors.map(\.fullFact))
        XCTAssertEqual(observed.ancestors.map(\.directoryRole), expected.ancestors.map(\.directoryRole))
    }
}
#endif

#if DEBUG
@MainActor
private final class OriginalRecoveryTransitionFixtureStateV1 {
    var serviceCount = 0
    var services = [EraseAllService]()
    var reservations = [AppAccessGateV1.EraseAdoptionToken]()
    var completions = [CompletedEraseReceiptV1]()
    var originalGenerationID: UUID?
    var targetGenerationID: UUID?
    var recoveryTargetsEntries = 0
    var probeFailure: Error?
    var probeReports = [OriginalRecoveryProjectionCallbackObservationForTestingV1]()
    var abandonedPayloadURL: URL?
    var abandonedPayloadBytes: Data?
    var hostileWriter: FileHandle?
    var hostileWriterCloseAttemptCount = 0
    var hostileWriterCloseReturned = false
    var hostileWriterIOOrCloseUncertain = false
    var hostileWriterFailure: Error?
    var atRecoveryTargets: ((StartupRouter) throws ->
        [OriginalRecoveryProjectionCallbackObservationForTestingV1])?
}

@MainActor
private final class OriginalRecoveryTransitionFixtureV1 {
    let root: URL
    let support: URL
    let router: StartupRouter
    let session: ProductionAppAccessSessionV1
    let presentation: AppAccessPresentationV1
    let state: OriginalRecoveryTransitionFixtureStateV1
    var abandonedPayloadURL: URL? { state.abandonedPayloadURL }
    var abandonedPayloadBytes: Data? { state.abandonedPayloadBytes }
    private static var retained: [OriginalRecoveryTransitionFixtureV1] = []

    init(root: URL, support: URL, router: StartupRouter,
        session: ProductionAppAccessSessionV1, presentation: AppAccessPresentationV1,
        state: OriginalRecoveryTransitionFixtureStateV1) {
        self.root = root; self.support = support; self.router = router
        self.session = session; self.presentation = presentation; self.state = state
        // Retain genuine production owners before startup/admission. A refused
        // fixture keeps its live tree and descriptors for the host lifetime.
        Self.retained.append(self)
    }
}

private enum OriginalRecoveryTransitionFixtureFailureV1: Error {
    case originalPointerSwitchNotReached, duplicateRecoveryTargets, payloadNotAvailable
}

extension V23ProductionAppAccessTests {
    @MainActor
    private func startOriginalRecoveryTransitionFixture(
        withAbandonedPayload: Bool = false
    ) async throws -> OriginalRecoveryTransitionFixtureV1 {
        let manager = FileManager.default
        let suite = "V23.OriginalRecoveryTransition." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = manager.temporaryDirectory.appendingPathComponent(
            "V23-OriginalRecoveryTransition-" + UUID().uuidString, isDirectory: true)
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        for directory in [support, caches, temporary] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let system = ProductionAccessNotificationSystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ProductionAccessAuthentication(), notificationSystem: system)
        let state = OriginalRecoveryTransitionFixtureStateV1()
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                state.serviceCount += 1
                let service = EraseAllService(applicationSupportURL: support,
                    cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                    userDefaults: defaults, defaultsDomainName: suite,
                    failureInjection: state.serviceCount == 1
                        ? EraseAllFailureInjection(failOnceAt: .afterPointerSwitch) : nil,
                    sceneNavigationStatePort: sceneState,
                    privateSystemDiscoveryIndex: nil, notificationSystem: system,
                    admitErase: { subject in
                        let actualAdmission = try XCTUnwrap(admission)
                        let reservation = try await actualAdmission(subject)
                        state.reservations.append(reservation)
                        return reservation
                    }, didCompleteErase: { receipt in
                        state.completions.append(receipt); completion?(receipt)
                    }, didAbortEraseAdmission: aborted)
                if state.serviceCount > 1 {
                    service.erasePhaseDiagnosticForTesting = { phase in
                        guard phase == "recovery.targets" else { return }
                        state.recoveryTargetsEntries += 1
                        guard let probe = state.atRecoveryTargets else { return }
                        state.atRecoveryTargets = nil
                        guard state.recoveryTargetsEntries == 1 else {
                            state.probeFailure = OriginalRecoveryTransitionFixtureFailureV1.duplicateRecoveryTargets
                            return
                        }
                        do { state.probeReports = try probe(router) }
                        catch { state.probeFailure = error }
                    }
                }
                state.services.append(service)
                return service
            }, sessionFactory: { session })
        let fixture = OriginalRecoveryTransitionFixtureV1(root: root, support: support,
            router: router, session: session, presentation: presentation, state: state)
        let ready = expectation(description: "Genuine original transition fixture publishes")
        let publication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in ready.fulfill() }
        defer { publication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [ready], timeout: 30)
        XCTAssertTrue(presentation.permitsContentPresentation)
        guard case .ready = router.route else {
            XCTFail("The production Router must publish its authentic original writer")
            throw OriginalRecoveryTransitionControlFailureForTestingV1.invalidConfiguration
        }
        if withAbandonedPayload {
            // The already retained genuine original is ready. Seed the real
            // abandoned lease now, before Erase admission/first-P capture.
            let bytes = Data("original recovery physical projection control".utf8)
            let created = Date(timeIntervalSince1970: 1_786_800_012)
            weak var endedProducer: ScratchDataLeaseStoreV1?
            state.abandonedPayloadURL = try await { @MainActor () async throws -> URL in
                let producer = try ScratchDataLeaseStoreV1(applicationSupportURL: support,
                    clock: { created }, capacityProvider: { _ in Int64.max })
                let request = try ScratchDataLeaseRequestV1(leaseID: UUID(),
                    purpose: .supportExport, owner: .supportExport, ownerOperationID: UUID(),
                    requestedByteCount: try XCTUnwrap(UInt64(exactly: bytes.count)),
                    createdAt: created, expiresAt: created.addingTimeInterval(900))
                let lease = try await producer.acquireScratchLease(request)
                let url = try await producer.writeScratchData(bytes, named: "support.json", lease: lease)
                endedProducer = producer
                return url
            }()
            XCTAssertNil(endedProducer, "The genuine Scratch producer ends before admission")
            XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(state.abandonedPayloadURL)), bytes)
            state.abandonedPayloadBytes = bytes
        }
        return fixture
    }

    @MainActor
    private func interruptOriginalRecoveryAfterPointerSwitch(
        _ fixture: OriginalRecoveryTransitionFixtureV1
    ) async throws {
        // No coordinator/model alias escapes this actual preparation frame.
        // Presentation, Router and the operation retain their genuine owners.
        try await { @MainActor () async throws -> Void in
            guard case let .ready(coordinator, diagnostics, _) = fixture.router.route else {
                throw OriginalRecoveryTransitionControlFailureForTestingV1.invalidConfiguration
            }
            fixture.state.originalGenerationID = coordinator.generationID
            do {
                try await fixture.presentation.performErase(applicationSupportURL: fixture.support,
                    confirmation: "ERASE", coordinator: coordinator, diagnosticsStore: diagnostics)
                XCTFail("The genuine original must reach its one-shot pointer-switch interruption")
                throw OriginalRecoveryTransitionFixtureFailureV1.originalPointerSwitchNotReached
            } catch {
                guard error as? EraseAllServiceError == .injectedFailure else { throw error }
            }
        }()
        XCTAssertEqual(fixture.state.serviceCount, 1)
        XCTAssertEqual(fixture.state.reservations.count, 1)
        XCTAssertTrue(fixture.state.completions.isEmpty)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        let intent = try EraseIntentCodecV1.decode(Data(contentsOf:
            fixture.support.appendingPathComponent("FieldEvidenceErase/erase.json")))
        let reservation = try XCTUnwrap(fixture.state.reservations.first)
        XCTAssertEqual(intent.phase, .emptyGenerationPrepared)
        XCTAssertEqual(intent.oldGenerationID, fixture.state.originalGenerationID)
        XCTAssertEqual(intent.eraseID, reservation.subject.eraseID)
        XCTAssertEqual(intent.newGenerationID, reservation.subject.newGenerationID)
        guard case .v3(let pointer, _) = try CurrentPointerCodecV1.decode(Data(contentsOf:
            fixture.support.appendingPathComponent("FieldEvidenceData/current.json"))) else {
            XCTFail("Only a genuine target-current original recovery exercises these controls")
            throw OriginalRecoveryTransitionControlFailureForTestingV1.invalidConfiguration
        }
        XCTAssertEqual(UUID(uuidString: pointer.generationID), intent.newGenerationID)
        fixture.state.targetGenerationID = intent.newGenerationID
    }

    @MainActor
    private func finishOriginalRecoveryTransition(
        _ fixture: OriginalRecoveryTransitionFixtureV1
    ) async throws {
        let ready = expectation(description: "Normal original recovery publishes its actual target")
        let publication = fixture.presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in ready.fulfill() }
        defer { publication.cancel() }
        await fixture.presentation.retryStartup()
        await fulfillment(of: [ready], timeout: 30)
        XCTAssertNil(fixture.state.probeFailure)
        XCTAssertTrue(fixture.presentation.permitsContentPresentation)
        XCTAssertNil(fixture.presentation.failure)
        XCTAssertEqual(fixture.state.serviceCount, 2)
        XCTAssertEqual(fixture.state.reservations.count, 2)
        let reservation = try XCTUnwrap(fixture.state.reservations.first)
        XCTAssertTrue(fixture.state.reservations.allSatisfy { $0 == reservation })
        XCTAssertEqual(fixture.state.completions.count, 1)
        XCTAssertEqual(fixture.state.completions.first?.subject, reservation.subject)
        guard case let .ready(coordinator, _, _) = fixture.router.route else {
            XCTFail("Actual ordinary continuation must activate the target writer")
            throw OriginalRecoveryTransitionControlFailureForTestingV1.invalidConfiguration
        }
        XCTAssertEqual(coordinator.generationID, fixture.state.targetGenerationID)
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision().generationID,
            fixture.state.targetGenerationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            fixture.support.appendingPathComponent("FieldEvidenceErase").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            StoreGenerationFactory(applicationSupportURL: fixture.support)
                .installedGenerationURL(id: try XCTUnwrap(fixture.state.originalGenerationID)).path))
    }

    @MainActor
    private func assertOriginalRecoveryOwnersRetained(
        _ observed: OriginalRecoveryTransitionObservationForTestingV1,
        fixture: OriginalRecoveryTransitionFixtureV1
    ) throws {
        XCTAssertFalse(observed.detached)
        let owner = try XCTUnwrap(observed.postPointerOwnerIdentity)
        XCTAssertEqual(observed.startingImageOwnerIdentity, owner)
        XCTAssertNil(observed.terminalOwnerIdentity)
        XCTAssertTrue(fixture.state.completions.isEmpty)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        for name in ["FieldEvidenceErase", "FieldEvidenceOperations"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath:
                fixture.support.appendingPathComponent(name).path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            StoreGenerationFactory(applicationSupportURL: fixture.support)
                .installedGenerationURL(id: try XCTUnwrap(fixture.state.originalGenerationID)).path))
    }

    @MainActor
    private func assertOriginalRecoveryCallbackRefusedBeforeEntry(
        _ report: OriginalRecoveryProjectionCallbackObservationForTestingV1
    ) {
        XCTAssertTrue(report.callbackInvoked)
        XCTAssertEqual(report.outcome, .uncertainOwner)
        XCTAssertEqual(report.after, report.before, "Foreign/terminal refusal precedes every projection entry")
        XCTAssertEqual(report.sourceModelReadsAfter, report.sourceModelReadsBefore)
        XCTAssertEqual(report.callbackOwnerUncertainAfter, report.callbackOwnerUncertainBefore)
        XCTAssertFalse(report.callbackOwnerUncertainBefore)
        XCTAssertFalse(report.after.failed)
    }

    @MainActor
    private func assertOriginalRecoveryHealthyWrapper(
        _ report: OriginalRecoveryProjectionCallbackObservationForTestingV1
    ) {
        XCTAssertEqual(report.probe, .exactBoundHealthyWrapper)
        XCTAssertTrue(report.callbackInvoked)
        XCTAssertEqual(report.outcome, .returned)
        XCTAssertFalse(report.before.failed)
        XCTAssertFalse(report.after.failed)
        XCTAssertFalse(report.callbackOwnerUncertainBefore)
        XCTAssertFalse(report.callbackOwnerUncertainAfter)
        XCTAssertGreaterThan(report.after.continuationEntries, report.before.continuationEntries)
        // This counter covers the selected actual requested coordinator's
        // retained-source identity reads, not every possible model read.
        XCTAssertGreaterThan(report.sourceModelReadsAfter, report.sourceModelReadsBefore)
        XCTAssertGreaterThan(report.after.sourceStoreEntries, report.before.sourceStoreEntries)
        XCTAssertGreaterThan(report.after.borrowedSupportBodyEntries, report.before.borrowedSupportBodyEntries)
        XCTAssertGreaterThan(report.after.observerEntries, report.before.observerEntries)
        XCTAssertGreaterThan(report.after.bodyEntries, report.before.bodyEntries)
    }

    @MainActor
    func testOriginalRecoveryScratchUncertainSettlementRetainsModelOwnerAssociations() async throws {
        let fixture = try await startOriginalRecoveryTransitionFixture()
        try await interruptOriginalRecoveryAfterPointerSwitch(fixture)
        try fixture.router.armOriginalRecoveryTransitionControlForTesting(.beforeScratchReceiptSettlement)
        await fixture.presentation.retryStartup()
        let observed = try fixture.router.originalRecoveryTransitionObservationForTesting()
        try assertOriginalRecoveryOwnersRetained(observed, fixture: fixture)
        XCTAssertEqual(observed.scratchCallerBoundaryInterruptions, 1)
        XCTAssertEqual(observed.aggregateMutationInterruptions, 0)
        XCTAssertTrue(observed.scratchInFlight)
        XCTAssertTrue(observed.scratchUncertain)
        XCTAssertFalse(observed.scratchReceiptPresent)
        XCTAssertEqual(observed.cleanupCompletedReturns, 0)
        XCTAssertThrowsError(try fixture.router.armOriginalRecoveryTransitionControlForTesting(
            .beforeScratchReceiptSettlement)) {
            XCTAssertEqual($0 as? OriginalRecoveryTransitionControlFailureForTestingV1, .alreadyConsumed)
        }
        // The injected refusal proves this caller settlement boundary only.
        // The actual uncertain operation, G evidence and owner remain held;
        // no native-close failure, rearm or recovery success is manufactured.
    }

    @MainActor
    func testOriginalRecoveryAggregateDetachInterruptionRetainsSameTransferredExclusionUntilRetry() async throws {
        let fixture = try await startOriginalRecoveryTransitionFixture()
        try await interruptOriginalRecoveryAfterPointerSwitch(fixture)
        try fixture.router.armOriginalRecoveryTransitionControlForTesting(.afterExTransferBeforeAggregate)
        await fixture.presentation.retryStartup()
        let before = try fixture.router.originalRecoveryTransitionObservationForTesting()
        try assertOriginalRecoveryOwnersRetained(before, fixture: fixture)
        let successor = try XCTUnwrap(before.transferredExclusionIdentity)
        let owner = try XCTUnwrap(before.postPointerOwnerIdentity)
        XCTAssertEqual(before.aggregateMutationInterruptions, 1)
        XCTAssertTrue(before.scratchReceiptPresent)
        XCTAssertFalse(before.scratchUncertain)
        XCTAssertEqual(before.cleanupCompletedReturns, 0)
        XCTAssertThrowsError(try fixture.router.armOriginalRecoveryTransitionControlForTesting(
            .afterExTransferBeforeAggregate)) {
            XCTAssertEqual($0 as? OriginalRecoveryTransitionControlFailureForTestingV1, .alreadyConsumed)
        }
        try await finishOriginalRecoveryTransition(fixture)
        let after = try fixture.router.originalRecoveryTransitionObservationForTesting()
        XCTAssertEqual(after.operationID, before.operationID)
        XCTAssertTrue(after.detached)
        XCTAssertNil(after.postPointerOwnerIdentity)
        XCTAssertNil(after.startingImageOwnerIdentity)
        XCTAssertEqual(after.terminalOwnerIdentity, owner)
        XCTAssertEqual(after.transferredExclusionIdentity, successor)
        XCTAssertEqual(after.aggregateMutationInterruptions, 1)
        XCTAssertEqual(after.cleanupCompletedReturns, 1)
    }

    @MainActor
    func testOriginalRecoveryProjectionRejectsDetachedCallbacksBeforeReadOrPoison() async throws {
        let old = try await startOriginalRecoveryTransitionFixture()
        try await interruptOriginalRecoveryAfterPointerSwitch(old)
        try old.router.armOriginalRecoveryTransitionControlForTesting(.detachedProjectionCallbacks)
        try await finishOriginalRecoveryTransition(old)
        let detached = old.router.originalRecoveryDetachedProjectionCallbackObservationsForTesting()
        let expectedDetached: [OriginalRecoveryProjectionCallbackProbeForTestingV1] = [
            .detachedFirst, .detachedProjected, .detachedReaderStartingImage, .detachedWrapper]
        XCTAssertEqual(detached.map(\.probe), expectedDetached)
        for report in detached {
            XCTAssertEqual(report.before.operationDetached, true)
            assertOriginalRecoveryCallbackRefusedBeforeEntry(report)
        }
        let expired = try XCTUnwrap(old.router.originalRecoveryRetainedProjectionEntryObservationForTesting())
        XCTAssertTrue(!expired.operationPresent || !expired.ownerPresent,
            "The actual weak original association must expire naturally")
        let next = try await startOriginalRecoveryTransitionFixture()
        try await interruptOriginalRecoveryAfterPointerSwitch(next)
        next.state.atRecoveryTargets = { router in
            var reports = [try router.probeOriginalRecoveryProjectionForTesting(.exactBoundHealthyWrapper)]
            let probes: [OriginalRecoveryProjectionCallbackProbeForTestingV1] = [
                .expiredFirst, .expiredProjected, .expiredReaderStartingImage, .expiredWrapper]
            for probe in probes {
                reports.append(try old.router.probeExpiredOriginalRecoveryProjectionForTesting(
                    probe, requestedRouter: router))
            }
            return reports
        }
        try await finishOriginalRecoveryTransition(next)
        XCTAssertEqual(next.state.recoveryTargetsEntries, 1)
        XCTAssertEqual(next.state.probeReports.map(\.probe), [.exactBoundHealthyWrapper,
            .expiredFirst, .expiredProjected, .expiredReaderStartingImage, .expiredWrapper])
        guard let healthy = next.state.probeReports.first else {
            return XCTFail("The genuine B wrapper baseline is mandatory")
        }
        assertOriginalRecoveryHealthyWrapper(healthy)
        for report in next.state.probeReports.dropFirst() {
            XCTAssertTrue(!report.before.operationPresent || !report.before.ownerPresent)
            assertOriginalRecoveryCallbackRefusedBeforeEntry(report)
        }
    }

    @MainActor
    func testOriginalRecoveryExternalSourceSessionAliasBlocksDrainUntilNaturalCallerRelease() async throws {
        let fixture = try await startOriginalRecoveryTransitionFixture()
        // This is the sole added strong caller alias. The getter returns the
        // existing Router-published session before genuine Erase admission.
        var alias: StoreGenerationSession? = try {
            guard case let .ready(coordinator, _, _) = fixture.router.route else {
                throw OriginalRecoveryTransitionControlFailureForTestingV1.invalidConfiguration
            }
            return try coordinator.sourceSessionForV949EraseFixture(router: fixture.router)
        }()
        weak var actualSourceSession = alias
        try await interruptOriginalRecoveryAfterPointerSwitch(fixture)
        let pending = expectation(description: "Actual cleanup observes the live external original session")
        var reportedPending = false
        fixture.presentation.eraseRecoveryDiagnosticForTesting = { message in
            if message == "phase=resume.cleanup-incomplete category=none", !reportedPending {
                reportedPending = true; pending.fulfill()
            }
        }
        defer { fixture.presentation.eraseRecoveryDiagnosticForTesting = nil }
        await fixture.presentation.retryStartup()
        await fulfillment(of: [pending], timeout: 30)
        XCTAssertNotNil(alias)
        XCTAssertNotNil(actualSourceSession)
        let before = try fixture.router.originalRecoveryTransitionObservationForTesting()
        XCTAssertTrue(before.detached)
        XCTAssertNil(before.postPointerOwnerIdentity)
        XCTAssertNil(before.startingImageOwnerIdentity)
        XCTAssertNotNil(before.terminalOwnerIdentity)
        XCTAssertGreaterThanOrEqual(before.cleanupPendingReturns, 1)
        XCTAssertEqual(before.cleanupCompletedReturns, 0)
        XCTAssertTrue(fixture.state.completions.isEmpty)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            StoreGenerationFactory(applicationSupportURL: fixture.support)
                .installedGenerationURL(id: try XCTUnwrap(fixture.state.originalGenerationID)).path))
        alias = nil
        XCTAssertNil(actualSourceSession, "Only natural release of the actual caller alias permits model drain")
        try await finishOriginalRecoveryTransition(fixture)
        let after = try fixture.router.originalRecoveryTransitionObservationForTesting()
        XCTAssertEqual(after.operationID, before.operationID)
        XCTAssertGreaterThanOrEqual(after.cleanupPendingReturns, before.cleanupPendingReturns)
        XCTAssertEqual(after.cleanupCompletedReturns, 1)
    }

    @MainActor
    func testOriginalRecoveryProjectionRejectsForeignOperationAndOwnerBeforePoison() async throws {
        let old = try await startOriginalRecoveryTransitionFixture()
        try await interruptOriginalRecoveryAfterPointerSwitch(old)
        try old.router.armOriginalRecoveryTransitionControlForTesting(.afterExTransferBeforeAggregate)
        await old.presentation.retryStartup()
        let donorCut = try old.router.originalRecoveryTransitionObservationForTesting()
        try assertOriginalRecoveryOwnersRetained(donorCut, fixture: old)
        XCTAssertEqual(donorCut.aggregateMutationInterruptions, 1)
        let donorSuccessor = try XCTUnwrap(donorCut.transferredExclusionIdentity)
        XCTAssertTrue(donorCut.scratchReceiptPresent)
        XCTAssertFalse(donorCut.scratchInFlight)
        XCTAssertFalse(donorCut.scratchUncertain)
        let next = try await startOriginalRecoveryTransitionFixture()
        try await interruptOriginalRecoveryAfterPointerSwitch(next)
        let probes: [OriginalRecoveryProjectionCallbackProbeForTestingV1] = [
            .foreignFirstOperation, .foreignFirstOwner, .foreignFirstOperationAndOwner,
            .foreignProjectedOperation, .foreignProjectedOwner, .foreignProjectedOperationAndOwner,
            .foreignReaderStartingImage, .foreignWrapper]
        next.state.atRecoveryTargets = { router in
            var reports = [try router.probeOriginalRecoveryProjectionForTesting(.exactBoundHealthyWrapper)]
            for probe in probes {
                reports.append(try old.router.probeOriginalRecoveryProjectionForTesting(
                    probe, requestedRouter: router))
            }
            let peer = try XCTUnwrap(router.originalRecoveryTransitionObservationForTesting().projection)
            XCTAssertFalse(peer.failed)
            XCTAssertEqual(peer.ownerUncertain, false,
                "The genuine live B peer remains healthy after A's foreign callbacks")
            return reports
        }
        try await finishOriginalRecoveryTransition(next)
        XCTAssertEqual(next.state.recoveryTargetsEntries, 1)
        XCTAssertEqual(next.state.probeReports.map(\.probe), [.exactBoundHealthyWrapper] + probes)
        guard let healthy = next.state.probeReports.first else {
            return XCTFail("A genuine B wrapper baseline must precede all foreign callbacks")
        }
        assertOriginalRecoveryHealthyWrapper(healthy)
        for report in next.state.probeReports.dropFirst() {
            XCTAssertTrue(report.before.operationPresent)
            XCTAssertTrue(report.before.ownerPresent)
            XCTAssertEqual(report.before.operationDetached, false)
            assertOriginalRecoveryCallbackRefusedBeforeEntry(report)
        }
        XCTAssertEqual(try old.router.originalRecoveryTransitionObservationForTesting()
            .transferredExclusionIdentity, donorSuccessor)
        try await finishOriginalRecoveryTransition(old)
    }

    @MainActor
    func testOriginalRecoveryProjectionSameOwnerWrongFirstImageStillPoisons() async throws {
        let other = try await startOriginalRecoveryTransitionFixture()
        try await interruptOriginalRecoveryAfterPointerSwitch(other)
        try other.router.armOriginalRecoveryTransitionControlForTesting(.afterExTransferBeforeAggregate)
        await other.presentation.retryStartup()
        let donorCut = try other.router.originalRecoveryTransitionObservationForTesting()
        try assertOriginalRecoveryOwnersRetained(donorCut, fixture: other)
        XCTAssertEqual(donorCut.aggregateMutationInterruptions, 1)
        let donorSuccessor = try XCTUnwrap(donorCut.transferredExclusionIdentity)
        XCTAssertTrue(donorCut.scratchReceiptPresent)
        XCTAssertFalse(donorCut.scratchInFlight)
        XCTAssertFalse(donorCut.scratchUncertain)
        let fixture = try await startOriginalRecoveryTransitionFixture()
        try await interruptOriginalRecoveryAfterPointerSwitch(fixture)
        fixture.state.atRecoveryTargets = { router in
            [try router.probeOriginalRecoveryProjectionForTesting(.exactBoundHealthyWrapper),
             try router.probeOriginalRecoveryProjectionForTesting(.exactBoundWrongFirst,
                requestedRouter: other.router)]
        }
        await fixture.presentation.retryStartup()
        XCTAssertNil(fixture.state.probeFailure)
        XCTAssertEqual(fixture.state.recoveryTargetsEntries, 1)
        XCTAssertEqual(fixture.state.probeReports.map(\.probe), [.exactBoundHealthyWrapper, .exactBoundWrongFirst])
        guard fixture.state.probeReports.count == 2 else {
            return XCTFail("The real healthy B wrapper and another genuine first image are both required")
        }
        assertOriginalRecoveryHealthyWrapper(fixture.state.probeReports[0])
        let poisoned = fixture.state.probeReports[1]
        XCTAssertTrue(poisoned.callbackInvoked)
        XCTAssertEqual(poisoned.outcome, .uncertainOwner)
        XCTAssertGreaterThan(poisoned.after.firstComparisonEntries, poisoned.before.firstComparisonEntries)
        XCTAssertTrue(poisoned.after.failed)
        XCTAssertEqual(poisoned.after.ownerUncertain, true)
        XCTAssertEqual(poisoned.after.observerEntries, poisoned.before.observerEntries)
        XCTAssertEqual(poisoned.after.bodyEntries, poisoned.before.bodyEntries)
        XCTAssertEqual(poisoned.sourceModelReadsAfter, poisoned.sourceModelReadsBefore)
        XCTAssertFalse(poisoned.callbackOwnerUncertainBefore)
        XCTAssertTrue(poisoned.callbackOwnerUncertainAfter, "The actual exact-bound B callback owner is poisoned")
        let donorAfter = try other.router.originalRecoveryTransitionObservationForTesting()
        XCTAssertEqual(donorAfter.transferredExclusionIdentity, donorSuccessor)
        let donor = try XCTUnwrap(donorAfter.projection)
        XCTAssertFalse(donor.failed)
        XCTAssertEqual(donor.ownerUncertain, false, "The independent real first-image donor A remains healthy")
        try assertOriginalRecoveryOwnersRetained(
            fixture.router.originalRecoveryTransitionObservationForTesting(), fixture: fixture)
        // The exact-bound owner is genuinely poisoned. Never advance it again
        // or reuse this fixture as a later healthy companion.
    }

    @MainActor
    func testOriginalRecoveryProjectionSameOwnerPhysicalFailureStillPoisons() async throws {
        let fixture = try await startOriginalRecoveryTransitionFixture(withAbandonedPayload: true)
        try await interruptOriginalRecoveryAfterPointerSwitch(fixture)
        fixture.state.atRecoveryTargets = { router in
            let healthy = try router.probeOriginalRecoveryProjectionForTesting(.exactBoundHealthyWrapper)
            guard let url = fixture.abandonedPayloadURL, let bytes = fixture.abandonedPayloadBytes,
                  !bytes.isEmpty, FileManager.default.fileExists(atPath: url.path),
                  try Data(contentsOf: url) == bytes else {
                throw OriginalRecoveryTransitionFixtureFailureV1.payloadNotAvailable
            }
            let leaf = try FileHandle(forUpdating: url)
            // Retain this actual object before the first throwing IO. A failed
            // seek/write/sync/close keeps it for the host lifetime, with the
            // actual attempt/return DATA and no close retry or reopened leaf.
            fixture.state.hostileWriter = leaf
            do {
                try leaf.seek(toOffset: 0)
                try leaf.write(contentsOf: Data([bytes[bytes.startIndex] ^ 0xff]))
                try leaf.synchronize()
                fixture.state.hostileWriterCloseAttemptCount += 1
                try leaf.close()
                fixture.state.hostileWriterCloseReturned = true
            } catch {
                fixture.state.hostileWriterIOOrCloseUncertain = true
                fixture.state.hostileWriterFailure = error
                throw error
            }
            // The observer path follows only an actually returned close.
            XCTAssertNotEqual(try Data(contentsOf: url), bytes)
            let poisoned = try router.probeOriginalRecoveryProjectionForTesting(.exactBoundPhysicalWrapper)
            return [healthy, poisoned]
        }
        await fixture.presentation.retryStartup()
        XCTAssertNil(fixture.state.probeFailure,
            "An absent leaf or earlier guard failure is a fixture gap, not proof of projection poisoning")
        XCTAssertNotNil(fixture.state.hostileWriter)
        XCTAssertEqual(fixture.state.hostileWriterCloseAttemptCount, 1)
        XCTAssertTrue(fixture.state.hostileWriterCloseReturned)
        XCTAssertFalse(fixture.state.hostileWriterIOOrCloseUncertain)
        XCTAssertNil(fixture.state.hostileWriterFailure)
        XCTAssertEqual(fixture.state.recoveryTargetsEntries, 1)
        XCTAssertEqual(fixture.state.probeReports.map(\.probe),
            [.exactBoundHealthyWrapper, .exactBoundPhysicalWrapper])
        guard fixture.state.probeReports.count == 2 else {
            return XCTFail("The genuine existing-leaf hostile callback must actually run")
        }
        assertOriginalRecoveryHealthyWrapper(fixture.state.probeReports[0])
        let poisoned = fixture.state.probeReports[1]
        XCTAssertTrue(poisoned.callbackInvoked)
        XCTAssertEqual(poisoned.outcome, .otherFailure,
            "The real physical observer preserves EraseAllServiceError.invalidAuthority")
        XCTAssertGreaterThan(poisoned.sourceModelReadsAfter, poisoned.sourceModelReadsBefore)
        XCTAssertGreaterThan(poisoned.after.sourceStoreEntries, poisoned.before.sourceStoreEntries)
        XCTAssertGreaterThan(poisoned.after.borrowedSupportBodyEntries, poisoned.before.borrowedSupportBodyEntries)
        XCTAssertGreaterThan(poisoned.after.observerEntries, poisoned.before.observerEntries)
        XCTAssertEqual(poisoned.after.bodyEntries, poisoned.before.bodyEntries)
        XCTAssertTrue(poisoned.after.failed)
        XCTAssertEqual(poisoned.after.ownerUncertain, true)
        XCTAssertFalse(poisoned.callbackOwnerUncertainBefore)
        XCTAssertTrue(poisoned.callbackOwnerUncertainAfter)
        try assertOriginalRecoveryOwnersRetained(
            fixture.router.originalRecoveryTransitionObservationForTesting(), fixture: fixture)
        // No metadata repair, second hostile primitive, reset, rearm, cleanup
        // retry or deletion of the retained source namespace follows refusal.
    }
}
#endif

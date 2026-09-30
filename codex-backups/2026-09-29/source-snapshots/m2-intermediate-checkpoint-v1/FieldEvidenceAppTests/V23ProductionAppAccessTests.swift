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
    func testTrackedMaintenanceDeletionRecoversActualPreparedJournalAndClosesOwner() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-MaintenanceDeletion-\(UUID().uuidString)", isDirectory: true)
        let generation = support.appendingPathComponent(
            "FieldEvidenceData/generations/\(UUID().uuidString.lowercased())",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: generation, withIntermediateDirectories: true)
        let schema = Schema([
            Site.self, Asset.self, WorkflowRecord.self, ObservationAndTimeRow.self,
            EvidenceFile.self,
            Issue.self, Packet.self, Report.self, DeletionLedgerRow.self,
        ], version: Schema.Version(3, 0, 0))
        let container = try ModelContainer(for: schema, migrationPlan: nil,
            configurations: [ModelConfiguration("MaintenanceDeletion", schema: schema,
                url: generation.appendingPathComponent("model.sqlite"),
                allowsSave: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        context.autosaveEnabled = false
        let site = Site(label: "Site")
        let asset = Asset(siteID: site.id,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: 1, packContentVersion: 1, label: "Sign")
        context.insert(site)
        context.insert(asset)
        let completed = Date(timeIntervalSince1970: 1_760_000_000)
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
            localDate: "2025-10-09", localTime: "04:53",
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
        XCTAssertEqual(try originalScenePort.loadSceneNavigationData(), originalSceneBytes)
        XCTAssertThrowsError(try originalScene.load())
        XCTAssertFalse(presentation.permitsContentPresentation)
        guard case let .eraseCleanupPending(.retiring(originalOperation)) = router.route else {
            return XCTFail("A live original context must retain the actual retirement operation")
        }
        XCTAssertTrue(originalOperation.detached)
        XCTAssertTrue(originalOperation.hasPreparedCleanup)
        let pendingIntent = try XCTUnwrap(EraseIntentStore(applicationSupportURL: support).load())
        let preparedGeneration = pendingIntent.newGenerationID
        XCTAssertEqual(try XCTUnwrap(coordinator).generationID, originalGeneration)
        XCTAssertNotEqual(preparedGeneration, originalGeneration)
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

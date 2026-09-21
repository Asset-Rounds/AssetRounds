import Combine
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23ProductionAppAccessTests: XCTestCase {
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
            try? FileManager.default.removeItem(at: root)
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
                    sleeper: ProductionAccessImmediateSleeper(), sceneNavigationStatePort: sceneState, privateSystemDiscoveryIndex: nil,
                    notificationSystem: system, admitErase: admission,
                    didCompleteErase: completion, didAbortEraseAdmission: aborted)
            }, sessionFactory: { session })
        let published = expectation(description: "Actual production startup publishes the deferred Erase owner")
        let publication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { publication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        guard case .ready(let coordinator, let diagnostics, _) = router.route else {
            return XCTFail("Production startup did not publish its original Erase owner")
        }
        let originalGeneration = coordinator.generationID
        let originalScene = try XCTUnwrap(presentation.sceneNavigationAccess)
        let sceneSnapshot = try SceneNavigationSnapshotV1(workspaceID: coordinator.workspaceID,
            selectedRoot: .work, paths: AppRootV1.frozenOrder.map { .init(root: $0, targets: []) },
            snapshotID: UUID())
        try originalScene.save(sceneSnapshot)
        let originalSceneBytes = try XCTUnwrap(originalScenePort.loadSceneNavigationData())
        var retainedOldContext: ModelContext? = coordinator.modelContext
        weak var weakOldContext = retainedOldContext

        try await presentation.performErase(applicationSupportURL: support,
            confirmation: "ERASE", coordinator: coordinator, diagnosticsStore: diagnostics)
        XCTAssertEqual(serviceCount, 1)
        XCTAssertEqual(try originalScenePort.loadSceneNavigationData(), originalSceneBytes)
        XCTAssertThrowsError(try originalScene.load())
        XCTAssertFalse(presentation.permitsContentPresentation)
        guard case let .eraseCleanupPending(deferredCoordinator) = router.route else {
            return XCTFail("A live original context must retain the deferred Erase route")
        }
        XCTAssertTrue(deferredCoordinator === coordinator)
        XCTAssertNotEqual(coordinator.generationID, originalGeneration)
        XCTAssertNotNil(weakOldContext)
        XCTAssertNotNil(try EraseIntentStore(applicationSupportURL: support).load())

        let inactiveHandled = expectation(description: "Lifecycle handles scene inactive")
        let inactiveReceipt = presentation.$accessState.dropFirst().prefix(1)
            .sink { _ in inactiveHandled.fulfill() }
        presentation.receive(.sceneInactive)
        await fulfillment(of: [inactiveHandled], timeout: 30)
        inactiveReceipt.cancel()
        let inactiveCover = await session.gate.privacyCoverRequired()
        XCTAssertTrue(inactiveCover)
        guard case let .eraseCleanupPending(pausedCoordinator) = router.route else {
            return XCTFail("Scene pause must retain the same deferred cleanup owner")
        }
        XCTAssertTrue(pausedCoordinator === coordinator)

        let backgroundHandled = expectation(description: "Lifecycle handles scene background")
        let backgroundReceipt = presentation.$accessState.dropFirst().prefix(1)
            .sink { _ in backgroundHandled.fulfill() }
        presentation.receive(.sceneBackground)
        await fulfillment(of: [backgroundHandled], timeout: 30)
        backgroundReceipt.cancel()
        let backgroundCover = await session.gate.privacyCoverRequired()
        XCTAssertTrue(backgroundCover)
        guard case let .eraseCleanupPending(backgroundCoordinator) = router.route else {
            return XCTFail("Background must retain the same deferred cleanup owner")
        }
        XCTAssertTrue(backgroundCoordinator === coordinator)

        let activeHandled = expectation(description: "Lifecycle handles scene active")
        let activeReceipt = presentation.$accessState.dropFirst().prefix(1)
            .sink { _ in activeHandled.fulfill() }
        presentation.receive(.sceneActive)
        await fulfillment(of: [activeHandled], timeout: 30)
        activeReceipt.cancel()
        let activeCover = await session.gate.privacyCoverRequired()
        XCTAssertTrue(activeCover)
        guard case let .eraseCleanupPending(activeCoordinator) = router.route else {
            return XCTFail("Active transition must retain the same deferred cleanup owner")
        }
        XCTAssertTrue(activeCoordinator === coordinator)

        let oldContextReleased = expectation(for: NSPredicate { _, _ in weakOldContext == nil },
            evaluatedWith: NSObject())
        retainedOldContext = nil
        await fulfillment(of: [oldContextReleased], timeout: 30)
        XCTAssertNil(weakOldContext)
        let preCleanupWriter = coordinator.workspaceWriter
        presentation.eraseRecoveryDiagnosticForTesting = { print("EraseProduction.retry " + $0) }
        await presentation.retryStartup()
        XCTAssertEqual(serviceCount, 2)
        XCTAssertTrue(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.failure)
        // Fresh activation must preserve the completed physical cleanup.
        XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: support))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: support.appendingPathComponent("FieldEvidenceErase", isDirectory: true).path))
        guard case let .ready(recoveredCoordinator, _, _) = router.route else {
            return XCTFail("Fresh-service recovery must publish the retained ticket's Erase session")
        }
        XCTAssertTrue(recoveredCoordinator === coordinator)
        XCTAssertFalse(coordinator.workspaceWriter === preCleanupWriter)
        XCTAssertThrowsError(try preCleanupWriter.currentRevision())
        XCTAssertNoThrow(try coordinator.workspaceWriter.currentRevision())
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
        let published = expectation(description: "Actual production startup publishes authorized content")
        let publication = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        defer { publication.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        XCTAssertTrue(presentation.permitsContentPresentation)
        guard case .ready(let coordinator, let diagnostics, _) = router.route else {
            return XCTFail("Production startup did not publish its sole coordinator")
        }
        let originalGeneration = coordinator.generationID
        let originalScene = try XCTUnwrap(presentation.sceneNavigationAccess)
        let sceneSnapshot = try SceneNavigationSnapshotV1(workspaceID: coordinator.workspaceID,
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
            confirmation: "ERASE", coordinator: coordinator, diagnosticsStore: diagnostics)
        if case .eraseCleanupPending = router.route {
            XCTAssertFalse(presentation.permitsContentPresentation)
            XCTAssertNil(presentation.sceneNavigationAccess)
            XCTAssertNotNil(try EraseIntentStore(applicationSupportURL: support).load())
            XCTAssertTrue(session.sceneNavigationStatePort() === originalScenePort)
            diagnosticPhase = "retry-startup"
            await presentation.retryStartup()
        }
        diagnosticPhase = "completed-owner-readback"
        XCTAssertNotEqual(coordinator.generationID, originalGeneration)
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

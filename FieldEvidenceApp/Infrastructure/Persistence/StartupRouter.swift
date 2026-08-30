import Foundation
import SwiftData
import SwiftUI

enum StartupMaintenanceReason: String, CaseIterable, Error, Sendable {
    case dataPointerInvalid = "data_pointer_invalid"
    case dataGenerationMissing = "data_generation_missing"
    case finalizationInconsistent = "finalization_inconsistent"
    case mediaInconsistent = "media_inconsistent"
    case restoreInconsistent = "restore_inconsistent"
    case eraseInconsistent = "erase_inconsistent"
    case fieldDraftInconsistent = "field_draft_inconsistent"
}

enum StartupStep: String, CaseIterable, Sendable {
    case erase
    case restore
    case currentOpen
    case fieldDraft
    case finalization
    case deletion
    case media
    case pdf
}

@MainActor
final class StartupRouter: ObservableObject {
    enum Route {
        case checking
        case ready(
            StoreSessionCoordinator,
            DiagnosticsStore,
            ReportRecoveryService
        )
        case eraseCleanupPending(StoreSessionCoordinator)
        case maintenance(StartupMaintenanceReason)
    }

    @Published private(set) var route: Route = .checking
    private(set) var maintenanceRestoreSession: StoreGenerationSession?
    private(set) var maintenanceEraseSession: StoreGenerationSession?
    var maintenanceDiagnosticsStore: DiagnosticsStore { diagnosticsStore }

    private let applicationSupportURL: URL
    private let generationFactory: StoreGenerationFactory
    private let diagnosticsStore: DiagnosticsStore
    private let fileManager: FileManager
    private let entitlementRuntime: StoreKitEntitlementRuntimeV1
    private let didBeginStep: (StartupStep) -> Void
    private var injectsReportRenderFailureOnce: Bool
    private let reportLaunchAttemptRegistry = ReportLaunchAttemptRegistry()
    private(set) var entitlementProcessor: StoreKitTransactionProcessor?

    private var hasStarted = false
    private var isRunning = false
    private var pendingEraseDrainProof: EraseGenerationDrainProof?
    private var retainsGenerationsUntilColdLaunch = false

    /// RouteCoordinatorV1 owns the frozen restoration precedence:
    /// maintenance, mutation recovery, explicit ingress, scene snapshot,
    /// then Today. Startup only invokes it after canonical recovery succeeds.
    func restoreSceneNavigation(
        _ request: RouteRestorationRequestV1,
        using coordinator: RouteCoordinatorV1
    ) throws -> RouteRestorationReceiptV1 {
        try coordinator.restore(request)
    }

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        injectsReportRenderFailureOnce: Bool = false,
        entitlementRuntime: StoreKitEntitlementRuntimeV1 = .live(),
        didBeginStep: @escaping (StartupStep) -> Void = { _ in }
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.generationFactory = StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        self.diagnosticsStore = DiagnosticsStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        self.fileManager = fileManager
        self.entitlementRuntime = entitlementRuntime
        self.injectsReportRenderFailureOnce = injectsReportRenderFailureOnce
        self.didBeginStep = didBeginStep
    }

    func startIfNeeded() async {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        await retryChecks()
    }

    func retryChecks() async {
        guard !isRunning else {
            return
        }
        entitlementProcessor?.stop()
        entitlementProcessor = nil
        if let pendingEraseDrainProof {
            guard pendingEraseDrainProof.isDrained else {
                route = .maintenance(.eraseInconsistent)
                return
            }
            self.pendingEraseDrainProof = nil
        }

        isRunning = true
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        defer { isRunning = false }
        var openedSession: StoreGenerationSession?

        do {
            didBeginStep(.erase)
            let erasedSession: StoreGenerationSession?
            do {
                erasedSession = try await EraseAllService(
                    applicationSupportURL: applicationSupportURL,
                    fileManager: fileManager
                ).reconcileAtStartup(diagnosticsStore: diagnosticsStore)
            } catch {
                throw StartupMaintenanceReason.eraseInconsistent
            }

            didBeginStep(.restore)
            let restoredSession: StoreGenerationSession?
            do {
                restoredSession = try BackupRestoreService(
                    applicationSupportURL: applicationSupportURL,
                    fileManager: fileManager
                ).reconcileAtStartup()
            } catch {
                throw StartupMaintenanceReason.restoreInconsistent
            }

            didBeginStep(.currentOpen)
            let session: StoreGenerationSession
            if let restoredSession {
                session = restoredSession
            } else if let erasedSession {
                session = erasedSession
            } else {
                session = try openCurrentGeneration()
            }
            openedSession = session
            do {
                try reconcileGenerationLeasesForStartup()
            } catch {
                throw StartupMaintenanceReason.dataPointerInvalid
            }
            let coordinator = try StoreSessionCoordinator(
                validatingSession: session
            )

            didBeginStep(.fieldDraft)
            do {
                _ = try DraftCommitSagaRecoveryV1(
                    modelContext: session.modelContext
                ).reconcile()
            } catch {
                throw StartupMaintenanceReason.fieldDraftInconsistent
            }

            didBeginStep(.finalization)
            do {
                _ = try await FinalizationRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL
                ).reconcile()
            } catch {
                throw StartupMaintenanceReason.finalizationInconsistent
            }

            didBeginStep(.deletion)
            do {
                _ = try await WholeSignDeletionService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager
                ).reconcile()
            } catch {
                throw StartupMaintenanceReason.finalizationInconsistent
            }

            didBeginStep(.media)
            do {
                let descriptor = FetchDescriptor<EvidenceFile>()
                let authorities = try session.modelContext.fetch(descriptor).map {
                    EvidenceBundleAuthority(
                        schemaVersion: $0.schemaVersion,
                        id: $0.id,
                        recordID: $0.recordID,
                        purposeKey: $0.purposeKey,
                        relativePath: $0.relativePath,
                        mimeType: $0.mimeType,
                        byteCount: $0.byteCount,
                        sha256: $0.sha256,
                        thumbnailRelativePath: $0.thumbnailRelativePath,
                        thumbnailByteCount: $0.thumbnailByteCount,
                        thumbnailSHA256: $0.thumbnailSHA256
                    )
                }
                try await EvidenceBundleStore(
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager
                ).reconcile(authorities: authorities)
            } catch {
                throw StartupMaintenanceReason.mediaInconsistent
            }

            didBeginStep(.pdf)
            let reportRecoveryService: ReportRecoveryService
            do {
                let failNextRenderAttempt = injectsReportRenderFailureOnce
                injectsReportRenderFailureOnce = false
                reportRecoveryService = try ReportRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager,
                    failNextRenderAttempt: failNextRenderAttempt,
                    launchAttemptRegistry: reportLaunchAttemptRegistry
                )
                try reportRecoveryService.reconcileAtStartup()
            } catch {
                throw StartupMaintenanceReason.finalizationInconsistent
            }

            await diagnosticsStore.prepare()
            do {
                try await installCommerceProcessor()
            } catch {
                throw StartupMaintenanceReason.finalizationInconsistent
            }
            route = .ready(
                coordinator,
                diagnosticsStore,
                reportRecoveryService
            )
        } catch let reason as StartupMaintenanceReason {
            maintenanceRestoreSession = openedSession.flatMap {
                eligibleMaintenanceRestoreSession($0)
            }
            maintenanceEraseSession = openedSession.flatMap {
                eligibleMaintenanceEraseSession($0)
            }
            route = .maintenance(reason)
        } catch {
            maintenanceRestoreSession = nil
            maintenanceEraseSession = nil
            route = .maintenance(.dataPointerInvalid)
        }
    }

    /// Unsafe explicit PDF recovery failures are not retryable delivery
    /// failures. They enter the existing closed maintenance surface directly.
    func failClosedPDFRecovery() {
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .maintenance(.finalizationInconsistent)
    }

    func beginEraseBlocking(coordinator: StoreSessionCoordinator) {
        entitlementProcessor?.stop()
        entitlementProcessor = nil
        pendingEraseDrainProof = EraseGenerationDrainProof(
            priorContext: coordinator.modelContext
        )
        isRunning = true
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
    }

    func beginErasedSessionActivation(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator
    ) async {
        if pendingEraseDrainProof == nil {
            pendingEraseDrainProof = EraseGenerationDrainProof(
                priorContext: coordinator.modelContext
            )
        }
        isRunning = true
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        do {
            try coordinator.activateValidating(session: session)
        } catch {
            failClosedErase()
            return
        }
        await Task.yield()
    }

    func finishErasedSessionActivation(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator
    ) async {
        defer { isRunning = false }
        do {
            guard pendingEraseDrainProof?.isDrained == true,
                  coordinator.generationID == session.generationID,
                  try generationFactory.currentGenerationID()
                    == session.generationID,
                  BackupRestoreService.isEmptyCurrent(session.modelContext),
                  noActiveJournal(
                    at: applicationSupportURL.appendingPathComponent(
                        "FieldEvidenceErase/erase.json"
                    )
                  ) else {
                throw StartupMaintenanceReason.eraseInconsistent
            }
            try reconcileGenerationLeasesForStartup()
            let recovery = try ReportRecoveryService(
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                fileManager: fileManager,
                launchAttemptRegistry: reportLaunchAttemptRegistry
            )
            try recovery.reconcileAtStartup()
            await diagnosticsStore.prepare()
            guard await diagnosticsStore.isExactlyZero() else {
                throw StartupMaintenanceReason.eraseInconsistent
            }
            try await installCommerceProcessor()
            pendingEraseDrainProof = nil
            route = .ready(coordinator, diagnosticsStore, recovery)
        } catch {
            maintenanceRestoreSession = nil
            maintenanceEraseSession = nil
            route = .maintenance(.eraseInconsistent)
        }
    }

    func deferErasedSessionCleanup(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator
    ) {
        defer { isRunning = false }
        let eraseJournalURL = applicationSupportURL.appendingPathComponent(
            "FieldEvidenceErase/erase.json"
        )
        guard coordinator.generationID == session.generationID,
              coordinator.generationRootURL.standardizedFileURL
                == session.generationRootURL.standardizedFileURL,
              coordinator.modelContext === session.modelContext,
              (try? generationFactory.currentGenerationID())
                == session.generationID,
              BackupRestoreService.isEmptyCurrent(session.modelContext),
              !noActiveJournal(at: eraseJournalURL) else {
            pendingEraseDrainProof = nil
            maintenanceRestoreSession = nil
            maintenanceEraseSession = nil
            route = .maintenance(.eraseInconsistent)
            return
        }
        pendingEraseDrainProof = nil
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .eraseCleanupPending(coordinator)
    }

    func failClosedErase() {
        isRunning = false
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .maintenance(.eraseInconsistent)
    }

    func activateRestoredSession(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator?
    ) async {
        guard !isRunning else { return }
        isRunning = true
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        defer { isRunning = false }

        do {
            // Restore has no equivalent of EraseGenerationDrainProof. Keep all
            // retired generation bytes for the remainder of this process even
            // after the coordinator releases its old session lease.
            retainsGenerationsUntilColdLaunch = true
            guard try generationFactory.currentGenerationID() == session.generationID
            else {
                throw StartupMaintenanceReason.restoreInconsistent
            }
            try reconcileGenerationLeasesForStartup()
            let activeCoordinator: StoreSessionCoordinator
            if let coordinator {
                try coordinator.activateValidating(session: session)
                activeCoordinator = coordinator
            } else {
                activeCoordinator = try StoreSessionCoordinator(
                    validatingSession: session
                )
            }

            do {
                _ = try await FinalizationRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL
                ).reconcile()
                _ = try await WholeSignDeletionService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager
                ).reconcile()
                let authorities = try session.modelContext.fetch(
                    FetchDescriptor<EvidenceFile>()
                ).map {
                    EvidenceBundleAuthority(
                        schemaVersion: $0.schemaVersion,
                        id: $0.id,
                        recordID: $0.recordID,
                        purposeKey: $0.purposeKey,
                        relativePath: $0.relativePath,
                        mimeType: $0.mimeType,
                        byteCount: $0.byteCount,
                        sha256: $0.sha256,
                        thumbnailRelativePath: $0.thumbnailRelativePath,
                        thumbnailByteCount: $0.thumbnailByteCount,
                        thumbnailSHA256: $0.thumbnailSHA256
                    )
                }
                try await EvidenceBundleStore(
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager
                ).reconcile(authorities: authorities)
                let recovery = try ReportRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager,
                    launchAttemptRegistry: reportLaunchAttemptRegistry
                )
                try recovery.reconcileAtStartup()
                await diagnosticsStore.prepare()
                try await ensureCommerceProcessor()
                route = .ready(activeCoordinator, diagnosticsStore, recovery)
            } catch {
                throw StartupMaintenanceReason.restoreInconsistent
            }
        } catch let reason as StartupMaintenanceReason {
            maintenanceRestoreSession = eligibleMaintenanceRestoreSession(session)
            maintenanceEraseSession = eligibleMaintenanceEraseSession(session)
            route = .maintenance(reason)
        } catch {
            maintenanceRestoreSession = nil
            maintenanceEraseSession = nil
            route = .maintenance(.restoreInconsistent)
        }
    }

    private func openCurrentGeneration() throws -> StoreGenerationSession {
        do {
            return try generationFactory.openOrBootstrapCurrent()
        } catch let failure as StoreGenerationFailure {
            switch failure {
            case .dataPointerInvalid:
                throw StartupMaintenanceReason.dataPointerInvalid
            case .dataGenerationMissing:
                throw StartupMaintenanceReason.dataGenerationMissing
            }
        } catch {
            throw StartupMaintenanceReason.dataPointerInvalid
        }
    }

    private func reconcileGenerationLeasesForStartup() throws {
        if retainsGenerationsUntilColdLaunch {
            let retainAllPolicy = try GenerationPrunePolicyV1(
                retainedInactiveAcceptedGenerationCount:
                    GenerationPrunePolicyV1
                        .productionRetainedInactiveAcceptedGenerationCount,
                pruningEnabled: false
            )
            _ = try generationFactory.reconcileGenerationLeasesAndPrune(
                policy: retainAllPolicy
            )
        } else {
            _ = try generationFactory.reconcileGenerationLeasesAndPrune()
        }
    }

    private func ensureCommerceProcessor() async throws {
        if entitlementProcessor?.isStarted == true { return }
        try await installCommerceProcessor()
    }

    private func installCommerceProcessor() async throws {
        entitlementProcessor?.stop()
        entitlementProcessor = nil
        let store = try EntitlementStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        let processor = StoreKitTransactionProcessor(
            store: store,
            runtime: entitlementRuntime
        )
        try await processor.start()
        entitlementProcessor = processor
    }

    private func requireNoPendingJournal(
        in rootURL: URL,
        reason: StartupMaintenanceReason
    ) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: rootURL.path,
            isDirectory: &isDirectory
        ) else {
            return
        }

        guard isDirectory.boolValue else {
            throw reason
        }

        let entries: [String]
        do {
            entries = try fileManager.contentsOfDirectory(atPath: rootURL.path)
        } catch {
            throw reason
        }

        guard entries.isEmpty else {
            throw reason
        }
    }

    private func eligibleMaintenanceRestoreSession(
        _ session: StoreGenerationSession
    ) -> StoreGenerationSession? {
        guard BackupRestoreService.isEmptyCurrent(session.modelContext),
              (try? generationFactory.currentGenerationID()) == session.generationID,
              maintenanceJournalAuthorityIsClear() else {
            return nil
        }
        return session
    }

    private func eligibleMaintenanceEraseSession(
        _ session: StoreGenerationSession
    ) -> StoreGenerationSession? {
        guard !session.modelContext.hasChanges,
              (try? generationFactory.currentGenerationID()) == session.generationID,
              maintenanceJournalAuthorityIsClear() else {
            return nil
        }
        do {
            try EraseAllService(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            ).validateMaintenanceEntry(session)
        } catch {
            return nil
        }
        return session
    }

    private func maintenanceJournalAuthorityIsClear() -> Bool {
        do {
            let root = try ReportPDFAnchoredFile.rootIdentity(
                at: applicationSupportURL
            )
            let authority = try generationFactory.makeRestoreGenerationAuthority(
                expectedApplicationSupportIdentity: StoreApplicationSupportIdentity(
                    device: root.device,
                    inode: root.inode
                )
            )
            try authority.requireNoEraseAuthority()
            try authority.requireNoRestoreJournal()
            return try authority.restoreGenerationNames().isEmpty
                && authority.importStagingNames().isEmpty
        } catch {
            return false
        }
    }

    private func noActiveJournal(at url: URL) -> Bool {
        !fileManager.fileExists(atPath: url.path)
    }
}

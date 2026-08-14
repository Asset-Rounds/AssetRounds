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
}

enum StartupStep: String, CaseIterable, Sendable {
    case erase
    case restore
    case currentOpen
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
        case maintenance(StartupMaintenanceReason)
    }

    @Published private(set) var route: Route = .checking
    private(set) var maintenanceRestoreSession: StoreGenerationSession?

    private let applicationSupportURL: URL
    private let generationFactory: StoreGenerationFactory
    private let diagnosticsStore: DiagnosticsStore
    private let fileManager: FileManager
    private let didBeginStep: (StartupStep) -> Void
    private var injectsReportRenderFailureOnce: Bool
    private let reportLaunchAttemptRegistry = ReportLaunchAttemptRegistry()

    private var hasStarted = false
    private var isRunning = false

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        injectsReportRenderFailureOnce: Bool = false,
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

        isRunning = true
        maintenanceRestoreSession = nil
        route = .checking
        defer { isRunning = false }
        var openedSession: StoreGenerationSession?

        do {
            didBeginStep(.erase)
            try requireNoPendingJournal(
                in: applicationSupportURL.appendingPathComponent(
                    "FieldEvidenceErase",
                    isDirectory: true
                ),
                reason: .eraseInconsistent
            )

            didBeginStep(.restore)
            do {
                _ = try BackupRestoreService(
                    applicationSupportURL: applicationSupportURL,
                    fileManager: fileManager
                ).reconcileAtStartup()
            } catch {
                throw StartupMaintenanceReason.restoreInconsistent
            }

            didBeginStep(.currentOpen)
            let session = try openCurrentGeneration()
            openedSession = session

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
            route = .ready(
                StoreSessionCoordinator(session: session),
                diagnosticsStore,
                reportRecoveryService
            )
        } catch let reason as StartupMaintenanceReason {
            maintenanceRestoreSession = openedSession.flatMap {
                eligibleMaintenanceSession($0)
            }
            route = .maintenance(reason)
        } catch {
            maintenanceRestoreSession = nil
            route = .maintenance(.dataPointerInvalid)
        }
    }

    /// Unsafe explicit PDF recovery failures are not retryable delivery
    /// failures. They enter the existing closed maintenance surface directly.
    func failClosedPDFRecovery() {
        maintenanceRestoreSession = nil
        route = .maintenance(.finalizationInconsistent)
    }

    func activateRestoredSession(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator?
    ) async {
        guard !isRunning else { return }
        isRunning = true
        maintenanceRestoreSession = nil
        route = .checking
        defer { isRunning = false }

        do {
            guard try generationFactory.currentGenerationID() == session.generationID
            else {
                throw StartupMaintenanceReason.restoreInconsistent
            }
            let activeCoordinator: StoreSessionCoordinator
            if let coordinator {
                coordinator.activate(session: session)
                activeCoordinator = coordinator
            } else {
                activeCoordinator = StoreSessionCoordinator(session: session)
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
                route = .ready(activeCoordinator, diagnosticsStore, recovery)
            } catch {
                throw StartupMaintenanceReason.restoreInconsistent
            }
        } catch let reason as StartupMaintenanceReason {
            maintenanceRestoreSession = eligibleMaintenanceSession(session)
            route = .maintenance(reason)
        } catch {
            maintenanceRestoreSession = nil
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

    private func eligibleMaintenanceSession(
        _ session: StoreGenerationSession
    ) -> StoreGenerationSession? {
        guard BackupRestoreService.isEmptyCurrent(session.modelContext),
              (try? generationFactory.currentGenerationID()) == session.generationID,
              noActiveJournal(
                at: applicationSupportURL.appendingPathComponent(
                    "FieldEvidenceRestore/restore.json"
                )
              ),
              noActiveJournal(
                at: applicationSupportURL.appendingPathComponent(
                    "FieldEvidenceErase/erase.json"
                )
              ) else {
            return nil
        }
        return session
    }

    private func noActiveJournal(at url: URL) -> Bool {
        !fileManager.fileExists(atPath: url.path)
    }
}

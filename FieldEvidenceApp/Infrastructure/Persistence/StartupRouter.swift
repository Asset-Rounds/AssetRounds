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

/// Read-only bootstrap input for the Recovery Center. It deliberately carries
/// no store session or recovery action, so a support projection cannot bypass
/// this router's validation gate.
enum StartupRecoveryBootstrapStateV1: Equatable, Sendable {
    case checking
    case ready
    case eraseCleanupPending
    case maintenance(StartupMaintenanceReason)
}

@MainActor
final class StartupRouter: ObservableObject {
    enum Route {
        case checking
        case awaitingIndependentValidation(StoreMigrationAwaitingValidationV1)
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
    var recoverySupportDiagnosticsStore: DiagnosticsStore { diagnosticsStore }

    /// The Recovery Center may derive bootstrap support state from this value,
    /// but cannot obtain a session or run a repair through it.
    var recoveryBootstrapState: StartupRecoveryBootstrapStateV1 {
        switch route {
        case .checking, .awaitingIndependentValidation:
            return .checking
        case .ready:
            return .ready
        case .eraseCleanupPending:
            return .eraseCleanupPending
        case .maintenance(let reason):
            return .maintenance(reason)
        }
    }

    private let applicationSupportURL: URL
    private let generationFactory: StoreGenerationFactory
    private let diagnosticsStore: DiagnosticsStore
    private let fileManager: FileManager
    private let entitlementRuntime: StoreKitEntitlementRuntimeV1
    private let didBeginStep: (StartupStep) -> Void
    private let beforeCommerceActivation: @MainActor (UUID) async -> Void
    private let lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1?
    private let startupPreparationFailure: StartupMaintenanceReason?
    private var injectsReportRenderFailureOnce: Bool
    private let reportLaunchAttemptRegistry = ReportLaunchAttemptRegistry()
    private(set) var entitlementProcessor: StoreKitTransactionProcessor?

    private var hasStarted = false
    private var isRunning = false
    private var operationID: UUID?
    private enum OperationKind { case startup, restored, erase }
    private var operationKind: OperationKind?
    private struct OwnedWriter {
        let coordinator: StoreSessionCoordinator
        let writer: WorkspaceWriterV1
        let generationID: UUID

        @MainActor init(_ coordinator: StoreSessionCoordinator) {
            self.coordinator = coordinator
            self.writer = coordinator.workspaceWriter
            self.generationID = coordinator.generationID
        }
    }
    private enum OperationFailure: Error { case superseded }
    private var operationOwnedWriter: OwnedWriter?
    private var publishedWriter: OwnedWriter?
    private var pendingEraseDrainProof: EraseGenerationDrainProof?
    private var pendingErasedActivation: (owner: OwnedWriter, session: StoreGenerationSession, operationID: UUID)?
    private var retainsGenerationsUntilColdLaunch = false
    private var pendingWriterLeaseReleases: [StoreSessionWriterCleanupFailureV1] = []
    private var pendingCoordinatorReleases: [OwnedWriter] = []
    private(set) var lastWriterCleanupFailure: Error?

    var hasPendingWriterCleanup: Bool {
        !pendingWriterLeaseReleases.isEmpty || !pendingCoordinatorReleases.isEmpty
    }

    /// RouteCoordinatorV1 owns the frozen restoration precedence:
    /// maintenance, mutation recovery, explicit ingress, scene snapshot,
    /// then Today. Startup only invokes it after canonical recovery succeeds.
    func restoreSceneNavigation(
        _ request: RouteRestorationRequestV1,
        using coordinator: RouteCoordinatorV1
    ) throws -> RouteRestorationReceiptV1 {
        try coordinator.restore(request)
    }

    /// C16 authenticated restoration entry. The legacy synchronous overload is
    /// retained for maintenance-only callers; production content restoration
    /// must use this gate-aware route.
    func restoreSceneNavigation(
        _ request: RouteRestorationRequestV1,
        using coordinator: RouteCoordinatorV1,
        accessGate: any AppAccessGatePortV1
    ) async throws -> RouteRestorationReceiptV1 {
        try await coordinator.restore(request, accessGate: accessGate)
    }

    func retryChecks(accessGate: any AppAccessGatePortV1) async throws {
        _ = try await accessGate.requireContentAccess(for: .startupRecovery)
        await retryChecks()
    }

    /// The sole startup operation allowed before an app-access permit. The
    /// injected ingress store guarantees metadata-only cleanup and fails
    /// closed on uncertain ownership; this method never opens a store.
    func performPreAuthenticationScratchHygiene(
        ingressStore: any ProtectedIngressStoreV1,
        now: Date,
        operationID: UUID
    ) async throws -> ProtectedIngressStartupHygieneReceiptV1 {
        let receipt = try await ingressStore.performBlindStartupHygiene(
            now: now, operationID: operationID
        )
        guard !receipt.contentRead,
              receipt.retainedValidCount == 0,
              receipt.deferredAmbiguousCount == 0 else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return receipt
    }

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        injectsReportRenderFailureOnce: Bool = false,
        entitlementRuntime: StoreKitEntitlementRuntimeV1 = .live(),
        startupPreparationFailure: StartupMaintenanceReason? = nil,
        didBeginStep: @escaping (StartupStep) -> Void = { _ in },
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1? = nil,
        beforeCommerceActivation: @escaping @MainActor (UUID) async -> Void = { _ in }
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
        self.startupPreparationFailure = startupPreparationFailure
        self.lifecycleProfileRegistry = lifecycleProfileRegistry
        self.beforeCommerceActivation = beforeCommerceActivation
    }

    func startIfNeeded() async {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        await retryChecks()
    }

    func startIfNeeded(accessGate: any AppAccessGatePortV1) async throws {
        guard !hasStarted else { return }
        _ = try await accessGate.requireContentAccess(for: .startupRecovery)
        hasStarted = true
        await retryChecks()
    }

    func retryChecks() async {
        guard !isRunning else {
            return
        }
        invalidateOperationAndPublishedWriter()
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.dataPointerInvalid)
            return
        }
        if let startupPreparationFailure {
            route = .maintenance(startupPreparationFailure)
            return
        }
        if let pendingEraseDrainProof {
            guard pendingEraseDrainProof.isDrained else {
                route = .maintenance(.eraseInconsistent)
                return
            }
            self.pendingEraseDrainProof = nil
        }

        let operation = beginOperation(.startup)
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        defer { endOperation(operation) }
        var openedSession: StoreGenerationSession?
        var unpublishedOwner: OwnedWriter?

        do {
            // The aggregate already proved the ordinary restore/erase owners
            // clear before reservation. Their abandoned-staging cleanup must
            // not mistake its bound candidate for an ordinary restore.
            let resumesAggregate = try generationFactory.hasAggregateMigrationReservation()
            didBeginStep(.erase)
            let erasedSession: StoreGenerationSession?
            do {
                if resumesAggregate { erasedSession = nil }
                else {
                    erasedSession = try await EraseAllService(
                        applicationSupportURL: applicationSupportURL,
                        fileManager: fileManager
                    ).reconcileAtStartup(diagnosticsStore: diagnosticsStore)
                }
            } catch {
                throw StartupMaintenanceReason.eraseInconsistent
            }
            try requireCurrentOperation(operation)

            didBeginStep(.restore)
            let restoredSession: StoreGenerationSession?
            do {
                if resumesAggregate { restoredSession = nil }
                else {
                    restoredSession = try await BackupRestoreService(
                        applicationSupportURL: applicationSupportURL,
                        fileManager: fileManager
                    ).reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
                }
            } catch {
                throw StartupMaintenanceReason.restoreInconsistent
            }
            try requireCurrentOperation(operation)

            didBeginStep(.currentOpen)
            let session: StoreGenerationSession
            if let restoredSession {
                session = restoredSession
            } else if let erasedSession {
                session = erasedSession
            } else {
                let result = try await generationFactory.openForStartup(recoverOriginalSource: { authority in
                    try self.requireCurrentOperation(operation)
                    try await self.recoverOriginalSource(authority, operation: operation)
                    try self.requireCurrentOperation(operation)
                })
                try requireCurrentOperation(operation)
                switch result {
                case .ready(let current): session = current
                case .awaitingIndependentValidation(let pending):
                    route = .awaitingIndependentValidation(pending)
                    return
                }
            }
            openedSession = session
            do {
                try reconcileGenerationLeasesForStartup()
            } catch {
                throw StartupMaintenanceReason.dataPointerInvalid
            }
            didBeginStep(.fieldDraft)
            do {
                _ = try DraftCommitSagaRecoveryV1(
                    modelContext: session.modelContext
                ).reconcile()
            } catch {
                throw StartupMaintenanceReason.fieldDraftInconsistent
            }

            didBeginStep(.finalization)
            // V2 effects and receipts are one transaction, so the journal is
            // already coherent before file-intent recovery. Keep this sole
            // writer unpublished until every recovery step succeeds.
            let coordinator = try StoreSessionCoordinator(
                validatingSession: session,
                lifecycleProfileRegistry: lifecycleProfileRegistry
            )
            let owner = OwnedWriter(coordinator)
            unpublishedOwner = owner
            operationOwnedWriter = owner
            do {
                _ = try await FinalizationRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    workspaceWriter: owner.writer,
                    lifecycleProfileRegistry: coordinator.lifecycleProfileRegistry
                ).reconcile()
            } catch {
                throw StartupMaintenanceReason.finalizationInconsistent
            }
            try requireCurrentOperation(operation, owner: owner)

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
            try requireCurrentOperation(operation, owner: owner)

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
            try requireCurrentOperation(operation, owner: owner)

            didBeginStep(.pdf)
            let reportRecoveryService: ReportRecoveryService
            do {
                let failNextRenderAttempt = injectsReportRenderFailureOnce
                injectsReportRenderFailureOnce = false
                reportRecoveryService = try makeActiveReportRecovery(
                    session: session,
                    coordinator: coordinator,
                    failNextRenderAttempt: failNextRenderAttempt
                )
                try reportRecoveryService.reconcileAtStartup()
            } catch {
                throw StartupMaintenanceReason.finalizationInconsistent
            }

            _ = try coordinator.workspaceWriter.sourceMutationHistorySnapshot()
            await diagnosticsStore.prepare()
            try requireCurrentOperation(operation, owner: owner)
            do {
                try await installCommerceProcessor(operation: operation, owner: owner)
            } catch {
                throw StartupMaintenanceReason.finalizationInconsistent
            }
            try requireCurrentOperation(operation, owner: owner)
            publishedWriter = owner
            operationOwnedWriter = nil
            route = .ready(
                coordinator,
                diagnosticsStore,
                reportRecoveryService
            )
        } catch {
            retainWriterCleanup(error, owner: unpublishedOwner)
            guard operationID == operation else {
                _ = resolvePendingWriterCleanup()
                return
            }
            stopCommerce()
            guard resolvePendingWriterCleanup() else {
                enterWriterCleanupMaintenance(.dataPointerInvalid)
                return
            }
            if let reason = error as? StartupMaintenanceReason {
                maintenanceRestoreSession = openedSession.flatMap {
                    eligibleMaintenanceRestoreSession($0)
                }
                maintenanceEraseSession = openedSession.flatMap {
                    eligibleMaintenanceEraseSession($0)
                }
                route = .maintenance(reason)
            } else {
                maintenanceRestoreSession = nil
                maintenanceEraseSession = nil
                route = .maintenance(.dataPointerInvalid)
            }
        }
    }

    private func stopCommerce() {
        entitlementProcessor?.stop()
        entitlementProcessor = nil
    }

    private func beginOperation(_ kind: OperationKind) -> UUID {
        let id = UUID()
        operationID = id
        operationKind = kind
        isRunning = true
        stopCommerce()
        return id
    }

    private func endOperation(_ id: UUID) {
        guard operationID == id else { return }
        operationID = nil
        operationKind = nil
        operationOwnedWriter = nil
        isRunning = false
    }

    private func requireCurrentOperation(_ id: UUID, owner: OwnedWriter? = nil) throws {
        guard operationID == id, isRunning else { throw OperationFailure.superseded }
        if let owner {
            guard owner.coordinator.workspaceWriter === owner.writer,
                  owner.coordinator.generationID == owner.generationID,
                  try generationFactory.currentGenerationID() == owner.generationID else {
                throw OperationFailure.superseded
            }
            _ = try owner.writer.sourceMutationHistorySnapshot()
        }
    }

    private func retainOwnedWriter(_ owner: OwnedWriter?) {
        guard let owner else { return }
        owner.writer.invalidate()
        if !pendingCoordinatorReleases.contains(where: { $0.writer === owner.writer }) {
            pendingCoordinatorReleases.append(owner)
        }
    }

    /// Retain exact writer ownership before discarding routes or pending work.
    /// A suspended continuation cannot reclaim a newer binding in the same
    /// mutable coordinator when its own operation resumes.
    private func invalidateOperationAndPublishedWriter() {
        operationID = nil
        operationKind = nil
        isRunning = false
        stopCommerce()
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        retainOwnedWriter(operationOwnedWriter)
        retainOwnedWriter(pendingErasedActivation?.owner)
        retainOwnedWriter(publishedWriter)
        operationOwnedWriter = nil
        pendingErasedActivation = nil
        publishedWriter = nil
    }

    private func retainWriterCleanup(_ error: Error, owner: OwnedWriter?) {
        if let failure = error as? StoreSessionWriterCleanupFailureV1,
           !pendingWriterLeaseReleases.contains(where: { $0 === failure }) {
            pendingWriterLeaseReleases.append(failure)
            // Replacement cleanup may preserve an earlier cleanup failure.
            retainWriterCleanup(failure.operationFailure, owner: nil)
        }
        retainOwnedWriter(owner)
    }

    private func resolvePendingWriterCleanup() -> Bool {
        var remainingLeases: [StoreSessionWriterCleanupFailureV1] = []
        for failure in pendingWriterLeaseReleases {
            do { try failure.retryRelease() }
            catch {
                remainingLeases.append(failure)
                lastWriterCleanupFailure = error
            }
        }
        pendingWriterLeaseReleases = remainingLeases
        var remainingCoordinators: [OwnedWriter] = []
        for owner in pendingCoordinatorReleases {
            do {
                if owner.coordinator.workspaceWriter === owner.writer {
                    try owner.coordinator.invalidateAndReleaseWriter()
                } else {
                    // activateValidating releases the previous lease before
                    // installing its replacement. Never close that new lease.
                    owner.writer.invalidate()
                }
            }
            catch {
                remainingCoordinators.append(owner)
                lastWriterCleanupFailure = error
            }
        }
        pendingCoordinatorReleases = remainingCoordinators
        if !hasPendingWriterCleanup { lastWriterCleanupFailure = nil }
        return !hasPendingWriterCleanup
    }

    private func enterWriterCleanupMaintenance(_ reason: StartupMaintenanceReason) {
        invalidateOperationAndPublishedWriter()
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .maintenance(reason)
    }

    private func makeActiveReportRecovery(
        session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator,
        failNextRenderAttempt: Bool = false
    ) throws -> ReportRecoveryService {
        guard coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID else {
            throw StartupMaintenanceReason.finalizationInconsistent
        }
        // The nonempty registry supplies only a construction seed. Recovery
        // resolves each actual report's exact package from its frozen source;
        // this order never selects or substitutes a report's active profile.
        let profile = coordinator.lifecycleProfileRegistry.firstRegisteredProfile
        let dependencies = try coordinator.packageLifecycleDependencies()
        return try ReportRecoveryService(
            modelContext: session.modelContext,
            lifecycleDependencies: dependencies,
            lifecycleProfile: profile,
            fileManager: fileManager,
            failNextRenderAttempt: failNextRenderAttempt,
            launchAttemptRegistry: reportLaunchAttemptRegistry
        )
    }

    /// Unsafe explicit PDF recovery failures are not retryable delivery
    /// failures. They enter the existing closed maintenance surface directly.
    func failClosedPDFRecovery() {
        invalidateOperationAndPublishedWriter()
        _ = resolvePendingWriterCleanup()
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .maintenance(.finalizationInconsistent)
    }

    func beginEraseBlocking(coordinator: StoreSessionCoordinator) {
        guard !isRunning else {
            failClosedErase()
            return
        }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.eraseInconsistent)
            return
        }
        guard publishedWriter.map({ $0.coordinator === coordinator && $0.writer === coordinator.workspaceWriter }) ?? true else {
            failClosedErase()
            return
        }
        _ = beginOperation(.erase)
        operationOwnedWriter = publishedWriter
        publishedWriter = nil
        pendingEraseDrainProof = EraseGenerationDrainProof(
            priorContext: coordinator.modelContext
        )
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
    }

    func beginErasedSessionActivation(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator
    ) async {
        guard pendingErasedActivation == nil else {
            failClosedErase()
            return
        }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.eraseInconsistent)
            return
        }
        // The erase callback continues its blocking operation. Direct
        // activation may start one only when no other recovery is running.
        if operationID == nil {
            guard !isRunning else { failClosedErase(); return }
            _ = beginOperation(.erase)
            operationOwnedWriter = publishedWriter
            publishedWriter = nil
        }
        guard let operation = operationID, operationKind == .erase,
              operationOwnedWriter.map({ $0.coordinator === coordinator }) ?? true else {
            failClosedErase()
            return
        }
        if pendingEraseDrainProof == nil {
            pendingEraseDrainProof = EraseGenerationDrainProof(
                priorContext: coordinator.modelContext
            )
        }
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        do {
            try requireCurrentOperation(operation)
            guard try generationFactory.currentGenerationID() == session.generationID else {
                throw StartupMaintenanceReason.eraseInconsistent
            }
            try coordinator.activateValidating(session: session)
            let owner = OwnedWriter(coordinator)
            operationOwnedWriter = owner
            pendingErasedActivation = (owner, session, operation)
        } catch {
            // A failed replacement did not transfer ownership of the old
            // coordinator. Retain only any uninstalled failed-release lease.
            retainWriterCleanup(error, owner: nil)
            _ = resolvePendingWriterCleanup()
            failClosedErase()
            return
        }
        await Task.yield()
        guard operationID == operation else { return }
    }

    func finishErasedSessionActivation(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator
    ) async {
        guard let activation = pendingErasedActivation else { failClosedErase(); return }
        let operation = activation.operationID
        let owner = activation.owner
        defer { endOperation(operation) }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.eraseInconsistent)
            return
        }
        let ownsActivatedWriter = owner.coordinator === coordinator
            && owner.writer === coordinator.workspaceWriter
            && activation.session.generationID == session.generationID
            && activation.session.modelContext === session.modelContext
        do {
            try requireCurrentOperation(operation, owner: owner)
            guard ownsActivatedWriter,
                  pendingEraseDrainProof?.isDrained == true,
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
            let recovery = try makeActiveReportRecovery(
                session: session,
                coordinator: coordinator
            )
            try recovery.reconcileAtStartup()
            _ = try coordinator.workspaceWriter.sourceMutationHistorySnapshot()
            await diagnosticsStore.prepare()
            try requireCurrentOperation(operation, owner: owner)
            let diagnosticsAreZero = await diagnosticsStore.isExactlyZero()
            try requireCurrentOperation(operation, owner: owner)
            guard diagnosticsAreZero else {
                throw StartupMaintenanceReason.eraseInconsistent
            }
            try await installCommerceProcessor(operation: operation, owner: owner)
            try requireCurrentOperation(operation, owner: owner)
            pendingEraseDrainProof = nil
            pendingErasedActivation = nil
            operationOwnedWriter = nil
            publishedWriter = owner
            route = .ready(coordinator, diagnosticsStore, recovery)
        } catch {
            retainWriterCleanup(error, owner: owner)
            _ = resolvePendingWriterCleanup()
            guard operationID == operation else { return }
            failClosedErase()
        }
    }

    func deferErasedSessionCleanup(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator
    ) {
        guard let activation = pendingErasedActivation else { failClosedErase(); return }
        let operation = activation.operationID
        defer { endOperation(operation) }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.eraseInconsistent)
            return
        }
        do { try requireCurrentOperation(operation, owner: activation.owner) }
        catch { failClosedErase(); return }
        let eraseJournalURL = applicationSupportURL.appendingPathComponent(
            "FieldEvidenceErase/erase.json"
        )
        let ownsActivatedWriter = operationID == operation
            && activation.owner.coordinator === coordinator
            && activation.owner.writer === coordinator.workspaceWriter
            && activation.session.generationID == session.generationID
            && activation.session.modelContext === session.modelContext
        guard ownsActivatedWriter,
              coordinator.generationID == session.generationID,
              coordinator.generationRootURL.standardizedFileURL
                == session.generationRootURL.standardizedFileURL,
              coordinator.modelContext === session.modelContext,
              (try? generationFactory.currentGenerationID())
                == session.generationID,
              BackupRestoreService.isEmptyCurrent(session.modelContext),
              !noActiveJournal(at: eraseJournalURL) else {
            if ownsActivatedWriter {
                pendingErasedActivation = nil
                retainWriterCleanup(StartupMaintenanceReason.eraseInconsistent, owner: activation.owner)
                _ = resolvePendingWriterCleanup()
            }
            pendingEraseDrainProof = nil
            failClosedErase()
            return
        }
        pendingEraseDrainProof = nil
        pendingErasedActivation = nil
        operationOwnedWriter = nil
        publishedWriter = activation.owner
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .eraseCleanupPending(coordinator)
    }

    func failClosedErase() {
        invalidateOperationAndPublishedWriter()
        _ = resolvePendingWriterCleanup()
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .maintenance(.eraseInconsistent)
    }

    func activateRestoredSession(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator?
    ) async {
        guard !isRunning else { return }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.restoreInconsistent)
            return
        }
        let operation = beginOperation(.restored)
        if let publishedWriter {
            if let coordinator, publishedWriter.coordinator === coordinator {
                operationOwnedWriter = publishedWriter
            } else {
                retainOwnedWriter(publishedWriter)
            }
            self.publishedWriter = nil
        }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.restoreInconsistent)
            return
        }
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        defer { endOperation(operation) }
        var unpublishedOwner: OwnedWriter?

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
                    validatingSession: session,
                    lifecycleProfileRegistry: lifecycleProfileRegistry
                )
            }
            let owner = OwnedWriter(activeCoordinator)
            unpublishedOwner = owner
            operationOwnedWriter = owner

            do {
                _ = try await FinalizationRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    workspaceWriter: owner.writer,
                    lifecycleProfileRegistry: activeCoordinator.lifecycleProfileRegistry
                ).reconcile()
                try requireCurrentOperation(operation, owner: owner)
                _ = try await WholeSignDeletionService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager
                ).reconcile()
                try requireCurrentOperation(operation, owner: owner)
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
                try requireCurrentOperation(operation, owner: owner)
                let recovery = try makeActiveReportRecovery(
                    session: session,
                    coordinator: activeCoordinator
                )
                try recovery.reconcileAtStartup()
                _ = try activeCoordinator.workspaceWriter.sourceMutationHistorySnapshot()
                await diagnosticsStore.prepare()
                try requireCurrentOperation(operation, owner: owner)
                try await installCommerceProcessor(operation: operation, owner: owner)
                try requireCurrentOperation(operation, owner: owner)
                operationOwnedWriter = nil
                publishedWriter = owner
                route = .ready(activeCoordinator, diagnosticsStore, recovery)
            } catch {
                retainWriterCleanup(error, owner: nil)
                throw StartupMaintenanceReason.restoreInconsistent
            }
        } catch {
            retainWriterCleanup(error, owner: unpublishedOwner)
            guard operationID == operation else {
                _ = resolvePendingWriterCleanup()
                return
            }
            stopCommerce()
            retainOwnedWriter(operationOwnedWriter)
            guard resolvePendingWriterCleanup() else {
                enterWriterCleanupMaintenance(.restoreInconsistent)
                return
            }
            if let reason = error as? StartupMaintenanceReason {
                maintenanceRestoreSession = eligibleMaintenanceRestoreSession(session)
                maintenanceEraseSession = eligibleMaintenanceEraseSession(session)
                route = .maintenance(reason)
            } else {
                maintenanceRestoreSession = nil
                maintenanceEraseSession = nil
                route = .maintenance(.restoreInconsistent)
            }
        }
    }

    private func recoverOriginalSource(
        _ authority: StoreMigrationSourceRecoveryAuthorityV1,
        operation: UUID
    ) async throws {
        let finalization = try FinalizationRecoveryService(sourceRecoveryAuthority: authority)
        _ = try await finalization.reconcile()
        try requireCurrentOperation(operation)
        _ = try WholeSignDeletionService.reconcileOriginalSource(authority: authority)
        func survivingMedia() throws -> [EvidenceBundleAuthority] {
            let context = try authority.recoveryContext()
            var descriptor = FetchDescriptor<EvidenceFile>()
            descriptor.fetchLimit = 100_001
            let rows = try context.fetch(descriptor)
            guard rows.count <= 100_000 else { throw StartupMaintenanceReason.mediaInconsistent }
            return rows.map {
                EvidenceBundleAuthority(schemaVersion: $0.schemaVersion, id: $0.id,
                    recordID: $0.recordID, purposeKey: $0.purposeKey,
                    relativePath: $0.relativePath, mimeType: $0.mimeType,
                    byteCount: $0.byteCount, sha256: $0.sha256,
                    thumbnailRelativePath: $0.thumbnailRelativePath,
                    thumbnailByteCount: $0.thumbnailByteCount, thumbnailSHA256: $0.thumbnailSHA256)
            }
        }
        let media = try EvidenceBundleStore(sourceRecoveryAuthority: authority)
        try await media.reconcile(authorities: survivingMedia())
        try requireCurrentOperation(operation)
        try ReportRecoveryService.settleOriginalSourcePDFs(authority: authority)
        // Re-enumerate original authorities after all effects. This callback
        // returns no context, writer or service to the aggregate engine.
        try await finalization.verifyOriginalRecoverySettled()
        try requireCurrentOperation(operation)
        try WholeSignDeletionService.verifyOriginalRecoverySettled(authority: authority)
        try await media.verifyOriginalRecoverySettled(authorities: survivingMedia())
        try requireCurrentOperation(operation)
        try ReportRecoveryService.verifyOriginalRecoverySettled(authority: authority)
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

    private func installCommerceProcessor(operation: UUID, owner: OwnedWriter) async throws {
        try requireCurrentOperation(operation, owner: owner)
        await beforeCommerceActivation(try owner.writer.currentRevision().writerInstanceID)
        try requireCurrentOperation(operation, owner: owner)
        stopCommerce()
        let store = try EntitlementStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        let processor = StoreKitTransactionProcessor(
            store: store,
            runtime: entitlementRuntime
        )
        do {
            try await processor.start()
            try requireCurrentOperation(operation, owner: owner)
        } catch {
            processor.stop()
            throw error
        }
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
        guard !hasPendingWriterCleanup,
              BackupRestoreService.isEmptyCurrent(session.modelContext),
              (try? generationFactory.currentGenerationID()) == session.generationID,
              maintenanceJournalAuthorityIsClear() else {
            return nil
        }
        return session
    }

    private func eligibleMaintenanceEraseSession(
        _ session: StoreGenerationSession
    ) -> StoreGenerationSession? {
        guard !hasPendingWriterCleanup,
              !session.modelContext.hasChanges,
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
